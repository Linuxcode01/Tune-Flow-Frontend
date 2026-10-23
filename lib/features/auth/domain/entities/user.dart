/// Roles understood by the API (`USER`, `ARTIST`, `ADMIN`).
enum UserRole {
  user,
  artist,
  admin;

  static UserRole fromWire(String? value) {
    switch ((value ?? '').toUpperCase()) {
      case 'ARTIST':
        return UserRole.artist;
      case 'ADMIN':
        return UserRole.admin;
      default:
        return UserRole.user;
    }
  }

  String get wire => name.toUpperCase();

  bool get canManageCatalog => this == UserRole.artist || this == UserRole.admin;
}

/// The signed-in user, as returned by `/auth/*` and `/users/me`.
///
/// The JSON mapping lives on the entity because the API contract *is* the domain contract here -
/// introducing a separate DTO layer with identical fields would be ceremony. Parsing is defensive:
/// the backend omits null fields, so every accessor tolerates a missing key.
class User {
  const User({
    required this.id,
    required this.name,
    required this.email,
    this.profileImageUrl,
    this.role = UserRole.user,
    this.artistId,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Listener',
      email: json['email'] as String? ?? '',
      profileImageUrl: json['profileImageUrl'] as String?,
      role: UserRole.fromWire(json['role'] as String?),
      artistId: json['artistId'] as String?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String name;
  final String email;
  final String? profileImageUrl;
  final UserRole role;

  /// Present once the user has an artist profile (`ARTIST` accounts).
  final String? artistId;
  final DateTime? createdAt;

  bool get isArtist => role == UserRole.artist || artistId != null;

  /// Initials for the avatar fallback.
  String get initials {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String part) => part.isNotEmpty).toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return _firstLetter(parts.first);
    }
    return '${_firstLetter(parts.first)}${_firstLetter(parts.last)}';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'email': email,
        if (profileImageUrl != null) 'profileImageUrl': profileImageUrl,
        'role': role.wire,
        if (artistId != null) 'artistId': artistId,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      };

  User copyWith({String? name, String? email, String? profileImageUrl}) {
    return User(
      id: id,
      name: name ?? this.name,
      email: email ?? this.email,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      role: role,
      artistId: artistId,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is User && other.id == id && other.name == name && other.email == email;

  @override
  int get hashCode => Object.hash(id, name, email);
}

/// First character, upper-cased, tolerant of empty strings.
String _firstLetter(String value) => value.isEmpty ? '?' : value.substring(0, 1).toUpperCase();
