# Tablet Notes: launched-site rebrand

Review branch: `codex/launched-site-rebrand`. This work is local, not deployed.

## Direction

**Keep the message with you.** Lead with what a person can do with Tablet Notes today: record a sermon, write a thought, and return to it later. Retain the pen-nib identity and Proverbs 3:3 origin. Use plain, specific language rather than launch hype or unverified social proof.

The public site reviewed September 14, 2026 still said “Coming to iPhone” and collected launch notifications. This version replaces the homepage waitlist with direct download links. Existing signup code and subscriber data remain intact; the old signup flow is no longer rendered on the homepage. Legal-page content has not been rewritten.

### Cinematic revision

After reviewing Velora's live site again on September 14, the opening was rebuilt around the qualities that give it impact: a full-screen stage, restrained navigation, large centered positioning, layered real product surfaces, and motion that continues into the scroll. Tablet Notes keeps its own pen-nib mark, serif voice, slate-and-ivory palette, and “Keep the message with you” campaign rather than borrowing Velora's product claims or visual identity.

The Seedance paper-arch generation now moves behind the hero copy. A real sermon summary rises through the center while real archive and AI Chat screens enter at the sides. The recording-status element connects the scene to the core action. Below the opening, key sections reveal once as they enter the viewport.

The final hero refinement keeps the real sermon screen at center and replaces the two awkwardly cropped side screenshots with purpose-built floating panels: a timestamped note and an AI-summary excerpt using content already visible in the sample sermon. The navigation is now sticky on a solid ink background, with no transitional gray band beneath it.

## Visual system

- Paper `#F7F3EA`: main canvas and cards.
- Ink `#222724`: body, logo, primary buttons.
- Slate `#526B80`: italic emphasis and closing panel.
- Mist `#DCE5EB`: product backgrounds.
- Brass `#C6A56B`: restrained optional campaign accent, not body text.
- Georgia headlines, Inter body. Large, quiet headlines; modest body copy.
- Rounded arches, thin rules, angled real screenshots, and margin notes.
- One short entrance animation; disabled when reduced motion is requested. No looping or autoplay background video.

## Verified content and assets

- App listing: https://apps.apple.com/us/app/tablet-notes/id6748637379 — seller Baise Thomas. Availability, features, free limits, and minimum operating systems checked September 14, 2026.
- Screens: existing August 30 product screenshots, copied from the app repository into `public/launch`. They are real UI, not invented marketing mockups.
- Film: the existing approved Seedance announcement, copied to `public/launch/film.mp4`.
- Brand still: generated from the app icon with Seedance 2.0 for the launch section, then selected from the 3.8-second frame. The generation cost $0.7623; the source video and contact sheet remain in `public/launch` for review.
- Instagram: https://www.instagram.com/tabletnotesapp/
- No fabricated testimonials, adoption figures, or paid-ad performance claims.

## Implementation

- Homepage is server rendered; only the native-dialog film player needs client interaction.
- Native disclosure FAQs, keyboard-operable controls, focus return after the film, reduced-motion support, meaningful image alternatives.
- Updated page title, description, Apple Smart App Banner metadata, and generated social-sharing image.
- Zod validation compatibility fix: use `issues` instead of obsolete `errors`, with safe empty-array handling. No external email was sent in testing.
- Production TypeScript checking re-enabled. Existing lint-skip configuration is unchanged.

## Review and launch

Run `pnpm install --frozen-lockfile`, `pnpm exec tsc --noEmit`, and `pnpm build`. Use `pnpm start --port 3018` for the production preview. Do not run the dev server and build concurrently against the same `.next` directory.

Before deployment, approve the visual direction and copy. Confirm the inherited privacy and terms pages still describe the shipped app accurately; this rebrand does not audit legal or data-processing claims. A deployment is a separate step. Keep the existing signup audience for any separately approved launch email.

Related competitor research and four-week content calendar live in the app repository at `Marketing/launch-direction-2026-09-14.md`; the companion visual board is `Marketing/launch-visual-board.html`.

## Verification completed

- Production build, including TypeScript validation: passed. `git diff --check`: passed.
- Desktop and 390px mobile visual inspection; 390px and 320px document widths match viewport widths with no horizontal overflow.
- No broken loaded images in the mobile check.
- Film dialog opens; Escape closes it, pauses playback, and returns focus to its trigger. FAQ expands to reveal its answer.
- The embedded browser crashed decoding the original MP4. Added a VP9/Opus WebM first source and a still poster, keeping MP4 fallback. WebM playback verified with readyState 4 and a 5.046-second duration.
- No external messages, deployments, or advertising spend.
- Cinematic revision: autoplay background is muted, has no audio track, and uses a 593 KB WebM with MP4 fallback. Motion is disabled and the video is replaced by its still poster when reduced motion is requested.
