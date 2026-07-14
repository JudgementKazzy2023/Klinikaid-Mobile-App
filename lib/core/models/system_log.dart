class SystemLog {
  final String id;
  final DateTime createdAt;
  final String userName;
  final String userRole;
  final String eventType;
  final String description;
  final String ipAddress;

  SystemLog({
    required this.id,
    required this.createdAt,
    required this.userName,
    required this.userRole,
    required this.eventType,
    required this.description,
    required this.ipAddress,
  });

  factory SystemLog.fromJson(Map<String, dynamic> json) {
    String name = 'System';
    String role = '';
    if (json['user'] is Map) {
      final userMap = json['user'] as Map;
      name = userMap['full_name'] as String? ?? userMap['name'] as String? ?? 'System';
      role = userMap['role'] as String? ?? '';
    } else if (json['user_name'] != null) {
      name = json['user_name'] as String? ?? 'System';
      role = json['user_role'] as String? ?? '';
    }
    
    return SystemLog(
      id: (json['id'] ?? '').toString(),
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String) 
          : (json['timestamp'] != null ? DateTime.parse(json['timestamp'] as String) : DateTime.now()),
      userName: name,
      userRole: role,
      eventType: json['event_type'] as String? ?? 'info',
      description: json['description'] as String? ?? '',
      ipAddress: json['ip_address'] as String? ?? '0.0.0.0',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'created_at': createdAt.toIso8601String(),
      'user': {
        'name': userName,
        'role': userRole,
      },
      'event_type': eventType,
      'description': description,
      'ip_address': ipAddress,
    };
  }
}
