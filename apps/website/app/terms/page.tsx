import Link from "next/link"

export default function TermsOfUsePage() {
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
            Terms of Use
          </h1>
          <p className="text-[#1F1F23]/60 text-center text-sm mb-12">
            <strong>Effective Date:</strong> July 17, 2025 &mdash; <strong>Last Updated:</strong> July 7, 2026
          </p>

          <div className="prose prose-lg prose-headings:font-medium prose-headings:tracking-tight max-w-none text-[#1F1F23]/80">
            <h2>1. Acceptance of Terms</h2>
            <p>
              {"These Terms of Use (\"Terms\") govern your access to and use of Tablet Notes (the \"App\"), operated by Loom & Logic Labs, LLC (\"we,\" \"us,\" or \"our\"). By downloading, accessing, or using the App, you agree to be bound by these Terms and our "}
              <Link href="/privacy">Privacy Policy</Link>
              {". If you do not agree, do not use the App."}
            </p>
            <p>
              You must be at least 13 years old to use Tablet Notes. If you are under 18, you may only use the App with the involvement of a parent or guardian.
            </p>

            <h2>2. Description of Service</h2>
            <p>
              Tablet Notes allows you to record audio (such as sermons, Bible studies, and similar teachings), take timestamped notes during recording, and receive AI-generated transcription and summaries of your recordings. The App also provides an AI chat feature to ask questions about your recorded content and a built-in Bible browser.
            </p>

            <h2>3. Your Account</h2>
            <p>
              You must create an account to use the App. You are responsible for maintaining the confidentiality of your login credentials and for all activity under your account. Notify us immediately of any unauthorized use of your account.
            </p>

            <h2>4. Recording Content — Your Responsibility</h2>
            <p>
              Tablet Notes is a tool for recording audio you have the right to record. You, not Tablet Notes, are solely responsible for:
            </p>
            <ul>
              <li>
                Obtaining any necessary permission or consent before recording a sermon, teaching, or any other individual&apos;s speech, including compliance with your venue&apos;s policies and applicable recording-consent laws in your location.
              </li>
              <li>
                Ensuring your use of recorded content (including sharing, storing, or distributing it) doesn&apos;t infringe the rights of the speaker or any third party.
              </li>
            </ul>
            <p>
              We do not review, endorse, or take responsibility for the content of your recordings, notes, or any AI-generated transcript, summary, or chat response derived from them.
            </p>

            <h2>5. AI-Generated Content</h2>
            <p>
              Transcripts, summaries, and chat responses are generated using automated AI processing and may contain errors, omissions, or inaccuracies. AI-generated content is provided for convenience and personal reference only and should not be relied upon as an authoritative or complete record of what was said. Always verify important information against the original audio.
            </p>

            <h2>6. Your Content and License to Us</h2>
            <p>
              {"You retain ownership of the audio, notes, and other content you create in the App (\"Your Content\"). By using the App, you grant us a limited, non-exclusive license to store, process, and transmit Your Content solely as necessary to provide the App's functionality (e.g., transcription, summarization, and cloud sync). We do not sell Your Content or use it to train AI models."}
            </p>
            <p>
              You are responsible for backing up content you consider important. While we take reasonable steps to protect your data, we do not guarantee against data loss.
            </p>

            <h2>7. Subscriptions and Billing</h2>
            <p>
              Tablet Notes offers a free tier with limited usage (currently 5 recordings per month, up to 30 minutes each, 1GB storage) and a Premium subscription with expanded limits and cross-device sync.
            </p>
            <ul>
              <li>
                <strong>Premium pricing:</strong> $9.99/month or $79.99/year, subject to change with notice as required by Apple&apos;s App Store guidelines.
              </li>
              <li>
                <strong>Free trial:</strong> New subscribers may receive a free trial period (currently 14 days). If you don&apos;t cancel before the trial ends, you will be charged for the subscription.
              </li>
              <li>
                <strong>Auto-renewal:</strong> Subscriptions automatically renew unless canceled at least 24 hours before the end of the current billing period. Your Apple ID account will be charged for renewal within 24 hours prior to the end of the current period.
              </li>
              <li>
                <strong>Managing your subscription:</strong> You can manage or cancel your subscription anytime in your Apple ID Account Settings. Deleting the App does not cancel your subscription.
              </li>
              <li>
                <strong>Refunds:</strong> All purchases are handled through Apple&apos;s App Store and are subject to Apple&apos;s refund policies. We do not directly process payments or issue refunds.
              </li>
              <li>
                <strong>No proration:</strong> Downgrading or canceling does not entitle you to a refund for the current billing period.
              </li>
            </ul>

            <h2>8. Acceptable Use</h2>
            <p>You agree not to:</p>
            <ul>
              <li>Use the App for any unlawful purpose or in violation of any applicable law or regulation.</li>
              <li>Attempt to gain unauthorized access to the App, other users&apos; accounts, or our systems.</li>
              <li>Reverse engineer, decompile, or attempt to extract the source code of the App, except as permitted by law.</li>
              <li>Use automated means (bots, scrapers) to access the App.</li>
              <li>Upload or record content that infringes the intellectual property or privacy rights of others.</li>
            </ul>
            <p>We reserve the right to suspend or terminate accounts that violate these Terms.</p>

            <h2>9. Account Deletion</h2>
            <p>
              You may delete your account at any time from within the App&apos;s settings. Account deletion permanently removes your recordings, notes, transcripts, summaries, and account data from our systems, subject to any retention required by law. Deleting your account does not automatically cancel an active Apple subscription — cancel separately through your Apple ID Account Settings.
            </p>

            <h2>10. Third-Party Services</h2>
            <p>
              The App uses third-party service providers to deliver its functionality, including cloud storage and authentication, speech-to-text transcription, and AI summarization/chat processing. These providers process Your Content solely to provide the App&apos;s features and are bound by appropriate data protection obligations. See our{" "}
              <Link href="/privacy">Privacy Policy</Link> for more detail.
            </p>

            <h2>11. Intellectual Property</h2>
            <p>
              The App, including its design, features, and underlying software, is owned by us and protected by intellectual property laws. These Terms do not grant you any rights to our trademarks, logos, or branding.
            </p>

            <h2>12. Disclaimer of Warranties</h2>
            <p>
              {"THE APP IS PROVIDED \"AS IS\" AND \"AS AVAILABLE\" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT. WE DO NOT WARRANT THAT THE APP WILL BE UNINTERRUPTED, ERROR-FREE, OR THAT AI-GENERATED CONTENT WILL BE ACCURATE."}
            </p>

            <h2>13. Limitation of Liability</h2>
            <p>
              TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, OR ANY LOSS OF DATA, ARISING FROM YOUR USE OF THE APP. OUR TOTAL LIABILITY FOR ANY CLAIM RELATING TO THE APP SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE 12 MONTHS PRECEDING THE CLAIM.
            </p>

            <h2>14. Changes to These Terms</h2>
            <p>
              We may update these Terms from time to time. Continued use of the App after changes take effect constitutes acceptance of the revised Terms. We&apos;ll update the &quot;Last Updated&quot; date above when changes are made.
            </p>

            <h2>15. Termination</h2>
            <p>
              We may suspend or terminate your access to the App at any time for violation of these Terms. You may stop using the App and delete your account at any time.
            </p>

            <h2>16. Governing Law</h2>
            <p>
              These Terms are governed by the laws of the State of California, without regard to its conflict of law principles.
            </p>

            <h2>17. Contact Us</h2>
            <p>Questions about these Terms? Contact us at:</p>
            <ul>
              <li><strong>Email</strong>: support@tabletnotes.io</li>
              <li><strong>Website</strong>: <a href="https://www.tabletnotes.io/terms">https://www.tabletnotes.io/terms</a></li>
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
