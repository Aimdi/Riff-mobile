package com.anandnet.harmonymusic

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * "riff/network/online": whether the phone has a connection at all, and
 * whether the one in use costs data (mobile data, a metered hotspot), sent
 * as {online, metered} as Dart starts listening and again each time either
 * changes (see lib/services/offline_playback.dart): with none, songs that
 * need one are passed over, as Spotify's offline mode does, and on mobile
 * data too with Stream on Wi-Fi only. Like riff/network it needs no
 * activity, as play goes on with the screen off.
 *
 * Back online is sent at once; offline only once it has held for
 * [SETTLE_MS], so the moment between Wi-Fi going and mobile data taking
 * over doesn't count.
 */
object ConnectionChannel : EventChannel.StreamHandler {
    /** Set by MainActivity. */
    var appContext: Context? = null

    private const val SETTLE_MS = 2000L

    private val main = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var sent: Map<String, Boolean>? = null
    private var confirming = false

    private val confirmOffline = Runnable {
        confirming = false
        send(online())
    }

    private fun manager(): ConnectivityManager? =
        appContext?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    /** A network that reaches the internet; when it can't tell, yes. */
    @Suppress("DEPRECATION")
    private fun online(): Boolean {
        val manager = manager() ?: return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val network = manager.activeNetwork ?: return false
                manager.getNetworkCapabilities(network)
                    ?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true
            } else {
                manager.activeNetworkInfo?.isConnected == true
            }
        } catch (_: SecurityException) {
            true
        }
    }

    /**
     * Whether the connection in use costs data; when it can't tell, no, so
     * nothing is passed over by mistake.
     */
    private fun metered(): Boolean = try {
        manager()?.isActiveNetworkMetered ?: false
    } catch (_: SecurityException) {
        false
    }

    private fun send(online: Boolean) {
        val now = mapOf("online" to online, "metered" to (online && metered()))
        if (now == sent) return
        sent = now
        events?.success(now)
    }

    /** Main thread: online at once, offline once it has held. */
    private fun changed() {
        if (online()) {
            main.removeCallbacks(confirmOffline)
            confirming = false
            send(true)
        } else if (!confirming) {
            confirming = true
            main.postDelayed(confirmOffline, SETTLE_MS)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        onCancel(null)
        events = sink
        send(online())
        val manager = manager() ?: return
        val watch = object : ConnectivityManager.NetworkCallback() {
            // These come on a binder thread; the sink is used on the main one.
            override fun onAvailable(network: Network) {
                main.post { changed() }
            }

            override fun onLost(network: Network) {
                main.post { changed() }
            }

            override fun onCapabilitiesChanged(
                network: Network,
                capabilities: NetworkCapabilities
            ) {
                main.post { changed() }
            }
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                manager.registerDefaultNetworkCallback(watch)
            } else {
                manager.registerNetworkCallback(
                    NetworkRequest.Builder()
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        .build(),
                    watch
                )
            }
            callback = watch
        } catch (_: Exception) {
            // Can't follow it (no permission, too many callbacks): the first
            // answer stands.
        }
    }

    override fun onCancel(arguments: Any?) {
        main.removeCallbacks(confirmOffline)
        confirming = false
        callback?.let { watch ->
            try {
                manager()?.unregisterNetworkCallback(watch)
            } catch (_: Exception) {
                // Already gone.
            }
        }
        callback = null
        events = null
        sent = null
    }
}
