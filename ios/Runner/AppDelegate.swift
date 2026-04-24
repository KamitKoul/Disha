import Flutter
import UIKit
import ARKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  private var sessionOriginMatrix: simd_float4x4 = matrix_identity_float4x4
  private var routePath: [[Double]] = []
    
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let arChannel = FlutterMethodChannel(name: "com.koul.disha/ar_navigation",
                                          binaryMessenger: controller.binaryMessenger)
    
    arChannel.setMethodCallHandler({
      (call: FlutterMethodCall, result: @escaping FlutterResult) -> Void in
      
      switch call.method {
      case "setSessionOrigin":
        if let args = call.arguments as? [String: Any],
           let matrixData = args["matrix"] as? [Double],
           matrixData.count == 16 {
            self.applySessionOrigin(matrixData: matrixData)
            result(nil)
        } else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Matrix must be 16 doubles", details: nil))
        }
        
      case "renderPath":
        if let args = call.arguments as? [String: Any],
           let points = args["points"] as? [[Double]] {
            self.updateRoutePath(points: points)
            result(nil)
        } else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "Points list missing", details: nil))
        }
        
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func applySessionOrigin(matrixData: [Double]) {
    // Convert Double array to simd_float4x4
    var matrix = matrix_identity_float4x4
    for i in 0..<16 {
        let row = i / 4
        let col = i % 4
        matrix[col][row] = Float(matrixData[i]) // Column-major order conversion
    }
    
    self.sessionOriginMatrix = matrix
    
    // Logic: ARKit WORLD ALIGNMENT
    // In ARKit, we use setWorldOrigin to redefine the session's coordinate system.
    // This is significantly more robust than manual offsetting.
    NotificationCenter.default.post(name: NSNotification.Name("UpdateARWorldOrigin"), object: matrix)
    print("ARKit: Session origin updated via setWorldOrigin.")
  }

  private func updateRoutePath(points: [[Double]]) {
    self.routePath = points
    print("ARKit: Path updated with \(routePath.count) coordinates.")
    
    // Notify AR controllers to update path rendering
    NotificationCenter.default.post(name: NSNotification.Name("UpdateARPath"), object: nil)
  }
}
