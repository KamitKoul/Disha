import 'dart:math';
import 'package:vector_math/vector_math_64.dart';
import '../../features/navigation/domain/models/node.dart';

class GpsConverter {
  /// Converts all nodes in the graph to local Vector3 coordinates relative to the start node.
  /// [graph] The map of nodes.
  /// [startNodeId] The ID of the node where the user scanned the QR code.
  /// [currentHeading] The compass heading (0-360 degrees) when the QR code was scanned.
  static void convertGraphToLocalCoordinates(
    Map<String, Node> graph,
    String startNodeId,
    double currentHeading,
  ) {
    final startNode = graph[startNodeId];
    if (startNode == null) return;

    // We take the existing Vector3 positions from MockData (which are meters)
    // and store their original state before rotation.
    final Map<String, Vector3> originalPositions = {};
    for (var node in graph.values) {
      originalPositions[node.id] = Vector3.copy(node.position);
    }

    // rotationRad is used to rotate the "Mock Map" to match the "Compass North"
    // So if a node is at (0,0,-5) [5m forward] in MockData, and we are facing North,
    // it stays at (0,0,-5) in the real world.
    final double rotationRad = -currentHeading * (pi / 180.0);

    for (var node in graph.values) {
      if (node.id == startNodeId) {
        node.position = Vector3(0, 0, 0);
        continue;
      }

      // Calculate relative offset in the "Mock" space (meters)
      final originalOffset = originalPositions[node.id]! - originalPositions[startNodeId]!;

      // Apply rotation to align with real-world orientation
      final double rx = originalOffset.x * cos(rotationRad) - originalOffset.z * sin(rotationRad);
      final double rz = originalOffset.x * sin(rotationRad) + originalOffset.z * cos(rotationRad);

      node.position = Vector3(rx, originalOffset.y, rz);
    }
  }

}
