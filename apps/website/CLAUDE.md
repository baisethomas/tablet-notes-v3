# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

- **Development Server**: `npm run dev` - Start Next.js development server
- **Build**: `npm run build` - Build production version 
- **Production**: `npm run start` - Start production server
- **Lint**: `npm run lint` - Run ESLint (currently ignores build errors via next.config.mjs)

## Project Architecture

This is a Next.js 15 landing page for Tablet Notes, a sermon recording and transcription app. The project uses the App Router with server actions for email signups.

### Key Technologies
- **Framework**: Next.js 15 with App Router
- **Styling**: Tailwind CSS with extensive custom design system
- **UI Components**: Radix UI primitives with custom shadcn/ui implementation
- **Email**: Resend API for email signups and welcome messages
- **Validation**: Zod for form validation
- **Package Manager**: pnpm (evident from pnpm-lock.yaml)

### Architecture Patterns

**Component Structure:**
- UI components in `/components/ui/` (shadcn/ui based)
- Business components in `/components/` 
- Server actions in `/actions/`
- Utility functions in `/utils/` and `/lib/`

**Email System:**
- Server action: `actions/email-signup.ts` handles newsletter subscriptions
- Email template: `components/email-templates/welcome.tsx` 
- Form component: `components/email-signup-form.tsx` with client-side validation
- Uses Resend with verified domain `hello@updates.tabletnotes.io`

**Styling System:**
- Custom design system in `tailwind.config.ts` with extensive color palette
- Calm, spiritual-focused color scheme (blues, earth tones)
- Custom animations and keyframes for landing page effects
- CSS custom properties for theming

### Key Files
- `app/page.tsx` - Main landing page with hero, features, pricing, FAQ sections
- `actions/email-signup.ts` - Server action for email signups with Resend integration
- `components/email-signup-form.tsx` - Client component with form validation
- `tailwind.config.ts` - Comprehensive design system configuration

### Build Configuration
- `next.config.mjs` configured to ignore ESLint and TypeScript errors during builds
- Images are unoptimized (likely for static deployment)
- Uses pnpm for package management

### Environment Variables Required
- `EMAIL_PROVIDER_API_KEY` - Resend API key for email functionality

## Development Notes

The landing page is a single-page application with smooth scrolling navigation between sections. The email signup system is designed to gracefully handle domain verification issues during development while still recording signups.

The codebase follows modern React patterns with server components where possible and client components only where interactivity is needed (forms, mobile navigation, FAQ toggles).
