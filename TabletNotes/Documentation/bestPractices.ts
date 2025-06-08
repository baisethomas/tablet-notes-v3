export interface BestPractice {
  category: string;
  practices: string[];
}

export const bestPractices: BestPractice[] = [
  {
    category: "Error Handling",
    practices: [
      "Implement retry with exponential backoff for network requests",
      "Show user-friendly error messages",
      "Cache requests for retry when online",
      "Provide manual correction interface for transcription errors",
      "Save partial results when possible",
      "Offer guidance for improving audio quality"
    ]
  },
  {
    category: "Offline Support",
    practices: [
      "Queue changes while offline",
      "Automatically sync when connection is restored",
      "Show sync status indicators",
      "Implement background fetch for sync",
      "Use background tasks for processing",
      "Optimize for battery efficiency"
    ]
  },
  {
    category: "Performance Optimization",
    practices: [
      "Optimize audio format for transcription",
      "Process in chunks for memory efficiency",
      "Use background threads for processing",
      "Use SwiftUI previews for component testing",
      "Implement loading states for async operations",
      "Optimize list rendering with lazy loading"
    ]
  },
  {
    category: "Testing Strategy",
    practices: [
      "Test core services in isolation",
      "Mock dependencies for predictable testing",
      "Aim for 80% code coverage of business logic",
      "Test end-to-end flows",
      "Verify Supabase integration",
      "Test offline to online transitions",
      "Use SwiftUI snapshot testing",
      "Test on multiple device sizes",
      "Verify accessibility support"
    ]
  }
];
