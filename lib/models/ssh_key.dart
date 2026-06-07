class SshKey {
  const SshKey({
    required this.id,
    required this.name,
    this.comment,
  });

  final String id;
  final String name;
  final String? comment;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (comment != null) 'comment': comment,
      };

  factory SshKey.fromJson(Map<String, dynamic> json) => SshKey(
        id: json['id'] as String,
        name: json['name'] as String,
        comment: json['comment'] as String?,
      );
}
