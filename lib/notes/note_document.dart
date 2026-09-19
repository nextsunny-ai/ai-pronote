enum InkTool { pen, highlighter, eraser, lasso }

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
      other is InkPoint &&
      x == other.x &&
      y == other.y &&
      pressure == other.pressure;
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
  int get hashCode =>
      Object.hash(id, tool, color, width, Object.hashAll(points));
}

class NotePage {
  const NotePage({required this.id, this.strokes = const []});
  final String id;
  final List<InkStroke> strokes;
  NotePage copyWith({List<InkStroke>? strokes}) =>
      NotePage(id: id, strokes: strokes ?? this.strokes);
  Map<String, Object> toJson() => {
    'id': id,
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
  };
  factory NotePage.fromJson(Map<String, Object?> json) => NotePage(
    id: json['id'] as String,
    strokes: (json['strokes'] as List<Object?>)
        .map((stroke) => InkStroke.fromJson(stroke as Map<String, Object?>))
        .toList(growable: false),
  );
  @override
  bool operator ==(Object other) =>
      other is NotePage &&
      id == other.id &&
      _listEquals(strokes, other.strokes);
  @override
  int get hashCode => Object.hash(id, Object.hashAll(strokes));
}

class NoteDocument {
  NoteDocument({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.isFavorite = false,
    List<InkStroke> strokes = const [],
    List<NotePage>? pages,
  }) : pages = pages ?? [NotePage(id: 'page-1', strokes: strokes)];
  final String id;
  final String title;
  final DateTime updatedAt;
  final bool isFavorite;
  final List<NotePage> pages;
  List<InkStroke> get strokes => pages.first.strokes;

  NoteDocument copyWith({
    String? title,
    DateTime? updatedAt,
    bool? isFavorite,
    List<InkStroke>? strokes,
    List<NotePage>? pages,
  }) {
    final nextPages =
        pages ??
        (strokes == null
            ? this.pages
            : [
                this.pages.first.copyWith(strokes: strokes),
                ...this.pages.skip(1),
              ]);
    return NoteDocument(
      id: id,
      title: title ?? this.title,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      pages: nextPages,
    );
  }

  Map<String, Object> toJson() => {
    'schemaVersion': 2,
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'isFavorite': isFavorite,
    // 구버전으로 되돌려도 첫 페이지를 열 수 있게 함께 기록한다.
    'strokes': strokes.map((stroke) => stroke.toJson()).toList(),
    'pages': pages.map((page) => page.toJson()).toList(),
  };

  factory NoteDocument.fromJson(Map<String, Object?> json) {
    final rawPages = json['pages'];
    final pages = rawPages is List<Object?>
        ? rawPages
              .map((page) => NotePage.fromJson(page as Map<String, Object?>))
              .toList(growable: false)
        : [
            NotePage(
              id: 'page-1',
              strokes: (json['strokes'] as List<Object?>)
                  .map(
                    (stroke) =>
                        InkStroke.fromJson(stroke as Map<String, Object?>),
                  )
                  .toList(growable: false),
            ),
          ];
    if (pages.isEmpty) {
      throw const FormatException('노트에는 페이지가 한 장 이상 필요합니다.');
    }
    return NoteDocument(
      id: json['id'] as String,
      title: json['title'] as String,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      isFavorite: json['isFavorite'] as bool? ?? false,
      pages: pages,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NoteDocument &&
      id == other.id &&
      title == other.title &&
      updatedAt == other.updatedAt &&
      isFavorite == other.isFavorite &&
      _listEquals(pages, other.pages);
  @override
  int get hashCode =>
      Object.hash(id, title, updatedAt, isFavorite, Object.hashAll(pages));
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
