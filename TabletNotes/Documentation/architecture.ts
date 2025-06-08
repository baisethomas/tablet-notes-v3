export interface ArchitectureContent {
  diagram: string;
  dataFlow: string[];
}

export const architectureContent: ArchitectureContent = {
  diagram: `
┌─────────────────────────────────────────────────────────────┐
│                      iOS Application                         │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Recording & │  │ Note-Taking │  │ Local Storage       │  │
│  │Transcription│  │   Module    │  │ - Audio Files       │  │
│  │   Module    │  │             │  │ - Transcriptions    │  │
│  └─────────────┘  └─────────────┘  │ - Notes             │  │
│         │                │         │ - User Preferences  │  │
│         └────────┬───────┘         └─────────────────────┘  │
│                  │                           │              │
│         ┌────────┴───────┐                   │              │
│         │  Sync Manager  │◄──────────────────┘              │
│         └────────┬───────┘                                  │
└─────────────────┬─────────────────────────────────────────┬─┘
                  │                                         │
                  ▼                                         │
┌─────────────────────────────────┐                         │
│         Supabase Backend        │                         │
│ ┌─────────────┐ ┌─────────────┐ │                         │
│ │    Auth     │ │  Database   │ │                         │
│ └─────────────┘ └─────────────┘ │                         │
│                                 │                         │
│ ┌─────────────┐ ┌─────────────┐ │                         │
│ │   Storage   │ │Edge Functions│ │                         │
│ └─────────────┘ └──────┬──────┘ │                         │
└────────────────────────┼────────┘                         │
                         │                                  │
                         ▼                                  │
                ┌─────────────────┐                         │
                │    OpenAI API   │                         │
                └─────────────────┘                         │
                         │                                  │
                         ▼                                  │
                ┌─────────────────┐                         │
                │  Email Service  │◄────────────────────────┘
                │  (Resend API)   │
                └─────────────────┘
`,
  dataFlow: [
    "User records sermon and takes notes on iOS device",
    "Audio is processed locally using SFSpeechRecognizer",
    "Notes and transcription are stored locally",
    "For paid users, data syncs to Supabase",
    "Summarization job is queued via Supabase Edge Function",
    "OpenAI generates summary",
    "User is notified via email when summary is ready",
    "User can view summary in app"
  ]
};
