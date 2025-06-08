export interface Section {
  id: string;
  title: string;
  description: string;
}

export const sections: Section[] = [
  {
    id: "overview",
    title: "Overview",
    description: "A comprehensive roadmap for building the TabletNotes MVP"
  },
  {
    id: "features",
    title: "Core MVP Features",
    description: "The essential features that make up the TabletNotes MVP"
  },
  {
    id: "architecture",
    title: "Technical Architecture",
    description: "System components and data flow for the TabletNotes app"
  },
  {
    id: "data-models",
    title: "Core Data Models",
    description: "Swift data structures for the application"
  },
  {
    id: "recording",
    title: "Recording & Transcription",
    description: "Implementation of sermon recording and on-device transcription"
  },
  {
    id: "note-taking",
    title: "Note-Taking Module",
    description: "Real-time note-taking during sermon recording"
  },
  {
    id: "storage",
    title: "Local Storage",
    description: "Persistence of sermons, transcriptions, and notes"
  },
  {
    id: "supabase",
    title: "Supabase Integration",
    description: "Cloud sync and authentication for paid users"
  },
  {
    id: "summarization",
    title: "AI Summarization",
    description: "OpenAI-powered sermon summarization"
  },
  {
    id: "notifications",
    title: "Email Notifications",
    description: "Alerting users when summaries are ready"
  },
  {
    id: "ui",
    title: "User Interface",
    description: "App navigation and screen implementation"
  },
  {
    id: "timeline",
    title: "Implementation Timeline",
    description: "6-week roadmap for building the MVP"
  },
  {
    id: "best-practices",
    title: "Best Practices",
    description: "Error handling, offline support, and performance optimization"
  },
  {
    id: "supabase-schema",
    title: "Supabase Schema",
    description: "Database tables and security policies"
  },
  {
    id: "edge-functions",
    title: "Edge Functions",
    description: "Serverless functions for AI processing and notifications"
  },
  {
    id: "monitoring",
    title: "Monitoring & Analytics",
    description: "Tracking app performance and user behavior"
  }
];
