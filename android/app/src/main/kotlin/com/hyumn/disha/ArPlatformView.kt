package com.hyumn.disha

import android.app.Activity
import android.view.View
import android.widget.ImageView
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.github.sceneview.ar.ArSceneView
import io.github.sceneview.ar.node.*
import io.github.sceneview.node.*
import com.google.ar.core.Config
import io.github.sceneview.math.Position
import io.github.sceneview.math.Rotation
import io.github.sceneview.math.Scale
import kotlin.math.*

class ArPlatformView(
    private val activity: Activity,
    id: Int,
    creationParams: Map<String?, Any?>?,
    messenger: BinaryMessenger
) : PlatformView {

    private val arSceneView = ArSceneView(activity)
    private val methodChannel = MethodChannel(messenger, "com.hyumn.disha/ar_navigation")

    private var isOcclusionEnabled = creationParams?.get("enableOcclusion") as? Boolean ?: true
    
    // Imperative root node for overall alignment
    private val rootNode = ArNode(arSceneView.engine)
    private val pathNodes = mutableListOf<ArNode>()
    private val ribbonNodes = mutableListOf<ArNode>() 
    private var lastPositionUpdateTime = 0L

    init {
        arSceneView.configureSession { _, config ->
            config.lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
            config.depthMode = if (isOcclusionEnabled) Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
        }

        // Synchronize with Activity lifecycle for camera feed
        if (activity is LifecycleOwner) {
            activity.lifecycle.addObserver(arSceneView)
        }

        arSceneView.addChild(rootNode)

        methodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "setSessionOrigin" -> {
                    val matrixData = call.argument<List<Double>>("matrix")
                    if (matrixData?.size == 16) {
                        applySessionOrigin(matrixData)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Matrix missing", null)
                    }
                }
                "renderPath" -> {
                    val points = call.argument<List<List<Double>>>("points")
                    if (points != null) {
                        renderPath(points)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Points missing", null)
                    }
                }
                "setOcclusionEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    isOcclusionEnabled = enabled
                    arSceneView.configureSession { _, config ->
                        config.depthMode = if (isOcclusionEnabled) Config.DepthMode.AUTOMATIC else Config.DepthMode.DISABLED
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Real-time camera position reporting (Optimized to 100ms for smooth movement)
        arSceneView.onArFrame = { _ ->
            val currentTime = System.currentTimeMillis()
            if (currentTime - lastPositionUpdateTime > 100) {
                lastPositionUpdateTime = currentTime

                val cameraNode = arSceneView.cameraNode
                val pos = cameraNode.worldPosition
                
                // Invoke method on Flutter side
                activity.runOnUiThread {
                    methodChannel.invokeMethod("updateCameraPosition", mapOf(
                        "x" to pos.x,
                        "y" to pos.y,
                        "z" to pos.z
                    ))
                }
            }
        }
    }

    override fun getView(): View = arSceneView

    override fun dispose() {
        if (activity is LifecycleOwner) {
            activity.lifecycle.removeObserver(arSceneView)
        }
    }

    private fun applySessionOrigin(matrixData: List<Double>) {
        val m = FloatArray(16) { i -> matrixData[i].toFloat() }

        // Position alignment
        rootNode.position = Position(m[12], m[13], m[14])

        // Yaw Rotation alignment
        val yaw = Math.toDegrees(Math.atan2(m[4].toDouble(), m[0].toDouble())).toFloat()
        rootNode.rotation = Rotation(0f, yaw, 0f)

        println("AR Native 0.10.0: World anchored (Yaw: $yaw)")
    }

    private fun renderPath(points: List<List<Double>>) {
        // Clear previous waypoints and ribbons
        pathNodes.forEach { rootNode.removeChild(it) }
        pathNodes.clear()
        ribbonNodes.forEach { rootNode.removeChild(it) }
        ribbonNodes.clear()

        points.indices.forEach { i ->
            val point = points[i]
            
            // 1. Render Path Node (Small base marker)
            val node = ArModelNode(arSceneView.engine).apply {
                position = Position(point[0].toFloat(), point[1].toFloat() - 1.2f, point[2].toFloat())
                scale = Scale(0.15f) // Smaller, cleaner dots
            }
            rootNode.addChild(node)
            pathNodes.add(node)

            // 2. Render Google Maps Style Directional Ribbon
            if (i < points.size - 1) {
                val nextPoint = points[i + 1]
                val dx = (nextPoint[0] - point[0]).toFloat()
                val dy = (nextPoint[1] - point[1]).toFloat()
                val dz = (nextPoint[2] - point[2]).toFloat()
                val distance = sqrt(dx * dx + dy * dy + dz * dz)

                // Render multiple small "arrows" along the segment for a premium feel
                val numArrows = max(1, (distance / 1.5).toInt()) // One arrow every 1.5 meters
                for (j in 0 until numArrows) {
                    val lerp = (j.toFloat() / numArrows)
                    val ribbon = ArModelNode(arSceneView.engine).apply {
                        position = Position(
                            (point[0] + dx * lerp).toFloat(),
                            ((point[1] + dy * lerp).toFloat()) - 1.25f,
                            (point[2] + dz * lerp).toFloat()
                        )
                        
                        val angle = Math.toDegrees(atan2(dx.toDouble(), dz.toDouble())).toFloat()
                        rotation = Rotation(0f, angle, 0f)
                        // Scale to look like a wide floor arrow
                        scale = Scale(0.4f, 0.05f, 0.8f) 
                    }
                    rootNode.addChild(ribbon)
                    ribbonNodes.add(ribbon)
                }
            }
        }
        println("AR Native: Rendering ${ribbonNodes.size} floor arrows along the path.")
    }
}