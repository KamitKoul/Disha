import 'package:vector_math/vector_math_64.dart';

class PathSimplifier {
  /// Simplifies a path using the Ramer-Douglas-Peucker algorithm.
  /// [epsilon] is the maximum perpendicular distance allowed from a point to the line segment.
  static List<Vector3> simplify(List<Vector3> points, {double epsilon = 0.1}) {
    if (points.length < 3) return points;

    return _rdp(points, 0, points.length - 1, epsilon);
  }

  static List<Vector3> _rdp(List<Vector3> points, int start, int end, double epsilon) {
    double maxDist = 0.0;
    int index = 0;

    for (int i = start + 1; i < end; i++) {
      double dist = _perpendicularDistance(points[i], points[start], points[end]);
      if (dist > maxDist) {
        index = i;
        maxDist = dist;
      }
    }

    if (maxDist > epsilon) {
      List<Vector3> res1 = _rdp(points, start, index, epsilon);
      List<Vector3> res2 = _rdp(points, index, end, epsilon);

      return [...res1.sublist(0, res1.length - 1), ...res2];
    } else {
      return [points[start], points[end]];
    }
  }

  static double _perpendicularDistance(Vector3 p, Vector3 a, Vector3 b) {
    Vector3 ab = b - a;
    Vector3 ap = p - a;

    if (ab.length2 == 0) return ap.length;

    // Projection of ap onto ab
    double t = ap.dot(ab) / ab.length2;
    
    if (t < 0.0) return ap.length;
    if (t > 1.0) return p.distanceTo(b);

    Vector3 projection = a + ab * t;
    return p.distanceTo(projection);
  }
}
