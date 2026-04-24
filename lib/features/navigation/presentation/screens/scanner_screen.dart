import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';


import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../bloc/navigation_bloc.dart';
import '../widgets/destination_picker_sheet.dart';
import 'package:permission_handler/permission_handler.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  final MobileScannerController controller = MobileScannerController();
  bool _hasPermission = false;
  bool _hasScanned = false;
  bool _showingSheet = false;
  late AnimationController _animationController;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  Future<void> _checkPermission() async {
    final statuses = await [
      Permission.camera,
      Permission.location,
    ].request();
    
    if (mounted) {
      setState(() {
        _hasPermission = (statuses[Permission.camera]?.isGranted ?? false) && 
                         (statuses[Permission.location]?.isGranted ?? false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Localize', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: BlocListener<NavigationBloc, NavigationState>(
        listener: (context, state) {
          if (state.currentNodeId != null && !_showingSheet && !_hasScanned) {
            if (state.destinationId == null) {
              _showDestinationPicker(this.context);
            } else {
              Navigator.pushReplacementNamed(this.context, '/navigation');
            }
          }
          
          if (state.status == NavigationStatus.error) {
            // Restart camera if there was a localization error
            if (mounted) {
              setState(() => _hasScanned = false);
            }
            _restartScanner();

            ScaffoldMessenger.of(this.context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage ?? 'Error', style: const TextStyle(color: Colors.white)),
                backgroundColor: Colors.red.shade800,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },

        child: _hasPermission
            ? Stack(
                fit: StackFit.expand,
                children: [
                  if (!_hasScanned)
                    MobileScanner(
                      controller: controller,
                      onDetect: (capture) async {
                        if (_hasScanned || _isDisposed) return;
                        final List<Barcode> barcodes = capture.barcodes;
                        
                        for (final barcode in barcodes) {
                          final rawValue = barcode.rawValue;
                          if (rawValue != null) {
                            // Success Vibration
                            HapticFeedback.mediumImpact();
                            if (mounted) {
                              setState(() => _hasScanned = true);
                            }
                            
                            try {
                              // 1. Try to decode as JSON
                              String? nodeId;
                              try {
                                final data = jsonDecode(rawValue);
                                nodeId = data['id'] as String?;
                              } catch (e) {
                                // 2. Fallback to raw text if it's not JSON
                                nodeId = rawValue;
                              }
                              
                              if (nodeId != null) {
                                // Capture Bloc before async gap
                                final navBloc = context.read<NavigationBloc>();
                                
                                // HARD STOP: Release hardware immediately
                                try {
                                  await controller.stop();
                                } catch (e) {
                                  debugPrint('Scanner stop error: $e');
                                }
                                
                                if (!mounted) return;

                                double heading = 0.0;
                                try {
                                  final event = await FlutterCompass.events?.first;
                                  if (event?.heading != null) heading = event!.heading!;
                                } catch (e) {
                                  debugPrint('Compass error: $e');
                                }

                                if (!mounted) return;
                                navBloc.add(ScanQRCode(
                                  rawValue.contains('{') ? rawValue : '{"id":"$nodeId"}', 
                                  heading
                                ));
                                
                                // Show picker if not automatically navigated
                                _showDestinationPicker(this.context);
                              }
                            } catch (e) {
                              if (mounted) {
                                setState(() => _hasScanned = false);
                                _restartScanner();
                              }
                            }
                            break;
                          }
                        }

                      },
                    ),

                  
                  // Dark overlay with cutout
                  ColorFiltered(
                    colorFilter: ColorFilter.mode(Colors.black.withValues(alpha: 0.8), BlendMode.srcOut),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.black,
                            backgroundBlendMode: BlendMode.dstOut,
                          ),
                        ),
                        Center(
                          child: Container(
                            height: 250,
                            width: 250,
                            decoration: BoxDecoration(
                              color: Colors.white, // This cuts out the transparent area
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Viewfinder Border and Animation
                  Center(
                    child: SizedBox(
                      height: 250,
                      width: 250,
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.8), width: 3),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          AnimatedBuilder(
                            animation: _animationController,
                            builder: (context, child) {
                              return Positioned(
                                top: _animationController.value * 240,
                                left: 0,
                                right: 0,
                                child: Container(
                                  height: 3,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    boxShadow: [
                                      BoxShadow(color: theme.colorScheme.primary, blurRadius: 10, spreadRadius: 2),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Glassmorphic Instruction Panel
                  Positioned(
                    bottom: 60,
                    left: 32,
                    right: 32,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [

                              const Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                              const SizedBox(height: 12),
                              const Text(
                                'Scan Start Anchor',
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Align the QR code within the frame to initialize your position.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.white70, fontSize: 14),
                              ),
                              const SizedBox(height: 20),
                              // New "Quick Map" button
                              OutlinedButton.icon(
                                onPressed: () async {
                                  if (!mounted) return;
                                  // Capture context members before async gaps
                                  final navBloc = context.read<NavigationBloc>();
                                  final navigator = Navigator.of(this.context);
                                  
                                  // 1. Tell the brain we are at the door
                                  if (mounted) {
                                    setState(() {
                                      _hasScanned = true;
                                      _showingSheet = true; 
                                    });
                                  }
                                  
                                  navBloc.add(const ScanQRCode('{"id":"home_entrance"}', 0.0));
                                  
                                  // 2. Shut down the scanner hardware safely
                                  try {
                                    await controller.stop();
                                  } catch (e) {
                                    debugPrint('Scanner stop error: $e');
                                  }
                                  
                                  // 3. Jump straight to the AR camera for mapping
                                  if (mounted) {
                                    navigator.pushReplacementNamed('/navigation');
                                  }
                                },

                                icon: const Icon(Icons.add_road_rounded, color: Colors.white),
                                label: const Text('New Map Session', style: TextStyle(color: Colors.white)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.white30),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],

                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              )
            : const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_alt, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('Camera permission required to scan anchors'),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _isDisposed = true;
    controller.dispose();
    _animationController.dispose();
    super.dispose();
  }


  void _restartScanner() async {
    if (_hasScanned || _isDisposed) return;
    try {
      // Small delay to ensure any previous lifecycle events finished
      await Future.delayed(const Duration(milliseconds: 300));
      if (!_isDisposed) {
        await controller.start();
      }
    } catch (e) {
      debugPrint('Scanner restart error: $e');
    }
  }


  void _showDestinationPicker(BuildContext context) async {
    if (_showingSheet || !mounted) return;
    
    setState(() => _showingSheet = true);
    
    final navigator = Navigator.of(this.context);
    
    final result = await showModalBottomSheet<bool>(
      context: this.context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const DestinationPickerSheet(),
    );

    if (mounted) {
      setState(() => _showingSheet = false);
      if (result == true) {
        // Safety Delay: 1s for full hardware camera release
        await Future.delayed(const Duration(milliseconds: 1000));
        
        if (mounted) {
          navigator.pushReplacementNamed('/navigation');
        }
      } else {
        if (mounted) {
          setState(() => _hasScanned = false);
          _restartScanner();
        }
      }
    }
  }
}
