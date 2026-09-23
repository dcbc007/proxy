class ProxySubscription {
  ProxySubscription({
    required this.id,
    required this.name,
    required this.url,
    this.enabled = true,
    this.nodeCount = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String id;
  String name;
  String url;
  bool enabled;
  int nodeCount;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'enabled': enabled,
        'nodeCount': nodeCount,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory ProxySubscription.fromJson(Map<String, dynamic> j) => ProxySubscription(
        id: j['id'] ?? '',
        name: j['name'] ?? '订阅',
        url: j['url'] ?? '',
        enabled: j['enabled'] ?? true,
        nodeCount: (j['nodeCount'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
      );
}
