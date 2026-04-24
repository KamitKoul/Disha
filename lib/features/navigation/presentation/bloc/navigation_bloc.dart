import 'dart:convert';
import 'dart:math' as math_dart;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:equatable/equatable.dart';
import 'package:vector_math/vector_math_64.dart';
import '../../domain/models/node.dart';
import '../../domain/a_star_router.dart';
import '../../../../core/utils/gps_converter.dart';
import '../../../../core/services/map_service.dart';
import '../../../../core/utils/spatial_hash.dart';
import '../../../../core/utils/path_simplifier.dart';

part 'navigation_event.dart';
part 'navigation_state.dart';

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {

  final Map<String, Node> graph;
  final SpatialHash _spatialHash = SpatialHash(cellSize: 2.0);

  // === Google Maps-grade position smoothing ===
  // EMA (Exponential Moving Average) filter removes AR sensor jitter
  static const double _emaAlpha = 0.35; // 0.0 = full smoothing, 1.0 = raw data
  Vector3? _smoothedPosition;

  // Heading smoothing (circular EMA to prevent compass jitter)
  double _smoothedHeading = 0.0;

  NavigationBloc({required this.graph}) : super(const NavigationState()) {
    _loadCustomNodes();

    on<ScanQRCode>(_onScanQRCode);
    on<SetDestination>(_onSetDestination);
    on<UpdateCurrentPosition>(_onUpdateCurrentPosition);
    on<ToggleVoice>(_onToggleVoice);
    on<ToggleAccessibility>(_onToggleAccessibility);
    on<FindNearestByCategory>(_onFindNearestByCategory);
    on<LogLocation>(_onLogLocation);
    on<DeleteLocation>(_onDeleteLocation);
    on<StartMapping>(_onStartMapping);
    on<StopMapping>(_onStopMapping);
    on<UpdateHeading>(_onUpdateHeading);
  }

  void _onUpdateHeading(UpdateHeading event, Emitter<NavigationState> emit) {
    // Circular EMA: handles the 359°→1° wraparound correctly
    final raw = event.heading;
    double diff = raw - _smoothedHeading;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;
    _smoothedHeading = (_smoothedHeading + _emaAlpha * diff) % 360;
    if (_smoothedHeading < 0) _smoothedHeading += 360;
    
    emit(state.copyWith(currentHeading: _smoothedHeading));
  }

  Future<void> _onDeleteLocation(DeleteLocation event, Emitter<NavigationState> emit) async {
    await MapService.deleteNode(event.id);
    graph.remove(event.id);

    // Also remove any references to this node in other nodes' neighbor lists
    for (var node in graph.values) {
      node.neighbors.remove(event.id);
    }

    _rebuildSpatialHash();

    emit(state.copyWith(
      status: NavigationStatus.idle,
      destinationId: state.destinationId == event.id ? null : state.destinationId,
      nextInstruction: "Location deleted.",
    ));
  }


  void _onStartMapping(StartMapping event, Emitter<NavigationState> emit) {
    // Reset distance and path to ensure no "teleport" jumps from previous sessions
    _smoothedPosition = null; 
    emit(state.copyWith(
      status: NavigationStatus.mapping,
      currentDistanceWalked: 0.0,
      stepsCount: 0,
      mappingPath: [], // Start empty; first UpdateCurrentPosition will add the first point
    ));
  }

  void _onStopMapping(StopMapping event, Emitter<NavigationState> emit) {
    emit(state.copyWith(status: NavigationStatus.idle));
  }


  Future<void> _loadCustomNodes() async {
    final customNodes = await MapService.loadNodes();
    graph.addAll(customNodes);
    _rebuildSpatialHash();
  }

  void _rebuildSpatialHash() {
    _spatialHash.clear();
    _spatialHash.addAll(graph.values);
  }

  Future<void> _onLogLocation(LogLocation event, Emitter<NavigationState> emit) async {
    final id = event.label.toLowerCase().replaceAll(' ', '_');
    final mappedPath = List<Vector3>.from(state.mappingPath);

    // Normalize coordinates to Map Space (North-aligned)
    final double rotationRad = state.currentHeading * (math_dart.pi / 180.0);
    
    // FIX: Calculate offset from the first recorded point to ensure path is relative to the start
    final Vector3 pathOffset = mappedPath.isNotEmpty ? mappedPath.first : Vector3.zero();

    Vector3 normalize(Vector3 p) {
      // 1. Subtract offset to make relative to anchor
      final relativeP = p - pathOffset;
      // 2. Rotate to align with North
      final double rx = relativeP.x * math_dart.cos(rotationRad) - relativeP.z * math_dart.sin(rotationRad);
      final double rz = relativeP.x * math_dart.sin(rotationRad) + relativeP.z * math_dart.cos(rotationRad);
      return Vector3(rx, p.y, rz);
    }

    final anchorId = state.currentNodeId ?? 'home_entrance';
    
    if (mappedPath.length >= 2) {
      final optimizedPath = PathSimplifier.simplify(mappedPath, epsilon: 0.1);
      
      String previousNodeId = anchorId;
      int waypointIndex = 0;
      
      // Start from 0 to ensure the first segment from anchor is included
      for (int i = 0; i < optimizedPath.length - 1; i++) {
        final wpId = '${id}_wp$waypointIndex';
        final wpNode = Node(
          id: wpId,
          label: '${event.label} Waypoint $waypointIndex',
          category: 'Waypoint',
          position: normalize(optimizedPath[i]),
          h3Cell: state.currentH3Cell ?? '',
          neighbors: {previousNodeId: 'walk'},
        );
        
        graph[wpId] = wpNode;
        _spatialHash.addNode(wpNode);
        await MapService.saveNode(wpNode);
        
        graph[previousNodeId]?.neighbors[wpId] = 'walk';
        await MapService.saveNode(graph[previousNodeId]!);
        
        previousNodeId = wpId;
        waypointIndex++;
      }
      
      final newNode = Node(
        id: id,
        label: event.label,
        category: event.category,
        position: normalize(event.position),
        h3Cell: state.currentH3Cell ?? '',
        neighbors: {previousNodeId: 'walk'},
      );
      
      graph[id] = newNode;
      _spatialHash.addNode(newNode);
      await MapService.saveNode(newNode);
      
      graph[previousNodeId]?.neighbors[id] = 'walk';
      await MapService.saveNode(graph[previousNodeId]!);
      
      HapticFeedback.mediumImpact();
    } else {
      final newNode = Node(
        id: id,
        label: event.label,
        category: event.category,
        position: normalize(event.position), // Save normalized
        h3Cell: state.currentH3Cell ?? '',
        neighbors: {anchorId: 'walk'},
      );
      
      graph[id] = newNode;
      _spatialHash.addNode(newNode);
      await MapService.saveNode(newNode);
      
      if (graph.containsKey(anchorId)) {
        graph[anchorId]!.neighbors[id] = 'walk';
        await MapService.saveNode(graph[anchorId]!);
      }
    }

    emit(state.copyWith(
      status: NavigationStatus.calculating,
      destinationId: id,
      nextInstruction: "Learned: ${event.label}",
    ));

    _calculateAndEmitRoute(anchorId, id, emit);
  }

  void _onToggleVoice(ToggleVoice event, Emitter<NavigationState> emit) {
    emit(state.copyWith(isMuted: !state.isMuted));
  }

  void _onToggleAccessibility(ToggleAccessibility event, Emitter<NavigationState> emit) {
    final newState = state.copyWith(isWheelchairAccessible: !state.isWheelchairAccessible);
    emit(newState);
    
    // Trigger reroute with new accessibility setting if already navigating
    if (state.currentNodeId != null && state.destinationId != null) {
      _calculateAndEmitRoute(state.currentNodeId!, state.destinationId!, emit);
    }
  }

  void _onFindNearestByCategory(FindNearestByCategory event, Emitter<NavigationState> emit) {
    if (state.currentPosition == null) return;

    Node? nearest;
    double minDist = double.infinity;

    // Search for nearest node with matching category or tag
    for (var node in graph.values) {
      if (node.category?.toLowerCase() == event.category.toLowerCase() || 
          node.tags.any((t) => t.toLowerCase() == event.category.toLowerCase())) {
        
        final d = state.currentPosition!.distanceTo(node.position);
        if (d < minDist) {
          minDist = d;
          nearest = node;
        }
      }
    }

    if (nearest != null) {
      add(SetDestination(nearest.id));
    } else {
      emit(state.copyWith(
        status: NavigationStatus.error,
        errorMessage: 'No ${event.category} found nearby',
      ));
    }
  }

  void _onScanQRCode(ScanQRCode event, Emitter<NavigationState> emit) {
    // debugPrint('🔍 DISHA: QR Scan Event Received. Payload: ${event.payload}');
    try {
      final payload = jsonDecode(event.payload);
      final nodeId = payload['id'] as String;

      // If the anchor is not in the graph, create it and save it for persistence
      if (!graph.containsKey(nodeId)) {
        final newAnchor = Node(
          id: nodeId,
          label: payload['name'] ?? 'Home Entrance',
          category: 'Anchor',
          position: Vector3.zero(),
          neighbors: {},
        );
        graph[nodeId] = newAnchor;
        MapService.saveNode(newAnchor);
      }

      final node = graph[nodeId]!;

      // Run GPS conversion to update the local Vector3 map
      GpsConverter.convertGraphToLocalCoordinates(graph, nodeId, event.heading);

      // Since positions changed, we must rebuild the spatial hash
      _rebuildSpatialHash();

      // debugPrint('📍 DISHA: Localized at Node: $nodeId');
      emit(state.copyWith(
        status: state.destinationId != null ? NavigationStatus.calculating : NavigationStatus.idle,
        currentNodeId: nodeId,
        stepsCount: 0,
        currentH3Cell: node.h3Cell,
        currentHeading: event.heading, // Store the alignment heading
      ));

      if (state.destinationId != null) {
        _calculateAndEmitRoute(nodeId, state.destinationId!, emit);
      }
    } catch (e) {
      emit(state.copyWith(
        status: NavigationStatus.error,
        errorMessage: 'Invalid QR payload',
      ));
    }
  }

  void _onSetDestination(SetDestination event, Emitter<NavigationState> emit) {
    // debugPrint('🎯 DISHA: Setting Destination to: ${event.destinationId}');
    emit(state.copyWith(
      status: state.currentNodeId != null ? NavigationStatus.calculating : NavigationStatus.idle,
      destinationId: event.destinationId,
    ));

    if (state.currentNodeId != null) {
      _calculateAndEmitRoute(state.currentNodeId!, event.destinationId, emit);
    }
  }

  void _onUpdateCurrentPosition(UpdateCurrentPosition event, Emitter<NavigationState> emit) {
    final rawPos = event.position;
    
    // === EMA Position Smoothing (removes AR sensor jitter) ===
    if (_smoothedPosition == null) {
      _smoothedPosition = rawPos.clone();
    } else {
      _smoothedPosition = Vector3(
        _smoothedPosition!.x + _emaAlpha * (rawPos.x - _smoothedPosition!.x),
        _smoothedPosition!.y + _emaAlpha * (rawPos.y - _smoothedPosition!.y),
        _smoothedPosition!.z + _emaAlpha * (rawPos.z - _smoothedPosition!.z),
      );
    }
    final currentPos = _smoothedPosition!;
    
    // Diagnostic Log
    debugPrint('AR POS: (${currentPos.x.toStringAsFixed(2)}, ${currentPos.y.toStringAsFixed(2)}, ${currentPos.z.toStringAsFixed(2)}) | Path: ${state.mappingPath.length}pts');

    // Dead-zone: Only process if moved > 5cm (AR sensor noise can drift ~2-3cm)
    if (state.currentPosition != null) {
      final distanceMovedSinceLastUpdate = state.currentPosition!.distanceTo(currentPos);
      if (distanceMovedSinceLastUpdate < 0.05) return; 
    }

    if (state.status != NavigationStatus.navigating && state.status != NavigationStatus.mapping) {
      emit(state.copyWith(currentPosition: currentPos));
      return;
    }

    // === Google Maps-grade Distance & Step Tracking ===
    // Calculate distance only if we have a valid previous position to avoid jump-on-start
    double distanceMovedSinceLastFrame = 0.0;
    if (state.currentPosition != null && state.currentDistanceWalked != null) {
      distanceMovedSinceLastFrame = currentPos.distanceTo(state.currentPosition!);
    }

    // FIX: Lower threshold (0.01m) to capture slow walking at 15Hz
    final isGenuineMovement = distanceMovedSinceLastFrame > 0.01; 
    
    final totalDistance = isGenuineMovement 
        ? (state.currentDistanceWalked ?? 0.0) + distanceMovedSinceLastFrame 
        : (state.currentDistanceWalked ?? 0.0);
    final newSteps = (totalDistance * 1.31).toInt();

    if (state.status == NavigationStatus.mapping) {
      // Optimization: Zone detection using Spatial Hash
      String? currentHex = state.currentH3Cell;
      final nearestZoneNode = _spatialHash.findNearestNode(currentPos, maxDistance: 3.0);
      if (nearestZoneNode != null) {
        currentHex = nearestZoneNode.h3Cell;
      }

      // Haptic feedback every 1 meter during mapping for physical confirmation
      if (totalDistance.toInt() > (state.currentDistanceWalked ?? 0.0).toInt()) {
        HapticFeedback.lightImpact();
      }

      // Record points for the breadcrumb trail and final path
      // FIX: 0.2m spacing provides higher fidelity for tight corners
      final bool shouldRecordPoint = isGenuineMovement && 
          (state.mappingPath.isEmpty || state.mappingPath.last.distanceTo(currentPos) > 0.2);

      emit(state.copyWith(
        currentPosition: currentPos,
        currentDistanceWalked: totalDistance,
        stepsCount: newSteps,
        currentH3Cell: currentHex,
        mappingPath: shouldRecordPoint
            ? [...state.mappingPath, currentPos] 
            : state.mappingPath,
      ));
      return;
    }


    if (state.route.isEmpty) {
      emit(state.copyWith(currentPosition: currentPos));
      return;
    }

    // === Snap-to-Path (Google Maps snaps GPS to nearest road) ===
    // Project user position onto the nearest route segment for sub-meter accuracy
    final currentIdx = state.currentWaypointIndex;
    double minDistanceToRoute = double.infinity;
    Vector3 snappedPos = currentPos; // fallback to raw pos

    if (currentIdx < state.route.length) {
      // Check current and next segment
      for (int seg = math_dart.max(0, currentIdx - 1); seg < math_dart.min(state.route.length - 1, currentIdx + 1); seg++) {
        final a = state.route[seg];
        final b = state.route[seg + 1];
        final ab = b - a;
        final ap = currentPos - a;
        final abLen2 = ab.length2;
        
        if (abLen2 > 0) {
          double t = ap.dot(ab) / abLen2;
          t = t.clamp(0.0, 1.0);
          final proj = a + ab * t;
          final dist = currentPos.distanceTo(proj);
          if (dist < minDistanceToRoute) {
            minDistanceToRoute = dist;
            snappedPos = proj;
          }
        }
      }
      
      // Also check distance to current waypoint directly
      final dWp = currentPos.distanceTo(state.route[currentIdx]);
      if (dWp < minDistanceToRoute) {
        minDistanceToRoute = dWp;
      }
    }

    // Dynamic Rerouting using Spatial Hash (Google Maps Style)
    if (minDistanceToRoute > 3.0 && state.destinationId != null) {
      final nearestNode = _spatialHash.findNearestNode(currentPos);

      if (nearestNode != null) {
        HapticFeedback.vibrate(); // Alert user that we are rerouting
        emit(state.copyWith(
          status: NavigationStatus.calculating,
          nextInstruction: "Rerouting...",
          currentPosition: currentPos,
          currentH3Cell: nearestNode.h3Cell,
        ));
        _calculateAndEmitRoute(nearestNode.id, state.destinationId!, emit);
        return;
      }
    }

    final nextWaypoint = state.route[currentIdx];
    // Use raw position for waypoint distance (arrival detection)
    // but snapped position for display (keeps user dot on the path)
    final distance = currentPos.distanceTo(nextWaypoint);

    double totalRemainingDistance = distance;
    for (int i = currentIdx; i < state.route.length - 1; i++) {
      totalRemainingDistance += state.route[i].distanceTo(state.route[i+1]);
    }
    
    // Average walking speed ~1.4 m/s
    final remainingSeconds = (totalRemainingDistance / 1.4).round();
    final estimatedTime = Duration(seconds: remainingSeconds);

    // Optimization: Zone detection using Spatial Hash
    String? currentHex = state.currentH3Cell;
    final nearestZoneNode = _spatialHash.findNearestNode(currentPos, maxDistance: 3.0);
    if (nearestZoneNode != null) {
      currentHex = nearestZoneNode.h3Cell;
    }

    if (currentHex != state.currentH3Cell) {
       HapticFeedback.mediumImpact();
    }

    // Check if arrived at waypoint (1.2m threshold works well with 1m waypoint spacing)
    if (distance < 1.2) { 
      final nextIdx = currentIdx + 1;

      if (nextIdx >= state.route.length) {
        HapticFeedback.heavyImpact();
        emit(state.copyWith(
          status: NavigationStatus.arrived,
          currentWaypointIndex: currentIdx,
          currentDistance: 0,
          nextInstruction: "You have arrived!",
          currentPosition: currentPos,
          currentDistanceWalked: totalDistance,
          stepsCount: newSteps,
          currentH3Cell: currentHex,
          estimatedTimeRemaining: Duration.zero,
        ));
      } else {
        // Haptic Turn Preview: Eyes-free guidance
        _triggerHapticTurnPreview(currentIdx);
        
        final newDistance = currentPos.distanceTo(state.route[nextIdx]);
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          currentDistance: newDistance,
          nextInstruction: _getInstruction(snappedPos, state.route[nextIdx]),
          currentPosition: snappedPos, // Snap to path for smooth display
          currentDistanceWalked: totalDistance,
          stepsCount: newSteps,
          currentH3Cell: currentHex,
          estimatedTimeRemaining: estimatedTime,
        ));
      }
    } else {
      emit(state.copyWith(
        currentDistance: distance,
        nextInstruction: _getInstruction(snappedPos, nextWaypoint),
        currentPosition: snappedPos, // Snap to path for smooth display
        currentDistanceWalked: totalDistance,
        stepsCount: newSteps,
        currentH3Cell: currentHex,
        estimatedTimeRemaining: estimatedTime,
      ));
    }
  }

  void _triggerHapticTurnPreview(int currentIdx) async {
    if (currentIdx + 2 >= state.route.length) {
      HapticFeedback.lightImpact(); // Approaching destination
      return;
    }

    // Vectors for the two segments
    final v1 = state.route[currentIdx + 1] - state.route[currentIdx];
    final v2 = state.route[currentIdx + 2] - state.route[currentIdx + 1];

    // Angle in the horizontal plane
    final angle = _calculateAngle(v1, v2);

    if (angle > 0.5) { // Significant Right Turn
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.mediumImpact();
    } else if (angle < -0.5) { // Significant Left Turn
      await HapticFeedback.lightImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.lightImpact();
    } else {
      HapticFeedback.selectionClick(); // Going straight
    }
  }

  double _calculateAngle(Vector3 v1, Vector3 v2) {
    // We care about the horizontal plane (X, Z) for turns
    final double angle1 = math_dart.atan2(v1.x, v1.z);
    final double angle2 = math_dart.atan2(v2.x, v2.z);
    double diff = angle2 - angle1;
    
    // Normalize to [-pi, pi]
    if (diff > math_dart.pi) diff -= 2 * math_dart.pi;
    if (diff <= -math_dart.pi) diff += 2 * math_dart.pi;
    
    return diff;
  }

  String _getInstruction(Vector3 current, Vector3 target) {
    final distance = current.distanceTo(target);
    if (distance < 1.5) return "Arriving shortly...";
    
    // Look ahead in the route to detect upcoming turns
    final idx = state.currentWaypointIndex;
    if (idx + 2 < state.route.length) {
      final seg1 = state.route[idx + 1] - state.route[idx];
      final seg2 = state.route[idx + 2] - state.route[idx + 1];
      final turnAngle = _calculateAngle(seg1, seg2);
      
      final distToTurn = current.distanceTo(state.route[idx + 1]);
      final int stableDist = distToTurn < 5 ? distToTurn.round() : ((distToTurn / 5).round() * 5);
      
      if (turnAngle > 0.8) {
        return "Turn right in $stableDist meters";
      } else if (turnAngle > 0.3) {
        return "Slight right in $stableDist meters";
      } else if (turnAngle < -0.8) {
        return "Turn left in $stableDist meters";
      } else if (turnAngle < -0.3) {
        return "Slight left in $stableDist meters";
      }
    }
    
    // No turn ahead — just report distance
    final int stableDistance;
    if (distance > 10.0) {
      stableDistance = (distance / 5.0).round() * 5;
    } else {
      stableDistance = distance.round();
    }
    
    return "Continue straight for $stableDistance meters";
  }

  void _calculateAndEmitRoute(String startId, String endId, Emitter<NavigationState> emit) async {
    // debugPrint('📍 DISHA: Calculating route from $startId to $endId...');
    
    try {
      // Running on main thread for stability in field tests
      final route = AStarRouter(graph, accessibilityMode: state.isWheelchairAccessible)
          .findPath(startId, endId);
      
      if (route != null && route.isNotEmpty) {
        // debugPrint('✅ DISHA: Route found with ${route.length} waypoints.');
        emit(state.copyWith(
          status: NavigationStatus.navigating,
          route: route,
          currentWaypointIndex: 0,
        ));
      } else {
        // debugPrint('❌ DISHA: No path found between $startId and $endId.');
        emit(state.copyWith(
          status: NavigationStatus.error,
          errorMessage: 'No path found. Ensure these locations are connected!',
        ));
      }
    } catch (e) {
      // debugPrint('⚠️ DISHA ERROR: $e');
      emit(state.copyWith(
        status: NavigationStatus.error,
        errorMessage: 'Calculation Error: $e',
      ));
    }
  }
}
