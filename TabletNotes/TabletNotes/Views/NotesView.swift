import SwiftUI
import Combine

struct NotesView: View {
    @ObservedObject var noteService: NoteService
    var onNext: (() -> Void)?
    @State private var editingNoteID: UUID? = nil
    @State private var editedText: String = ""
    @State private var notes: [Note] = []
    @State private var cancellables = Set<AnyCancellable>()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HeaderView(title: "Notes", showLogo: true, showSearch: false, showSyncStatus: true, showBack: false, syncStatus: HeaderView.SyncStatus.synced)
                Spacer(minLength: 0)
                VStack(spacing: 24) {
                    List {
                        ForEach(notes as [Note], id: \Note.id) { note in
                            if editingNoteID == note.id {
                                TextField("Edit Note", text: $editedText)
                                HStack {
                                    Button("Save") {
                                        noteService.updateNote(id: note.id, newText: editedText)
                                        editingNoteID = nil
                                    }
                                    Button("Cancel") {
                                        editingNoteID = nil
                                    }
                                }
                            } else {
                                HStack {
                                    Text("[\(timeString(from: note.timestamp))] \(note.text)")
                                    Spacer()
                                    Button("Edit") {
                                        editingNoteID = note.id
                                        editedText = note.text
                                    }
                                    Button(role: .destructive) {
                                        noteService.deleteNote(id: note.id)
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                }
                            }
                        }
                    }
                    Button("Go to Summary") {
                        onNext?()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        .onAppear {
            noteService.notesPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    notes = value
                }
                .store(in: &cancellables)
        }
    }

    private func timeString(from interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    NotesView(noteService: NoteService())
}
