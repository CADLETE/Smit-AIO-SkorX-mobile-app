/// An organization role held by the signed-in user, from `GET /auth/me`.
class Membership {
  const Membership({
    required this.organizationId,
    required this.organizationName,
    required this.role,
    required this.capabilities,
  });

  final String organizationId;
  final String organizationName;

  /// owner, tournament_admin, referee, scorer, check_in_staff, finance, viewer.
  final String role;

  /// What the role allows (backend/src/organizations/permissions.ts). Used to
  /// hide what the user cannot do; the server enforces it regardless.
  final Set<String> capabilities;

  bool can(String capability) => capabilities.contains(capability);

  Map<String, dynamic> toJson() => {
        'organizationId': organizationId,
        'organizationName': organizationName,
        'role': role,
        'capabilities': capabilities.toList(),
      };

  factory Membership.fromJson(Map<String, dynamic> json) => Membership(
        organizationId: json['organizationId'] as String,
        organizationName: json['organizationName'] as String,
        role: json['role'] as String,
        capabilities: {...((json['capabilities'] as List<dynamic>?) ?? const []).cast<String>()},
      );
}

class CurrentUser {
  const CurrentUser({
    required this.id,
    required this.name,
    required this.phone,
    required this.profileComplete,
    required this.memberships,
    this.email,
    this.xCode,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;

  /// The player's X code ("7K2Q", see `XCode`); null until the server has
  /// assigned one.
  final String? xCode;

  /// False right after a phone number's first sign-in: ask for name and details.
  final bool profileComplete;
  final List<Membership> memberships;

  factory CurrentUser.fromJson(Map<String, dynamic> json) => CurrentUser(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        email: json['email'] as String?,
        xCode: json['xCode'] as String?,
        profileComplete: json['profileComplete'] as bool? ?? true,
        memberships: ((json['memberships'] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(Membership.fromJson)
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        if (xCode != null) 'xCode': xCode,
        'profileComplete': profileComplete,
        'memberships': memberships.map((m) => m.toJson()).toList(),
      };

  String get firstName => name.trim().split(' ').first;
}
