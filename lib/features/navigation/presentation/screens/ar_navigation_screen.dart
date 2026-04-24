import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/navigation_bloc.dart';
import '../../../../core/services/ar_service.dart';
import '../../../../core/services/tts_service.dart';

import '../widgets/ar_view_widget.dart';
import '../widgets/minimap_widget.dart';
import '../widgets/compass_widget.dart';
import '../widgets/trip_stats_row.dart';
import 'destination_search_screen.dart';


class ArNavigationScreen extends StatefulWidget {
  const ArNavigationScreen({super.key});

  @override
  State<ArNavigationScreen> createState() => _ArNavigationScreenState();
}

class _ArNavigationScreenState extends State<ArNavigationScreen> {
    String? _lastSpokenInstruction;
    int _lastSpokenTime = 0; // Cooldown for TTS
  bool _showAr = false;
  Timer? _initTimer;
  
  // Mapping state
  bool _isMapping = false;
  String? _mappingLabel;

  // Optimization: Throttling updates
  int _lastUpdateTime = 0;

  @override
  void initState() {
    super.initState();
    TtsService().init();
    
    // Safety Delay: Wait 4 seconds before touching any camera hardware
    // This allows the Scanner to fully release its locks on Pixel devices.
    _initTimer = Timer(const Duration(milliseconds: 4000), () {
      if (mounted) {
        final navBloc = context.read<NavigationBloc>();
        setState(() => _showAr = true);
        ArService().setOnCameraUpdate((position) {
          if (mounted) {
            // Optimization: Throttle logic to ~15Hz (once every 66ms)
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - _lastUpdateTime > 66) {
              _lastUpdateTime = now;
              navBloc.add(UpdateCurrentPosition(position));
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
    TtsService().stop();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false, // Prevent AR view jitter when keyboard appears
      appBar: AppBar(
        title: Text(_isMapping ? 'Mapping Mode' : 'Navigating', style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => _showCancelDialog(context, theme),
        ),
        actions: [
          BlocBuilder<NavigationBloc, NavigationState>(
            builder: (context, state) {
              return IconButton(
                icon: Icon(
                  state.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  color: Colors.white,
                ),
                onPressed: () => context.read<NavigationBloc>().add(const ToggleVoice()),
              );
            },
          ),
        ],
      ),
      body: BlocConsumer<NavigationBloc, NavigationState>(
        listener: (context, state) {
          if (state.nextInstruction != null && state.nextInstruction != _lastSpokenInstruction && !state.isMuted) {
             final now = DateTime.now().millisecondsSinceEpoch;
             if (now - _lastSpokenTime > 2000) {
                _lastSpokenInstruction = state.nextInstruction;
                _lastSpokenTime = now;
                TtsService().speak(state.nextInstruction!);
             }
          }
        },
        listenWhen: (previous, current) {
          // Render full route when it changes
          if (previous.route != current.route || previous.status != current.status) {
            if (current.status == NavigationStatus.navigating) {
              ArService().renderPath(current.route);
            }
          }

          // Live Breadcrumbs during mapping
          if (previous.mappingPath.length != current.mappingPath.length && current.status == NavigationStatus.mapping) {
            ArService().renderBreadcrumbs(current.mappingPath);
          }

          // Cleanup when mapping stops
          if (previous.status == NavigationStatus.mapping && current.status != NavigationStatus.mapping) {
            ArService().clearBreadcrumbs();
          }

          return true;
        },
        builder: (context, state) {
          return Stack(
            fit: StackFit.expand,
            children: [
              // Native AR View (Delayed start)
              if (_showAr)
                const ArViewWidget()
              else
                Container(
                  color: const Color(0xFF0F172A),
                  child: const Center(
                    child: CircularProgressIndicator(color: Colors.white24),
                  ),
                ),
              
              // Top Navigation Dashboard

              Positioned(
                top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                left: 16,
                right: 16,
                child: _buildNavigationCard(context, state, theme),
              ),
              
              if (state.status == NavigationStatus.calculating)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: theme.colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          'Setting up AR Path to ${state.destinationId ?? "Destination"}...', 
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Move phone slowly to initialize tracking',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),

              if (state.status == NavigationStatus.mapping)
                Positioned(
                  top: MediaQuery.of(context).padding.top + kToolbarHeight + 8,
                  left: 16,
                  right: 16,
                  child: _buildMappingCard(context, state, theme),
                ),
              
              // Minimap
              const Positioned(
                bottom: 32,
                right: 16,
                child: MinimapWidget(),
              ),

              // Trace-Steps Mapping Button
              Positioned(
                bottom: 32,
                left: 16,
                child: FloatingActionButton.extended(
                  onPressed: () {
                    if (_isMapping) {
                      _finishMapping(context, state);
                    } else {
                      _startMappingFlow(context);
                    }
                  },
                  backgroundColor: _isMapping ? Colors.greenAccent : theme.colorScheme.secondary,
                  icon: Icon(_isMapping ? Icons.check_circle_rounded : Icons.add_location_alt_rounded, color: _isMapping ? Colors.black : Colors.white),
                  label: Text(
                    _isMapping ? 'Set $_mappingLabel Here' : 'Log Room', 
                    style: TextStyle(color: _isMapping ? Colors.black : Colors.white, fontWeight: FontWeight.bold)
                  ),
                ),
              ),



              // Arrival Indicator
              if (state.status == NavigationStatus.arrived)
                _buildArrivalOverlay(context, theme)
              else if (state.status == NavigationStatus.navigating && state.route.isNotEmpty)
                // 2D Directional Arrow Fallback
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 100),
                      Transform.rotate(
                        angle: _calculateArrowAngle(state),
                        child: Icon(
                          Icons.navigation_rounded,
                          size: 120,
                          color: theme.colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                      const Text(
                        'Follow the Arrow',
                        style: TextStyle(color: Colors.white54, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              
              if (state.status == NavigationStatus.mapping)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       Icon(Icons.add_location_alt_rounded, size: 80, color: Colors.greenAccent),
                       SizedBox(height: 16),
                       Text(
                         'WALK TO ROOM',
                         style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.w900, letterSpacing: 2),
                       ),
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
    
    // Calculate angle in 2D plane (X, Z) using math.atan2
    // We use the current waypoint index instead of .first to ensure the arrow moves as we progress
    return -1 * (math.pi / 2 + math.atan2(target.z - current.z, target.x - current.x));
  }



  void _showCancelDialog(BuildContext context, ThemeData theme) {
    showDialog(
      context: context,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('End Navigation?', style: TextStyle(color: Colors.white)),
          content: const Text('Are you sure you want to stop this navigation session?', style: TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep Going', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context);
              },
              child: Text('Stop', style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationCard(BuildContext context, NavigationState state, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _getInstructionIcon(state.nextInstruction),
                          key: ValueKey(state.nextInstruction),
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Text(
                              state.nextInstruction ?? 'Locating...',
                              key: ValueKey(state.nextInstruction),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          if (state.currentDistance != null)
                            Text(
                              '${state.currentDistance!.toStringAsFixed(1)} meters to next turn',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.white70,
                                letterSpacing: 0.2,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const CompassWidget(size: 36),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Divider(height: 1, color: Colors.white10),
                ),
                TripStatsRow(
                  eta: state.estimatedTimeRemaining,
                  steps: state.stepsCount,
                  h3Cell: state.currentH3Cell,
                ),

                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const DestinationSearchScreen()),
                          );
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.search_rounded, size: 18, color: theme.colorScheme.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  state.destinationId != null 
                                    ? 'To: ${state.destinationId}' 
                                    : 'Change Destination...',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600, 
                                    color: Colors.white.withValues(alpha: 0.8)
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(state.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _getStatusColor(state.status).withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        state.status.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: _getStatusColor(state.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMappingCard(BuildContext context, NavigationState state, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.edit_location_alt_rounded, color: Colors.greenAccent, size: 32),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mapping: ${_mappingLabel ?? "Unnamed"}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const Text(
                            'Walk to the center of the room...',
                            style: TextStyle(fontSize: 13, color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16.0),
                  child: Divider(height: 1, color: Colors.white10),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatItem('Distance', '${state.currentDistanceWalked?.toStringAsFixed(1)}m', Icons.straighten_rounded, theme),
                    _buildStatItem('Steps', '${state.stepsCount}', Icons.directions_walk_rounded, theme),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, ThemeData theme) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.greenAccent),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildArrivalOverlay(BuildContext context, ThemeData theme) {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              margin: const EdgeInsets.all(32),
              padding: const EdgeInsets.all(40.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle_rounded, size: 80, color: Colors.greenAccent),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Arrived!',
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'You have successfully arrived at your target location.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: const Color(0xFF0F172A),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('Back to Home', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
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
        title: const Text('Start Mapping', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('What room are you walking to?', style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. Kitchen, Lab...',
                hintStyle: TextStyle(color: Colors.white24),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar(); // Clear previous "TEST NOW" actions
                setState(() {
                  _isMapping = true;
                  _mappingLabel = nameController.text;
                });
                context.read<NavigationBloc>().add(const StartMapping());
                Navigator.pop(context);
              }
            },
            child: const Text('Start Walking'),
          ),
        ],
      ),
    );
  }

  void _finishMapping(BuildContext context, NavigationState state) {
    if (state.currentPosition != null && _mappingLabel != null) {
      final label = _mappingLabel!;
      final id = label.toLowerCase().replaceAll(' ', '_');
      
      context.read<NavigationBloc>().add(LogLocation(
        label: label,
        category: 'Custom',
        position: state.currentPosition!,
      ));
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved "$label" exactly here!'),
          backgroundColor: Colors.green.shade800,
          action: SnackBarAction(
            label: 'TEST NOW',
            textColor: Colors.white,
            onPressed: () {
              // Immediately start navigation to the room we just logged
              context.read<NavigationBloc>().add(SetDestination(id));
            },
          ),
          duration: const Duration(seconds: 5),
        ),
      );

      setState(() {
        _isMapping = false;
        _mappingLabel = null;
      });
      context.read<NavigationBloc>().add(const StopMapping());
    }
  }



  IconData _getInstructionIcon(String? instruction) {

    if (instruction == null) return Icons.navigation;
    if (instruction.contains('arrived')) return Icons.flag;
    if (instruction.contains('left')) return Icons.turn_left;
    if (instruction.contains('right')) return Icons.turn_right;
    return Icons.straight;
  }

  Color _getStatusColor(NavigationStatus status) {
    switch (status) {
      case NavigationStatus.navigating: return Colors.greenAccent;
      case NavigationStatus.arrived: return Colors.blueAccent;
      case NavigationStatus.error: return Colors.redAccent;
      default: return Colors.orangeAccent;
    }
  }
}
