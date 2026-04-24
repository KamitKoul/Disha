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

  // STRIDE-SYNC SETTINGS
  static const double _strideLength = 0.75; // Average human step in meters
  Vector3? _lastStepPosition;
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
        ));
      } else {
        HapticFeedback.mediumImpact();
        final next = state.route[nextIdx];
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          nextInstruction: _getInstruction(state.currentPosition ?? Vector3.zero(), next),
          lastActionFeedback: "Advanced to next turn.",
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
      lastActionFeedback: "Location deleted.",
    ));
  }

  void _onStartMapping(StartMapping event, Emitter<NavigationState> emit) {
    _lastStepPosition = null;
    emit(state.copyWith(
      status: NavigationStatus.mapping,
      currentDistanceWalked: 0.0,
      stepsCount: 0,
      mappingPath: [], 
      lastActionFeedback: "Mapping started. Walk and mark corners.",
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
        graph[previousNodeId]?.neighbors[wpId] = 'walk';
        await MapService.saveNode(graph[previousNodeId]!);
        previousNodeId = wpId;
      }
      HapticFeedback.heavyImpact();
    }

    emit(state.copyWith(
      status: NavigationStatus.idle,
      destinationId: id,
      nextInstruction: "Location '${event.label}' saved.",
      lastActionFeedback: "Saved successfully!",
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
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'No ${event.category} found.'));
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
      _lastStepPosition = null;

      emit(state.copyWith(
        status: state.destinationId != null ? NavigationStatus.calculating : NavigationStatus.idle,
        currentNodeId: nodeId,
        stepsCount: 0,
        currentDistanceWalked: 0.0,
        currentH3Cell: graph[nodeId]?.h3Cell,
        currentHeading: event.heading,
        lastActionFeedback: "Anchored at ${graph[nodeId]?.label}",
      ));
      if (state.destinationId != null) {
        _calculateAndEmitRoute(nodeId, state.destinationId!, emit);
      }
    } catch (e) {
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'QR scan failed.'));
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
    
    // INITIALIZATION
    if (_lastStepPosition == null) {
      _lastStepPosition = rawPos.clone();
      emit(state.copyWith(currentPosition: rawPos));
      return;
    }

    // DISPLACEMENT CALCULATION
    double distanceFromLastStep = rawPos.distanceTo(_lastStepPosition!);

    // THE STRIDE-SYNC GATE:
    // We only process movement if the user has physically moved > 0.75m (one full step)
    // This makes the UI 100% immune to standing-still jitter.
    if (distanceFromLastStep >= _strideLength) {
      
      // HARD GLITCH PROTECTION:
      // If the jump is > 3 meters, it's an AR glitch (lost tracking).
      // We resync but don't count it as a step.
      if (distanceFromLastStep > 3.0) {
        _lastStepPosition = rawPos.clone();
        emit(state.copyWith(currentPosition: rawPos));
        return;
      }

      // LEGIT STEP DETECTED
      _lastStepPosition = rawPos.clone();
      
      final int newSteps = state.stepsCount + 1;
      final double newDistance = (state.currentDistanceWalked ?? 0.0) + _strideLength;

      if (state.status == NavigationStatus.mapping) {
        emit(state.copyWith(
          currentPosition: rawPos,
          currentDistanceWalked: newDistance,
          stepsCount: newSteps,
        ));
        return;
      }

      if (state.status == NavigationStatus.navigating && state.route.isNotEmpty) {
        final currentIdx = state.currentWaypointIndex;
        final target = state.route[currentIdx];
        final distToTarget = rawPos.distanceTo(target);

        // Auto-advance turn logic
        if (distToTarget < 1.5) {
          final nextIdx = currentIdx + 1;
          if (nextIdx >= state.route.length) {
            HapticFeedback.heavyImpact();
            emit(state.copyWith(
              status: NavigationStatus.arrived,
              nextInstruction: "You have arrived!",
              currentPosition: rawPos,
              currentDistanceWalked: newDistance,
              stepsCount: newSteps,
            ));
          } else {
            HapticFeedback.mediumImpact();
            emit(state.copyWith(
              currentWaypointIndex: nextIdx,
              currentDistance: rawPos.distanceTo(state.route[nextIdx]),
              nextInstruction: _getInstruction(rawPos, state.route[nextIdx]),
              currentPosition: rawPos,
              currentDistanceWalked: newDistance,
              stepsCount: newSteps,
            ));
          }
        } else {
          emit(state.copyWith(
            currentDistance: distToTarget,
            nextInstruction: _getInstruction(rawPos, target),
            currentPosition: rawPos,
            currentDistanceWalked: newDistance,
            stepsCount: newSteps,
          ));
        }
        return;
      }

      // If just idling, update position but maintain stats
      emit(state.copyWith(currentPosition: rawPos));
    } else {
      // Still update the visible AR position for the camera, but don't update stats
      emit(state.copyWith(currentPosition: rawPos));
    }
  }

  String _getInstruction(Vector3 current, Vector3 target) {
    final distance = current.distanceTo(target);
    final int displayDist = distance.round();
    if (displayDist < 2) return "Turn reached.";
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
