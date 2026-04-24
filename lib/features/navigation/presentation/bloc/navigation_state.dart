part of 'navigation_bloc.dart';

enum NavigationStatus { idle, scanning, calculating, navigating, relocalizing, mapping, arrived, error }

class NavigationState extends Equatable {
  final NavigationStatus status;
  final String? currentNodeId;
  final String? destinationId;
  final String? errorMessage;
  final String? nextInstruction;
  final List<Vector3> route;
  final int currentWaypointIndex;
  final double? currentDistance;
  final Vector3? currentPosition;
  final bool isMuted;
  final bool isWheelchairAccessible;
  final Duration estimatedTimeRemaining;
  final int stepsCount;
  final String? currentH3Cell;
  final double? currentDistanceWalked;
  final List<Vector3> mappingPath;
  final double currentHeading;
  final String? lastActionFeedback; // Added field for user feedback

  const NavigationState({
    this.status = NavigationStatus.idle,
    this.currentNodeId,
    this.destinationId,
    this.errorMessage,
    this.nextInstruction,
    this.route = const [],
    this.currentWaypointIndex = 0,
    this.currentDistance,
    this.currentPosition,
    this.isMuted = false,
    this.isWheelchairAccessible = false,
    this.estimatedTimeRemaining = Duration.zero,
    this.stepsCount = 0,
    this.currentH3Cell,
    this.currentDistanceWalked = 0.0,
    this.mappingPath = const [],
    this.currentHeading = 0.0,
    this.lastActionFeedback,
  });

  NavigationState copyWith({
    NavigationStatus? status,
    String? currentNodeId,
    String? destinationId,
    String? errorMessage,
    String? nextInstruction,
    List<Vector3>? route,
    int? currentWaypointIndex,
    double? currentDistance,
    Vector3? currentPosition,
    bool? isMuted,
    bool? isWheelchairAccessible,
    Duration? estimatedTimeRemaining,
    int? stepsCount,
    String? currentH3Cell,
    double? currentDistanceWalked,
    List<Vector3>? mappingPath,
    double? currentHeading,
    String? lastActionFeedback,
  }) {
    return NavigationState(
      status: status ?? this.status,
      currentNodeId: currentNodeId ?? this.currentNodeId,
      destinationId: destinationId ?? this.destinationId,
      errorMessage: errorMessage ?? this.errorMessage,
      nextInstruction: nextInstruction ?? this.nextInstruction,
      route: route ?? this.route,
      currentWaypointIndex: currentWaypointIndex ?? this.currentWaypointIndex,
      currentDistance: currentDistance ?? this.currentDistance,
      currentPosition: currentPosition ?? this.currentPosition,
      isMuted: isMuted ?? this.isMuted,
      isWheelchairAccessible: isWheelchairAccessible ?? this.isWheelchairAccessible,
      estimatedTimeRemaining: estimatedTimeRemaining ?? this.estimatedTimeRemaining,
      stepsCount: stepsCount ?? this.stepsCount,
      currentH3Cell: currentH3Cell ?? this.currentH3Cell,
      currentDistanceWalked: currentDistanceWalked ?? this.currentDistanceWalked,
      mappingPath: mappingPath ?? this.mappingPath,
      currentHeading: currentHeading ?? this.currentHeading,
      lastActionFeedback: lastActionFeedback ?? this.lastActionFeedback,
    );
  }

  @override
  List<Object?> get props => [
        status,
        currentNodeId,
        destinationId,
        errorMessage,
        nextInstruction,
        route,
        currentWaypointIndex,
        currentDistance,
        currentPosition,
        isMuted,
        isWheelchairAccessible,
        estimatedTimeRemaining,
        stepsCount,
        currentH3Cell,
        currentDistanceWalked,
        mappingPath,
        currentHeading,
        lastActionFeedback,
      ];
}
