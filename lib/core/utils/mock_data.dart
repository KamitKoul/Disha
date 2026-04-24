import 'package:vector_math/vector_math_64.dart';
import '../../features/navigation/domain/models/node.dart';
import '../services/h3_service.dart';

class MockData {
  static Map<String, Node> get campusGraph {
    // We only keep the Entrance Anchor. All other rooms will be learned by the user.
    final nodes = [
      Node(
        id: 'home_entrance',
        label: 'Main Entrance (QR)',
        category: 'Anchor',
        position: Vector3(0, 0, 0),
        latitude: 19.130832,
        longitude: 72.844516,
        h3Cell: H3Service.getHex(19.130832, 72.844516),
        neighbors: {},
      ),
    ];



    return {for (var node in nodes) node.id: node};
  }
}


