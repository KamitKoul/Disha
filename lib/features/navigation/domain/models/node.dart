import 'package:vector_math/vector_math_64.dart';

class Node {
  final String id;
  // position is now mutable so the GPS converter can update it dynamically
  Vector3 position;
  final String? label;
  final String? category;
  
  /// Map of neighbor ID to connection type (e.g., 'walk', 'stairs', 'elevator', 'ramp')
  final Map<String, String> neighbors;
  
  // New fields for GPS integration
  final double? latitude;
  final double? longitude;
  final String? h3Cell;

  // Multi-floor and Semantic support
  final int floor;
  final List<String> tags;

  Node({
    required this.id,
    required this.position,
    this.label,
    this.category,
    this.neighbors = const {},
    this.latitude,
    this.longitude,
    this.h3Cell,
    this.floor = 0,
    this.tags = const [],
  });

  factory Node.fromJson(Map<String, dynamic> json) {
    // Migration logic for old neighborIds List
    Map<String, String> parsedNeighbors = {};
    final rawNeighbors = json['neighbors'];
    if (rawNeighbors is List) {
      for (var id in rawNeighbors) {
        parsedNeighbors[id as String] = 'walk';
      }
    } else if (rawNeighbors is Map) {
      parsedNeighbors = Map<String, String>.from(rawNeighbors);
    }

    return Node(
      id: json['id'] as String,
      position: Vector3(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
        (json['z'] as num).toDouble(),
      ),
      label: json['label'] as String?,
      category: json['category'] as String?,
      neighbors: parsedNeighbors,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      h3Cell: json['h3Cell'] as String?,
      floor: json['floor'] as int? ?? 0,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'x': position.x,
      'y': position.y,
      'z': position.z,
      'label': label,
      'category': category,
      'neighbors': neighbors,
      'latitude': latitude,
      'longitude': longitude,
      'h3Cell': h3Cell,
      'floor': floor,
      'tags': tags,
    };
  }

  List<String> get neighborIds => neighbors.keys.toList();
}
