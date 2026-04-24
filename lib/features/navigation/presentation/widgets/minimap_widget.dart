import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' as math;
import '../bloc/navigation_bloc.dart';
import '../../domain/models/node.dart';
import 'dart:math' as math_lib;

class MinimapWidget extends StatefulWidget {
  const MinimapWidget({super.key});

  @override
  State<MinimapWidget> createState() => _MinimapWidgetState();
}

class _MinimapWidgetState extends State<MinimapWidget> {
  bool _isExpanded = false;
  final TransformationController _viewerController = TransformationController();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<NavigationBloc, NavigationState>(
      builder: (context, state) {
        // We show the minimap if we are in any state other than error or idle/scanning
        final isVisible = state.status != NavigationStatus.idle && 
                         state.status != NavigationStatus.scanning &&
                         state.status != NavigationStatus.error;

        if (!isVisible) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isExpanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: FloatingActionButton.small(
                  heroTag: 'minimap_zoom_reset',
                  onPressed: () => _viewerController.value = Matrix4.identity(),
                  backgroundColor: Colors.white,
                  child: const Icon(Icons.center_focus_strong, color: Colors.blueAccent),
                ),
              ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOutBack,
                width: _isExpanded ? MediaQuery.of(context).size.width * 0.8 : 70,
                height: _isExpanded ? MediaQuery.of(context).size.height * 0.4 : 70,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(_isExpanded ? 24 : 35),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(_isExpanded ? 24 : 35),
                  child: _isExpanded
                      ? LayoutBuilder(
                          builder: (context, constraints) {
                            final nodes = context.read<NavigationBloc>().graph;
                            return InteractiveViewer(
                              transformationController: _viewerController,
                              minScale: 0.5,
                              maxScale: 5.0,
                              child: GestureDetector(
                                onDoubleTap: () => _viewerController.value = Matrix4.identity(),
                                onTapUp: (details) => _handleMapTap(details, constraints, state, nodes),
                                child: CustomPaint(
                                  size: Size(constraints.maxWidth, constraints.maxHeight),
                                  painter: MapPainter(
                                    route: state.route,
                                    currentPosition: state.currentPosition,
                                    graph: nodes,
                                    destinationId: state.destinationId,
                                    accentColor: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            );
                          },
                        )
                      : const Icon(Icons.map_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _handleMapTap(TapUpDetails details, BoxConstraints constraints, NavigationState state, Map<String, Node> graph) {
    if (graph.isEmpty) return;

    // 1. Get tap position in local coordinates
    final tapPos = details.localPosition;
    
    // 2. We need the same bounds logic as the painter to reverse the mapping
    final bounds = _calculateBounds(graph.values, state.currentPosition);
    final scaleData = _calculateScale(bounds, Size(constraints.maxWidth, constraints.maxHeight));
    
    // 3. Reverse the projection
    const padding = 20.0;
    final worldX = (tapPos.dx - padding) / scaleData.scale + bounds.minX;
    final worldZ = (tapPos.dy - padding) / scaleData.scale + bounds.minZ;
    final tapWorldVector = math.Vector3(worldX, 0, worldZ);

    // 4. Find nearest node to tap
    String? nearestNodeId;
    double minDist = 2.0; // 2 meter radius for tap detection

    for (final node in graph.values) {
      final dist = tapWorldVector.distanceTo(math.Vector3(node.position.x, 0, node.position.z));
      if (dist < minDist) {
        minDist = dist;
        nearestNodeId = node.id;
      }
    }

    if (nearestNodeId != null) {
      HapticFeedback.lightImpact();
      context.read<NavigationBloc>().add(SetDestination(nearestNodeId));
    }
  }

  // Shared bounds logic
  _MapBounds _calculateBounds(Iterable<Node> nodes, math.Vector3? currentPos) {
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    void update(math.Vector3 p) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (var n in nodes) {
      update(n.position);
    }
    if (currentPos != null) update(currentPos);

    if (maxX - minX < 5.0) { minX -= 10; maxX += 10; }
    if (maxZ - minZ < 5.0) { minZ -= 10; maxZ += 10; }

    return _MapBounds(minX, maxX, minZ, maxZ);
  }

  _MapScale _calculateScale(_MapBounds b, Size size) {
    const padding = 20.0;
    final mapWidth = size.width - padding * 2;
    final mapHeight = size.height - padding * 2;
    final scaleX = mapWidth / (b.maxX - b.minX);
    final scaleZ = mapHeight / (b.maxZ - b.minZ);
    return _MapScale(math_lib.min(scaleX, scaleZ));
  }
}

class _MapBounds {
  final double minX, maxX, minZ, maxZ;
  _MapBounds(this.minX, this.maxX, this.minZ, this.maxZ);
}

class _MapScale {
  final double scale;
  _MapScale(this.scale);
}

class MapPainter extends CustomPainter {
  final List<math.Vector3> route;
  final math.Vector3? currentPosition;
  final Map<String, Node> graph;
  final String? destinationId;
  final Color accentColor;

  MapPainter({
    required this.route,
    this.currentPosition,
    required this.graph,
    this.destinationId,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Calculate Bounds and Scale
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;

    void updateBounds(math.Vector3 p) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    for (var node in graph.values) {
      updateBounds(node.position);
    }
    if (currentPosition != null) updateBounds(currentPosition!);

    if (maxX - minX < 5.0) { minX -= 10; maxX += 10; }
    if (maxZ - minZ < 5.0) { minZ -= 10; maxZ += 10; }

    const padding = 20.0;
    final mapWidth = size.width - padding * 2;
    final mapHeight = size.height - padding * 2;
    final scaleX = mapWidth / (maxX - minX);
    final scaleZ = mapHeight / (maxZ - minZ);
    final scale = math_lib.min(scaleX, scaleZ);

    Offset toOffset(math.Vector3 p) {
      return Offset(
        padding + (p.x - minX) * scale,
        padding + (p.z - minZ) * scale,
      );
    }

    // 2. Draw Connections (Background)
    final edgePaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 1.0;

    for (var node in graph.values) {
      final start = toOffset(node.position);
      for (var neighborId in node.neighborIds) {
        final neighbor = graph[neighborId];
        if (neighbor != null) {
          canvas.drawLine(start, toOffset(neighbor.position), edgePaint);
        }
      }
    }

    // 3. Draw Route
    if (route.isNotEmpty) {
      final pathPaint = Paint()
        ..color = accentColor.withValues(alpha: 0.6)
        ..strokeWidth = 5.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final path = Path();
      if (currentPosition != null) {
        path.moveTo(toOffset(currentPosition!).dx, toOffset(currentPosition!).dy);
        path.lineTo(toOffset(route.first).dx, toOffset(route.first).dy);
      } else {
        path.moveTo(toOffset(route.first).dx, toOffset(route.first).dy);
      }

      for (int i = 1; i < route.length; i++) {
        path.lineTo(toOffset(route[i]).dx, toOffset(route[i]).dy);
      }
      canvas.drawPath(path, pathPaint);
    }

    // 4. Draw Nodes
    for (var node in graph.values) {
      final isDestination = node.id == destinationId;
      final nodePaint = Paint()
        ..color = isDestination ? Colors.redAccent : Colors.white24
        ..style = PaintingStyle.fill;
      
      canvas.drawCircle(toOffset(node.position), isDestination ? 6.0 : 3.0, nodePaint);
      
      if (isDestination) {
        final glow = Paint()
          ..color = Colors.redAccent.withValues(alpha: 0.3)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(toOffset(node.position), 12.0, glow);
      }
    }

    // 5. Draw User Position
    if (currentPosition != null) {
      final userPaint = Paint()..color = accentColor;
      final userPos = toOffset(currentPosition!);
      
      // Outer glow
      canvas.drawCircle(userPos, 10.0, Paint()..color = accentColor.withValues(alpha: 0.2));
      canvas.drawCircle(userPos, 6.0, userPaint);
      canvas.drawCircle(userPos, 6.0, Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0);
    }
  }

  @override
  bool shouldRepaint(covariant MapPainter oldDelegate) => true;
}
