/// Music genre, the primary axis of the catalogue and of recommendations.
class Genre {
  const Genre({
    required this.id,
    required this.name,
    required this.slug,
    this.coverImageUrl,
  });

  factory Genre.fromJson(Map<String, dynamic> json) {
    return Genre(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      coverImageUrl: json['coverImageUrl'] as String?,
    );
  }

  final String id;
  final String name;
  final String slug;
  final String? coverImageUrl;

  @override
  bool operator ==(Object other) => other is Genre && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => name;
}
