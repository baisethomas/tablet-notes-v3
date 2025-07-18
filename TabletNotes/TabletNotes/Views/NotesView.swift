import SwiftUI
import Combine

struct NotesView: View {
    @ObservedObject var noteService: NoteService
    var onNext: (() -> Void)?
    @State private var editingNoteID: UUID? = nil
    @State private var editedText: String = ""
    @State private var notes: [Note] = []
    @State private var cancellables = Set<AnyCancellable>()
    @State private var showingAddNoteSheet = false
    @State private var newNoteText = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                HeaderView(title: "Notes", showLogo: true, showSearch: false, showSyncStatus: true, showBack: false, syncStatus: HeaderView.SyncStatus.synced)
                
                if notes.isEmpty {
                    // Empty state
                    VStack(spacing: 24) {
                        Spacer()
                        
                        VStack(spacing: 16) {
                            Image(systemName: "note.text")
                                .font(.system(size: 64))
                                .foregroundColor(.secondary.opacity(0.5))
                            
                            VStack(spacing: 8) {
                                Text("No Notes Yet")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                                
                                Text("Add your first note or scripture reference using the buttons below")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                showingAddNoteSheet = true
                            }) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("Add Note")
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Color.accentColor)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Go to Summary") {
                            onNext?()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 100)
                    }
                } else {
                    // Notes list
                    VStack(spacing: 0) {
                        List {
                            ForEach(notes as [Note], id: \Note.id) { note in
                                VStack(alignment: .leading, spacing: 8) {
                                    if editingNoteID == note.id {
                                        VStack(spacing: 12) {
                                            TextEditor(text: $editedText)
                                                .frame(minHeight: 60)
                                                .padding(8)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(8)
                                            
                                            HStack {
                                                Button("Cancel") {
                                                    editingNoteID = nil
                                                }
                                                .foregroundColor(.secondary)
                                                
                                                Spacer()
                                                
                                                Button("Save") {
                                                    noteService.updateNote(id: note.id, newText: editedText)
                                                    editingNoteID = nil
                                                }
                                                .fontWeight(.medium)
                                                .foregroundColor(.accentColor)
                                            }
                                        }
                                    } else {
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack {
                                                Text(timeString(from: note.timestamp))
                                                    .font(.caption)
                                                    .fontWeight(.medium)
                                                    .foregroundColor(.accentColor)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.accentColor.opacity(0.1))
                                                    .cornerRadius(4)
                                                
                                                Spacer()
                                                
                                                HStack(spacing: 8) {
                                                    Button(action: {
                                                        editingNoteID = note.id
                                                        editedText = note.text
                                                    }) {
                                                        Image(systemName: "pencil")
                                                            .font(.caption)
                                                    }
                                                    .foregroundColor(.accentColor)
                                                    
                                                    Button(role: .destructive, action: {
                                                        noteService.deleteNote(id: note.id)
                                                    }) {
                                                        Image(systemName: "trash")
                                                            .font(.caption)
                                                    }
                                                }
                                            }
                                            
                                            // Use ClickableScriptureText for note content
                                            ClickableScriptureText(
                                                text: note.text,
                                                font: .body,
                                                lineSpacing: 4
                                            )
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                        .listStyle(PlainListStyle())
                        
                        Spacer()
                        
                        Button("Go to Summary") {
                            onNext?()
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.bottom, 100)
                    }
                }
            }
            
            // Floating Action Buttons
            VStack(spacing: 16) {
                // Bible FAB
                BibleFAB { reference, content in
                    addScriptureToNotes(reference: reference, content: content)
                }
                
                // Add Note FAB
                Button(action: {
                    showingAddNoteSheet = true
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 56, height: 56)
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.trailing, 20)
            .padding(.bottom, 120)
        }
        .ignoresSafeArea(edges: .bottom)
        .sheet(isPresented: $showingAddNoteSheet) {
            NavigationView {
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: "note.text")
                            .foregroundColor(.accentColor)
                        Text("Add Note")
                            .font(.headline)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding()
                    
                    TextEditor(text: $newNoteText)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .frame(minHeight: 150)
                    
                    Spacer()
                    
                    HStack(spacing: 16) {
                        Button("Cancel") {
                            newNoteText = ""
                            showingAddNoteSheet = false
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                        
                        Button("Add Note") {
                            let trimmed = newNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty {
                                noteService.addNote(text: trimmed, timestamp: 0) // Use 0 timestamp for manual notes
                                newNoteText = ""
                                showingAddNoteSheet = false
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .disabled(newNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                }
                .padding()
                .navigationTitle("")
                .navigationBarHidden(true)
            }
        }
        .onAppear {
            noteService.notesPublisher
                .receive(on: RunLoop.main)
                .sink { value in
                    notes = value
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Private Methods
    
    private func addScriptureToNotes(reference: ScriptureReference, content: String) {
        let noteText = """
        📖 \(reference.displayText)
        
        \(content)
        """
        
        noteService.addNote(text: noteText, timestamp: 0)
        
        // Provide haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
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
