# MVP Implementation Task List

## Project setup & Xcode configuration
- [ ] Add all folders/files to Xcode project
- [ ] Remove old model references
- [ ] Update Info.plist and entitlements paths

## Data model implementation (Sermon, Note, Transcript, Summary)
- [ ] Implement Sermon model
- [ ] Implement Note model
- [ ] Implement Transcript and TranscriptSegment models
- [ ] Implement Summary model
- [ ] Test model relationships in SwiftData

## RecordingService implementation
- [ ] Setup AVFoundation session
- [ ] Implement start/stop/pause/resume
- [ ] Save audio file locally
- [ ] Handle interruptions

## TranscriptionService implementation
- [ ] Setup SFSpeechRecognizer
- [ ] Implement real-time transcription
- [ ] Handle 1-minute session limit
- [ ] Error handling and fallback

## NoteService implementation
- [ ] Add note
- [ ] Update note
- [ ] Delete note
- [ ] Link notes to transcript timeline

## SummaryService implementation
- [ ] Trigger summary after transcription
- [ ] Call OpenAI API
- [ ] Handle summary status and errors

## SyncService implementation
- [ ] Automatic sync to Supabase
- [ ] Handle sync retries and offline
- [ ] Delete all cloud data

## AuthService implementation
- [ ] Sign in
- [ ] Sign out

## NotificationService implementation
- [ ] Show in-app banner

## AnalyticsService implementation
- [ ] Log key events

## Home screen UI
- [ ] Add start recording button

## Recording screen UI
- [ ] Show recording status and waveform
- [ ] Show live transcript
- [ ] Note-taking area

## Notes screen UI
- [ ] Display notes list
- [ ] Edit note
- [ ] Link notes to transcript

## Summary screen UI
- [ ] Display summary text
- [ ] Retry button

## Settings screen UI
- [ ] Show user info and subscription status
- [ ] Delete cloud data button
- [ ] Sign out button

## Coordinator/navigation logic
- [ ] Implement navigation enum and state
- [ ] Wire up navigation closures

## Testing & QA
- [ ] Manual QA
- [ ] Snapshot testing 