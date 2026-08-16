package br.com.flashcards.flashcards

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkRequest
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "br.com.mnemos/device_wifi"
    private val wifiPermissionRequestCode = 4703
    private val wifiScanPermissionRequestCode = 4704

    private var callback: ConnectivityManager.NetworkCallback? = null
    private var boundNetwork: Network? = null
    private var pendingConnect: Pair<String, String>? = null
    private var pendingResult: MethodChannel.Result? = null
    private var pendingScanResult: MethodChannel.Result? = null
    private var scanReceiver: BroadcastReceiver? = null
    private var bleBridge: MnemosBleBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bleBridge = MnemosBleBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connect" -> connect(call, result)
                "disconnect" -> {
                    disconnect()
                    result.success(null)
                }
                "currentSsid" -> result.success(currentSsid())
                "scanNetworks" -> scanNetworks(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun requiredConnectPermissions(): Array<String> = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            arrayOf(Manifest.permission.NEARBY_WIFI_DEVICES)
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
        else -> emptyArray()
    }

    private fun requiredScanPermissions(): Array<String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return emptyArray()
        val permissions = mutableListOf(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.NEARBY_WIFI_DEVICES
        }
        return permissions.toTypedArray()
    }

    private fun missingPermissions(permissions: Array<String>): Array<String> =
        permissions.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }.toTypedArray()

    private fun hasConnectPermission(): Boolean = missingPermissions(requiredConnectPermissions()).isEmpty()

    @Suppress("DEPRECATION")
    private fun currentSsid(): String? {
        if (!hasConnectPermission()) return null
        return try {
            val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val raw = wifi.connectionInfo?.ssid ?: return null
            if (raw == WifiManager.UNKNOWN_SSID || raw == "<unknown ssid>") return null
            raw.removePrefix("\"").removeSuffix("\"").takeIf { it.isNotBlank() }
        } catch (_: SecurityException) {
            null
        }
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid")?.trim().orEmpty()
        val password = call.argument<String>("password").orEmpty()
        if (ssid.isEmpty()) {
            result.error("INVALID_SSID", "SSID ausente", null)
            return
        }

        val missing = missingPermissions(requiredConnectPermissions())
        if (missing.isNotEmpty()) {
            if (pendingResult != null || pendingScanResult != null) {
                result.error("WIFI_BUSY", "Já existe uma solicitação Wi-Fi em andamento", null)
                return
            }
            pendingConnect = ssid to password
            pendingResult = result
            requestPermissions(missing, wifiPermissionRequestCode)
            return
        }

        connectWithPermission(ssid, password, result)
    }

    private fun connectWithPermission(
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        disconnect()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            connectSpecifier(ssid, password, result)
        } else {
            connectLegacy(ssid, password, result)
        }
    }

    private fun scanNetworks(result: MethodChannel.Result) {
        if (pendingScanResult != null || pendingResult != null) {
            result.error("WIFI_BUSY", "Já existe uma solicitação Wi-Fi em andamento", null)
            return
        }
        val missing = missingPermissions(requiredScanPermissions())
        if (missing.isNotEmpty()) {
            pendingScanResult = result
            requestPermissions(missing, wifiScanPermissionRequestCode)
            return
        }
        scanNetworksWithPermission(result)
    }

    @Suppress("DEPRECATION")
    private fun scanNetworksWithPermission(result: MethodChannel.Result) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        if (!wifi.isWifiEnabled) {
            result.error("WIFI_DISABLED", "Ative o Wi-Fi para listar redes disponíveis", null)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val location = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            if (!location.isLocationEnabled) {
                result.error(
                    "LOCATION_DISABLED",
                    "O Android exige que os Serviços de localização estejam ativos para listar redes Wi-Fi próximas",
                    null,
                )
                return
            }
        }

        fun deliver() {
            val rows = try {
                wifi.scanResults
            } catch (e: SecurityException) {
                unregisterScanReceiver()
                result.error("WIFI_SCAN_PERMISSION", e.message ?: "Permissão insuficiente para listar redes Wi-Fi", null)
                return
            }

            data class Aggregate(
                val ssid: String,
                var level: Int = -100,
                var secure: Boolean = false,
                var enterprise: Boolean = false,
                var personal: Boolean = false,
                var has24: Boolean = false,
                var has5: Boolean = false,
                var has6: Boolean = false,
            )

            val grouped = linkedMapOf<String, Aggregate>()
            for (scan in rows) {
                val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    scan.wifiSsid?.toString()?.removePrefix("\"")?.removeSuffix("\"") ?: scan.SSID
                } else {
                    @Suppress("DEPRECATION")
                    scan.SSID
                }.trim()
                if (ssid.isEmpty() || ssid == WifiManager.UNKNOWN_SSID) continue

                val capabilities = scan.capabilities ?: ""
                val aggregate = grouped.getOrPut(ssid) { Aggregate(ssid) }
                aggregate.level = maxOf(aggregate.level, scan.level)
                aggregate.has24 = aggregate.has24 || scan.frequency in 2400..2500
                aggregate.has5 = aggregate.has5 || scan.frequency in 4900..5924
                aggregate.has6 = aggregate.has6 || scan.frequency >= 5925

                val isEnterprise = capabilities.contains("EAP", ignoreCase = true) ||
                    capabilities.contains("SUITE_B", ignoreCase = true)
                // WEP is intentionally not classified as a supported personal
                // profile. The terminal contract accepts contemporary PSK/SAE
                // credentials; legacy WEP remains visible as unsupported.
                val isPersonal = capabilities.contains("PSK", ignoreCase = true) ||
                    capabilities.contains("SAE", ignoreCase = true)
                val isLegacyOrEnhancedOpen = capabilities.contains("WEP", ignoreCase = true) ||
                    capabilities.contains("OWE", ignoreCase = true)
                val isSecure = isEnterprise || isPersonal || isLegacyOrEnhancedOpen
                aggregate.enterprise = aggregate.enterprise || isEnterprise
                aggregate.personal = aggregate.personal || isPersonal
                aggregate.secure = aggregate.secure || isSecure
            }

            val values = grouped.values
                .sortedByDescending { it.level }
                .map { network ->
                    mapOf(
                        "ssid" to network.ssid,
                        "level" to network.level,
                        "secure" to network.secure,
                        "securityType" to when {
                            network.enterprise -> "enterprise"
                            network.personal -> "personal"
                            network.secure -> "unknown"
                            else -> "open"
                        },
                        "has24GHz" to network.has24,
                        "has5GHz" to network.has5,
                        "has6GHz" to network.has6,
                    )
                }
            unregisterScanReceiver()
            result.success(values)
        }

        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == WifiManager.SCAN_RESULTS_AVAILABLE_ACTION) deliver()
            }
        }
        scanReceiver = receiver
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(receiver, filter)
        }

        val started = try {
            wifi.startScan()
        } catch (e: SecurityException) {
            unregisterScanReceiver()
            result.error("WIFI_SCAN_PERMISSION", e.message ?: "Permissão insuficiente para iniciar a varredura Wi-Fi", null)
            return
        }

        if (!started) {
            // Android can throttle active scans. Cached results remain useful
            // for a provisioning selector, so return them instead of failing.
            deliver()
        }
    }

    private fun unregisterScanReceiver() {
        scanReceiver?.let {
            try {
                unregisterReceiver(it)
            } catch (_: Exception) {
            }
        }
        scanReceiver = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (bleBridge?.onRequestPermissionsResult(requestCode, grantResults) == true) return
        when (requestCode) {
            wifiPermissionRequestCode -> {
                val pair = pendingConnect
                val result = pendingResult
                pendingConnect = null
                pendingResult = null
                if (pair == null || result == null) return
                if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                    connectWithPermission(pair.first, pair.second, result)
                } else {
                    result.error(
                        "WIFI_PERMISSION",
                        "Permissão de dispositivos Wi-Fi próximos negada",
                        null,
                    )
                }
            }

            wifiScanPermissionRequestCode -> {
                val result = pendingScanResult
                pendingScanResult = null
                if (result == null) return
                if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                    scanNetworksWithPermission(result)
                } else {
                    result.error(
                        "WIFI_SCAN_PERMISSION",
                        "Permissão necessária para listar redes Wi-Fi foi negada. O SSID ainda pode ser digitado manualmente.",
                        null,
                    )
                }
            }

            else -> super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        }
    }

    private fun connectSpecifier(
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val builder = WifiNetworkSpecifier.Builder().setSsid(ssid)
        if (password.isNotEmpty()) builder.setWpa2Passphrase(password)

        // The Mnemos SoftAP is a local provisioning link and intentionally has
        // no Internet capability. Binding the process makes HTTP calls to
        // 192.168.4.1 deterministic while the provisioning session is active.
        val request = NetworkRequest.Builder()
            .addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(android.net.NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(builder.build())
            .build()

        var replied = false
        val networkCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                boundNetwork = network
                connectivity.bindProcessToNetwork(network)
                if (!replied) {
                    replied = true
                    result.success(true)
                }
            }

            override fun onUnavailable() {
                if (!replied) {
                    replied = true
                    result.success(false)
                }
            }

            override fun onLost(network: Network) {
                if (boundNetwork == network) {
                    boundNetwork = null
                    connectivity.bindProcessToNetwork(null)
                }
            }
        }
        callback = networkCallback
        try {
            connectivity.requestNetwork(request, networkCallback)
        } catch (e: SecurityException) {
            callback = null
            if (!replied) result.error("WIFI_PERMISSION", e.message, null)
        }
    }

    @Suppress("DEPRECATION")
    private fun connectLegacy(
        ssid: String,
        password: String,
        result: MethodChannel.Result,
    ) {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val configuration = WifiConfiguration().apply {
            SSID = "\"$ssid\""
            if (password.isEmpty()) {
                allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            } else {
                preSharedKey = "\"$password\""
            }
        }
        val id = wifi.addNetwork(configuration)
        val ok = id >= 0 && wifi.disconnect() && wifi.enableNetwork(id, true) && wifi.reconnect()
        result.success(ok)
    }

    private fun disconnect() {
        val connectivity = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        callback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: Exception) {
            }
        }
        callback = null
        boundNetwork = null
        connectivity.bindProcessToNetwork(null)
    }

    override fun onDestroy() {
        pendingConnect = null
        pendingResult?.error("WIFI_CANCELLED", "Activity encerrada durante a conexão Wi-Fi", null)
        pendingResult = null
        pendingScanResult?.error("WIFI_SCAN_CANCELLED", "Activity encerrada durante a varredura Wi-Fi", null)
        pendingScanResult = null
        unregisterScanReceiver()
        disconnect()
        super.onDestroy()
    }
}
