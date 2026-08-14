class Division {
  final String id;
  final String name;
  final String description;

  const Division({
    required this.id,
    required this.name,
    required this.description,
  });

  factory Division.fromJson(Map<String, dynamic> json) {
    return Division(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
  };

  Division copyWith({
    String? id,
    String? name,
    String? description,
  }) {
    return Division(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
    );
  }
}
