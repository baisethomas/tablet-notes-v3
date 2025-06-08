export interface EdgeFunction {
  name: string;
  description: string;
}

export const edgeFunctions: EdgeFunction[] = [
  {
    name: "generate-summary",
    description: "Processes transcription text, calls OpenAI API, updates summary status, and triggers email notification"
  },
  {
    name: "process-transcription",
    description: "Performs post-processing on transcription, identifies potential scripture references, and improves formatting"
  }
];

export interface MonitoringItem {
  category: string;
  items: string[];
}

export const monitoring: MonitoringItem[] = [
  {
    category: "PostHog Integration",
    items: [
      "Track key user events",
      "Monitor feature usage",
      "Analyze user retention"
    ]
  },
  {
    category: "Error Tracking",
    items: [
      "Log errors to monitoring service",
      "Track crash-free sessions",
      "Monitor API response times"
    ]
  }
];
