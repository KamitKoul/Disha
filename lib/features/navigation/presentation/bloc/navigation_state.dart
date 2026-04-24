part of 'navigation_bloc.dart';

enum NavigationStatus { idle, scanning, calculating, navigating, relocalizing, mapping, arrived, error }

class NavigationState extends Equatable {
  final NavigationStatus status;
  final String? currentNodeId;
  final String? destinationId;
  final List<Vector3> route;
  final int currentWaypointIndex;
  final double? currentDistance;
  final String? nextInstruction;
  final String? errorMessage;
  final Vector3? currentPosition;
  final bool isMuted;
  final bool isWheelchairAccessible;
  final Duration estimatedTimeRemaining;
  final int stepsCount;
  final String? currentH3Cell;
  final double? currentDistanceWalked;
  final List<Vector3> mappingPath;
  final double currentHeading;

  const NavigationState({
    this.status = NavigationStatus.idle,
    this.currentNodeId,
    this.destinationId,
    this.route = const [],
    this.currentWaypointIndex = 0,
    this.currentDistance,
    this.nextInstruction,
    this.errorMessage,
    this.currentPosition,
    this.isMuted = false,
    this.isWheelchairAccessible = false,
    this.estimatedTimeRemaining = Duration.zero,
    this.stepsCount = 0,
    this.currentH3Cell,
    this.currentDistanceWalked = 0.0,
    this.mappingPath = const [],
    this.currentHeading = 0.0,
  });

  NavigationState copyWith({
    NavigationStatus? status,
    String? currentNodeId,
    String? destinationId,
    List<Vector3>? route,
    int? currentWaypointIndex,
    double? currentDistance,
    String? nextInstruction,
    String? errorMessage,
    Vector3? currentPosition,
    bool? isMuted,
    bool? isWheelchairAccessible,
    Duration? estimatedTimeRemaining,
    int? stepsCount,
    String? currentH3Cell,
    double? currentDistanceWalked,
    List<Vector3>? mappingPath,
    double? currentHeading,
  }) {
    return NavigationState(
      status: status ?? this.status,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      destinationId: destinationId ?? this.destinationId,
      route: route ?? this.route,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
      currentDistance: currentDistance ?? this.currentDistance,
      nextInstruction: nextInstruction ?? this.nextInstruction,
      errorMessage: errorMessage ?? this.errorMessage,
      currentPosition: currentPosition ?? this.currentPosition,
      isMuted: isMuted ?? this.isMuted,
      isWheelchairAccessible: isWheelchairAccessible ?? this.isWheelchairAccessible,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      stepsCount: stepsCount ?? this.stepsCount,
      currentH3Cell: currentH3Cell ?? this.currentH3Cell,
      currentDistanceWalked: currentDistanceWalked ?? this.currentDistanceWalked,
      mappingPath: mappingPath ?? this.mappingPath,
      currentHeading: currentHeading ?? this.currentHeading,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentNodeId,
        destinationId,
        route,
        currentWaypointIndex,
        currentDistance,
        nextInstruction,
        errorMessage,
        currentPosition,
        isMuted,
        isWheelchairAccessible,
        estimatedTimeRemaining,
        stepsCount,
        currentH3Cell,
        currentDistanceWalked,
        mappingPath,
        currentHeading,
      ];
}



