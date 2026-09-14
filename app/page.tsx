import Image from "next/image";
import Link from "next/link";
import {
  ArrowDown,
  ArrowUpRight,
  AudioLines,
  BookOpen,
  Check,
  MessageCircle,
  NotebookPen,
} from "lucide-react";
import { LaunchFilm } from "@/components/launch-film";
import { ScrollReveal } from "@/components/scroll-reveal";
import "./launch.css";

const appStore = "https://apps.apple.com/app/tablet-notes/id6748637379";

function DownloadLink({ compact = false }: { compact?: boolean }) {
  return (
    <a className={`download-link ${compact ? "compact" : ""}`} href={appStore}>
      {compact ? "Get the app" : "Download on the App Store"}
      <ArrowUpRight size={17} aria-hidden="true" />
    </a>
  );
}

function Brand() {
  return (
    <Link href="/" className="launch-brand" aria-label="Tablet Notes home">
      <Image src="/launch/icon.png" alt="" width={38} height={38} />
      <span>Tablet Notes</span>
    </Link>
  );
}

const questions = [
  [
    "Can I try it for free?",
    "Yes. The free plan includes 5 recordings a month, up to 30 minutes each, and 1 GB of storage. Premium adds longer recordings and cross-device sync. You can see the current plans and trial terms in the app.",
  ],
  [
    "Does it work on my iPhone or iPad?",
    "Tablet Notes is available for iPhone and iPad running iOS or iPadOS 17.6 or later. Download it from the App Store.",
  ],
  [
    "What does the AI do?",
    "After a recording, AI creates a transcript and summary. You can also ask questions about the sermon in AI Chat. AI can make mistakes, so check important details against the recording and Scripture.",
  ],
  [
    "Can I use it for a Bible study?",
    "Yes. You can record Bible studies and other teaching, too. Ask the speaker and anyone involved for permission before recording.",
  ],
];

export default function Home() {
  return (
    <div className="launch-site">
      <ScrollReveal />
      <a href="#main" className="skip-link">
        Skip to content
      </a>
      <header className="launch-header top-nav">
        <div className="nav-inner wrap">
          <Brand />
          <nav aria-label="Main navigation">
            <a href="#how-it-works">How it works</a>
            <a href="#our-story">Our story</a>
            <DownloadLink compact />
          </nav>
        </div>
      </header>
      <div className="cinematic-top">
        <section
          id="main"
          className="launch-hero wrap"
          aria-labelledby="hero-title"
        >
          <video
            className="hero-film"
            autoPlay
            muted
            loop
            playsInline
            poster="/launch/seedance-brand-still.jpg"
            aria-hidden="true"
            tabIndex={-1}
          >
            <source
              src="/launch/seedance-brand-background.webm"
              type="video/webm"
            />
            <source
              src="/launch/seedance-brand-landscape.mp4"
              type="video/mp4"
            />
          </video>
          <div className="hero-shade" aria-hidden="true" />
          <div className="hero-copy">
            <p className="eyebrow">
              <span className="status-dot" /> NOW ON THE APP STORE
            </p>
            <h1 id="hero-title">
              Keep the{" "}
              <br />
              message
              <br />
              <em>with you.</em>
            </h1>
            <p className="hero-description">
              Record the sermon. Write down what speaks to you. Come back to it
              during the week, with your notes, a transcript, and a summary in
              one place.
            </p>
            <div className="hero-actions">
              <DownloadLink />
              <a className="text-link" href="#launch-film">
                Watch the film <span aria-hidden="true">↗</span>
              </a>
            </div>
            <p className="availability">
              Free to start <span>·</span> iPhone &amp; iPad
            </p>
          </div>
          <div className="hero-stage">
            <div className="stage-slice note-slice" aria-hidden="true">
              <div className="slice-heading">
                <span>
                  <NotebookPen size={15} /> NOTE
                </span>
                <time>18:42</time>
              </div>
              <blockquote>
                “The hand of God was aligning your footsteps and setting you in
                the right place at the exact right time.”
              </blockquote>
              <p>Linked to the recording</p>
            </div>
            <div className="phone hero-phone">
              <Image
                src="/launch/summary.png"
                alt="Tablet Notes sermon summary with a linked Scripture reference"
                width={1206}
                height={2622}
                priority
                sizes="(max-width: 600px) 65vw, 300px"
              />
            </div>
            <div className="stage-slice summary-slice" aria-hidden="true">
              <div className="slice-heading">
                <span>
                  <BookOpen size={15} /> AI SUMMARY
                </span>
                <span>SERMON</span>
              </div>
              <h3>Recognizing God&apos;s Presence</h3>
              <span className="scripture-ref">Luke 2:25–27</span>
              <p>
                The sermon explores the significance of the Holy Spirit in
                recognizing God&apos;s presence.
              </p>
            </div>
            <div className="hero-listening" aria-hidden="true">
              <span className="listening-pulse" />
              Recording Sunday&apos;s message
              <span>18:42</span>
            </div>
          </div>
        </section>
      </div>
      <main>
        <div className="chapter-rule wrap">
          <span>SERMON NOTES, MADE FOR THE WEEK AHEAD</span>
          <a href="#how-it-works" aria-label="Explore how Tablet Notes works">
            <ArrowDown size={19} />
          </a>
        </div>
        <section
          id="how-it-works"
          className="how-section wrap"
          aria-labelledby="how-title"
        >
          <div className="section-heading" data-reveal>
            <p className="eyebrow">FROM THE PEW TO EVERYDAY LIFE</p>
            <h2 id="how-title">
              You don&apos;t have to
              <br />
              catch every word.
            </h2>
            <p>
              Listen closely. Jot down a thought. The recording will be there
              when you want to return to it.
            </p>
          </div>
          <div className="steps">
            <article data-reveal>
              <span className="step-number">01 / DURING</span>
              <AudioLines aria-hidden="true" />
              <h3>Be there for the message.</h3>
              <p>
                Start a recording and take notes as you listen. Each note is
                linked to that moment in the audio.
              </p>
            </article>
            <article data-reveal>
              <span className="step-number">02 / AFTER</span>
              <NotebookPen aria-hidden="true" />
              <h3>Find the part that stayed.</h3>
              <p>
                Read the transcript, review the summary, or jump back to the
                moment behind a note.
              </p>
            </article>
            <article data-reveal>
              <span className="step-number">03 / THROUGH THE WEEK</span>
              <BookOpen aria-hidden="true" />
              <h3>Spend a little longer with it.</h3>
              <p>
                Ask a question about the sermon. Open the Scripture. Make room
                for your own reflection.
              </p>
            </article>
          </div>
        </section>
        <section className="product-section" aria-labelledby="product-title">
          <div className="wrap">
            <div className="product-heading">
              <div>
                <p className="eyebrow">A CLOSER LOOK</p>
                <h2 id="product-title">
                  Pick up where
                  <br />
                  the sermon left off.
                </h2>
              </div>
              <p>
                The recording, the words, and your questions.
                <br />
                All together, ready when you are.
              </p>
            </div>
            <div className="product-grid">
              <article className="product-card transcript-card" data-reveal>
                <div className="product-card-copy">
                  <AudioLines size={22} aria-hidden="true" />
                  <h3>Go back to the words.</h3>
                  <p>
                    A searchable transcript alongside the audio, so you can
                    revisit what was actually said.
                  </p>
                </div>
                <div className="screen-window">
                  <Image
                    src="/launch/transcript.png"
                    alt="Sermon transcript with audio playback controls"
                    width={1206}
                    height={2622}
                    sizes="(max-width: 700px) 85vw, 460px"
                  />
                </div>
              </article>
              <article className="product-card chat-card" data-reveal>
                <div className="product-card-copy">
                  <MessageCircle size={22} aria-hidden="true" />
                  <h3>Bring your questions.</h3>
                  <p>
                    Ask about a point in the sermon. AI Chat draws on the
                    transcript to help you explore it.
                  </p>
                </div>
                <div className="screen-window">
                  <Image
                    src="/launch/chat.png"
                    alt="AI Chat inside a Tablet Notes sermon"
                    width={1206}
                    height={2622}
                    sizes="(max-width: 700px) 85vw, 460px"
                  />
                </div>
              </article>
            </div>
            <p className="product-disclaimer">
              Real app screens. AI-generated text may contain errors; check the
              recording and Scripture.
            </p>
          </div>
        </section>
        <section
          id="launch-film"
          className="film-section wrap"
          aria-labelledby="film-title"
          data-reveal
        >
          <div>
            <p className="eyebrow">TABLET NOTES IS HERE</p>
            <h2 id="film-title">
              A small app.
              <br />A meaningful beginning.
            </h2>
            <p>Made for the messages you want to remember.</p>
            <LaunchFilm />
          </div>
          <div className="film-art">
            <Image
              src="/launch/seedance-brand-still.jpg"
              alt="Tablet Notes pen-nib mark above an arch of sculpted paper in warm morning light"
              fill
              sizes="(max-width: 760px) calc(100vw - 40px), 50vw"
            />
            <span>Keep the message with you.</span>
          </div>
        </section>
        <section
          id="our-story"
          className="story-section wrap"
          aria-labelledby="story-title"
        >
          <p className="eyebrow">THE THOUGHT BEHIND TABLET NOTES</p>
          <div className="story-grid" data-reveal>
            <h2 id="story-title">
              “Write them on
              <br />
              the tablet of
              <br />
              your heart.”<span>PROVERBS 3:3</span>
            </h2>
            <div>
              <p>
                A sermon can give you something to think about long after you
                leave church. But a line you wanted to remember gets fuzzy. A
                question you meant to come back to slips away.
              </p>
              <p>
                Tablet Notes gives those things a place to live. Recordings to
                return to. Notes in your own words. Space to keep thinking.
              </p>
              <p className="story-signoff">
                That&apos;s the idea behind the name.
              </p>
            </div>
          </div>
        </section>
        <section className="faq-section wrap" aria-labelledby="faq-title">
          <div>
            <p className="eyebrow">BEFORE SUNDAY</p>
            <h2 id="faq-title">
              A few things
              <br />
              to know.
            </h2>
          </div>
          <div className="faq-list" data-reveal>
            {questions.map(([question, answer]) => (
              <details key={question}>
                <summary>
                  {question}
                  <span aria-hidden="true">+</span>
                </summary>
                <p>{answer}</p>
              </details>
            ))}
          </div>
        </section>
        <section className="final-cta" aria-labelledby="cta-title">
          <div className="wrap">
            <p className="eyebrow">READY FOR YOUR NEXT SERMON</p>
            <h2 id="cta-title">
              Take the message
              <br />
              <em>into your week.</em>
            </h2>
            <DownloadLink />
            <p>
              <Check size={14} aria-hidden="true" /> Free to start. Available
              for iPhone &amp; iPad.
            </p>
          </div>
        </section>
      </main>
      <footer className="launch-footer wrap">
        <Brand />
        <p>© 2026 Tablet Notes</p>
        <nav aria-label="Footer">
          <a
            href="https://www.instagram.com/tabletnotesapp/"
            target="_blank"
            rel="noopener noreferrer"
          >
            Instagram ↗
          </a>
          <Link href="/privacy">Privacy</Link>
          <Link href="/terms">Terms</Link>
        </nav>
      </footer>
    </div>
  );
}
