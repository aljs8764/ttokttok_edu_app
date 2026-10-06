/// AuthController.AuthResponse / UserResponse (백엔드)
enum Role {
  owner,
  admin,
  teacher,
  parent;

  static Role parse(String v) => Role.values.firstWhere((r) => r.name == v.toLowerCase(), orElse: () => Role.parent);

  bool get isStaff => this != Role.parent;
  bool get isManager => this == Role.owner || this == Role.admin;

  String get label => switch (this) {
        Role.owner => '원장',
        Role.admin => '실장',
        Role.teacher => '교사',
        Role.parent => '학부모',
      };
}

class Membership {
  const Membership({required this.institutionId, required this.institutionName, required this.role});

  final String institutionId;
  final String institutionName;
  final Role role;

  factory Membership.fromJson(Map<String, dynamic> j) => Membership(
        institutionId: j['institutionId'] as String,
        institutionName: j['institutionName'] as String,
        role: Role.parse(j['role'] as String),
      );

  Map<String, dynamic> toJson() => {'institutionId': institutionId, 'institutionName': institutionName, 'role': role.name.toUpperCase()};
}

class AppUser {
  const AppUser({required this.id, required this.name, required this.mustChangePassword, required this.memberships});

  final String id;
  final String name;
  final bool mustChangePassword;
  final List<Membership> memberships;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String,
        mustChangePassword: j['mustChangePassword'] as bool? ?? false,
        memberships: (j['memberships'] as List).map((m) => Membership.fromJson(m as Map<String, dynamic>)).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mustChangePassword': mustChangePassword,
        'memberships': memberships.map((m) => m.toJson()).toList(),
      };

  List<Membership> get staffMemberships => memberships.where((m) => m.role.isStaff).toList();

  AppUser copyWith({bool? mustChangePassword}) =>
      AppUser(id: id, name: name, mustChangePassword: mustChangePassword ?? this.mustChangePassword, memberships: memberships);
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken, required this.accessExpiresAt});

  final String accessToken;
  final String refreshToken;
  final DateTime accessExpiresAt;

  factory TokenPair.fromJson(Map<String, dynamic> j) => TokenPair(
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
        accessExpiresAt: DateTime.parse(j['accessExpiresAt'] as String),
      );

  /// 만료 30초 전부터는 만료로 본다 (요청 도중 만료 방지)
  bool get accessExpired => DateTime.now().isAfter(accessExpiresAt.subtract(const Duration(seconds: 30)));
}
