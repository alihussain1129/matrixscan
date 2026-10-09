package com.exaltedcoding.exalted

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiConfiguration
import android.net.wifi.WifiManager
import android.media.AudioManager
import android.media.ToneGenerator
import android.net.wifi.WifiNetworkSuggestion
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var scanToneGenerator: ToneGenerator? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "connect" -> connect(call, result)
                    "openWifiSettings" -> openWifiSettings(result)
                    else -> result.notImplemented()
                }
            }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FEEDBACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "beep" -> beep(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun beep(result: MethodChannel.Result) {
        try {
            val tone = scanToneGenerator
                ?: ToneGenerator(AudioManager.STREAM_MUSIC, 100).also {
                    scanToneGenerator = it
                }
            tone.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
            result.success(true)
        } catch (e: Exception) {
            result.error("sound_failed", e.message, null)
        }
    }

    override fun onDestroy() {
        scanToneGenerator?.release()
        scanToneGenerator = null
        super.onDestroy()
    }

    private fun connect(call: MethodCall, result: MethodChannel.Result) {
        val ssid = call.argument<String>("ssid")
        val password = call.argument<String>("password") ?: ""
        val security = call.argument<String>("security") ?: "wpa"
        val hidden = call.argument<Boolean>("hidden") ?: false

        if (ssid.isNullOrEmpty()) {
            result.error("bad_args", "Missing network name", null)
            return
        }
        if (pendingResult != null) {
            result.error("busy", "Another Wi-Fi request is running", null)
            return
        }

        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.R ->
                    addWithSystemPanel(result, ssid, password, security, hidden)
                // Android 10 has no supported way for a normal app to join.
                Build.VERSION.SDK_INT == Build.VERSION_CODES.Q ->
                    result.success("manual")
                else -> connectLegacy(result, ssid, password, security, hidden)
            }
        } catch (e: IllegalArgumentException) {
            pendingResult = null
            result.error("bad_password", e.message, null)
        } catch (e: Exception) {
            pendingResult = null
            result.error("failed", e.message, null)
        }
    }

    // Android 11+: the system asks the user to save the network.
    @Suppress("DEPRECATION")
    private fun addWithSystemPanel(
        result: MethodChannel.Result,
        ssid: String,
        password: String,
        security: String,
        hidden: Boolean,
    ) {
        val builder = WifiNetworkSuggestion.Builder()
            .setSsid(ssid)
            .setIsHiddenSsid(hidden)
        when (security) {
            "open" -> {}
            "wpa" -> builder.setWpa2Passphrase(password)
            "wpa3" -> builder.setWpa3Passphrase(password)
            else -> {
                // WEP cannot be added through this panel.
                result.success("manual")
                return
            }
        }
        val intent = Intent(Settings.ACTION_WIFI_ADD_NETWORKS).apply {
            putParcelableArrayListExtra(
                Settings.EXTRA_WIFI_NETWORK_LIST,
                arrayListOf(builder.build()),
            )
        }
        pendingResult = result
        startActivityForResult(intent, REQUEST_ADD_WIFI)
    }

    // Android 7-9: add and enable the network directly.
    @Suppress("DEPRECATION")
    private fun connectLegacy(
        result: MethodChannel.Result,
        ssid: String,
        password: String,
        security: String,
        hidden: Boolean,
    ) {
        if (security == "wpa3") {
            result.success("manual")
            return
        }
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
        if (wifi == null) {
            result.error("unavailable", "Wi-Fi is not available on this device", null)
            return
        }
        if (!wifi.isWifiEnabled) wifi.isWifiEnabled = true

        val config = WifiConfiguration()
        config.SSID = "\"" + ssid + "\""
        config.hiddenSSID = hidden
        when (security) {
            "open" -> config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
            "wep" -> {
                config.allowedKeyManagement.set(WifiConfiguration.KeyMgmt.NONE)
                config.allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.OPEN)
                config.allowedAuthAlgorithms.set(WifiConfiguration.AuthAlgorithm.SHARED)
                config.wepKeys[0] = if (isWepHex(password)) password else "\"" + password + "\""
                config.wepTxKeyIndex = 0
            }
            else -> config.preSharedKey = "\"" + password + "\""
        }

        val netId = wifi.addNetwork(config)
        if (netId == -1) {
            result.error("failed", "Android refused to add the network", null)
            return
        }
        wifi.disconnect()
        val enabled = wifi.enableNetwork(netId, true)
        wifi.reconnect()
        if (enabled) {
            result.success("connecting")
        } else {
            result.error("failed", "Android could not enable the network", null)
        }
    }

    private fun isWepHex(key: String): Boolean {
        val lengthOk = key.length == 10 || key.length == 26 || key.length == 32
        return lengthOk && key.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }
    }

    private fun openWifiSettings(result: MethodChannel.Result) {
        try {
            startActivity(Intent(Settings.ACTION_WIFI_SETTINGS))
            result.success(null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST_ADD_WIFI) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }
        val result = pendingResult
        pendingResult = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK) {
            result.success("cancelled")
            return
        }
        val codes = data?.getIntegerArrayListExtra(Settings.EXTRA_WIFI_NETWORK_RESULT_LIST)
        val first = codes?.firstOrNull()
        if (first == null ||
            first == Settings.ADD_WIFI_RESULT_SUCCESS ||
            first == Settings.ADD_WIFI_RESULT_ALREADY_EXISTS
        ) {
            result.success("saved")
        } else {
            result.error("failed", "Android could not save the network", null)
        }
    }

    private companion object {
        const val CHANNEL = "com.exaltedcoding.exalted/wifi"
        const val FEEDBACK_CHANNEL = "com.exaltedcoding.exalted/scan_feedback"
        const val REQUEST_ADD_WIFI = 4711
    }
}

