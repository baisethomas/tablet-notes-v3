export interface TimelineWeek {
  week: number;
  title: string;
  tasks: string[];
}

export const timeline: TimelineWeek[] = [
  {
    week: 1,
    title: "Core Recording & Transcription",
    tasks: [
      "Setup audio recording service",
      "Implement on-device transcription with SFSpeechRecognizer",
      "Build recording UI with waveform visualization",
      "Implement session management for transcription"
    ]
  },
  {
    week: 2,
    title: "Note-Taking & Local Storage",
    tasks: [
      "Create note editor with real-time editing",
      "Implement highlighting and bookmarking",
      "Setup local storage for sermons, transcriptions, and notes",
      "Build timeline integration"
    ]
  },
  {
    week: 3,
    title: "Supabase Integration & Authentication",
    tasks: [
      "Setup Supabase client and authentication",
      "Implement sync manager for paid users",
      "Create data models in Supabase",
      "Build account management UI"
    ]
  },
  {
    week: 4,
    title: "AI Summarization & Email Notifications",
    tasks: [
      "Implement OpenAI integration via Edge Functions",
      "Create summary job queue system",
      "Setup email notification with Resend",
      "Build summary viewing interface"
    ]
  },
  {
    week: 5,
    title: "Polish & Testing",
    tasks: [
      "Implement error handling and retry logic",
      "Add offline mode improvements",
      "Create loading states and error messages",
      "Perform cross-device testing"
    ]
  },
  {
    week: 6,
    title: "Final Refinements & Launch Preparation",
    tasks: [
      "Fix bugs from testing",
      "Optimize performance",
      "Prepare App Store assets",
      "Finalize documentation"
    ]
  }
];
