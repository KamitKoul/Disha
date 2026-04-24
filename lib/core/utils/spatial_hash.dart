import 'package:vector_math/vector_math_64.dart';
import '../../features/navigation/domain/models/node.dart';

class SpatialHash {
  final double cellSize;
  final Map<String, List<Node>> _grid = {};

  SpatialHash({this.cellSize = 2.0});

  String _getKey(Vector3 position) {
    final x = (position.x / cellSize).floor();
    final z = (position.z / cellSize).floor();
    return '$x,$z';
  }

  void clear() => _grid.clear();

  void addNode(Node node) {
    final key = _getKey(node.position);
    _grid.putIfAbsent(key, () => []).add(node);
  }

  void addAll(Iterable<Node> nodes) {
    for (final node in nodes) {
      addNode(node);
    }
  }

  List<Node> getNearbyNodes(Vector3 position) {
    final List<Node> nearby = [];
    final centerX = (position.x / cellSize).floor();
    final centerZ = (position.z / cellSize).floor();

    // Check 3x3 grid around the position
    for (int x = centerX - 1; x <= centerX + 1; x++) {
      for (int z = centerZ - 1; z <= centerZ + 1; z++) {
        final key = '$x,$z';
        if (_grid.containsKey(key)) {
          nearby.addAll(_grid[key]!);
        }
      }
    }
    return nearby;
  }

  Node? findNearestNode(Vector3 position, {double maxDistance = double.infinity}) {
    final nearby = getNearbyNodes(position);
    Node? nearest;
    double minDist = maxDistance;

    for (final node in nearby) {
      final dist = position.distanceTo(node.position);
      if (dist < minDist) {
        minDist = dist;
        nearest = node;
      }
    }

    // Fallback to full search only if nearby is empty and maxDistance is infinity
    if (nearest == null && maxDistance == double.infinity) {
        // This should rarely happen if the graph is well-distributed
        return null; 
    }

    return nearest;
  }
}
