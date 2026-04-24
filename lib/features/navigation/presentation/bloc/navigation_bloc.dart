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
  double _stepBuffer = 0.0; // Cumulative distance waiting to become a 'step'
  DateTime _lastMovementTime = DateTime.now();
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
          nextInstruction: "You have arrived!",
          lastActionFeedback: "Destination reached.",
          currentDistance: 0.0,
        ));
      } else {
        HapticFeedback.mediumImpact();
        final next = state.route[nextIdx];
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          nextInstruction: _getInstruction(state.currentPosition ?? Vector3.zero(), next),
          lastActionFeedback: "Advanced to next turn.",
          currentDistance: (state.currentPosition ?? Vector3.zero()).distanceTo(next),
        ));
      }
    }
  }

  void _onAddWaypoint(AddWaypoint event, Emitter<NavigationState> emit) {
    if (state.currentPosition != null && state.status == NavigationStatus.mapping) {
      HapticFeedback.mediumImpact();
      emit(state.copyWith(
        mappingPath: [...state.mappingPath, state.currentPosition!],
        lastActionFeedback: "Corner marked.",
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
      lastActionFeedback: "Location deleted successfully.",
    ));
  }

  void _onStartMapping(StartMapping event, Emitter<NavigationState> emit) {
    _lastLegitPosition = null;
    _stepBuffer = 0.0;
    emit(state.copyWith(
      status: NavigationStatus.mapping,
      currentDistanceWalked: 0.0,
      stepsCount: 0,
      mappingPath: [], 
      lastActionFeedback: null,
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
        
        if (graph.containsKey(previousNodeId)) {
          graph[previousNodeId]!.neighbors[wpId] = 'walk';
          await MapService.saveNode(graph[previousNodeId]!);
        }
        
        previousNodeId = wpId;
      }
      HapticFeedback.heavyImpact();
    }

    emit(state.copyWith(
      status: NavigationStatus.idle,
      destinationId: id,
      nextInstruction: "Saved: ${event.label}",
      lastActionFeedback: "Room '${event.label}' saved successfully!",
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
          label: payload['name'] ?? 'Entrance',
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
      _stepBuffer = 0.0;

      emit(state.copyWith(
        status: state.destinationId != null ? NavigationStatus.calculating : NavigationStatus.idle,
        currentNodeId: nodeId,
        stepsCount: 0,
        currentDistanceWalked: 0.0,
        currentH3Cell: graph[nodeId]?.h3Cell,
        currentHeading: event.heading,
        lastActionFeedback: "Localized at ${graph[nodeId]?.label}",
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
    
    if (_lastLegitPosition == null) {
      _lastLegitPosition = rawPos.clone();
      emit(state.copyWith(currentPosition: rawPos));
      return;
    }

    double dist = rawPos.distanceTo(_lastLegitPosition!);

    // 1. HARD GLITCH REJECTION
    if (dist > 0.8) {
       _lastLegitPosition = rawPos.clone(); // Resync but ignore the distance
       return; 
    }

    // 2. IDLE JITTER PROTECTION
    // If we haven't moved at least 5cm, it's vibration. Ignore it.
    if (dist < 0.05) {
       emit(state.copyWith(currentPosition: rawPos));
       return;
    }

    _lastLegitPosition = rawPos.clone();
    
    // Only process distance if we are Mapping or Navigating
    if (state.status != NavigationStatus.navigating && state.status != NavigationStatus.mapping) {
      emit(state.copyWith(currentPosition: rawPos));
      return;
    }

    // 3. THE STEP GATE (STRIDE SYNC)
    // We collect the distance in a buffer. We only "confirm" the movement 
    // when the user has covered 0.7m (a human step).
    _stepBuffer += dist;
    
    // Auto-clear buffer if standing still for 2 seconds (sensor noise cleanup)
    final now = DateTime.now();
    if (now.difference(_lastMovementTime).inSeconds > 2) {
      _stepBuffer = 0.0;
    }
    _lastMovementTime = now;

    if (_stepBuffer >= 0.7) {
      // CONFIRMED LEGIT STEP
      final double confirmDist = _stepBuffer;
      _stepBuffer = 0.0; // Reset for next step

      final totalDistance = (state.currentDistanceWalked ?? 0.0) + confirmDist;
      final int totalSteps = state.stepsCount + 1;

      if (state.status == NavigationStatus.mapping) {
        emit(state.copyWith(
          currentPosition: rawPos,
          currentDistanceWalked: totalDistance,
          stepsCount: totalSteps,
        ));
        return;
      }

      if (state.route.isEmpty) return;

      // TURN-BY-TURN LOGIC
      final currentIdx = state.currentWaypointIndex;
      final target = state.route[currentIdx];
      final distanceToTarget = rawPos.distanceTo(target);

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
          nextInstruction: _getInstruction(rawPos, target),
          currentPosition: rawPos, 
          currentDistanceWalked: totalDistance,
          stepsCount: totalSteps,
        ));
      }
    } else {
      // NOT ENOUGH FOR A STEP: Just update camera position but don't move the numbers
      emit(state.copyWith(currentPosition: rawPos));
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
    final int displayDist = distance.round();
    if (displayDist < 2) return "Arriving...";
    return "Walk straight for $displayDist meters";
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
