import Link from "next/link"

export default function PrivacyPolicyPage() {
  return (
    <div className="flex min-h-screen flex-col bg-[#F7F8FA] text-[#1F1F23]">
      <header className="px-6 lg:px-8 h-16 flex items-center justify-center border-b border-[#1F1F23]/5 bg-[#F7F8FA]">
        <Link href="/" className="tracking-[0.2em] text-sm font-medium text-[#1F1F23]/90 hover:text-[#1F1F23] transition-colors">
          Tablet Notes
        </Link>
      </header>

      <main className="flex-1">
        <div className="max-w-3xl mx-auto px-6 py-16">
          <h1 className="text-3xl md:text-4xl font-medium tracking-tight mb-4 text-center">
            Privacy Policy
          </h1>
          <p className="text-[#1F1F23]/60 text-center text-sm mb-12">
            <strong>Effective Date:</strong> July 17, 2025 &mdash; <strong>Last Updated:</strong> December 21, 2025
          </p>

          <div className="prose prose-lg prose-headings:font-medium prose-headings:tracking-tight max-w-none text-[#1F1F23]/80">
            <h2>Introduction</h2>
            <p>{"Tablet Notes (\"we,\" \"our,\" or \"us\") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application and related services."}</p>

            <h2>Information We Collect</h2>
            <h3>Personal Information You Provide</h3>
            <ul>
              <li><strong>Account Information</strong>: Email address, display name (optional)</li>
              <li><strong>Audio Recordings</strong>: Sermon recordings and related notes you create</li>
              <li><strong>User-Generated Content</strong>: Notes, summaries, and annotations you add to recordings</li>
            </ul>
            <h3>Automatically Collected Information</h3>
            <ul>
              <li><strong>Usage Data</strong>: App usage patterns, feature usage, and performance metrics</li>
              <li><strong>Device Information</strong>: Device type, operating system version, app version</li>
              <li><strong>Technical Data</strong>: Crash reports, error logs (anonymized)</li>
            </ul>

            <h2>How We Use Your Information</h2>
            <ul>
              <li><strong>Core Functionality</strong>: Recording, transcribing, and summarizing audio content</li>
              <li><strong>Cloud Storage</strong>: Syncing your data across devices securely</li>
              <li><strong>User Experience</strong>: Personalizing features and improving app performance</li>
              <li><strong>Support</strong>: Providing customer service and technical support</li>
            </ul>

            <h2>Data Processing and Storage</h2>
            <ul>
              <li>All data encrypted in transit and at rest</li>
              <li>Primary storage in the United States</li>
              <li><strong>Active Accounts</strong>: Data retained while your account is active</li>
              <li><strong>Deleted Content</strong>: Permanently deleted within 30 days of user deletion</li>
              <li><strong>Account Deletion</strong>: All user data deleted within 90 days of account closure</li>
            </ul>

            <h2>Third-Party Services</h2>
            <ul>
              <li>We do NOT sell your personal information</li>
              <li>We do NOT share content with third parties except as necessary for core functionality</li>
              <li>Service providers are bound by strict data protection agreements</li>
            </ul>

            <h2>Your Rights and Choices</h2>
            <ul>
              <li><strong>Access</strong>: View all your stored data through the app</li>
              <li><strong>Correction</strong>: Edit or update your information at any time</li>
              <li><strong>Deletion</strong>: Delete specific recordings or your entire account</li>
              <li><strong>Export</strong>: Download your data in a standard format</li>
            </ul>

            <h2>Security Measures</h2>
            <ul>
              <li><strong>Encryption</strong>: All data encrypted in transit and at rest</li>
              <li><strong>Authentication</strong>: Secure login with industry-standard protocols</li>
              <li><strong>Access Controls</strong>: Strict limits on who can access your data</li>
              <li><strong>Regular Audits</strong>: Ongoing security assessments and updates</li>
            </ul>

            <h2>{"Children's Privacy"}</h2>
            <p>Tablet Notes is not intended for children under 13. We do not knowingly collect personal information from children under 13.</p>

            <h2>Changes to This Policy</h2>
            <p>We may update this Privacy Policy to reflect changes in our practices or legal requirements. We will notify you of significant changes via email or app notification.</p>

            <h2>Contact Information</h2>
            <p>If you have questions or concerns about this Privacy Policy:</p>
            <ul>
              <li><strong>Email</strong>: privacy@tabletnotes.io</li>
              <li><strong>Website</strong>: <a href="https://www.tabletnotes.io/privacy">https://www.tabletnotes.io/privacy</a></li>
            </ul>
          </div>

          <div className="mt-12 text-center">
            <Link
              href="/"
              className="inline-block bg-[#2F4FA2] hover:bg-[#243D7C] text-[#FFFFFF] text-sm font-medium px-6 py-3 rounded-md transition-colors"
            >
              Back to Home
            </Link>
          </div>
        </div>
      </main>
    </div>
  )
}
