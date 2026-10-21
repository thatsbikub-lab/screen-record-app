class Recording {
  const Recording({
    required this.id,
    required this.path,
    required this.title,
    required this.createdAt,
    required this.duration,
  });

  final String id;
  final String path;
  final String title;
  final DateTime createdAt;
  final Duration duration;

  Recording copyWith({String? title, String? path, Duration? duration}) {
    return Recording(
      id: id,
      path: path ?? this.path,
      title: title ?? this.title,
      createdAt: createdAt,
      duration: duration ?? this.duration,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'path': path,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
      };

  factory Recording.fromJson(Map<String, dynamic> json) => Recording(
        id: json['id']! as String,
        path: json['path']! as String,
        title: json['title']! as String,
        createdAt: DateTime.parse(json['createdAt']! as String),
        duration: Duration(milliseconds: json['durationMs']! as int),
      );
}


