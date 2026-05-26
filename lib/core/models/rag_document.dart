class RagDocument {
  final String id;
  final String title;
  final String content;
  final List<double> embedding;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  RagDocument({
    required this.id,
    required this.title,
    required this.content,
    required this.embedding,
    this.metadata,
    required this.createdAt,
  });

  factory RagDocument.fromJson(Map<String, dynamic> json) {
    final rawEmbedding = json['embedding'];
    final parsedEmbedding = rawEmbedding is List
        ? rawEmbedding.map((e) => (e as num).toDouble()).toList()
        : <double>[];

    return RagDocument(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      embedding: parsedEmbedding,
      metadata: json['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'embedding': embedding,
      'metadata': metadata,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
