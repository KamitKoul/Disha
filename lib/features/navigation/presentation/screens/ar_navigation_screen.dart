import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/navigation_bloc.dart';
import '../widgets/ar_view_widget.dart';
import '../widgets/minimap_widget.dart';
import '../widgets/trip_stats_row.dart';
import '../../../../core/services/ar_service.dart';
import '../../../../core/services/tts_service.dart';
import 'dart:math' as math;

class ArNavigationScreen extends StatefulWidget {
  const ArNavigationScreen({super.key});

  @override
  State<ArNavigationScreen> createState() => _ArNavigationScreenState();
}

class _ArNavigationScreenState extends State<ArNavigationScreen> {
  bool _showAr = false;
  Timer? _initTimer;
  bool _isMapping = false;
  String? _mappingLabel;
  String? _lastSpokenInstruction;
  int _lastSpokenTime = 0;
  int _lastUpdateTime = 0;

  @override
  void initState() {
    super.initState();
    TtsService().init();
    _initTimer = Timer(const Duration(milliseconds: 2000), () {
      if (mounted) {
        setState(() => _showAr = true);
        ArService().setOnCameraUpdate((position) {
          if (mounted) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastUpdateTime > 66) {
              _lastUpdateTime = now;
              context.read<NavigationBloc>().add(UpdateCurrentPosition(position));
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    ArService().dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: BlocConsumer<NavigationBloc, NavigationState>(
        listener: (context, state) {
          if (state.nextInstruction != null && state.nextInstruction != _lastSpokenInstruction) {
             final now = DateTime.now().millisecondsSinceEpoch;
             if (now - _lastSpokenTime > 3000) {
                _lastSpokenInstruction = state.nextInstruction;
                _lastSpokenTime = now;
                if (!state.isMuted) TtsService().speak(state.nextInstruction!);
             }
          }
        },
        listenWhen: (previous, current) {
          if (previous.route != current.route || previous.status != current.status) {
            if (current.status == NavigationStatus.navigating) {
              ArService().renderPath(current.route);
            }
          }
          if (previous.mappingPath.length != current.mappingPath.length && current.status == NavigationStatus.mapping) {
            ArService().renderBreadcrumbs(current.mappingPath);
          }
          if (previous.status == NavigationStatus.mapping && current.status != NavigationStatus.mapping) {
            ArService().clearBreadcrumbs();
          }
          return true;
        },
        builder: (context, state) {
          return Stack(
            fit: StackFit.expand,
            children: [
              if (_showAr) const ArViewWidget() else Container(color: const Color(0xFF0F172A), child: const Center(child: CircularProgressIndicator(color: Colors.white24))),
              
              Positioned(
                top: MediaQuery.of(context).padding.top + 16,
                left: 16,
                right: 16,
                child: _buildNavigationCard(context, state, theme),
              ),

              if (state.status == NavigationStatus.mapping)
                Positioned(
                  top: MediaQuery.of(context).padding.top + 16,
                  left: 16,
                  right: 16,
                  child: _buildMappingCard(context, state, theme),
                ),
              
              const Positioned(bottom: 32, right: 16, child: MinimapWidget()),

              // ACTION BUTTONS
              Positioned(
                bottom: 32,
                left: 16,
                right: 80, // Leave room for minimap
                child: Row(
                  children: [
                    if (!_isMapping)
                      FloatingActionButton.extended(
                        heroTag: 'log_btn',
                        onPressed: () => _startMappingFlow(context),
                        backgroundColor: theme.colorScheme.secondary,
                        icon: const Icon(Icons.add_location_alt_rounded),
                        label: const Text('Log Room'),
                      ),
                    if (_isMapping) ...[
                      FloatingActionButton.extended(
                        heroTag: 'wp_btn',
                        onPressed: () => context.read<NavigationBloc>().add(const AddWaypoint()),
                        backgroundColor: Colors.orangeAccent,
                        icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.black),
                        label: const Text('Mark Corner', style: TextStyle(color: Colors.black)),
                      ),
                      const SizedBox(width: 8),
                      FloatingActionButton(
                        heroTag: 'done_btn',
                        onPressed: () => _finishMapping(context, state),
                        backgroundColor: Colors.greenAccent,
                        child: const Icon(Icons.check_rounded, color: Colors.black),
                      ),
                    ]
                  ],
                ),
              ),

              if (state.status == NavigationStatus.arrived) _buildArrivalOverlay(context, theme)
              else if (state.status == NavigationStatus.navigating && state.route.isNotEmpty)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 100),
                      Transform.rotate(
                        angle: _calculateArrowAngle(state),
                        child: Icon(Icons.navigation_rounded, size: 120, color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                      ),
                      const Text('Follow the Arrow', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, shadows: [Shadow(blurRadius: 10, color: Colors.black)])),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  double _calculateArrowAngle(NavigationState state) {
    if (state.route.isEmpty || state.currentPosition == null || state.currentWaypointIndex >= state.route.length) return 0.0;
    final target = state.route[state.currentWaypointIndex];
    final current = state.currentPosition!;
    // In AR space, -Z is forward. atan2(dx, dz) gives angle from forward.
    return math.atan2(target.x - current.x, target.z - current.z) + math.pi;
  }

  Widget _buildNavigationCard(BuildContext context, NavigationState state, ThemeData theme) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.black.withValues(alpha: 0.7),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.directions, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.nextInstruction ?? "Ready to Navigate",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (state.status == NavigationStatus.navigating) ...[
              const Divider(color: Colors.white24, height: 20),
              TripStatsRow(
                eta: state.estimatedTimeRemaining,
                steps: state.stepsCount,
                h3Cell: state.currentH3Cell,
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildMappingCard(BuildContext context, NavigationState state, ThemeData theme) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      color: Colors.black.withValues(alpha: 0.8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Mapping: ${_mappingLabel ?? "Room"}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Waypoints marked: ${state.mappingPath.length}', style: const TextStyle(color: Colors.greenAccent)),
            const SizedBox(height: 8),
            const Text('Click "Mark Corner" at every turn you make', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  void _startMappingFlow(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('New Room', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(hintText: 'e.g. Office, Lab...', hintStyle: TextStyle(color: Colors.white24)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() { _isMapping = true; _mappingLabel = nameController.text; });
                context.read<NavigationBloc>().add(const StartMapping());
                Navigator.pop(context);
              }
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }

  void _finishMapping(BuildContext context, NavigationState state) {
    if (state.currentPosition != null && _mappingLabel != null) {
      context.read<NavigationBloc>().add(LogLocation(
        label: _mappingLabel!,
        category: 'Custom',
        position: state.currentPosition!,
      ));
      setState(() { _isMapping = false; _mappingLabel = null; });
      context.read<NavigationBloc>().add(const StopMapping());
    }
  }

  Widget _buildArrivalOverlay(BuildContext context, ThemeData theme) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 100, color: Colors.greenAccent),
            const SizedBox(height: 24),
            const Text('Arrived!', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 32),
            ElevatedButton(onPressed: () => Navigator.pop(context), child: const Text('Back to Home')),
          ],
        ),
      ),
    );
  }
}
