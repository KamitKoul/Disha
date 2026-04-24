import 'dart:convert';
import 'dart:math' as math_dart;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:equatable/equatable.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'dart:async';
import '../../domain/models/node.dart';
import '../../domain/a_star_router.dart';
import '../../../../core/utils/gps_converter.dart';
import '../../../../core/services/map_service.dart';
import '../../../../core/utils/spatial_hash.dart';

part 'navigation_event.dart';
part 'navigation_state.dart';

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  final Map<String, Node> graph;
  final SpatialHash _spatialHash = SpatialHash(cellSize: 2.0);

  Vector3? _lastLegitPosition;
  StreamSubscription<CompassEvent>? _compassSubscription;

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
    on<AddWaypoint>(_onAddWaypoint);
    on<ManualNextWaypoint>(_onManualNextWaypoint);

    _compassSubscription = FlutterCompass.events?.listen((event) {
      if (event.heading != null) {
        add(UpdateHeading(event.heading!));
      }
    });
  }

  @override
  Future<void> close() {
    _compassSubscription?.cancel();
    return super.close();
  }

  void _onManualNextWaypoint(ManualNextWaypoint event, Emitter<NavigationState> emit) {
    if (state.status == NavigationStatus.navigating && state.route.isNotEmpty) {
      final nextIdx = state.currentWaypointIndex + 1;
      if (nextIdx >= state.route.length) {
        HapticFeedback.heavyImpact();
        emit(state.copyWith(
          status: NavigationStatus.arrived,
          nextInstruction: "You have arrived at your destination!",
        ));
      } else {
        HapticFeedback.mediumImpact();
        final current = state.route[state.currentWaypointIndex];
        final next = state.route[nextIdx];
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          currentPosition: current, // Snap position to node
          nextInstruction: _getInstruction(current, next),
        ));
      }
    }
  }

  void _onAddWaypoint(AddWaypoint event, Emitter<NavigationState> emit) {
    if (state.currentPosition != null && state.status == NavigationStatus.mapping) {
      HapticFeedback.mediumImpact();
      emit(state.copyWith(
        mappingPath: [...state.mappingPath, state.currentPosition!],
      ));
    }
  }

  void _onUpdateHeading(UpdateHeading event, Emitter<NavigationState> emit) {
    emit(state.copyWith(currentHeading: event.heading));
  }

  Future<void> _onDeleteLocation(DeleteLocation event, Emitter<NavigationState> emit) async {
    await MapService.deleteNode(event.id);
    graph.remove(event.id);
    for (var node in graph.values) {
      node.neighbors.remove(event.id);
    }
    _rebuildSpatialHash();
    emit(state.copyWith(
      status: NavigationStatus.idle,
      destinationId: state.destinationId == event.id ? null : state.destinationId,
    ));
  }

  void _onStartMapping(StartMapping event, Emitter<NavigationState> emit) {
    _lastLegitPosition = null;
    emit(state.copyWith(
      status: NavigationStatus.mapping,
      currentDistanceWalked: 0.0,
      stepsCount: 0,
      mappingPath: [], 
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
    
    // UBER-STYLE MAPPING: Coordinates are saved as they are relative to the anchor
    final double rotationRad = state.currentHeading * (math_dart.pi / 180.0);
    Vector3 normalize(Vector3 p) {
      final double rx = p.x * math_dart.cos(rotationRad) - p.z * math_dart.sin(rotationRad);
      final double rz = p.x * math_dart.sin(rotationRad) + p.z * math_dart.cos(rotationRad);
      return Vector3(rx, p.y, rz);
    }

    final anchorId = state.currentNodeId ?? 'home_entrance';
    mappedPath.add(event.position);

    if (mappedPath.isNotEmpty) {
      String previousNodeId = anchorId;
      for (int i = 0; i < mappedPath.length; i++) {
        final isLast = i == mappedPath.length - 1;
        final wpId = isLast ? id : '${id}_wp$i';
        final wpNode = Node(
          id: wpId,
          label: isLast ? event.label : '${event.label} Waypoint $i',
          category: isLast ? event.category : 'Waypoint',
          position: normalize(mappedPath[i]),
          h3Cell: state.currentH3Cell ?? '',
          neighbors: {previousNodeId: 'walk'},
        );
        graph[wpId] = wpNode;
        _spatialHash.addNode(wpNode);
        await MapService.saveNode(wpNode);
        graph[previousNodeId]?.neighbors[wpId] = 'walk';
        await MapService.saveNode(graph[previousNodeId]!);
        previousNodeId = wpId;
      }
      HapticFeedback.mediumImpact();
    }

    emit(state.copyWith(
      status: NavigationStatus.idle,
      destinationId: id,
      nextInstruction: "Learned: ${event.label}",
    ));
  }

  void _onToggleVoice(ToggleVoice event, Emitter<NavigationState> emit) {
    emit(state.copyWith(isMuted: !state.isMuted));
  }

  void _onToggleAccessibility(ToggleAccessibility event, Emitter<NavigationState> emit) {
    final newState = state.copyWith(isWheelchairAccessible: !state.isWheelchairAccessible);
    emit(newState);
    if (state.currentNodeId != null && state.destinationId != null) {
      _calculateAndEmitRoute(state.currentNodeId!, state.destinationId!, emit);
    }
  }

  void _onFindNearestByCategory(FindNearestByCategory event, Emitter<NavigationState> emit) {
    if (state.currentPosition == null) return;
    Node? nearest;
    double minDist = double.infinity;
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
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'No ${event.category} found nearby'));
    }
  }

  void _onScanQRCode(ScanQRCode event, Emitter<NavigationState> emit) {
    try {
      final payload = jsonDecode(event.payload);
      final nodeId = payload['id'] as String;
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
      GpsConverter.convertGraphToLocalCoordinates(graph, nodeId, event.heading);
      _rebuildSpatialHash();
      
      _lastLegitPosition = null;

      emit(state.copyWith(
        status: state.destinationId != null ? NavigationStatus.calculating : NavigationStatus.idle,
        currentNodeId: nodeId,
        stepsCount: 0,
        currentDistanceWalked: 0.0,
        currentH3Cell: graph[nodeId]?.h3Cell,
        currentHeading: event.heading,
      ));
      if (state.destinationId != null) {
        _calculateAndEmitRoute(nodeId, state.destinationId!, emit);
      }
    } catch (e) {
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'Invalid QR payload'));
    }
  }

  void _onSetDestination(SetDestination event, Emitter<NavigationState> emit) {
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
    
    // ==========================================
    // HARD SLAM GLITCH FILTER (THE 10m JUMP FIX)
    // ==========================================
    if (_lastLegitPosition == null) {
      _lastLegitPosition = rawPos.clone();
      emit(state.copyWith(currentPosition: rawPos));
      return;
    }

    double jumpDistance = rawPos.distanceTo(_lastLegitPosition!);

    // If ARCore jumps more than 0.5 meters in 1 frame (100ms), it's a sensor tracking loss.
    // Humans walk at max 2m/s (0.2m per 100ms).
    // WE REJECT THIS UPDATE COMPLETELY to prevent distance skyrocketing.
    if (jumpDistance > 0.5) {
      return; 
    }

    // Ignore micro-jitters less than 5cm
    if (jumpDistance < 0.05) {
      return;
    }

    // We have legit, human-speed movement.
    _lastLegitPosition = rawPos.clone();
    
    // Only accumulate distance if we are actually recording/navigating
    if (state.status != NavigationStatus.navigating && state.status != NavigationStatus.mapping) {
      emit(state.copyWith(currentPosition: rawPos));
      return;
    }

    final totalDistance = (state.currentDistanceWalked ?? 0.0) + jumpDistance;
    final int totalSteps = (totalDistance * 1.3).toInt();

    if (state.status == NavigationStatus.mapping) {
      emit(state.copyWith(
        currentPosition: rawPos,
        currentDistanceWalked: totalDistance,
        stepsCount: totalSteps,
      ));
      return;
    }

    if (state.route.isEmpty) return;

    // TURN-BY-TURN NAVIGATION LOGIC (Uber/Google Maps Style)
    // We snap the user to the current route segment to keep the UI perfectly stable
    final currentIdx = state.currentWaypointIndex;
    final targetWaypoint = state.route[currentIdx];
    final distanceToTarget = rawPos.distanceTo(targetWaypoint);

    // Auto-advance if they reach the waypoint within 1.5 meters
    if (distanceToTarget < 1.5) { 
      final nextIdx = currentIdx + 1;
      if (nextIdx >= state.route.length) {
        HapticFeedback.heavyImpact();
        emit(state.copyWith(
          status: NavigationStatus.arrived,
          currentWaypointIndex: currentIdx,
          currentDistance: 0,
          nextInstruction: "You have arrived!",
          currentPosition: rawPos,
          currentDistanceWalked: totalDistance,
          stepsCount: totalSteps,
        ));
      } else {
        _triggerHapticTurnPreview(currentIdx);
        final nextTarget = state.route[nextIdx];
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          currentDistance: rawPos.distanceTo(nextTarget),
          nextInstruction: _getInstruction(rawPos, nextTarget),
          currentPosition: rawPos, 
          currentDistanceWalked: totalDistance,
          stepsCount: totalSteps,
        ));
      }
    } else {
      emit(state.copyWith(
        currentDistance: distanceToTarget,
        nextInstruction: _getInstruction(rawPos, targetWaypoint),
        currentPosition: rawPos, 
        currentDistanceWalked: totalDistance,
        stepsCount: totalSteps,
      ));
    }
  }

  void _triggerHapticTurnPreview(int currentIdx) async {
    if (currentIdx + 2 >= state.route.length) return;
    final v1 = state.route[currentIdx + 1] - state.route[currentIdx];
    final v2 = state.route[currentIdx + 2] - state.route[currentIdx + 1];
    final angle = _calculateTurnAngle(v1, v2);
    if (angle.abs() > 0.5) { 
      await HapticFeedback.mediumImpact();
    }
  }

  double _calculateTurnAngle(Vector3 v1, Vector3 v2) {
    final double angle1 = math_dart.atan2(v1.x, v1.z);
    final double angle2 = math_dart.atan2(v2.x, v2.z);
    double diff = angle2 - angle1;
    if (diff > math_dart.pi) diff -= 2 * math_dart.pi;
    if (diff <= -math_dart.pi) diff += 2 * math_dart.pi;
    return diff;
  }

  String _getInstruction(Vector3 current, Vector3 target) {
    final distance = current.distanceTo(target);
    final int displayDist = (distance).round();
    
    if (displayDist < 2) return "You are here.";

    // Uber-style Turn-by-Turn Instruction
    final idx = state.currentWaypointIndex;
    if (idx + 1 < state.route.length) {
      final seg1 = state.route[idx] - current;
      final seg2 = state.route[idx + 1] - state.route[idx];
      final turnAngle = _calculateTurnAngle(seg1, seg2);
      
      if (turnAngle > 0.8) return "In $displayDist meters, Turn Right";
      if (turnAngle < -0.8) return "In $displayDist meters, Turn Left";
      if (turnAngle > 0.3) return "In $displayDist meters, Slight Right";
      if (turnAngle < -0.3) return "In $displayDist meters, Slight Left";
    }
    
    return "Continue straight for $displayDist meters";
  }

  void _calculateAndEmitRoute(String startId, String endId, Emitter<NavigationState> emit) async {
    try {
      GpsConverter.convertGraphToLocalCoordinates(graph, startId, state.currentHeading);
      final route = AStarRouter(graph, accessibilityMode: state.isWheelchairAccessible).findPath(startId, endId);
      if (route != null && route.isNotEmpty) {
        emit(state.copyWith(
          status: NavigationStatus.navigating, 
          route: route, 
          currentWaypointIndex: 0,
          nextInstruction: _getInstruction(route.first, route[1 % route.length])
        ));
      } else {
        emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'No path found.'));
      }
    } catch (e) {
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'Calculation Error: $e'));
    }
  }
}
