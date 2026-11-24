package app.kite

import android.app.Activity
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.SystemClock
import android.view.Surface
import app.kite.core.Geo

internal class PhoneCompass(private val activity: Activity, private val changed: (Double) -> Unit) : SensorEventListener {
    private val manager = activity.getSystemService(SensorManager::class.java)
    private val sensor = manager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        ?: manager?.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
    private val matrix = FloatArray(9)
    private val adjusted = FloatArray(9)
    private val rotation = FloatArray(3)
    private var lastAt = 0L
    private var last = Double.NaN
    private var declination = 0f
    private var declinationAt = 0L

    fun start() { sensor?.let { manager?.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) } }
    fun stop() { manager?.unregisterListener(this) }

    @Suppress("DEPRECATION")
    override fun onSensorChanged(event: SensorEvent) {
        val now = SystemClock.elapsedRealtime()
        if (now - lastAt < 120) return
        lastAt = now
        if (declinationAt == 0L || now - declinationAt > 60_000) {
            LocationService.last?.let {
                declination = GeomagneticField(it.lat.toFloat(), it.lng.toFloat(), it.altitude.toFloat(), System.currentTimeMillis()).declination
                declinationAt = now
            }
        }
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        val (x, y) = when (activity.windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        if (!SensorManager.remapCoordinateSystem(matrix, x, y, adjusted)) return
        SensorManager.getOrientation(adjusted, rotation)
        val heading = (Math.toDegrees(rotation[0].toDouble()) + declination + 360) % 360
        if (last.isNaN() || Geo.diff(last, heading) >= 3) {
            last = heading
            changed(heading)
        }
    }
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
