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

  static const double _emaAlpha = 0.35; 
  Vector3? _smoothedPosition;
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
    on<AddWaypoint>(_onAddWaypoint);
  }

  void _onAddWaypoint(AddWaypoint event, Emitter<NavigationState> emit) {
    if (state.currentPosition != null && state.status == NavigationStatus.mapping) {
      HapticFeedback.heavyImpact();
      emit(state.copyWith(
        mappingPath: [...state.mappingPath, state.currentPosition!],
      ));
    }
  }

  void _onUpdateHeading(UpdateHeading event, Emitter<NavigationState> emit) {
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
    _smoothedPosition = null; 
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
    final double rotationRad = state.currentHeading * (math_dart.pi / 180.0);
    
    Vector3 normalize(Vector3 p) {
      final double rx = p.x * math_dart.cos(rotationRad) - p.z * math_dart.sin(rotationRad);
      final double rz = p.x * math_dart.sin(rotationRad) + p.z * math_dart.cos(rotationRad);
      return Vector3(rx, p.y, rz);
    }

    final anchorId = state.currentNodeId ?? 'home_entrance';
    
    // Add the final position as the last waypoint
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
      emit(state.copyWith(
        status: state.destinationId != null ? NavigationStatus.calculating : NavigationStatus.idle,
        currentNodeId: nodeId,
        stepsCount: 0,
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
    
    if (state.currentPosition != null && currentPos.distanceTo(state.currentPosition!) < 0.05) return;

    if (state.status != NavigationStatus.navigating && state.status != NavigationStatus.mapping) {
      emit(state.copyWith(currentPosition: currentPos));
      return;
    }

    double distanceMoved = state.currentPosition != null ? currentPos.distanceTo(state.currentPosition!) : 0.0;
    final totalDistance = (state.currentDistanceWalked ?? 0.0) + distanceMoved;

    if (state.status == NavigationStatus.mapping) {
      emit(state.copyWith(
        currentPosition: currentPos,
        currentDistanceWalked: totalDistance,
        stepsCount: (totalDistance * 1.31).toInt(),
      ));
      return;
    }

    if (state.route.isEmpty) {
      emit(state.copyWith(currentPosition: currentPos));
      return;
    }

    final currentIdx = state.currentWaypointIndex;
    double minDistanceToRoute = double.infinity;
    Vector3 snappedPos = currentPos; 

    if (currentIdx < state.route.length) {
      for (int seg = math_dart.max(0, currentIdx - 1); seg < math_dart.min(state.route.length - 1, currentIdx + 1); seg++) {
        final a = state.route[seg];
        final b = state.route[seg + 1];
        final ab = b - a;
        final ap = currentPos - a;
        final abLen2 = ab.length2;
        if (abLen2 > 0) {
          double t = (ap.dot(ab) / abLen2).clamp(0.0, 1.0);
          final proj = a + ab * t;
          final dist = currentPos.distanceTo(proj);
          if (dist < minDistanceToRoute) {
            minDistanceToRoute = dist;
            snappedPos = proj;
          }
        }
      }
    }

    if (minDistanceToRoute > 3.0 && state.destinationId != null) {
      final nearestNode = _spatialHash.findNearestNode(currentPos);
      if (nearestNode != null) {
        HapticFeedback.vibrate();
        emit(state.copyWith(status: NavigationStatus.calculating, nextInstruction: "Rerouting...", currentPosition: currentPos));
        _calculateAndEmitRoute(nearestNode.id, state.destinationId!, emit);
        return;
      }
    }

    final nextWaypoint = state.route[currentIdx];
    final distance = currentPos.distanceTo(nextWaypoint);

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
          stepsCount: (totalDistance * 1.31).toInt(),
          estimatedTimeRemaining: Duration.zero,
        ));
      } else {
        _triggerHapticTurnPreview(currentIdx);
        emit(state.copyWith(
          currentWaypointIndex: nextIdx,
          currentDistance: currentPos.distanceTo(state.route[nextIdx]),
          nextInstruction: _getInstruction(snappedPos, state.route[nextIdx]),
          currentPosition: snappedPos, 
          currentDistanceWalked: totalDistance,
          stepsCount: (totalDistance * 1.31).toInt(),
        ));
      }
    } else {
      emit(state.copyWith(
        currentDistance: distance,
        nextInstruction: _getInstruction(snappedPos, nextWaypoint),
        currentPosition: snappedPos, 
        currentDistanceWalked: totalDistance,
        stepsCount: (totalDistance * 1.31).toInt(),
      ));
    }
  }

  void _triggerHapticTurnPreview(int currentIdx) async {
    if (currentIdx + 2 >= state.route.length) return;
    final v1 = state.route[currentIdx + 1] - state.route[currentIdx];
    final v2 = state.route[currentIdx + 2] - state.route[currentIdx + 1];
    final angle = _calculateAngle(v1, v2);
    if (angle.abs() > 0.5) { 
      await HapticFeedback.mediumImpact();
      await Future.delayed(const Duration(milliseconds: 150));
      await HapticFeedback.mediumImpact();
    }
  }

  double _calculateAngle(Vector3 v1, Vector3 v2) {
    final double angle1 = math_dart.atan2(v1.x, v1.z);
    final double angle2 = math_dart.atan2(v2.x, v2.z);
    double diff = angle2 - angle1;
    if (diff > math_dart.pi) diff -= 2 * math_dart.pi;
    if (diff <= -math_dart.pi) diff += 2 * math_dart.pi;
    return diff;
  }

  String _getInstruction(Vector3 current, Vector3 target) {
    final distance = current.distanceTo(target);
    if (distance < 1.5) return "Arriving shortly...";
    final int stableDistance = distance > 10.0 ? (distance / 5.0).round() * 5 : distance.round();
    return "Continue straight for $stableDistance meters";
  }

  void _calculateAndEmitRoute(String startId, String endId, Emitter<NavigationState> emit) async {
    try {
      GpsConverter.convertGraphToLocalCoordinates(graph, startId, state.currentHeading);
      final route = AStarRouter(graph, accessibilityMode: state.isWheelchairAccessible).findPath(startId, endId);
      if (route != null && route.isNotEmpty) {
        emit(state.copyWith(status: NavigationStatus.navigating, route: route, currentWaypointIndex: 0));
      } else {
        emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'No path found.'));
      }
    } catch (e) {
      emit(state.copyWith(status: NavigationStatus.error, errorMessage: 'Calculation Error: $e'));
    }
  }
}
