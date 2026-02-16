# 🎙️ SwiftUI Architecture for Dual Transcription (Tablet App)

This architecture enables both:
- Real-time transcription for immediate feedback
- Post-recording cleanup transcription for accuracy

---

## 🧱 Core Components

### 1. `AudioRecorderService`
Handles:
- AVAudioEngine for mic input
- Recording to file (`.m4a` or `.caf`)
- Routing live audio to both the disk and transcription buffer

### 2. `LiveTranscriptionService`
Handles:
- `SFSpeechRecognizer` + `SFSpeechAudioBufferRecognitionRequest`
- Captures partial + final results
- Restarts session every 55 seconds to avoid Apple's 60s cap
- Sends updates to `@Published var liveTranscript`

### 3. `PostTranscriptionProcessor`
Handles:
- Reads final audio file
- Sends it to `SFSpeechURLRecognitionRequest`
- Returns cleaner, uninterrupted transcript
- Fires AI summarization job after transcript is ready

---

## 🧩 Data Flow

1. **Start Recording**
   - Start audio engine & file recorder
   - Start real-time transcription session

2. **Live Session Handling**
   - Restart `SFSpeechRecognizer` every ~55 seconds
   - Append recognized text segments to live transcript buffer

3. **User Stops Recording**
   - Stop file + mic recording
   - Save audio to local file
   - Launch `PostTranscriptionProcessor`

4. **Post-Processing**
   - Run `SFSpeechURLRecognitionRequest` on saved file
   - Replace live transcript with cleaner version
   - Trigger summary via Supabase Edge Function / OpenAI

---

## 🧠 Optional Enhancements

- Store both transcripts:
  - `liveTranscriptRaw`
  - `finalTranscriptCleaned`
- Compare and display diffs for advanced users
- Add background task support for longer audio post-processing

---

## 🧪 Testing Strategy

- Unit test transcription restarts
- Snapshot test summary screens
- QA real-time sync between notes and transcript stream