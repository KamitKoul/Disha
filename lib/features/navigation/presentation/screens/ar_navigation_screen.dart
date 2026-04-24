import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
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
  bool _isCalibrated = false;

  @override
  void initState() {
    super.initState();
    TtsService().init();
    _initTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _showAr = true);
        ArService().setOnCameraUpdate((position) {
          if (mounted) {
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastUpdateTime > 100) {
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
      backgroundColor: const Color(0xFF0F172A),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // FIXED AR LAYER: Move outside BlocConsumer to stop jitter
          if (_showAr) const ArViewWidget(),
          
          // UI OVERLAY LAYER
          BlocConsumer<NavigationBloc, NavigationState>(
            listenWhen: (prev, curr) => prev.status != curr.status || prev.currentNodeId != curr.currentNodeId || prev.nextInstruction != curr.nextInstruction,
            listener: (context, state) {
              if (state.currentNodeId != null && !_isCalibrated) {
                setState(() => _isCalibrated = true);
              }
              if (state.nextInstruction != null && state.nextInstruction != _lastSpokenInstruction) {
                 final now = DateTime.now().millisecondsSinceEpoch;
                 if (now - _lastSpokenTime > 4000) {
                    _lastSpokenInstruction = state.nextInstruction;
                    _lastSpokenTime = now;
                    if (!state.isMuted) TtsService().speak(state.nextInstruction!);
                 }
              }
              
              // Native path rendering listeners
              if (state.status == NavigationStatus.navigating) {
                ArService().renderPath(state.route);
              }
              if (state.status == NavigationStatus.mapping) {
                ArService().renderBreadcrumbs(state.mappingPath);
              }
            },
            buildWhen: (prev, curr) => 
                prev.status != curr.status || 
                prev.mappingPath.length != curr.mappingPath.length ||
                prev.stepsCount != curr.stepsCount ||
                prev.currentWaypointIndex != curr.currentWaypointIndex ||
                prev.currentNodeId != curr.currentNodeId,
            builder: (context, state) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  if (!_isCalibrated) _buildCalibrationOverlay(context, theme),

                  if (_isCalibrated)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 16,
                      right: 16,
                      child: _buildNavigationCard(context, state, theme),
                    ),

                  if (state.status == NavigationStatus.mapping)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 12,
                      left: 16,
                      right: 16,
                      child: _buildMappingCard(context, state, theme),
                    ),
                  
                  if (_isCalibrated && state.status != NavigationStatus.mapping)
                    const Positioned(bottom: 32, right: 16, child: MinimapWidget()),

                  if (_isCalibrated)
                    Positioned(
                      bottom: 32,
                      left: 16,
                      child: _buildActionButtons(context, state, theme),
                    ),

                  if (state.status == NavigationStatus.arrived) 
                    _buildArrivalOverlay(context, theme)
                  else if (state.status == NavigationStatus.navigating && state.route.isNotEmpty)
                    _buildDirectionalArrow(state, theme),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalibrationOverlay(BuildContext context, ThemeData theme) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_scanner_rounded, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 24),
            const Text('WAITING FOR CALIBRATION', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1.5)),
            const Padding(
              padding: EdgeInsets.all(32.0),
              child: Text('Scan the QR code to start.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            ),
            const CircularProgressIndicator(color: Colors.blueAccent),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, NavigationState state, ThemeData theme) {
    if (_isMapping) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            heroTag: 'wp_btn',
            onPressed: () => context.read<NavigationBloc>().add(const AddWaypoint()),
            backgroundColor: Colors.orangeAccent,
            icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.black),
            label: const Text('Mark Corner', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 12),
          FloatingActionButton(
            heroTag: 'done_btn',
            onPressed: () => _finishMapping(context, state),
            backgroundColor: Colors.greenAccent,
            child: const Icon(Icons.check_rounded, color: Colors.black, size: 32),
          ),
        ],
      );
    }

    return FloatingActionButton.extended(
      heroTag: 'log_btn',
      onPressed: () => _startMappingFlow(context),
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      icon: const Icon(Icons.add_location_alt_rounded),
      label: const Text('Add New Room', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildDirectionalArrow(NavigationState state, ThemeData theme) {
    // Arrow needs high-frequency updates, so we use a separate BlocBuilder for just the rotation
    return BlocBuilder<NavigationBloc, NavigationState>(
      buildWhen: (prev, curr) => prev.currentPosition != curr.currentPosition || prev.currentWaypointIndex != curr.currentWaypointIndex,
      builder: (context, state) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 120),
              Transform.rotate(
                angle: _calculateArrowAngle(state),
                child: Icon(Icons.navigation_rounded, size: 100, color: theme.colorScheme.primary.withValues(alpha: 0.8)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                child: const Text('FOLLOW ARROW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 1)),
              ),
            ],
          ),
        );
      },
    );
  }

  double _calculateArrowAngle(NavigationState state) {
    if (state.route.isEmpty || state.currentPosition == null || state.currentWaypointIndex >= state.route.length) return 0.0;
    final target = state.route[state.currentWaypointIndex];
    final current = state.currentPosition!;
    double dx = target.x - current.x;
    double dz = target.z - current.z;
    return math.atan2(dx, -dz);
  }

  Widget _buildNavigationCard(BuildContext context, NavigationState state, ThemeData theme) {
    return Card(
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: const Color(0xFF1E293B).withValues(alpha: 0.9),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.2), shape: BoxShape.circle),
                  child: Icon(Icons.directions_rounded, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    state.nextInstruction ?? "Calibrated & Ready",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (state.status == NavigationStatus.navigating) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12.0),
                child: Divider(color: Colors.white10, height: 1),
              ),
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
      elevation: 12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      color: const Color(0xFF0F172A).withValues(alpha: 0.95),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.edit_location_alt_rounded, color: Colors.orangeAccent),
                const SizedBox(width: 12),
                Text('Mapping: ${_mappingLabel ?? "Room"}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildSmallStat('Corners', '${state.mappingPath.length}', Colors.orangeAccent),
                _buildSmallStat('Distance', '${state.currentDistanceWalked?.toStringAsFixed(1)}m', Colors.blueAccent),
                _buildSmallStat('Steps', '${state.stepsCount}', Colors.greenAccent),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(label.toUpperCase(), style: const TextStyle(color: Colors.white38, fontSize: 9, fontWeight: FontWeight.w800)),
      ],
    );
  }

  void _startMappingFlow(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Name this Location', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'e.g. Server Room, Office...',
            hintStyle: const TextStyle(color: Colors.white24),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('CANCEL', style: TextStyle(color: Colors.white38))),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() { _isMapping = true; _mappingLabel = nameController.text; });
                context.read<NavigationBloc>().add(const StartMapping());
                Navigator.pop(dialogContext);
              }
            },
            style: ElevatedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('START MAPPING'),
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
      color: Colors.black.withValues(alpha: 0.9),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stars_rounded, size: 120, color: Colors.greenAccent),
            const SizedBox(height: 24),
            const Text('YOU HAVE ARRIVED', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: () => Navigator.pop(context), 
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
              child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
