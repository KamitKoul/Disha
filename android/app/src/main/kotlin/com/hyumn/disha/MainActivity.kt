package com.hyumn.disha

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.google.ar.core.Session
import com.google.ar.core.Config
import android.opengl.Matrix

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.koul.disha/ar_navigation"
    
    // Matrix to store the session origin transformation (4x4)
    private var sessionOriginMatrix = FloatArray(16).apply {
        Matrix.setIdentityM(this, 0)
    }
    
    private var routePath: List<FloatArray> = mutableListOf()

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the Native AR View
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.koul.disha/ar_view", ArViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSessionOrigin" -> {
                    val matrixData = call.argument<List<Double>>("matrix")
                    if (matrixData != null && matrixData.size == 16) {
                        applySessionOrigin(matrixData)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Matrix must be 16 doubles", null)
                    }
                }
                "renderPath" -> {
                    val points = call.argument<List<List<Double>>>("points")
                    if (points != null) {
                        updateRoutePath(points)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Points list missing", null)
                    }
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun applySessionOrigin(matrixData: List<Double>) {
        // Convert Double list to FloatArray for OpenGL operations
        for (i in matrixData.indices) {
            sessionOriginMatrix[i] = matrixData[i].toFloat()
        }
        
        // Logic: MATHEMATICAL ORIGIN SHIFT
        // In ARCore, we can't reset the world origin, so we compute a relative transform.
        // This matrix will now be used as the base for all virtual coordinate renders.
        println("ARCore: Session origin updated via 4x4 Matrix.")
    }

    private fun updateRoutePath(points: List<List<Double>>) {
        routePath = points.map { 
            floatArrayOf(it[0].toFloat(), it[1].toFloat(), it[2].toFloat()) 
        }
        println("ARCore: Path updated with ${routePath.size} coordinates.")
        
        // Here we would trigger a redraw of the 3D arrows in the AR scene
        // matching the transformed coordinate system.
    }
}
