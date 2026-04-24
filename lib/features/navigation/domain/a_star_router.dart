import 'package:vector_math/vector_math_64.dart';
import 'models/node.dart';

class PathRequestParams {
  final Map<String, Node> graph;
  final String startId;
  final String endId;
  final bool accessibilityMode;

  PathRequestParams({
    required this.graph,
    required this.startId,
    required this.endId,
    this.accessibilityMode = false,
  });
}

class AStarRouter {
  final Map<String, Node> graph;
  final bool accessibilityMode;

  AStarRouter(this.graph, {this.accessibilityMode = false});

  /// Isolated version of pathfinding to be used with Flutter's [compute]
  static List<Vector3>? findPathIsolated(PathRequestParams params) {
    return AStarRouter(params.graph, accessibilityMode: params.accessibilityMode)
        .findPath(params.startId, params.endId);
  }

  List<Vector3>? findPath(String startId, String endId) {
    if (!graph.containsKey(startId) || !graph.containsKey(endId)) return null;

    final openSet = PriorityQueue<_NodeWrapper>((a, b) => a.fScore.compareTo(b.fScore));
    final closedSet = <String>{};
    final cameFrom = <String, String>{};
    
    final gScore = <String, double>{startId: 0.0};
    final fScore = <String, double>{startId: _heuristic(startId, endId)};

    openSet.add(_NodeWrapper(startId, fScore[startId]!));

    while (openSet.isNotEmpty) {
      final current = openSet.removeFirst().id;

      if (current == endId) {
        return _reconstructPath(cameFrom, current);
      }

      closedSet.add(current);

      final currentNode = graph[current]!;
      for (final neighborEntry in currentNode.neighbors.entries) {
        final neighborId = neighborEntry.key;
        final connectionType = neighborEntry.value;

        if (closedSet.contains(neighborId)) continue;
        if (!graph.containsKey(neighborId)) continue;

        // Accessibility filtering
        if (accessibilityMode && connectionType == 'stairs') {
          continue; // Skip stairs in wheelchair mode
        }

        final neighborNode = graph[neighborId]!;
        final tentativeGScore = gScore[current]! + 
            currentNode.position.distanceTo(neighborNode.position);

        if (!gScore.containsKey(neighborId) || tentativeGScore < gScore[neighborId]!) {
          cameFrom[neighborId] = current;
          gScore[neighborId] = tentativeGScore;
          fScore[neighborId] = tentativeGScore + _heuristic(neighborId, endId);
          
          openSet.add(_NodeWrapper(neighborId, fScore[neighborId]!));
        }
      }
    }

    return null; // No path found
  }

  double _heuristic(String aId, String bId) {
    return graph[aId]!.position.distanceTo(graph[bId]!.position);
  }

  List<Vector3> _reconstructPath(Map<String, String> cameFrom, String current) {
    final path = <Vector3>[graph[current]!.position];
    while (cameFrom.containsKey(current)) {
      current = cameFrom[current]!;
      path.add(graph[current]!.position);
    }
    return path.reversed.toList();
  }
}

class _NodeWrapper {
  final String id;
  final double fScore;
  _NodeWrapper(this.id, this.fScore);
}

// Simple Priority Queue implementation since collection doesn't export one directly
class PriorityQueue<T> {
  final List<T> _heap = [];
  final int Function(T, T) comparator;

  PriorityQueue(this.comparator);

  bool get isNotEmpty => _heap.isNotEmpty;
  bool get isEmpty => _heap.isEmpty;

  void add(T element) {
    _heap.add(element);
    _bubbleUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) throw StateError('Queue is empty');
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  void _bubbleUp(int index) {
    while (index > 0) {
      int parent = (index - 1) ~/ 2;
      if (comparator(_heap[index], _heap[parent]) >= 0) break;
      _swap(index, parent);
      index = parent;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
      int left = 2 * index + 1;
      int right = 2 * index + 2;
      int smallest = index;

      if (left < _heap.length && comparator(_heap[left], _heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < _heap.length && comparator(_heap[right], _heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == index) break;
      _swap(index, smallest);
      index = smallest;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}
