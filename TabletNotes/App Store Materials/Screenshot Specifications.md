# TabletNotes App Store Screenshots Specification

This document outlines the requirements and specifications for creating compelling App Store screenshots for TabletNotes.

## Technical Requirements

### Screenshot Sizes (iOS)

#### iPhone 6.9" (iPhone 15 Pro Max)
```
Size: 1320 x 2868 pixels
Format: PNG or JPEG
Max file size: 500MB
Required: Yes (primary display size)
```

#### iPhone 6.7" (iPhone 14 Pro Max)
```
Size: 1290 x 2796 pixels
Format: PNG or JPEG
Max file size: 500MB
Required: Yes (fallback for older devices)
```

#### iPhone 6.1" (iPhone 15 Pro)
```
Size: 1179 x 2556 pixels
Format: PNG or JPEG
Max file size: 500MB
Required: Optional (recommended)
```

#### iPad Pro 12.9" (6th generation)
```
Size: 2048 x 2732 pixels
Format: PNG or JPEG
Max file size: 500MB
Required: Yes (if supporting iPad)
```

### General Requirements
- Maximum 10 screenshots per device type
- Screenshots appear in order uploaded
- First screenshot is most important (primary display)
- Text should be legible at small sizes
- Avoid showing personal information
- Use high-contrast, readable fonts

## Screenshot Strategy

### Primary Message Hierarchy
1. **Recording Excellence** - Professional audio recording
2. **AI Intelligence** - Smart transcription and summaries
3. **Spiritual Focus** - Church and sermon-specific features
4. **Organization** - Library and search capabilities
5. **Sync & Share** - Cloud features and collaboration

### Target User Journey
```
Discovery → Interest → Understanding → Trust → Download
```

## Required Screenshots (iPhone)

### Screenshot 1: Recording Screen
**Purpose**: Show primary value proposition - professional recording interface

**Content**:
- Active recording screen with clean, professional UI
- Real-time note-taking panel visible
- Service type selected (e.g., "Sunday Service")
- Recording timer showing active session
- High-quality visual design

**Text Overlay**:
- **Headline**: "Record with Confidence"
- **Subtext**: "Professional audio recording designed for sermons and spiritual talks"

**UI Elements to Highlight**:
- Large, prominent record button
- Service type selector
- Note-taking area
- Clean, spiritual-themed design

### Screenshot 2: AI Transcription View
**Purpose**: Demonstrate AI transcription capabilities and accuracy

**Content**:
- Completed transcription with speaker labels
- Clean, readable text formatting
- Sample sermon content (theologically appropriate)
- Accuracy indicators or confidence scores
- Search/edit capabilities visible

**Text Overlay**:
- **Headline**: "AI-Powered Transcription"
- **Subtext**: "Accurate speech-to-text with speaker identification and theological understanding"

**UI Elements to Highlight**:
- Speaker labels (e.g., "Pastor John", "Congregation")
- Formatted transcript text
- Search functionality
- Edit/correction tools

### Screenshot 3: Intelligent Summary
**Purpose**: Showcase AI-powered summarization and scripture detection

**Content**:
- Well-formatted sermon summary with key points
- Scripture references automatically identified
- Main themes and takeaways highlighted
- Practical applications section
- Clean, scannable layout

**Text Overlay**:
- **Headline**: "Intelligent Summaries"
- **Subtext**: "Key insights and scripture references automatically extracted"

**UI Elements to Highlight**:
- Structured summary sections
- Scripture reference links
- Key points bulleted clearly
- Practical applications

### Screenshot 4: Sermon Library
**Purpose**: Show organization and library features

**Content**:
- Grid/list view of sermon recordings
- Search and filter options
- Recent recordings prominently displayed
- Various service types visible
- Cloud sync status indicators

**Text Overlay**:
- **Headline**: "Your Spiritual Library"
- **Subtext**: "Organize and search your growing collection of recordings"

**UI Elements to Highlight**:
- Search bar
- Filter options (date, speaker, service type)
- Sermon thumbnails/cards
- Sync status indicators

### Screenshot 5: Note-Taking Interface
**Purpose**: Demonstrate real-time note-taking capabilities

**Content**:
- Split screen or overlay showing note-taking during recording
- Sample notes with timestamps
- Rich text formatting options
- Integration with recording timeline
- Easy-to-use interface

**Text Overlay**:
- **Headline**: "Take Notes While Recording"
- **Subtext**: "Capture thoughts and insights in real-time"

**UI Elements to Highlight**:
- Note editor with formatting tools
- Timestamp synchronization
- Easy switching between recording and notes
- Rich text capabilities

## Additional Screenshots (Optional)

### Screenshot 6: Scripture Integration
**Purpose**: Show Bible integration and reference features

**Content**:
- Scripture lookup interface
- Multiple Bible translations
- Cross-references and study tools
- Integration with sermon content
- Clean, respectful religious design

### Screenshot 7: Cloud Sync & Sharing
**Purpose**: Demonstrate cloud features and collaboration

**Content**:
- Sync status across devices
- Sharing options for sermons/notes
- Export capabilities
- Team/church collaboration features
- Data security indicators

### Screenshot 8: Settings & Customization
**Purpose**: Show app flexibility and user control

**Content**:
- Settings screen with key options
- Audio quality settings
- Transcription preferences
- Privacy controls
- Subscription/account management

## iPad Screenshots (if supporting)

### iPad-Specific Features
- Larger screen real estate utilization
- Split-screen capabilities
- Enhanced note-taking with larger text areas
- Better visualization of transcripts and summaries
- Multi-tasking integration

## Content Guidelines

### Text Content (Sample Sermon Excerpts)
```
Appropriate Topics:
- Hope and encouragement
- Love and community
- Spiritual growth
- Biblical wisdom
- Faith and trust

Example Scripture References:
- Philippians 4:13
- Romans 8:28
- John 3:16
- Psalm 23:1
- Matthew 6:33

Sample Speaker Names:
- Pastor Johnson
- Dr. Smith
- Rev. Williams
- Minister Davis
```

### Visual Design Principles
- **Clean & Professional**: Avoid clutter, use white space effectively
- **Readable Typography**: Large, clear fonts that work at small sizes
- **Consistent Branding**: Use app colors and design language
- **Spiritual Sensitivity**: Respectful treatment of religious content
- **Accessibility**: High contrast, readable by diverse users

## Text Overlay Design

### Typography
```
Headline Font: San Francisco Display Bold, 32-40pt
Subtext Font: San Francisco Text Regular, 18-24pt
Colors: High contrast against background
Positioning: Top or bottom third of image
Background: Semi-transparent overlay for readability
```

### Layout Guidelines
```
Headline: 1-4 words maximum, clear benefit
Subtext: 8-12 words, supporting detail
Positioning: Consistent across all screenshots
Margin: 40-60px from screen edges
Alignment: Left-aligned or centered
```

## Production Workflow

### 1. UI State Preparation
- Create realistic, appropriate content
- Ensure all UI elements are properly styled
- Remove any debug elements or placeholder text
- Test on actual devices for accuracy

### 2. Screenshot Capture
- Use Xcode Simulator for consistency
- Capture at exact required resolutions
- Ensure status bar shows good signal/battery
- Use consistent time (9:41 AM - Apple standard)

### 3. Post-Processing
- Add text overlays using design tools (Figma, Sketch, Photoshop)
- Ensure color accuracy and consistency
- Optimize file sizes while maintaining quality
- Create variants for different device sizes

### 4. Quality Assurance
- Review on actual App Store listing preview
- Test legibility at thumbnail sizes
- Verify message clarity and appeal
- Get feedback from target users

## Tools & Resources

### Design Tools
- **Figma**: For overlay design and layout
- **Sketch**: Alternative design tool
- **Adobe Photoshop**: Advanced editing
- **Canva**: Quick overlay creation

### Screenshot Tools
- **Xcode Simulator**: Primary capture tool
- **Screenshot Studio**: App Store screenshot generator
- **AppLaunchpad**: Automated screenshot creation
- **Rottenwood**: Device frame mockups

### Testing Tools
- **App Store Preview**: Official preview tool
- **StoreMaven**: A/B testing for screenshots
- **SplitMetrics**: App store optimization
- **TestFlight**: Beta tester feedback on screenshots

## Localization Considerations

### Text Overlays
- Keep text concise for easy translation
- Consider text expansion (20-30% for most languages)
- Use universal icons where possible
- Plan for right-to-left languages if supporting

### Cultural Sensitivity
- Avoid region-specific religious references
- Use inclusive imagery and language
- Consider cultural color meanings
- Respect diverse religious practices

## Performance Metrics

### Success Indicators
- **Conversion Rate**: Install rate from App Store views
- **Engagement**: Time spent viewing screenshots
- **Feedback**: Beta tester comments on clarity
- **Store Performance**: Ranking and visibility

### Testing Approach
- A/B testing different screenshot orders
- User feedback on clarity and appeal
- Competitor analysis and differentiation
- Regular updates based on feature releases

This specification ensures TabletNotes screenshots effectively communicate the app's value proposition while meeting all App Store requirements and appealing to the target audience of church members, pastors, and spiritual learners.