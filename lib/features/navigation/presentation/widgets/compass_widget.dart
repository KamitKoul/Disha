import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';

class CompassWidget extends StatelessWidget {
  final double size;
  const CompassWidget({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CompassEvent>(
      stream: FlutterCompass.events,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Icon(Icons.error, color: Colors.red);
        }

        double? direction = snapshot.data?.heading;

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Rotating Needle
              Transform.rotate(
                angle: ((direction ?? 0) * (math.pi / 180) * -1),
                child: CustomPaint(
                  size: Size(size * 0.8, size * 0.8),
                  painter: _CompassPainter(),
                ),
              ),
              // Center Dot
              Container(
                width: 4,
                height: 4,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill;

    final path = Path();
    
    // North Needle (Red)
    paint.color = Colors.redAccent;
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width * 0.65, size.height / 2);
    path.lineTo(size.width * 0.35, size.height / 2);
    path.close();
    canvas.drawPath(path, paint);

    // South Needle (White)
    paint.color = Colors.white;
    path.reset();
    path.moveTo(size.width / 2, size.height);
    path.lineTo(size.width * 0.65, size.height / 2);
    path.lineTo(size.width * 0.35, size.height / 2);
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
