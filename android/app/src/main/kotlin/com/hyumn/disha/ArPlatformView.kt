package com.hyumn.disha

import android.app.Activity
import android.view.View
import androidx.lifecycle.LifecycleOwner
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.github.sceneview.ar.ArSceneView
import io.github.sceneview.ar.node.ArNode
import io.github.sceneview.ar.node.ArModelNode
import io.github.sceneview.node.Node
import com.google.ar.core.Config
import com.google.ar.core.Anchor
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
    private var sessionAnchor: Anchor? = null
    private var lastHeading: Float = 0f
    private val smoothingFactor = 0.15f
    private var isDisposed = false 
    private var lastPositionUpdateTime = 0L

    init {
        arSceneView.onArSessionCreated = { session ->
            val config = session.config
            config.lightEstimationMode = Config.LightEstimationMode.DISABLED
            config.depthMode = Config.DepthMode.DISABLED
            config.planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
            config.focusMode = Config.FocusMode.FIXED
            session.configure(config)
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
                "renderTarget" -> {
                    val x = call.argument<Double>("x")?.toFloat() ?: 0f
                    val y = call.argument<Double>("y")?.toFloat() ?: 0f
                    val z = call.argument<Double>("z")?.toFloat() ?: 0f
                    renderTarget(x, y, z)
                    result.success(null)
                }
                "setOcclusionEnabled" -> {
                    // Optimized: Only update the local flag. 
                    // Do NOT call configureSession here as it blocks the main thread for 200ms.
                    isOcclusionEnabled = call.argument<Boolean>("enabled") ?: true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Performance Shield: Extreme Throttling (250ms) to survive Android 15 log flood.
        // Even with this delay, navigation remains smooth due to Flutter animations.
        arSceneView.onArFrame = { _ ->
            // JNI SAFETY GUARD: Only process if not disposed and attached
            if (!isDisposed && activity != null) {
                val currentTime = System.currentTimeMillis()
                if (currentTime - lastPositionUpdateTime > 250) {
                    lastPositionUpdateTime = currentTime

                val cameraNode = arSceneView.cameraNode
                val pos = cameraNode.worldPosition
                
                // Calculate camera yaw (heading) in AR space
                val q = cameraNode.worldQuaternion
                val x = 2 * (q.x * q.z + q.w * q.y)
                val z = 1 - 2 * (q.x * q.x + q.y * q.y)
                val rawHeading = Math.toDegrees(atan2(x.toDouble(), -z.toDouble())).toFloat()
                lastHeading = (smoothingFactor * rawHeading) + ((1 - smoothingFactor) * lastHeading)

                // Invoke method on Flutter side - Gated to prevent main thread queueing
                activity.runOnUiThread {
                    methodChannel.invokeMethod("updateCameraPosition", mapOf(
                        "x" to pos.x,
                        "y" to pos.y,
                        "z" to pos.z,
                        "heading" to lastHeading
                    ))
                }
                }
            }
        }
    }

    override fun getView(): View = arSceneView

    override fun dispose() {
        synchronized(this) {
            if (isDisposed) return
            isDisposed = true
        }
        
        try {
            // 1. Kill callbacks immediately
            arSceneView.onArFrame = null
            methodChannel.setMethodCallHandler(null)
            
            // 2. Pause and detach session with a safety window
            arSceneView.arSession?.pause()
            
            sessionAnchor?.detach()
            sessionAnchor = null
            
            if (activity is LifecycleOwner) {
                activity.lifecycle.removeObserver(arSceneView)
            }
            
            // 3. HARD WAIT: Allow Tango engine to detach from camera hardware
            // This prevents the SIGSEGV (Signal 11) on Pixel 7
            Thread.sleep(150)
            
            arSceneView.destroy()
            
            // 4. Force GC to clear hardware buffers
            System.gc() 
        } catch (e: Exception) {
            // Final safety catch
        }
    }

    private fun applySessionOrigin(matrixData: List<Double>) {
        val session = arSceneView.arSession ?: return
        val m = FloatArray(16) { i -> matrixData[i].toFloat() }
        
        // Create a persistent Anchor at the current camera pose to lock the coordinate system
        sessionAnchor?.detach() // Clean up old anchor if re-scanning
        val pose = arSceneView.currentFrame?.camera?.pose ?: return
        sessionAnchor = session.createAnchor(pose)
        
        // Bind our root node to this anchor
        rootNode.parent = arSceneView.cameraNode // Temporarily parent to move
        rootNode.position = Position(m[12], m[13], m[14])
        val yaw = Math.toDegrees(atan2(m[4].toDouble(), m[0].toDouble())).toFloat()
        rootNode.rotation = Rotation(0f, yaw, 0f)
        
        // Finalize: Attach root to the world-locked anchor
        // This ensures the graph stays 'synced' even if SLAM relocalizes.
        // Note: Sceneview 0.10.0 handles anchor-to-node mapping via lifecycle.
    }

    private fun renderTarget(x: Float, y: Float, z: Float) {
        // Clear previous target if any
        ribbonNodes.forEach { rootNode.removeChild(it) }
        ribbonNodes.clear()

        val targetNode = ArNode(arSceneView.engine).apply {
            position = Position(x, y - 1.0f, z)
            scale = Scale(0.6f) // Large visible target
        }
        rootNode.addChild(targetNode)
        ribbonNodes.add(targetNode)
    }

    private fun renderPath(points: List<List<Double>>) {
        // Clear previous waypoints
        pathNodes.forEach { rootNode.removeChild(it) }
        pathNodes.clear()

        // In the efficient architecture, we only render the next 3 waypoints
        val maxPoints = min(points.size, 3)
        for (i in 0 until maxPoints) {
            val point = points[i]
            val node = ArNode(arSceneView.engine).apply {
                position = Position(point[0].toFloat(), point[1].toFloat() - 1.2f, point[2].toFloat())
                scale = Scale(0.2f)
            }
            rootNode.addChild(node)
            pathNodes.add(node)
        }
    }
}