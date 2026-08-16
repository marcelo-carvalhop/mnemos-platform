package br.com.flashcards.flashcards

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * On-demand BLE transport for Mnemos direct synchronization.
 *
 * BLE is intentionally not a second data model. It transports the same
 * mnemos.sync/v1 snapshot and mnemos.review-batch/v1 used by HTTP.
 */
class MnemosBleBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    companion object {
        private const val CHANNEL = "br.com.mnemos/device_ble"
        private const val PERMISSION_REQUEST = 4810
        private val SERVICE_UUID = UUID.fromString("6d6e656d-6f73-4001-8000-000000000001")
        private val CONTROL_UUID = UUID.fromString("6d6e656d-6f73-4001-8000-000000000002")
        private val DATA_UUID = UUID.fromString("6d6e656d-6f73-4001-8000-000000000003")
        private val STATUS_UUID = UUID.fromString("6d6e656d-6f73-4001-8000-000000000004")
        private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingPermissionAction: (() -> Unit)? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val busy = AtomicBoolean(false)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "scan" -> withPermissions(result) { scan(call, result) }
                "sync" -> withPermissions(result) { sync(call, result) }
                else -> result.notImplemented()
            }
        }
    }

    private fun requiredPermissions(): Array<String> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        // BLE scanning before Android 12 is tied to location permission.
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

    private fun withPermissions(result: MethodChannel.Result, action: () -> Unit) {
        val missing = requiredPermissions().filter {
            activity.checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isEmpty()) {
            action()
            return
        }
        if (pendingPermissionAction != null) {
            result.error("BLE_BUSY", "Já existe uma solicitação Bluetooth em andamento", null)
            return
        }
        pendingPermissionAction = action
        pendingPermissionResult = result
        activity.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST) return false
        val action = pendingPermissionAction
        val result = pendingPermissionResult
        pendingPermissionAction = null
        pendingPermissionResult = null
        if (action == null || result == null) return true
        if (grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
            action()
        } else {
            result.error("BLE_PERMISSION", "Permissão de Bluetooth foi negada", null)
        }
        return true
    }

    private fun adapter(): BluetoothAdapter? {
        val manager = activity.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        return manager.adapter
    }

    private fun scan(call: MethodCall, result: MethodChannel.Result) {
        if (!busy.compareAndSet(false, true)) {
            result.error("BLE_BUSY", "O Bluetooth já está sendo utilizado", null)
            return
        }
        val timeout = (call.argument<Int>("timeoutMs") ?: 5000).coerceIn(1000, 15000)
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) {
            busy.set(false)
            result.error("BLE_DISABLED", "Ative o Bluetooth para localizar o Mnemos", null)
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            busy.set(false)
            result.error("BLE_UNAVAILABLE", "Bluetooth LE indisponível neste aparelho", null)
            return
        }

        val found = linkedMapOf<String, Map<String, Any>>()
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                val name = try { scanResult.device.name } catch (_: SecurityException) { null }
                    ?: scanResult.scanRecord?.deviceName
                    ?: return
                if (!name.startsWith("MNEMOS-")) return
                val deviceId = name.removePrefix("MNEMOS-")
                val old = found[deviceId]
                if (old == null || scanResult.rssi > (old["rssi"] as Int)) {
                    found[deviceId] = mapOf(
                        "deviceId" to deviceId,
                        "name" to name,
                        "rssi" to scanResult.rssi,
                    )
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Handler(Looper.getMainLooper()).post {
                    try { scanner.stopScan(this) } catch (_: Exception) {}
                    busy.set(false)
                    result.error("BLE_SCAN_FAILED", "Falha ao procurar o Mnemos por Bluetooth ($errorCode)", null)
                }
            }
        }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanner.startScan(listOf(filter), settings, callback)
        Handler(Looper.getMainLooper()).postDelayed({
            try { scanner.stopScan(callback) } catch (_: Exception) {}
            if (busy.getAndSet(false)) result.success(found.values.toList())
        }, timeout.toLong())
    }

    private sealed class Event {
        data class Connected(val gatt: BluetoothGatt) : Event()
        data class Failed(val message: String) : Event()
        data object Services : Event()
        data class Mtu(val value: Int) : Event()
        data class Write(val uuid: UUID, val ok: Boolean) : Event()
        data class Descriptor(val ok: Boolean) : Event()
        data class Notification(val uuid: UUID, val value: ByteArray) : Event()
    }

    private fun sync(call: MethodCall, result: MethodChannel.Result) {
        if (!busy.compareAndSet(false, true)) {
            result.error("BLE_BUSY", "O Bluetooth já está sendo utilizado", null)
            return
        }
        val deviceId = call.argument<String>("deviceId")?.trim().orEmpty()
        val snapshot = call.argument<String>("snapshot").orEmpty()
        if (deviceId.isEmpty() || snapshot.isEmpty()) {
            busy.set(false)
            result.error("BLE_ARGUMENT", "Identificador ou snapshot ausente", null)
            return
        }
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) {
            busy.set(false)
            result.error("BLE_DISABLED", "Ative o Bluetooth para sincronizar", null)
            return
        }

        Thread {
            var gatt: BluetoothGatt? = null
            try {
                val device = findDevice(adapter, deviceId, 7000)
                    ?: throw IllegalStateException("O Mnemos $deviceId não foi encontrado. Abra Sincronização no terminal.")
                val queue = LinkedBlockingQueue<Event>()
                val callback = object : BluetoothGattCallback() {
                    override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                        if (status == BluetoothGatt.GATT_SUCCESS && newState == BluetoothProfile.STATE_CONNECTED) {
                            queue.offer(Event.Connected(g))
                        } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                            queue.offer(Event.Failed("A conexão Bluetooth com o Mnemos foi encerrada."))
                        }
                    }
                    override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                        if (status == BluetoothGatt.GATT_SUCCESS) queue.offer(Event.Services)
                        else queue.offer(Event.Failed("O serviço de sincronização do Mnemos não foi encontrado."))
                    }
                    override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
                        queue.offer(Event.Mtu(if (status == BluetoothGatt.GATT_SUCCESS) mtu else 23))
                    }
                    @Suppress("DEPRECATION")
                    override fun onCharacteristicWrite(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, status: Int) {
                        queue.offer(Event.Write(characteristic.uuid, status == BluetoothGatt.GATT_SUCCESS))
                    }
                    @Suppress("DEPRECATION")
                    override fun onDescriptorWrite(g: BluetoothGatt, descriptor: BluetoothGattDescriptor, status: Int) {
                        queue.offer(Event.Descriptor(status == BluetoothGatt.GATT_SUCCESS))
                    }
                    @Suppress("DEPRECATION")
                    override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
                        queue.offer(Event.Notification(characteristic.uuid, characteristic.value.copyOf()))
                    }
                    override fun onCharacteristicChanged(g: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
                        queue.offer(Event.Notification(characteristic.uuid, value.copyOf()))
                    }
                }

                @Suppress("DEPRECATION")
                val opened = device.connectGatt(activity, false, callback, android.bluetooth.BluetoothDevice.TRANSPORT_LE)
                gatt = opened
                waitFor(queue, 12000) { it is Event.Connected }
                if (!opened.discoverServices()) throw IllegalStateException("Não foi possível consultar os serviços Bluetooth do Mnemos.")
                waitFor(queue, 8000) { it is Event.Services }
                val service = opened.getService(SERVICE_UUID)
                    ?: throw IllegalStateException("Firmware sem Mnemos BLE Sync Service.")
                val control = service.getCharacteristic(CONTROL_UUID)
                    ?: throw IllegalStateException("Characteristic de controle ausente.")
                val data = service.getCharacteristic(DATA_UUID)
                    ?: throw IllegalStateException("Characteristic de dados ausente.")
                val status = service.getCharacteristic(STATUS_UUID)
                    ?: throw IllegalStateException("Characteristic de status ausente.")

                var mtu = 23
                if (opened.requestMtu(247)) {
                    val ev = waitFor(queue, 4000) { it is Event.Mtu } as Event.Mtu
                    mtu = ev.value
                }
                enableNotify(opened, status, queue)
                enableNotify(opened, data, queue)

                val payload = snapshot.toByteArray(StandardCharsets.UTF_8)
                writeText(opened, control, JSONObject().put("op", "begin").put("size", payload.size).toString(), queue)
                val chunkSize = (mtu - 3).coerceIn(20, 244)
                var offset = 0
                while (offset < payload.size) {
                    val end = minOf(offset + chunkSize, payload.size)
                    writeBytes(opened, data, payload.copyOfRange(offset, end), queue)
                    offset = end
                }
                writeText(opened, control, JSONObject().put("op", "commit").toString(), queue)
                val committed = waitStatus(queue, "snapshot_committed", 15000)
                val sentCards = committed.optInt("cards", JSONObject(snapshot).optJSONArray("cards")?.length() ?: 0)

                writeText(opened, control, JSONObject().put("op", "reviews").toString(), queue)
                val reviewsBuffer = ArrayList<Byte>()
                var reviewCount = 0
                val deadline = System.currentTimeMillis() + 15000
                var finished = false
                while (!finished && System.currentTimeMillis() < deadline) {
                    when (val event = queue.poll(1500, TimeUnit.MILLISECONDS)) {
                        is Event.Notification -> {
                            if (event.uuid == DATA_UUID) {
                                for (b in event.value) reviewsBuffer.add(b)
                            } else if (event.uuid == STATUS_UUID) {
                                val obj = JSONObject(String(event.value, StandardCharsets.UTF_8))
                                when (obj.optString("event")) {
                                    "reviews_end" -> {
                                        reviewCount = obj.optInt("count", 0)
                                        finished = true
                                    }
                                    "error" -> throw IllegalStateException(obj.optString("message", "Falha na sincronização Bluetooth."))
                                }
                            }
                        }
                        is Event.Failed -> throw IllegalStateException(event.message)
                        else -> Unit
                    }
                }
                if (!finished) throw IllegalStateException("O Mnemos não concluiu o envio das revisões.")
                val reviewsJson = String(ByteArray(reviewsBuffer.size) { reviewsBuffer[it] }, StandardCharsets.UTF_8)
                writeText(opened, control, JSONObject().put("op", "reviews_ack").toString(), queue)

                opened.disconnect()
                opened.close()
                gatt = null
                busy.set(false)
                activity.runOnUiThread {
                    result.success(
                        mapOf(
                            "deviceId" to deviceId,
                            "sentCards" to sentCards,
                            "receivedReviews" to reviewCount,
                            "reviewsJson" to reviewsJson,
                        )
                    )
                }
            } catch (e: Exception) {
                try { gatt?.disconnect() } catch (_: Exception) {}
                try { gatt?.close() } catch (_: Exception) {}
                busy.set(false)
                activity.runOnUiThread {
                    result.error("BLE_SYNC_FAILED", e.message ?: "Falha na sincronização Bluetooth", null)
                }
            }
        }.start()
    }

    private fun findDevice(adapter: BluetoothAdapter, deviceId: String, timeoutMs: Long): android.bluetooth.BluetoothDevice? {
        val scanner = adapter.bluetoothLeScanner ?: return null
        val lock = Object()
        var found: android.bluetooth.BluetoothDevice? = null
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                val name = try { result.device.name } catch (_: SecurityException) { null }
                    ?: result.scanRecord?.deviceName
                    ?: return
                if (name == "MNEMOS-$deviceId") {
                    synchronized(lock) {
                        found = result.device
                        lock.notifyAll()
                    }
                }
            }
        }
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE_UUID)).build()
        scanner.startScan(listOf(filter), ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), callback)
        synchronized(lock) {
            if (found == null) lock.wait(timeoutMs)
        }
        try { scanner.stopScan(callback) } catch (_: Exception) {}
        return found
    }

    private fun waitFor(queue: LinkedBlockingQueue<Event>, timeoutMs: Long, predicate: (Event) -> Boolean): Event {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val event = queue.poll(500, TimeUnit.MILLISECONDS) ?: continue
            if (event is Event.Failed) throw IllegalStateException(event.message)
            if (predicate(event)) return event
        }
        throw IllegalStateException("Tempo esgotado aguardando resposta Bluetooth do Mnemos.")
    }

    private fun waitStatus(queue: LinkedBlockingQueue<Event>, expected: String, timeoutMs: Long): JSONObject {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            val event = queue.poll(800, TimeUnit.MILLISECONDS) ?: continue
            if (event is Event.Failed) throw IllegalStateException(event.message)
            if (event !is Event.Notification || event.uuid != STATUS_UUID) continue
            val obj = JSONObject(String(event.value, StandardCharsets.UTF_8))
            if (obj.optString("event") == "error") {
                throw IllegalStateException(obj.optString("message", "Falha no Mnemos."))
            }
            if (obj.optString("event") == expected) return obj
        }
        throw IllegalStateException("O Mnemos não confirmou a operação Bluetooth.")
    }

    private fun enableNotify(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, queue: LinkedBlockingQueue<Event>) {
        if (!gatt.setCharacteristicNotification(characteristic, true)) {
            throw IllegalStateException("Não foi possível habilitar notificações Bluetooth.")
        }
        val descriptor = characteristic.getDescriptor(CCCD_UUID)
            ?: throw IllegalStateException("Descriptor de notificação Bluetooth ausente.")
        val value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (gatt.writeDescriptor(descriptor, value) != android.bluetooth.BluetoothStatusCodes.SUCCESS) {
                throw IllegalStateException("Não foi possível configurar notificações Bluetooth.")
            }
        } else {
            @Suppress("DEPRECATION")
            descriptor.value = value
            @Suppress("DEPRECATION")
            if (!gatt.writeDescriptor(descriptor)) throw IllegalStateException("Não foi possível configurar notificações Bluetooth.")
        }
        val event = waitFor(queue, 5000) { it is Event.Descriptor } as Event.Descriptor
        if (!event.ok) throw IllegalStateException("O Android rejeitou as notificações Bluetooth.")
    }

    private fun writeText(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, text: String, queue: LinkedBlockingQueue<Event>) {
        writeBytes(gatt, characteristic, text.toByteArray(StandardCharsets.UTF_8), queue)
    }

    private fun writeBytes(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray, queue: LinkedBlockingQueue<Event>) {
        val started = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            gatt.writeCharacteristic(characteristic, value, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT) == android.bluetooth.BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            characteristic.value = value
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(characteristic)
        }
        if (!started) throw IllegalStateException("Não foi possível enviar dados Bluetooth ao Mnemos.")
        val event = waitFor(queue, 7000) { it is Event.Write && it.uuid == characteristic.uuid } as Event.Write
        if (!event.ok) throw IllegalStateException("O Mnemos rejeitou um bloco da transferência Bluetooth.")
    }

}
