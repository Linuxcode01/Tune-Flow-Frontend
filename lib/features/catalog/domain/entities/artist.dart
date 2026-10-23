/// Compact artist reference embedded in song payloads.
class ArtistSummary {
  const ArtistSummary({
    required this.id,
    required this.name,
    this.profileImageUrl,
    this.verified = false,
  });

  factory ArtistSummary.fromJson(Map<String, dynamic> json) {
    return ArtistSummary(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown artist',
      profileImageUrl: json['profileImageUrl'] as String?,
      verified: json['verified'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final String? profileImageUrl;
  final bool verified;

  @override
  bool operator ==(Object other) => other is ArtistSummary && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Full artist profile (`GET /artists/{id}`, `GET /artists/me`).
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.bio,
    this.profileImageUrl,
    this.country,
    this.verified = false,
    this.followerCount = 0,
    this.songCount = 0,
    this.albumCount = 0,
    this.userId,
    this.following,
    this.createdAt,
  });

  factory Artist.fromJson(Map<String, dynamic> json) {
    return Artist(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Unknown artist',
      bio: json['bio'] as String?,
      profileImageUrl: json['profileImageUrl'] as String?,
      country: json['country'] as String?,
      verified: json['verified'] as bool? ?? false,
      followerCount: (json['followerCount'] as num?)?.toInt() ?? 0,
      songCount: (json['songCount'] as num?)?.toInt() ?? 0,
      albumCount: (json['albumCount'] as num?)?.toInt() ?? 0,
      userId: json['userId'] as String?,
      following: json['following'] as bool?,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String id;
  final String name;
  final String? bio;
  final String? profileImageUrl;
  final String? country;
  final bool verified;
  final int followerCount;
  final int songCount;
  final int albumCount;
  final String? userId;

  /// `null` for anonymous callers.
  final bool? following;
  final DateTime? createdAt;

  bool get isFollowed => following ?? false;

  ArtistSummary toSummary() => ArtistSummary(
        id: id,
        name: name,
        profileImageUrl: profileImageUrl,
        verified: verified,
      );

  Artist copyWith({bool? following, int? followerCount, String? name, String? bio, String? profileImageUrl}) {
    return Artist(
      id: id,
      name: name ?? this.name,
      bio: bio ?? this.bio,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      country: country,
      verified: verified,
      followerCount: followerCount ?? this.followerCount,
      songCount: songCount,
      albumCount: albumCount,
      userId: userId,
      following: following ?? this.following,
      createdAt: createdAt,
    );
  }

  @override
  bool operator ==(Object other) => other is Artist && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
