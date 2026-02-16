# Product Requirements Document (PRD)

## Product Name: Tablet

### Overview
**Tablet** is a mobile-first sermon note-taking app that uses AI to transcribe, summarize, and provide scriptural insights from sermons. It supports two user tiers (Free & Paid), allowing pastors, note-takers, and spiritual seekers to revisit sermon content meaningfully. It draws inspiration from Otter.ai, which is the primary competitor and influence for this product.

---

## Competitor Influence
- **Primary Influence & Competitor**: Otter.ai
  - Tablet aims to provide a similar seamless, AI-powered note-taking experience, tailored for sermons and spiritual content.
  - **Key Difference**: Unlike Otter.ai, Tablet allows users to take notes immediately while recording, not just after recording is complete.

---

## Goals
- Deliver real-time or recorded sermon transcription and summarization
- Provide different levels of AI-generated content based on user tier
- Maintain a minimal, distraction-free, tablet-like interface
- Include scripture references with contextual insights
- Enable sermon categorization by service type (Sunday, Bible Study, etc.)
- Support immediate note-taking during sermon recording

---

## Target Users
- Churchgoers who want to revisit sermons
- Pastors and spiritual leaders
- Bible study participants
- Students of theology

---

## User Tiers

### Free Users
- Upload audio
- Receive general summary
- Transcript access
- Basic scripture references
- **Storage**: 30 days retention for recordings and transcripts

### Paid Users
- All free features plus:
  - Deep-dive theological summary
  - Scripture insights
  - Preaching-style recognition
  - Dynamic tagging and search
  - Export notes (PDF, markdown)
  - AI-driven highlights
  - **Storage**: Unlimited retention, cloud backup
  - **Audio Quality**: Option for higher quality (up to 256kbps)

---

## Core Features

### 1. Audio Recording
- **User Flow**: 
  - Simplified: Open app → Tap record button → Select service type → Begin recording and taking notes immediately
- **Service Types**: Sunday Service, Bible Study, Midweek, Conference, Guest Speaker
- **UI Elements**:
  - Prominent Button: "Record" (centrally located in tab bar)
  - Quick Modal: Service Type selection appears after hitting record
  - Visual Indicator: Recording in progress
  - Immediate transition to note-taking interface
- **Offline Support**: Users can record audio offline; recordings are uploaded when internet is available
- **Audio Format**: AAC, 128kbps, 44.1kHz (industry standard; paid users may access 256kbps)
- **Max Duration**: Industry standard (TBD based on iOS and AssemblyAI limits)

### 2. Notes During Recording
- **Real-time Note-taking**: Users can type notes immediately while recording is in progress
- **Split-screen Experience**: Recording status at top, note-taking area below
- **Auto-save**: Notes are saved continuously as user types
- **Post-recording**: Notes are preserved and associated with the transcription for a complete record
- **Benefit**: Captures immediate thoughts and insights that might be lost if waiting for transcription

### 3. AI Summarization
- **Processing**:
  - Transcription and summarization via AssemblyAI (asynchronous API)
  - No speaker diarization required
  - Scripture detection (using Bible Reference API)
- **Tier Behavior**:
  - Free: High-level summary
  - Paid: Deep summary + insights + preaching tone

### 4. Scripture Insights
- Uses Bible Reference API for:
  - Auto-linking verses
  - Contextual background info
  - Related passages

### 5. Notes + Export
- Interactive note viewer
- Download/export: PDF, Markdown
- Copy/share with formatted structure

### 6. User Account System
- Auth via Supabase (email/password only for MVP)
- Stripe billing integration
- Roles: Free, Paid

---

## Design & UI/UX

### Visual Style
- **Primary Color**: #4A6D8C (Calm Blue)
- **Secondary Color**: #8A9BA8 (Muted Blue-Gray)
- **Background**: #FFFFFF / #F5F7F9
- **Text**: #333333 / #666666
- **Accent Colors**:
  - Success: #4A8C6A
  - Error: #B55A5A
  - Warning: #D9A55A
  - Info: #5A7DB5

### Typography
- Font used: **Inter** (for logo and app)

### Buttons & Components
- Primary button: Rounded, pill-style, filled
- Secondary button: Outlined with accent border
- Tabs for filtering past sermons
- Cards for sermon previews
- **UI Toolkit**: Native SwiftUI components (no ShadCN; TCA for state management if needed)

### Screens
1. **Welcome / Login**
2. **Dashboard**
3. **Select Service Type** (quick modal after tapping record)
4. **Recording + Note-taking** (combined screen)
5. **Transcription & Summary Viewer**
6. **Export & Save**
7. **Account Settings / Subscription**
8. **Empty States & Loading Animations**

---

## Tech Stack

- **Frontend**: iOS (SwiftUI)
- **Backend**: Supabase
- **AI**: AssemblyAI (asynchronous API for transcription and summarization)
- **Scripture Data**: Bible Reference API
- **Billing**: Stripe
- **Email Service**: Resend or MailerSend
- **Domain**: `tabletnotes.io` with subdomain for app (`app.tabletnotes.io`)

---

## Future Features
- AI search by keyword/topic
- Collaborative notes
- Church account tier
- Custom sermon templates
- Voice-style tagging ("Pastor T's tone")

---

## Success Metrics
- User retention rate
- Weekly active users
- Upgrade conversion (Free → Paid)
- Sermon uploads per user
- Export/download count

---

## Timeline
- **Week 1–2**: MVP Design & Setup (Auth, Upload, AI summary)
- **Week 3–4**: Billing, Tiered Summary Logic
- **Week 5**: Polish, Testing, UI Enhancements
- **Week 6**: Launch Beta

---

## Appendix

### Current Implementation Status

*Last updated: February 2026*

This section documents the current state of the implementation relative to the original PRD above.

#### Actual Tech Stack

| Layer | Planned | Implemented |
|-------|---------|-------------|
| Frontend | iOS (SwiftUI) | iOS (SwiftUI) with `@Observable` (iOS 17+) |
| Backend | Supabase | Supabase (auth, storage, sync) + Netlify Functions (serverless API) |
| AI | AssemblyAI | AssemblyAI via Netlify Functions (transcription + summarization) |
| Scripture | Bible Reference API | API.Bible |
| Billing | Stripe | StoreKit (in-app purchases) |
| Email | Resend or MailerSend | Not yet implemented |

#### Additional Shipped Features (Beyond Original PRD)

- **AI Chat**: Sermon Q&A — users can ask questions about sermon content and get AI-powered answers
- **Live Transcription**: Real-time WebSocket-based transcription during recording via AssemblyAI
- **Network Resilience**: NWPathMonitor connectivity tracking, exponential backoff retry, WebSocket auto-reconnect
- **Bible Browser**: In-app Bible text browsing via API.Bible integration
- **Scripture Detection**: Automatic detection and linking of scripture references in transcripts and summaries

#### Planned But Not Yet Implemented

- Stripe billing integration (using StoreKit instead)
- Email notifications
- Export to PDF/Markdown
- Preaching-style recognition
- Dynamic tagging and search
- AI-driven highlights
- Collaborative notes

#### Architecture Notes

The app uses a service-layer architecture rather than traditional ViewModels. Core services use the `@Observable` macro (iOS 17+ Swift Observation framework) instead of `ObservableObject`. See [ARCHITECTURE.md](ARCHITECTURE.md) for the full technical architecture.

