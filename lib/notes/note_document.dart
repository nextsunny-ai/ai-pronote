enum InkTool { pen, highlighter, eraser }

class InkPoint {
  const InkPoint({required this.x, required this.y, required this.pressure});

  final double x;
  final double y;
  final double pressure;

  Map<String, Object> toJson() => {'x': x, 'y': y, 'pressure': pressure};

  factory InkPoint.fromJson(Map<String, Object?> json) => InkPoint(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        pressure: (json['pressure'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is InkPoint && x == other.x && y == other.y && pressure == other.pressure;

  @override
  int get hashCode => Object.hash(x, y, pressure);
}

class InkStroke {
  const InkStroke({
    required this.id,
    required this.tool,
    required this.color,
    required this.width,
    required this.points,
  });

  final String id;
  final InkTool tool;
  final int color;
  final double width;
  final List<InkPoint> points;

  Map<String, Object> toJson() => {
        'id': id,
        'tool': tool.name,
        'color': color,
        'width': width,
        'points': points.map((point) => point.toJson()).toList(),
      };

  factory InkStroke.fromJson(Map<String, Object?> json) => InkStroke(
        id: json['id'] as String,
        tool: InkTool.values.byName(json['tool'] as String),
        color: json['color'] as int,
        width: (json['width'] as num).toDouble(),
        points: (json['points'] as List<Object?>)
            .map((point) => InkPoint.fromJson(point as Map<String, Object?>))
            .toList(growable: false),
      );

  @override
  bool operator ==(Object other) =>
      other is InkStroke &&
      id == other.id &&
      tool == other.tool &&
      color == other.color &&
      width == other.width &&
      _listEquals(points, other.points);

  @override
  int get hashCode => Object.hash(id, tool, color, width, Object.hashAll(points));
}

class NoteDocument {
  const NoteDocument({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.strokes = const [],
  });

  final String id;
  final String title;
  final DateTime updatedAt;
  final List<InkStroke> strokes;

  NoteDocument copyWith({String? title, DateTime? updatedAt, List<InkStroke>? strokes}) =>
      NoteDocument(
        id: id,
        title: title ?? this.title,
        updatedAt: updatedAt ?? this.updatedAt,
        strokes: strokes ?? this.strokes,
      );

  Map<String, Object> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
      };

  factory NoteDocument.fromJson(Map<String, Object?> json) => NoteDocument(
        id: json['id'] as String,
        title: json['title'] as String,
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        strokes: (json['strokes'] as List<Object?>)
            .map((stroke) => InkStroke.fromJson(stroke as Map<String, Object?>))
            .toList(growable: false),
      );

  @override
  bool operator ==(Object other) =>
      other is NoteDocument &&
      id == other.id &&
      title == other.title &&
      updatedAt == other.updatedAt &&
      _listEquals(strokes, other.strokes);

  @override
  int get hashCode => Object.hash(id, title, updatedAt, Object.hashAll(strokes));
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
