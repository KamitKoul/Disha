import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'features/navigation/presentation/bloc/navigation_bloc.dart';
import 'features/navigation/presentation/screens/scanner_screen.dart';
import 'features/navigation/presentation/screens/ar_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DishaApp());
}

class DishaApp extends StatelessWidget {
  const DishaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => NavigationBloc(graph: {}),
      child: MaterialApp(
        title: 'Disha AR',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF38BDF8),
            secondary: Color(0xFFA78BFA),
            surface: Color(0xFF0F172A),
          ),
          scaffoldBackgroundColor: const Color(0xFF0F172A),
        ),
        // Start directly with the Welcome Screen
        home: const WelcomeScreen(),
        routes: {
          '/scanner': (context) => const ScannerScreen(),
          '/navigation': (context) => const ArNavigationScreen(),
        },
      ),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1E293B), Color(0xFF0F172A)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              // Icon with glow
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  boxShadow: [
                    BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.2), blurRadius: 40),
                  ],
                ),
                child: Icon(Icons.explore_rounded, size: 80, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 32),
              const Text(
                'DISHA AR',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 4),
              ),
              const Text(
                'Campus Navigation Redefined',
                style: TextStyle(color: Colors.white54, fontSize: 16, letterSpacing: 1),
              ),
              const Spacer(),
              // Action Area
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  children: [
                    const Text(
                      'To begin, please scan the floor anchor QR code located at the building entrance.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamed(context, '/scanner'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colorScheme.primary,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        child: const Text('SCAN & START', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
