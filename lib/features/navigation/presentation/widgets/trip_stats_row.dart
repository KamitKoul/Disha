import 'package:flutter/material.dart';
import '../../../../core/services/h3_service.dart';


class TripStatsRow extends StatelessWidget {
  final Duration eta;
  final int steps;
  final String? h3Cell;
  
  const TripStatsRow({
    super.key,
    required this.eta,
    required this.steps,
    this.h3Cell,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(
          context,
          Icons.access_time_rounded,
          _formatDuration(eta),
          'ETA',
          theme.colorScheme.primary,
        ),
        Container(width: 1, height: 24, color: Colors.white10),
        _buildStatItem(
          context,
          Icons.directions_walk_rounded,
          steps.toString(),
          'STEPS',
          Colors.greenAccent,
        ),
        Container(width: 1, height: 24, color: Colors.white10),
        _buildStatItem(
          context,
          Icons.grid_3x3_rounded,
          H3Service.getZoneName(h3Cell ?? 'unknown_hex'),
          'ZONE',
          theme.colorScheme.secondary,
        ),
      ],
    );
  }


  Widget _buildStatItem(BuildContext context, IconData icon, String value, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds % 60}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
}
