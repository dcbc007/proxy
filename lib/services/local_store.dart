import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/proxy_node.dart';
import '../models/subscription.dart';

class LocalStore {
  static const _nodesKey = 'nodes_v1';
  static const _subsKey = 'subscriptions_v1';
  static const _selectedKey = 'selected_node_v1';

  Future<List<ProxyNode>> loadNodes() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_nodesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return ProxyNode.decodeList(raw);
    } catch (_) {
      return [];
    }
  }

  Future<void> saveNodes(List<ProxyNode> nodes) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_nodesKey, ProxyNode.encodeList(nodes));
  }

  Future<List<ProxySubscription>> loadSubscriptions() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_subsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => ProxySubscription.fromJson(e)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveSubscriptions(List<ProxySubscription> subs) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_subsKey, jsonEncode(subs.map((e) => e.toJson()).toList()));
  }

  Future<String?> loadSelectedNodeId() async {
    final p = await SharedPreferences.getInstance();
    return p.getString(_selectedKey);
  }

  Future<void> saveSelectedNodeId(String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_selectedKey, id);
  }
}
