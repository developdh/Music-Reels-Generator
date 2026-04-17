# MUSIC REELS GENERATOR - Complete Reference Guide

## EXECUTIVE SUMMARY

**Music Reels Generator** is a macOS desktop application that converts music videos into vertical lyric videos (9:16 Reels/Shorts format) with AI-powered speech recognition alignment.

**Tech Stack**: Swift 5.9 + SwiftUI + AVFoundation + FFmpeg + whisper.cpp + Sparkle

**Core Innovation**: Two-stage intelligent alignment engine that matches lyrics to audio segments with drift detection, boundary snapping, and user-anchored piecewise correction.

---

## ARCHITECTURE AT A GLANCE

```
┌─────────────────────────────────────────────────────────────┐
│                   MusicReelsGeneratorApp                    │
│              (Entry point + Sparkle updater)                │
└──────────────────────┬──────────────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────────────┐
│                  ProjectViewModel                           │
│        (Single source of truth, @MainActor)                 │
│  - Manages all @Published properties                        │
│  - Orchestrates services (alignment, export, download)      │
│  - Coordinates playback and UI state                        │
└──────────────────────┬──────────────────────────────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼────┐  ┌─────▼──────┐  ┌────▼──────┐
   │  Models │  │   Views    │  │ Services  │
   ├────────┤  ├──────────┤  ├─────────┤
   │ Project│  │ Content  │  │ Whisper │
   │ Lyric  │  │ Toolbar  │  │ Align   │
   │ Block  │  │ Inspector│  │ Export  │
   │ Styles │  │ Lyrics   │  │ YouTube │
   │ Video  │  │ Preview  │  │ Audio   │
   │ Meta   │  │ Playback │  │ Persist │
   └────────┘  └──────────┘  └─────────┘
        │              │              │
        └──────────────┼──────────────┘
                       │
        ┌──────────────┼──────────────┐
        │              │              │
   ┌────▼────────┐ ┌──▼──────┐ ┌────▼──────┐
   │ Utilities   │ │ External │ │ Resources │
   ├────────────┤ │ Tools    │ ├─────────┤
   │ L10n       │ │ FFmpeg   │ │ Info    │
   │ ProcessRun │ │ whisper  │ │ Icons   │
   │ Renderer   │ │ Python   │ │ Strings │
   │ TimeFormat │ │ yt-dlp   │ │         │
   └────────────┘ └──────────┘ └─────────┘
```

---

## FILE DEPENDENCIES MAP

### Critical Path for Alignment Feature
```
1. LyricBlock.swift (data model)
   ↓
2. ProjectViewModel.swift (state + orchestration)
   ↓
3. AudioExtractionService.swift (FFmpeg audio extraction)
   ↓
4. WhisperAlignmentService.swift (whisper.cpp transcription + DP matching)
   ↓
5. Project.swift (update blocks with timing)
   ↓
6. InspectorPanelView.swift (display results, allow manual adjustment)
```

### Critical Path for Export
```
1. Project.swift (all settings)
   ↓
2. ExportService.swift (stage 1: FFmpeg crop/scale/trim)
   ↓
3. SubtitleRenderer.swift + SubtitleRenderService.swift (prepare CGImages)
   ↓
4. ExportService.swift (stage 2: frame-by-frame burn-in)
   ↓
5. AVAssetReader/Writer (write final output)
```

### Critical Path for UI Rendering
```
1. Project.swift (current project state)
   ↓
2. ProjectViewModel.swift (@Published properties)
   ↓
3. ContentView.swift (main layout container)
   ├→ ToolbarView.swift (top toolbar)
   ├→ LyricsPanelView.swift (left: lyrics)
   ├→ VideoPreviewView.swift (center: video + playback)
   └→ InspectorPanelView.swift (right: all editing tools)
   ↓
4. L10n.swift (UI strings in current language)
```

---

## DATA MODEL RELATIONSHIPS

```
Project (root)
├─ id: UUID
├─ title: String
├─ sourceVideoPath: String?
│   └─ Loaded as AVAsset in VideoPreviewView
├─ videoMetadata: VideoMetadata
│   ├─ width, height, duration, fps, fileSize
│   └─ Used for export canvas (1080x1920)
├─ cropSettings: CropSettings
│   ├─ mode: vertical | horizontal
│   ├─ zoomScale: 1x-3x
│   ├─ horizontalOffset, verticalOffset
│   └─ Applied in ExportService Stage 1 (FFmpeg filter)
├─ trimSettings: TrimSettings
│   ├─ startTime, endTime
│   └─ Applied in ExportService (FFmpeg seek)
├─ subtitleStyle: SubtitleStyle
│   ├─ japaneseFont, japaneseSize, japaneseColor
│   ├─ koreanFont, koreanSize, koreanColor
│   ├─ outlineWidth, shadowEnabled
│   ├─ lineSpacing, bottomMargin
│   └─ Used by SubtitleRenderer + SubtitleRenderService
├─ metadataOverlay: MetadataOverlaySettings
│   ├─ title, artist (content)
│   ├─ font, size, color (both)
│   ├─ opacity, padding, cornerRadius
│   └─ Rendered in ExportService Stage 2
├─ primaryLanguage: PrimaryLanguage
│   └─ Used by WhisperAlignmentService (language param)
├─ ignoreRegions: [IgnoreRegion]
│   ├─ startTime, endTime
│   └─ Filtered from alignment results
├─ lyricBlocks: [LyricBlock]
│   ├─ id: UUID
│   ├─ japanese: String (primary text)
│   ├─ korean: String (secondary text, optional)
│   ├─ startTime, endTime: Double? (set by alignment)
│   ├─ confidence: Double? (0-1, set by alignment)
│   ├─ manuallyAdjustedStart, manuallyAdjustedEnd: Bool
│   ├─ isAnchor: Bool (auto-set by alignment if confidence >= 0.6)
│   ├─ isUserAnchor: Bool (only set by user)
│   └─ Used for subtitle rendering + export
└─ createdAt, updatedAt: Date
```

---

## KEY ALGORITHMS

### Whisper Alignment (WhisperAlignmentService.swift)

**Input**: 
- Audio file URL
- Lyric blocks (text only)
- Primary language
- Ignore regions (time ranges to skip)

**Process**:
1. Run whisper.cpp subprocess → CSV with (startTime, endTime, text) segments
2. For each lyric block, find best-matching segment using:
   - Levenshtein ratio (textScore)
   - Position-aware beam-search DP (prefers sequential order)
   - Considers surrounding blocks and drift
3. Detect systematic drift (runs of positional deviation) → re-anchor locally
4. Snap block boundaries to nearest segment edges
5. Set confidence = textScore (0-1)
6. Auto-anchor blocks with confidence >= 0.6
7. Apply piecewise correction between trusted anchor pairs:
   - User-set blue anchors (always trusted)
   - Blocks with both start+end manually adjusted (trusted)
   - Distributes timing proportionally by character count

**Output**:
- Updated LyricBlock array with startTime, endTime, confidence, isAnchor

### Export Pipeline (ExportService.swift)

**Stage 1 - FFmpeg Preprocessing**:
- Input: source video, crop/trim settings, quality mode
- Apply FFmpeg filter chain:
  - `crop=1080:1920:cropX:cropY` (vertical mode with zoom + offset)
  - or `scale=1080:1920:force_original_aspect_ratio=decrease:pad=1080:1920:(ow-iw)/2:(oh-ih)/2` (horizontal with blur background)
- Trim: seek to startTime, read duration=endTime-startTime
- Encode: H.264 (CRF 18), AAC 192k
- Output: /tmp/mreels_export/cropped.mp4

**Stage 2 - Frame-by-Frame Burn-In**:
- Input: cropped.mp4 + lyric blocks + styles + overlay settings
- For each video frame (at 1080x1920 canvas):
  - Determine current time
  - Find active subtitle blocks
  - Render Japanese line (SubtitleRenderer.swift)
  - Render Korean line (if present)
  - Render metadata overlay (title/artist box)
  - Write frame back with AVAssetWriter
- Output: final 1080x1920 .mp4 with burned subtitles and overlay

### Subtitle Rendering (SubtitleRenderer.swift)

**Multi-Pass Text Rendering** (Core Graphics):
1. Measure text with font + size
2. Create CGImage canvas
3. Shadow pass: draw text 2px offset in black (if enabled)
4. Outline pass: draw text in outline color with 2px expansion (configurable 0-8px)
5. Fill pass: draw text in foreground color
6. Result: crisp antialiased text with outline/shadow effects

---

## CRITICAL DESIGN PATTERNS

### 1. Single Source of Truth (ProjectViewModel)
All state lives in ProjectViewModel (@Published properties):
- Views subscribe to changes and re-render
- Services modify project via ProjectViewModel methods
- This ensures consistency across all UI components

### 2. Service-Based Architecture
Separation of concerns:
- Services are stateless, encapsulating specific functionality
- ProjectViewModel orchestrates services
- Views call ProjectViewModel, never services directly
- Makes testing and reuse easier

### 3. Codable Models with Backward Compatibility
All models implement Codable + custom init(from:) for forward/backward compatibility:
```swift
init(from decoder: Decoder) throws {
    // decode with defaults for missing fields
    // map legacy field names to new names
}
```
Enables loading old .mreels files in new app versions.

### 4. Async/Await with @MainActor
All UI updates run on main thread via @MainActor:
```swift
@MainActor
class ProjectViewModel: ObservableObject {
    @Published var project: Project
    
    func alignWithWhisper() async {
        Task { @MainActor in
            // UI updates here
        }
    }
}
```

### 5. Subprocess Orchestration (ProcessRunner)
Unified interface for all external tools:
- FFmpeg, whisper-cli, python, yt-dlp
- Handles process launch, argument escaping, output parsing
- Async/await, progress callbacks
- Centralizes error handling

### 6. Two-Stage Export
Separation of concerns:
- Stage 1: Low-level FFmpeg operations (crop/scale/trim/encode)
- Stage 2: High-level subtitle/overlay burn-in (AVAssetReader/Writer)
- Allows reuse of Stage 1 for preview, Stage 2 for final output

---

## REUSABLE PATTERNS FOR COMMUNITY APP

### 1. Service Architecture Template
**Applicable to**: Community submission, review queue, collaborative editing

```swift
service {
    static func process(_ input: Model) async throws -> Result
}
```

### 2. Confidence Scoring
**Applicable to**: Community voting, quality assessment

- LyricBlock.confidence (0-1) from textScore
- Extend to: user credibility, submission quality, voting weight

### 3. Anchor/Bookmark System
**Applicable to**: Collaborative refinement, version control

- LyricBlock.isUserAnchor, manuallyAdjustedStart/End
- Can track who made changes, when, confidence in changes
- Extend to: distributed collaborative alignment

### 4. Piecewise Correction
**Applicable to**: Distributed refinement, consensus building

- Respects trusted reference points (anchors)
- Interpolates unknown regions
- Can extend to: weighted voting between community submissions

### 5. Multi-Language Support (L10n)
**Applicable to**: Internationalization

```swift
enum L10n {
    case Common
    case Menu
    case Dialogs
    // All strings organized by context
}
```

### 6. Project Persistence (Codable + Custom Decodable)
**Applicable to**: Cloud sync, version control, export

- JSON-based, version-aware
- Backward compatibility built-in
- Easy to add new fields

### 7. Style Preset System
**Applicable to**: Community templates, shared workflows

- Save/load reusable configurations
- Store in ~/Application Support/
- Enable sharing via export/import

### 8. HSplitView Layout
**Applicable to**: Multi-panel editors

- Left: input/list
- Center: main editor/preview
- Right: properties/settings
- Flexible resizing, minimum widths

---

## CRITICAL FILE LOCATIONS

### Absolute Paths
```
/Users/dh/project/Music-Reels-Generator/
├── Package.swift
├── MusicReelsGenerator/
│   ├── App/MusicReelsGeneratorApp.swift
│   ├── Models/
│   ├── ViewModels/
│   ├── Views/
│   ├── Services/
│   ├── Utilities/
│   └── Resources/
├── Scripts/
│   ├── alignment_pipeline.py
│   ├── yt_download.sh
│   └── setup_alignment.sh
├── build.sh
└── setup.sh
```

### Runtime Paths (User's System)
```
~/.local/share/whisper-cpp/models/ggml-medium.bin
~/Library/Application Support/MusicReelsGenerator/
├── StylePresets/
└── Scripts/
    └── yt_download.sh
```

### Temporary Paths
```
/tmp/mreels_export/
├── cropped.mp4
└── (stage 2 intermediate files)
/tmp/whisper_output.csv
```

---

## INTEGRATION POINTS WITH COMMUNITY APP

### 1. Use Alignment Service Directly
```swift
import Foundation

// Copy WhisperAlignmentService.swift
let segments = try await WhisperAlignmentService.transcribe(
    audioURL: audioFile,
    language: "ja"
)
```

### 2. Reuse Export Pipeline
```swift
// Copy ExportService.swift, SubtitleRenderer.swift
let exporter = ExportService()
try await exporter.export(
    project: project,
    outputURL: outputURL
)
```

### 3. Adapt ProcessRunner for Other Tools
```swift
// ProcessRunner is generic, can add new subprocess types
let result = try await ProcessRunner.run(
    executable: "/path/to/tool",
    arguments: [...]
)
```

### 4. Extend Models with Community Fields
```swift
extension Project {
    var communityMetadata: CommunityMetadata? // Add this
}

extension LyricBlock {
    var contributor: String? // Add this
    var reviewedBy: [String]? // Add this
    var communityVotes: Int = 0 // Add this
}
```

### 5. Reuse Style System
```swift
// Copy StylePreset.swift, StylePresetStore.swift
// Add community voting, sharing, ratings
```

---

## NEXT STEPS FOR COMMUNITY REELS GENERATOR

1. **Architecture**: Keep Service + ViewModel + Views pattern
2. **Models**: Extend Project/LyricBlock with community fields
3. **Services**: Add API client service (NetworkService)
4. **Persistence**: Extend ProjectPersistenceService to sync with backend
5. **Alignment**: Reuse WhisperAlignmentService, add community refinement
6. **UI**: Adapt Inspector panel for community submission/voting
7. **Export**: Keep two-stage export, add watermarks/attribution
8. **Strings**: Extend L10n.swift with community-specific terms

