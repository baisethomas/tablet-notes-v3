# Enhanced Product Requirements Document (PRD)

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
- Ensure accessibility for all users
- Provide seamless offline and online experience

---

## Target Users
- Churchgoers who want to revisit sermons
- Pastors and spiritual leaders
- Bible study participants
- Students of theology
- Individuals with hearing impairments who need transcription assistance
- Spiritual seekers exploring religious content

---

## User Tiers

### Free Users
- Upload audio
- Receive general summary
- Transcript access
- Basic scripture references
- **Storage**: 30 days retention for recordings and transcripts
- **Recording Limits**: Maximum 5 hours total storage
- **Quality**: Standard quality (128kbps)

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
  - **Recording Limits**: 100 hours total storage
  - **Offline Access**: Extended offline access to past sermons

---

## Core Features

### 1. User Onboarding
- **First-time User Flow**: 3-step onboarding carousel highlighting key features
- **Feature Discovery**: Tooltips for first-time feature usage
- **Sample Content**: Demo sermon with transcription for new users to explore
- **Personalization**: Initial setup questions (denomination, interests) to personalize experience
- **UI Elements**:
  - Welcome screens with clear value proposition
  - Progress indicators for setup completion
  - Skip option for experienced users

### 2. Authentication System
- **Sign-up Methods**:
  - Email/password with verification
  - Apple Sign-in (required for iOS apps)
- **Account Recovery**:
  - Password reset via email
  - Optional phone number recovery
- **Session Management**:
  - Auto-refresh tokens
  - Secure token storage
  - Multiple device support
- **UI Elements**:
  - Clean login/signup forms
  - Biometric authentication option
  - Clear error messaging

### 3. Audio Upload/Recording
- **User Flow**: 
  - Simplified: Open app → Tap record button → Select service type → Begin recording and taking notes immediately
- **Service Types**: Sunday Service, Bible Study, Midweek, Conference, Guest Speaker
- **UI Elements**:
  - Prominent Button: "Record" (centrally located in tab bar)
  - Quick Modal: Service type selection appears after hitting record
  - Visual Indicator: Recording in progress with audio levels
  - Immediate transition to note-taking interface
- **Offline Support**: Users can record audio offline; recordings are uploaded when internet is available
- **Audio Format**: AAC, 128kbps, 44.1kHz (industry standard; paid users may access 256kbps)
- **Max Duration**: 3 hours per recording session
- **File Size Limits**: Maximum 500MB per recording
- **Quality Settings**: Allow quality adjustment (Low: 64kbps, Standard: 128kbps, High: 256kbps)
- **Background Recording**: Continue recording when app is in background

### 4. Notes During Recording
- **Real-time Note-taking**: Users can type notes immediately while recording is in progress
- **Split-screen Experience**: Recording status at top, note-taking area below
- **Auto-save**: Notes are saved continuously as user types
- **Post-recording**: Notes are preserved and associated with the transcription for a complete record
- **Benefit**: Captures immediate thoughts and insights that might be lost if waiting for transcription
- **Formatting Options**: Basic text formatting (bold, italic, bullet points)
- **Scripture Tagging**: Auto-detection of scripture references while typing
- **Offline Support**: Full note-taking functionality without internet connection

### 5. AI Summarization
- **Processing**:
  - Transcription and summarization via AssemblyAI (asynchronous API)
  - No speaker diarization required
  - Scripture detection (using Bible Reference API)
- **Tier Behavior**:
  - Free: High-level summary (1-2 paragraphs)
  - Paid: Deep summary + insights + preaching tone (3-5 paragraphs with theological context)
- **Processing Status**:
  - Clear progress indicators
  - Push notification when complete
- **Error Handling**:
  - Retry mechanisms for failed transcriptions
  - User-friendly error messages
  - Manual correction options

### 6. Scripture Insights
- **Bible API Integration**:
  - API.Bible or Bible.org API for verse content
  - Multiple translations support
- **Features**:
  - Auto-linking verses
  - Contextual background info
  - Related passages
  - Historical context (paid tier)
- **User Preferences**:
  - Preferred Bible translation selection
  - Insight depth customization
- **Offline Access**:
  - Caching of commonly referenced verses
  - Core translations available offline

### 7. Notes & Export
- **Interactive Note Viewer**:
  - Combined view of user notes and transcription
  - Highlighting and annotation tools
  - Scripture reference linking
- **Export Options**:
  - PDF with formatting and branding
  - Markdown for digital use
  - Plain text option
- **Sharing Features**:
  - Direct share to messaging apps
  - Email sharing
  - Copy link functionality
- **Organization**:
  - Folder organization
  - Tagging system
  - Search functionality

### 8. Search Functionality
- **Full-Text Search**: Search across transcriptions and notes
- **Filters**: Filter by date, service type, and scripture references
- **Saved Searches**: Save common searches for quick access
- **Search History**: View and reuse recent searches
- **Voice Search**: Search using voice input
- **Advanced Search** (Paid tier):
  - Semantic search capabilities
  - Topic clustering
  - Theological concept search

### 9. User Settings
- **Account Settings**:
  - Email, password, profile information
  - Subscription management
  - Data export options
- **Notification Preferences**:
  - Push, email, in-app notifications
  - Weekly digest options
- **Audio Settings**:
  - Recording quality preferences
  - Playback speed options
- **Appearance**:
  - Light/dark mode
  - Text size adjustment
  - Accent color options
- **Privacy Controls**:
  - Data retention settings
  - Sharing preferences
  - Analytics opt-out option
- **Bible Preferences**:
  - Default translation
  - Insight depth
- **Export Preferences**:
  - Default format
  - Include/exclude options

### 10. Notification System
- **Types**:
  - Transcription completion
  - Processing updates
  - Weekly sermon summaries
  - Subscription alerts
- **Delivery Methods**:
  - Push notifications
  - In-app notifications
  - Email digests (optional)
- **User Control**:
  - Granular notification settings
  - Do not disturb periods
  - Frequency controls

### 11. Error Handling
- **Network Failures**:
  - Offline mode activation
  - Background retry mechanism
  - Clear user feedback
- **Transcription Errors**:
  - Quality warnings for poor audio
  - Manual correction options
  - Feedback mechanism for improvement
- **App Crashes**:
  - Automatic recovery
  - State preservation
  - Crash reporting with user consent

### 12. Accessibility Features
- **VoiceOver Support**: All UI elements properly labeled
- **Dynamic Type**: Support for all text size settings
- **Reduced Motion**: Alternative animations for users with motion sensitivity
- **Color Contrast**: WCAG AA compliance for all text
- **Haptic Feedback**: Tactile feedback for important actions
- **Closed Captions**: For audio playback
- **Voice Control**: Key functions accessible via voice commands

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
- Support for Dynamic Type
- Minimum text size: 14pt
- Line spacing: 1.2x for readability

### Buttons & Components
- Primary button: Rounded, pill-style, filled
- Secondary button: Outlined with accent border
- Tabs for filtering past sermons
- Cards for sermon previews
- Minimum touch target size: 44x44pt
- **UI Toolkit**: Native SwiftUI components (no ShadCN; TCA for state management if needed)

### Screens
1. **Onboarding / Welcome**
2. **Login / Registration**
3. **Dashboard / Home**
4. **Select Service Type** (quick modal after tapping record)
5. **Recording + Note-taking** (combined screen)
6. **Transcription & Summary Viewer**
7. **Scripture Insights**
8. **Export & Share**
9. **Search**
10. **Settings**
11. **Account / Subscription**
12. **Error States & Empty States**

### Responsive Design
- Support for all iPhone screen sizes
- iPad optimization with split-view support
- Landscape/portrait orientation support
- Adaptive layouts for accessibility settings

---

## Tech Stack

### Frontend
- **Framework**: iOS (SwiftUI)
- **State Management**: Combine framework
- **Navigation**: Coordinator pattern
- **Persistence**: SwiftData
- **Networking**: URLSession with Combine
- **Dependency Injection**: Custom DI container

### Backend
- **Platform**: Supabase
- **Authentication**: Supabase Auth with JWT
- **Database**: PostgreSQL (via Supabase)
- **Storage**: Supabase Storage for audio files
- **Schema**:
  - User table
  - Sermon table
  - Transcription table
  - Notes table
  - Subscription table

### Third-Party Services
- **AI**: AssemblyAI (asynchronous API for transcription and summarization)
- **Scripture Data**: API.Bible or Bible.org API
- **Billing**: Stripe + StoreKit 2
- **Analytics**: Firebase Analytics
- **Crash Reporting**: Firebase Crashlytics
- **Email Service**: Resend or MailerSend
- **Push Notifications**: Firebase Cloud Messaging

### Development Tools
- **Version Control**: Git
- **CI/CD**: GitHub Actions or Bitbucket Pipelines
- **Code Quality**: SwiftLint
- **Testing**: XCTest
- **Beta Distribution**: TestFlight
- **Environment Management**: Configuration files for dev/staging/prod

### Domain
- `tabletnotes.io` with subdomain for app (`app.tabletnotes.io`)
- SSL certificates for all domains

---

## Performance Requirements

- **App Launch Time**: < 2 seconds on iPhone X or newer
- **Recording Initialization**: < 1 second from tap to recording
- **Transcription Processing**: Clear progress indicators for longer operations
- **Battery Usage**: < 5% battery per hour during recording
- **Memory Footprint**: < 200MB memory usage during normal operation
- **Offline Performance**: Full functionality for core features without internet
- **Network Efficiency**: Optimized uploads/downloads to minimize data usage

---

## Security Requirements

- **Data Encryption**: At-rest encryption for all stored audio and transcriptions
- **Transport Security**: TLS 1.3 for all API communications
- **Authentication**: JWT with short expiration and refresh token rotation
- **Sensitive Data Handling**: PII handling and storage policies
- **App Privacy**: Detailed App Store privacy report
- **Local Storage**: Secure storage for offline data
- **Access Control**: Role-based access for user tiers

---

## Testing Strategy

- **Unit Testing**: 80% code coverage for business logic
- **Integration Testing**: API integrations and data flow
- **UI Testing**: Automated tests for critical user journeys
- **Performance Testing**: Baseline performance metrics and regression testing
- **Accessibility Testing**: Regular audits with VoiceOver and other accessibility tools
- **Beta Testing**: TestFlight distribution to internal, then external testers
- **User Acceptance Testing**: Structured feedback collection

---

## Analytics & Metrics

- **User Journey Events**: Track key user flows and conversion points
- **Feature Usage**: Monitor usage patterns of core features
- **Performance Metrics**: Track app performance in production
- **Retention Indicators**: Identify patterns in user retention and churn
- **Conversion Funnel**: Track progression from free to paid tier
- **Implementation**: Firebase Analytics or Amplitude
- **Key Events**:
  - App open
  - Recording start/stop
  - Transcription completion
  - Note creation/edit
  - Search queries
  - Export actions
  - Subscription view/purchase

---

## Future Features
- AI search by keyword/topic
- Collaborative notes
- Church account tier
- Custom sermon templates
- Voice-style tagging ("Pastor T's tone")
- Multi-language support
- Audio enhancement tools
- Integration with church management systems
- Web application version
- Android version

---

## Success Metrics
- User retention rate (target: 60% after 30 days)
- Weekly active users (target: 40% of total users)
- Upgrade conversion (Free → Paid) (target: 5% conversion rate)
- Sermon uploads per user (target: 4 per month)
- Export/download count (target: 2 per active user per month)
- User satisfaction (target: 4.5/5 star rating)

---

## Timeline
- **Week 1**: MVP Design & Setup
  - Authentication system
  - Basic UI framework
  - Recording functionality
- **Week 2**: Core Functionality
  - Note-taking interface
  - AssemblyAI integration
  - Basic transcription display
- **Week 3**: Tier Implementation
  - Subscription setup
  - Tiered feature implementation
  - Bible API integration
- **Week 4**: Polish & Testing
  - UI refinement
  - Performance optimization
  - Initial testing
- **Week 5**: Beta Preparation
  - TestFlight setup
  - Analytics implementation
  - Bug fixes from internal testing
- **Week 6**: Launch Beta
  - External tester distribution
  - Feedback collection
  - Final adjustments

---

## Appendix
- [Branding Assets](#)
- [Animated Prototypes](#)
- [Logo Variants](#)
- [Privacy Policy & Terms](#)
- [Accessibility Compliance Checklist](#)
- [API Documentation](#)
