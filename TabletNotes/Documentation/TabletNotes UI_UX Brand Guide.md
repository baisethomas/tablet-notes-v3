# Tablet Notes UI/UX Brand Guide

![Tablet Notes Logo](https://placeholder.com/logo)

## Table of Contents
1. [Brand Foundation](#brand-foundation)
2. [Visual Identity](#visual-identity)
3. [Typography](#typography)
4. [Color System](#color-system)
5. [UI Components](#ui-components)
6. [Interaction Patterns](#interaction-patterns)
7. [Navigation System](#navigation-system)
8. [Content Guidelines](#content-guidelines)
9. [Accessibility Standards](#accessibility-standards)
10. [App Screens](#app-screens)

---

<a id="brand-foundation"></a>
## 1. Brand Foundation

### Mission
Help users engage more deeply with spiritual messages by offering a calm space to record, reflect, and revisit sermons.

### Brand Essence
A sermon-first app designed to feel like writing on a spiritual tablet—quiet, minimal, and deeply intentional.

### Brand Values
- **Presence**: Enabling users to be fully present during spiritual moments
- **Clarity**: Making sermon content accessible and understandable
- **Growth**: Supporting ongoing spiritual development
- **Respect**: Honoring the sacred nature of religious teachings

### Brand Voice
- **Warm**: Inviting and comforting, never cold or clinical
- **Intelligent**: Thoughtful and articulate, but never pretentious
- **Focused**: Clear and direct, avoiding unnecessary complexity
- **Spiritually aware**: Respectful of faith traditions without being denominationally specific

### Target Audience
- Tech-savvy churchgoers
- Pastors and ministry leaders
- Students of faith
- Regular sermon attendees
- Individuals seeking spiritual growth

---

<a id="visual-identity"></a>
## 2. Visual Identity

### Logo System
- **Wordmark**: "Tablet" in SF Pro (Medium or Semi-Bold)
- **Preferred Logo Colors**:
  - Primary Blue: `#4A6D8C`
  - Alternate: Black or white as needed

### Logo Layouts
- **Stacked**: Icon above the wordmark
- **Horizontal**: Icon to the left of the wordmark

### Logo Clear Space
Always maintain clear space around the logo equal to the height of the "T" in "Tablet" to ensure visual impact.

### Logo Don'ts
- Don't stretch or distort the logo
- Don't change the logo colors outside of the approved palette
- Don't add effects like shadows or glows
- Don't place the logo on busy backgrounds that reduce legibility

### Design Inspiration
- **Otter.ai**: For minimalist, distraction-free interface
- **Physical tablets**: For tactile, tangible feeling
- **Sacred spaces**: For calm, focused atmosphere

---

<a id="typography"></a>
## 3. Typography

### Primary Font
**SF Pro** (San Francisco)
- Native Apple system font for iOS/macOS
- Clean, legible, and professional
- Used across the app, marketing, and icons

### Typography Scale

| Element | Font | Weight | Size | Line Height |
|---------|------|--------|------|------------|
| H1 (Screen Title) | SF Pro | Semi-Bold | 28px | 34px |
| H2 (Section Title) | SF Pro | Medium | 22px | 28px |
| H3 (Card Title) | SF Pro | Medium | 18px | 24px |
| Body | SF Pro | Regular | 16px | 22px |
| Caption | SF Pro | Regular | 14px | 20px |
| Small/Legal | SF Pro | Regular | 12px | 16px |

### Typography Guidelines
- Maintain left alignment for most text
- Use sentence case for headings and buttons
- Limit line length to 60-75 characters for optimal readability
- Use font weight rather than size to create hierarchy when possible

---

<a id="color-system"></a>
## 4. Color System

### Primary Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| Primary Blue | `#4A6D8C` | Primary buttons, active states, key UI elements |
| Secondary Blue-Gray | `#8A9BA8` | Secondary elements, icons, borders |

### Background Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| Background White | `#FFFFFF` | Primary background |
| Background Gray | `#F5F7F9` | Secondary background, cards, sections |

### Text Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| Text Primary | `#333333` | Primary text, headings |
| Text Secondary | `#666666` | Secondary text, captions |

### Accent Colors

| Color Name | Hex Code | Usage |
|------------|----------|-------|
| Success Green | `#4A8C6A` | Success states, confirmations |
| Error Red | `#B55A5A` | Error states, critical alerts |
| Warning Amber | `#D9A55A` | Warnings, cautionary messages |
| Info Blue | `#5A7DB5` | Informational elements |

### Color Usage Guidelines
- Use color purposefully to guide attention, not for decoration
- Maintain sufficient contrast for readability (minimum 4.5:1 for text)
- Use accent colors sparingly to highlight important information
- Ensure the interface remains calm and focused by limiting color usage

---

<a id="ui-components"></a>
## 5. UI Components

### Buttons

#### Primary Button
- Background: Primary Blue (`#4A6D8C`)
- Text: White (`#FFFFFF`)
- Corner Radius: 8px
- Height: 48px
- Padding: 16px horizontal

#### Secondary Button
- Border: 1px solid Primary Blue (`#4A6D8C`)
- Text: Primary Blue (`#4A6D8C`)
- Background: Transparent
- Corner Radius: 8px
- Height: 48px
- Padding: 16px horizontal

#### Tertiary Button
- Text: Primary Blue (`#4A6D8C`)
- Background: Transparent
- Height: 48px
- Padding: 16px horizontal

#### Icon Button
- Size: 44px × 44px (minimum touch target)
- Icon: 24px × 24px
- Background: Transparent or Background Gray (`#F5F7F9`)

### Cards

#### Standard Card
- Background: White (`#FFFFFF`)
- Border: None
- Shadow: Subtle (0px 2px 4px rgba(0, 0, 0, 0.05))
- Corner Radius: 12px
- Padding: 16px

#### Sermon Card
- Background: White (`#FFFFFF`)
- Border: None
- Shadow: Subtle (0px 2px 4px rgba(0, 0, 0, 0.05))
- Corner Radius: 12px
- Padding: 16px
- Elements:
  - Sermon title (H3)
  - Date
  - Duration
  - Preview of transcript or notes
  - Action buttons

### Form Elements

#### Text Input
- Height: 48px
- Border: 1px solid Secondary Blue-Gray (`#8A9BA8`)
- Border Radius: 8px
- Padding: 12px horizontal
- Active State: 2px border Primary Blue (`#4A6D8C`)
- Error State: 2px border Error Red (`#B55A5A`)

#### Checkbox
- Size: 20px × 20px
- Border Radius: 4px
- Checked State: Primary Blue (`#4A6D8C`) background with white checkmark

#### Toggle
- Height: 24px
- Width: 44px
- Border Radius: 12px
- Off State: Gray background
- On State: Primary Blue (`#4A6D8C`) background

### Lists

#### Standard List
- Item Height: 64px minimum
- Divider: 1px line, Light Gray (`#E5E5E5`)
- Padding: 16px horizontal

#### Sermon List
- Item Height: Variable based on content
- Divider: 1px line, Light Gray (`#E5E5E5`)
- Padding: 16px horizontal
- Elements:
  - Sermon title
  - Date
  - Duration
  - Preview text
  - Action icons

---

<a id="interaction-patterns"></a>
## 6. Interaction Patterns

### Touch Targets
- Minimum size: 44px × 44px for all interactive elements
- Spacing between targets: Minimum 8px

### Feedback States
- **Hover**: Subtle opacity change (0.9)
- **Active/Pressed**: Darken color by 10%
- **Disabled**: 0.5 opacity, no interaction

### Animations
Use animations purposefully for:
- Transitions between screens (subtle slide or fade)
- Loading states (gentle pulse or shimmer)
- Sync status indicators
- Summary generation progress

### Animation Principles
- **Subtle**: Never distracting from content
- **Purposeful**: Communicating state or progress
- **Quick**: Generally 200-300ms duration
- **Eased**: Natural feeling with appropriate easing curves

### Gestures
- **Tap**: Primary selection
- **Long Press**: Access additional options
- **Swipe**: Navigate between related content
- **Pinch**: Zoom in transcript view (where applicable)

---

<a id="navigation-system"></a>
## 7. Navigation System

### Primary Navigation
- **Bottom Tab Bar**: Main navigation method
  - Record (primary action)
  - Library (sermon collection)
  - Account (settings and profile)

### Secondary Navigation
- **Back Button**: Top left of screen
- **Close Button**: Modal dismissal, top right
- **Breadcrumbs**: For deep navigation paths

### Navigation Principles
- Keep primary actions within thumb reach
- Maintain consistent navigation patterns
- Provide clear visual feedback for current location
- Allow users to return to previous screens easily

### Screen Transitions
- Use consistent, subtle transitions between screens
- Maintain spatial relationships in transitions
- Ensure transitions communicate navigation direction

---

<a id="content-guidelines"></a>
## 8. Content Guidelines

### Writing Style
- **Clear**: Direct and straightforward
- **Concise**: Brief but complete
- **Warm**: Friendly without being casual
- **Respectful**: Honoring the spiritual nature of content

### Terminology
- Use consistent terminology throughout the app
- Prefer "sermon" over "recording" or "audio"
- Use "notes" for user-generated content
- Use "summary" for AI-generated content
- Use "transcript" for verbatim text

### Empty States
- Provide helpful guidance rather than just "No content"
- Suggest next actions
- Maintain brand voice even in utility messages

### Error Messages
- Be clear about what went wrong
- Suggest solutions when possible
- Avoid technical jargon
- Maintain a calm, reassuring tone

### Notifications
- Be respectful of user attention
- Focus on high-value information
- Use consistent formatting
- Provide clear next steps when applicable

---

<a id="accessibility-standards"></a>
## 9. Accessibility Standards

### Color Contrast
- Maintain minimum 4.5:1 contrast ratio for normal text
- Maintain minimum 3:1 contrast ratio for large text
- Never rely on color alone to convey information

### Text Sizing
- Support dynamic type in iOS
- Ensure layouts adapt to larger text sizes
- Maintain readability at all supported sizes

### Touch Targets
- Minimum size of 44px × 44px
- Adequate spacing between interactive elements

### Screen Readers
- Provide meaningful labels for all UI elements
- Use semantic HTML elements
- Ensure logical navigation order
- Test with VoiceOver on iOS

### Reduced Motion
- Respect user preferences for reduced motion
- Provide alternatives to animation where necessary
- Ensure functionality without animation

---

<a id="app-screens"></a>
## 10. App Screens

### Onboarding
- **Welcome**: App introduction and value proposition
- **Permissions**: Request necessary permissions with clear explanations
- **Account Creation**: Simple email/password or Apple ID sign-in
- **Feature Highlights**: Brief overview of key features

### Recording
- **Pre-Recording**: Simple, focused interface with prominent record button
- **Active Recording**: Minimal interface showing audio waveform and duration
- **Note-Taking**: Split view with transcript developing in real-time and note area
- **Post-Recording**: Options to title, tag, and save the sermon

### Library
- **Sermon List**: Chronological list of recorded sermons
- **Search**: Filter by title, date, tags, or content
- **Sermon Detail**: Complete view of transcript, notes, and summary
- **Edit View**: Interface for editing notes and highlights

### Account
- **Profile**: Basic user information
- **Subscription**: Current plan and upgrade options
- **Settings**: App preferences and controls
- **Help**: Support resources and documentation

---

## Implementation Guidelines

### iOS Development
- Follow Apple Human Interface Guidelines
- Use native iOS components when possible
- Implement proper keyboard handling
- Support all current iOS devices and orientations

### Design Files
- Maintain a component library in design software
- Document all components and variations
- Provide adequate handoff documentation for developers
- Include interaction specifications

### Quality Assurance
- Test on multiple device sizes
- Verify accessibility compliance
- Ensure consistent implementation of design standards
- Validate performance of animations and transitions

---

*This UI/UX Brand Guide for TabletNotes serves as the definitive reference for all design decisions. Any deviations should be carefully considered and approved by the design team.*

*Version 1.0 - June 2025*
