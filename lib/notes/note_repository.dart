import 'note_document.dart';

abstract interface class NoteRepository {
  Future<List<NoteDocument>> list();
  Future<void> save(NoteDocument note);
}

class MemoryNoteRepository implements NoteRepository {
  final Map<String, NoteDocument> _notes = {};

  @override
  Future<List<NoteDocument>> list() async {
    final notes = _notes.values.toList(growable: false);
    notes.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return notes;
  }

  @override
  Future<void> save(NoteDocument note) async {
    _notes[note.id] = NoteDocument.fromJson(note.toJson());
  }
}
