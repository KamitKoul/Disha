import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

class ArService {
  static const MethodChannel _channel = MethodChannel('com.hyumn.disha/ar_navigation');
  
  // Singleton pattern
  static final ArService _instance = ArService._internal();
  factory ArService() => _instance;
  
  Function(Vector3, double)? _onCameraUpdate;
  
  ArService._internal() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'updateCameraPosition') {
        final Map<dynamic, dynamic> args = call.arguments;
        final position = Vector3(
          args['x'].toDouble(),
          args['y'].toDouble(),
          args['z'].toDouble(),
        );
        final double heading = args['heading']?.toDouble() ?? 0.0;
        _onCameraUpdate?.call(position, heading);
      }
    });
  }

  void setOnCameraUpdate(Function(Vector3, double) callback) {
    _onCameraUpdate = callback;
  }

  void dispose() {
    _onCameraUpdate = null;
  }

  Future<void> setSessionOrigin(Matrix4 transform) async {
    final List<double> matrixList = transform.storage.toList();
    
    // Retry logic to handle hardware warmup delay
    for (int i = 0; i < 3; i++) {
      try {
        await _channel.invokeMethod('setSessionOrigin', {'matrix': matrixList});
        return; // Success!
      } on MissingPluginException {
        // Native view not ready yet, wait and retry
        await Future.delayed(Duration(milliseconds: 500 * (i + 1)));
      } catch (e) {
        debugPrint("AR Sync Error: $e");
        return;
      }
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
      // For the new efficient architecture, we simplify the path to just the next turn points
      // This reduces native rendering load significantly.
      final List<List<double>> pointsList = points.map((v) => [v.x, v.y, v.z]).toList();
      await _channel.invokeMethod('renderPath', {
        'points': pointsList,
        'color': color,
        'thickness': 0.15,
        'pulsing': true,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to render path: '${e.message}'.");
    }
  }

  /// Renders a single high-visibility target marker at the specified point.
  /// Used for the "Vector HUD" architecture to show the immediate next destination.
  Future<void> renderTarget(Vector3 point, {String color = '#EA4335'}) async {
    try {
      await _channel.invokeMethod('renderTarget', {
        'x': point.x,
        'y': point.y,
        'z': point.z,
        'color': color,
      });
    } on PlatformException catch (e) {
      debugPrint("Failed to render target: '${e.message}'.");
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
