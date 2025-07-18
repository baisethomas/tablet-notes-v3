export interface OverviewContent {
  title: string;
  description: string;
}

export const overviewContent: OverviewContent = {
  title: "TabletNotes MVP Implementation Plan",
  description: "This implementation plan combines the technical requirements with architectural recommendations to create a comprehensive roadmap for building the TabletNotes MVP. The plan focuses on practical next steps for implementation, assuming project setup is already complete."
};

export interface Feature {
  id: string;
  title: string;
  description: string;
  icon: string;
}

export const features: Feature[] = [
  {
    id: "recording",
    title: "Real-Time Sermon Recording",
    description: "Captures spoken audio using iOS on-device transcription with SFSpeechRecognizer",
    icon: "mic"
  },
  {
    id: "note-taking",
    title: "Live Note-Taking",
    description: "Allows users to write notes in real time while recording with timestamp linking",
    icon: "pencil"
  },
  {
    id: "summarization",
    title: "AI Sermon Summarization",
    description: "Generates concise summaries after transcription using OpenAI",
    icon: "brain"
  },
  {
    id: "sync",
    title: "Supabase Sync",
    description: "Syncs notes and transcripts to Supabase cloud for paid users",
    icon: "cloud"
  },
  {
    id: "notifications",
    title: "Email Notifications",
    description: "Notifies users via email when summaries are ready with deep links",
    icon: "mail"
  }
];
