package com.anandnet.harmonymusic

import android.content.Context
import android.net.ConnectivityManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * "riff/network": whether the connection in use costs data (mobile data, a
 * metered hotspot), so "Download new episodes: On Wi-Fi" waits for Wi-Fi
 * (lib/services/network_kind.dart). Needs no activity, like riff/newpipe:
 * the Inbox can refresh with the app in the background.
 */
object NetworkChannel : MethodChannel.MethodCallHandler {
    /** Set by MainActivity. */
    var appContext: Context? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "isMetered") {
            result.notImplemented()
            return
        }
        // Can't tell: say metered, so nothing big goes over mobile data.
        val manager =
            appContext?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (manager == null) {
            result.success(true)
            return
        }
        try {
            result.success(manager.isActiveNetworkMetered)
        } catch (e: SecurityException) {
            result.success(true)
        }
    }
}
