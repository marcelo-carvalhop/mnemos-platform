package br.com.flashcards.flashcards

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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

    private var callback: ConnectivityManager.NetworkCallback? = null
    private var boundNetwork: Network? = null
    private var pendingConnect: Pair<String, String>? = null
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
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
                else -> result.notImplemented()
            }
        }
    }

    private fun requiredWifiPermission(): String? = when {
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU ->
            Manifest.permission.NEARBY_WIFI_DEVICES
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ->
            Manifest.permission.ACCESS_FINE_LOCATION
        else -> null
    }

    private fun hasWifiRuntimePermission(): Boolean {
        val permission = requiredWifiPermission() ?: return true
        return checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    @Suppress("DEPRECATION")
    private fun currentSsid(): String? {
        if (!hasWifiRuntimePermission()) return null
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

        val permission = requiredWifiPermission()
        if (permission != null && !hasWifiRuntimePermission()) {
            if (pendingResult != null) {
                result.error("WIFI_BUSY", "Já existe uma solicitação Wi-Fi em andamento", null)
                return
            }
            pendingConnect = ssid to password
            pendingResult = result
            requestPermissions(arrayOf(permission), wifiPermissionRequestCode)
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

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != wifiPermissionRequestCode) {
            super.onRequestPermissionsResult(requestCode, permissions, grantResults)
            return
        }

        val pair = pendingConnect
        val result = pendingResult
        pendingConnect = null
        pendingResult = null

        if (pair == null || result == null) return
        if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
            connectWithPermission(pair.first, pair.second, result)
        } else {
            result.error(
                "WIFI_PERMISSION",
                "Permissão de dispositivos Wi-Fi próximos negada",
                null,
            )
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
        disconnect()
        super.onDestroy()
    }
}
