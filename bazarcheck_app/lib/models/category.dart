class Category {
  final String id;
  final String name;
  final String description;
  final String divisionId;

  const Category({
    required this.id,
    required this.name,
    required this.description,
    required this.divisionId,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      divisionId: json['division_id'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'division_id': divisionId,
  };

  Category copyWith({
    String? id,
    String? name,
    String? description,
    String? divisionId,
  }) {
    return Category(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      divisionId: divisionId ?? this.divisionId,
    );
  }
}
