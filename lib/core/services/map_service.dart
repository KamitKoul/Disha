import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vector_math/vector_math_64.dart';
import '../../features/navigation/domain/models/node.dart';



class MapService {
  static const String _key = 'custom_map_nodes';

  static Future<void> saveNode(Node node) async {
    final prefs = await SharedPreferences.getInstance();
    final nodes = await loadNodes();
    nodes[node.id] = node;
    
    final encoded = jsonEncode(nodes.map((key, value) => MapEntry(key, _nodeToJson(value))));
    await prefs.setString(_key, encoded);
  }

  static Future<void> deleteNode(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final nodes = await loadNodes();
    nodes.remove(id);
    
    final encoded = jsonEncode(nodes.map((key, value) => MapEntry(key, _nodeToJson(value))));
    await prefs.setString(_key, encoded);
  }


  static Future<Map<String, Node>> loadNodes() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encoded = prefs.getString(_key);
    if (encoded == null) return {};

    final Map<String, dynamic> decoded = jsonDecode(encoded);
    return decoded.map((key, value) => MapEntry(key, _nodeFromJson(value)));
  }

  static Map<String, dynamic> _nodeToJson(Node node) => {
    'id': node.id,
    'label': node.label,
    'category': node.category,
    'px': node.position.x,
    'py': node.position.y,
    'pz': node.position.z,
    'lat': node.latitude,
    'lng': node.longitude,
    'h3': node.h3Cell,
    'neighbors': node.neighbors,
    'floor': node.floor,
    'tags': node.tags,
  };

  static Node _nodeFromJson(Map<String, dynamic> json) {
    Map<String, String> neighbors = {};
    final rawNeighbors = json['neighbors'];
    if (rawNeighbors is List) {
      for (var id in rawNeighbors) {
        neighbors[id as String] = 'walk';
      }
    } else if (rawNeighbors is Map) {
      neighbors = Map<String, String>.from(rawNeighbors);
    }

    return Node(
      id: json['id'],
      label: json['label'],
      category: json['category'],
      position: Vector3(json['px'], json['py'], json['pz']),
      latitude: json['lat'],
      longitude: json['lng'],
      h3Cell: json['h3'],
      neighbors: neighbors,
      floor: json['floor'] ?? 0,
      tags: List<String>.from(json['tags'] ?? []),
    );
  }
}
