part of 'navigation_bloc.dart';

abstract class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

class ScanQRCode extends NavigationEvent {
  final String payload;
  final double heading;
  const ScanQRCode(this.payload, this.heading);

  @override
  List<Object?> get props => [payload, heading];
}

class SetDestination extends NavigationEvent {
  final String destinationId;
  const SetDestination(this.destinationId);

  @override
  List<Object?> get props => [destinationId];
}

class UpdateHeading extends NavigationEvent {
  final double heading;
  const UpdateHeading(this.heading);

  @override
  List<Object?> get props => [heading];
}

class UpdateCurrentPosition extends NavigationEvent {
  final Vector3 position;
  const UpdateCurrentPosition(this.position);

  @override
  List<Object?> get props => [position];
}

class ToggleVoice extends NavigationEvent {
  const ToggleVoice();

  @override
  List<Object?> get props => [];
}

class ToggleAccessibility extends NavigationEvent {
  const ToggleAccessibility();

  @override
  List<Object?> get props => [];
}

class FindNearestByCategory extends NavigationEvent {
  final String category;
  const FindNearestByCategory(this.category);

  @override
  List<Object?> get props => [category];
}

class AddWaypoint extends NavigationEvent {
  const AddWaypoint();
  @override
  List<Object?> get props => [];
}

class LogLocation extends NavigationEvent {
  final String label;
  final String category;
  final Vector3 position;

  const LogLocation({
    required this.label,
    required this.category,
    required this.position,
  });

  @override
  List<Object?> get props => [label, category, position];
}

class DeleteLocation extends NavigationEvent {
  final String id;
  const DeleteLocation(this.id);

  @override
  List<Object?> get props => [id];
}
class StartMapping extends NavigationEvent {
  const StartMapping();
}

class StopMapping extends NavigationEvent {
  const StopMapping();
}

