import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';
import '../utils/path_simplifier.dart';

class ArService {
  static const MethodChannel _channel = MethodChannel('com.hyumn.disha/ar_navigation');
  
  // Singleton pattern
  static final ArService _instance = ArService._internal();
  factory ArService() => _instance;
  
  Function(Vector3)? _onCameraUpdate;
  
  ArService._internal() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateCameraPosition') {
        final Map<dynamic, dynamic> args = call.arguments;
        final position = Vector3(
          args['x'].toDouble(),
          args['y'].toDouble(),
          args['z'].toDouble(),
        );
        _onCameraUpdate?.call(position);
      }
    });
  }

  void setOnCameraUpdate(Function(Vector3) callback) {
    _onCameraUpdate = callback;
  }

  void dispose() {
    _onCameraUpdate = null;
  }

  Future<void> setSessionOrigin(Matrix4 transform) async {
    try {
      // Small delay to ensure native view is ready
      await Future.delayed(const Duration(milliseconds: 500));
      final List<double> matrixList = transform.storage.toList();
      await _channel.invokeMethod('setSessionOrigin', {'matrix': matrixList});
    } on PlatformException catch (e) {
      debugPrint("Failed to set session origin: '${e.message}'.");
    }
  }

  Future<void> setOcclusionEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setOcclusionEnabled', {'enabled': enabled});
    } on PlatformException catch (e) {
      debugPrint("Failed to set occlusion: '${e.message}'.");
    }
  }

  Future<void> renderPath(List<Vector3> points, {String color = '#4285F4'}) async {
    if (points.isEmpty) return;
    
    try {
      // Optimization: Simplify the path before sending to native AR engine
      // Low epsilon (0.05m) preserves turn detail while removing redundant straight-line points
      final simplifiedPoints = PathSimplifier.simplify(points, epsilon: 0.05);
      
      final List<List<double>> pointsList = simplifiedPoints.map((v) => [v.x, v.y, v.z]).toList();
      await _channel.invokeMethod('renderPath', {
        'points': pointsList,
        'color': color, // Customizable color (defaults to Google Blue)
        'thickness': 0.18,  // Slightly thicker for better visibility
        'pulsing': true,    // Dynamic pulsing effect
        'dashed': false,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to render path: '${e.message}'.");
    }
  }

  /// Renders breadcrumb markers at each recorded mapping point.
  /// Each point becomes a small glowing sphere in AR space,
  /// giving the user live visual feedback that AR is tracking their walk.
  Future<void> renderBreadcrumbs(List<Vector3> points) async {
    if (points.isEmpty) return;
    
    try {
      final List<List<double>> pointsList = points.map((v) => [v.x, v.y, v.z]).toList();
      await _channel.invokeMethod('renderBreadcrumbs', {
        'points': pointsList,
        'color': '#4ADE80',   // Green breadcrumb
        'radius': 0.06,       // 6cm sphere — visible but not obstructive
        'glowing': true,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to render breadcrumbs: '${e.message}'.");
    }
  }

  /// Clears all breadcrumb markers from the AR scene.
  Future<void> clearBreadcrumbs() async {
    try {
      await _channel.invokeMethod('clearBreadcrumbs');
    } on PlatformException catch (e) {
      debugPrint("Failed to clear breadcrumbs: '${e.message}'.");
    }
  }
}
