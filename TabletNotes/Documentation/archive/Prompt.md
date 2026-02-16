

# Tablet App – Technical PRD Structure for Manus

## 🎯 Goal

Act as a Senior Software Engineer and help structure the technical and architectural side of the app "Tablet". This is a sermon note-taking app with real-time recording, transcription, AI summarization, and scripture analysis.

---

## 📌 Considerations

- **WHAT**: What is being built?
- **WHO**: Who is it for?
- **WHY**: What problem does it solve?
- **HOW**: How is it different from Otter.ai or similar tools?

---

## 🚀 Launch Features (MVP)

### 🎙️ Real-Time Sermon Recording
**Captures spoken audio using iOS on-device transcription**

- Records sermons with low latency
- Transcribes on-device using `SFSpeechRecognizer`
- Local audio storage
#### Tech Involved
- SwiftUI
- SFSpeechRecognizer
- FileManager (for local audio)
#### Main Requirements
- Recording persists through interruptions
- Save as `.m4a` or `.caf` files

---

### 📝 Live Note-Taking During Recording
**Allows users to write notes in real time while recording**

- Timestamped notes
- Editable text field with floating buttons for highlights/bookmarks
- Syncs with transcript for timeline view
#### Tech Involved
- SwiftUI
- Core Data or local storage
#### Main Requirements
- Notes must be linked to time in recording
- Works offline

---

### 🤖 AI Sermon Summarization
**Generates concise summaries after transcription is complete**

- OpenAI-generated summaries
- Summary format is user-selected (devotional, bullet point, theological)
- Summary jobs are queued after transcription
#### Tech Involved
- Supabase
- OpenAI API
- Edge Functions
#### Main Requirements
- Users can retry failed jobs
- Summary generated in background after stop

---

### 📦 Supabase Sync (Paid Feature)
**Sync notes + transcripts to Supabase cloud**

- Manual or automatic sync
- Cloud summaries saved for access from other devices
#### Tech Involved
- Supabase Postgres
#### Main Requirements
- Auth required
- Free users get 30-day local data only

---

### 📧 Email Notification
**Notify users via email when summaries are ready**

- Email summary with title + deep link to view
#### Tech Involved
- Resend or MailerSend
#### Main Requirements
- Triggered by edge function upon summary completion

---

## 🌱 Future Features (Post-MVP)

### 🔁 AssemblyAI Integration
* Cloud transcription fallback or premium option
#### Tech Involved
- AssemblyAI API

---

### 📱 Multi-Device Sync & Backup
* Access notes and summaries across devices
#### Tech Involved
- iCloud, Supabase
#### Main Requirements
- Sync conflict resolution

---

### 🔔 Push Notifications
* Push alert when summary or transcript is ready
#### Tech Involved
- APNs or Firebase Cloud Messaging

---

## 🧱 System Diagram (To Be Generated)

- SwiftUI frontend
- Local device storage (audio & notes)
- Supabase backend (summary, transcript, notes)
- OpenAI summarization job queue (via edge functions)
- Resend email notification
- PostHog event tracking

---

## ❓ Questions & Clarifications

- Clarify AI summary job retries and queueing
- What should happen if sync fails offline?
- Should summaries always generate, or be user-initiated?

---

## 🔍 Architecture Consideration Questions

- Should Supabase handle auth + queueing, or be decoupled?
- What’s the preferred syncing method for iOS local data?
- Would an async notification banner be useful later?
- At scale, would you want to transition AI to your own hosted model?

---

## ⚠️ Warnings or Guidance

- MVP should be scoped to offline transcription, real-time note-taking, and async AI summary
- No push notifications yet — email only
- All audio stays local unless exported by user
- SwiftUI snapshots and manual QA acceptable for launch

---

## 🧠 Context Summary

**WHAT**: A sermon-first mobile app for capturing messages through real-time transcription, personal notes, and AI-generated summaries  
**WHO**: Churchgoers, pastors, students of scripture  
**WHY**: People want to reflect on sermons later, but often miss critical points while listening  
**HOW**: Unlike Otter.ai, this app is spiritually contextual, offers scripture linking, and feels like writing on a physical tablet

---

## ⚙️ Current Tech Choices

- **Frontend**: SwiftUI  
- **Backend**: Supabase (Postgres)  
- **Auth**: Supabase Auth  
- **Summarization**: OpenAI via edge functions  
- **Transcription**: Apple’s SFSpeechRecognizer (on-device)  
- **Audio Storage**: Local device only  
- **Notes/Transcript/Summaries**: Supabase  
- **Notifications**: Resend (email)  
- **Analytics**: PostHog  
- **Testing**: Manual QA + Swift Snapshot Testing



