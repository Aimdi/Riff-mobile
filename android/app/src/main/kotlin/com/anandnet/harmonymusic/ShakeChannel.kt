package com.anandnet.harmonymusic

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.SystemClock
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import io.flutter.plugin.common.EventChannel
import kotlin.math.sqrt

/**
 * "riff/shake": an event each time the phone is shaken, while Dart listens
 * (a timed sleep timer runs with "Shake to restart" on, see
 * lib/services/sleep_shake.dart), and a short buzz so you know it took.
 * Like riff/newpipe it needs no activity, so it works with the screen off
 * while music plays.
 *
 * A shake is two jolts past [JOLT_G] (gravity included, as AntennaPod
 * measures it) within [WINDOW_MS], so a single knock or the phone landing
 * on the bed doesn't count.
 */
object ShakeChannel : EventChannel.StreamHandler, SensorEventListener {
    /** Set by MainActivity. */
    var appContext: Context? = null

    private const val JOLT_G = 2.25f
    /** Below this the next jolt can start. */
    private const val CALM_G = 1.5f
    private const val JOLTS = 2
    private const val WINDOW_MS = 800L
    /** At most one shake this often. */
    private const val COOLDOWN_MS = 2000L
    private const val BUZZ_MS = 80L

    private var events: EventChannel.EventSink? = null
    private var inJolt = false
    private var jolts = 0
    private var firstJoltAt = 0L
    private var lastShakeAt = 0L

    private fun sensors(): SensorManager? =
        appContext?.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        events = sink
        inJolt = false
        jolts = 0
        val manager = sensors() ?: return
        val accelerometer = manager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER) ?: return
        // No handler: events arrive on the main thread, where the sink
        // must be used.
        manager.registerListener(this, accelerometer, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(arguments: Any?) {
        sensors()?.unregisterListener(this)
        events = null
    }

    override fun onSensorChanged(event: SensorEvent) {
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val g = sqrt(x * x + y * y + z * z) / SensorManager.GRAVITY_EARTH
        if (g < CALM_G) {
            inJolt = false
            return
        }
        if (g < JOLT_G || inJolt) return
        inJolt = true
        val now = SystemClock.elapsedRealtime()
        if (now - lastShakeAt < COOLDOWN_MS) return
        if (jolts == 0 || now - firstJoltAt > WINDOW_MS) {
            jolts = 0
            firstJoltAt = now
        }
        jolts++
        if (jolts < JOLTS) return
        jolts = 0
        lastShakeAt = now
        buzz()
        events?.success(null)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // Vibrator.vibrate(long) before Android 8.
    @Suppress("DEPRECATION")
    private fun buzz() {
        val context = appContext ?: return
        try {
            val vibrator = vibrator(context) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(
                    VibrationEffect.createOneShot(BUZZ_MS, VibrationEffect.DEFAULT_AMPLITUDE)
                )
            } else {
                vibrator.vibrate(BUZZ_MS)
            }
        } catch (_: Exception) {
        }
    }

    // VIBRATOR_SERVICE before Android 12.
    @Suppress("DEPRECATION")
    private fun vibrator(context: Context): Vibrator? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager)
                ?.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        }
}
