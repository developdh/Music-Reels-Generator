# MUSIC REELS GENERATOR - COMPREHENSIVE OVERVIEW

## TECH STACK
- **Platform**: macOS 14.0+ (Sonoma+)
- **UI Framework**: SwiftUI
- **Language**: Swift 5.9+
- **Media Handling**: AVFoundation (playback, video composition)
- **Video Processing**: FFmpeg (CLI)
- **Speech Recognition**: whisper.cpp (offline, with ggml models)
- **Auto-Updates**: Sparkle Framework v2.6.0+
- **Build System**: Swift Package Manager (SPM)
- **External Tools**: yt-dlp (YouTube download)
- **Advanced Alignment**: Python 3 (optional, with openai-whisper, pykakasi, numpy, demucs)

## PROJECT STRUCTURE

### Root Level
- **Package.swift** - SPM manifest, declares MusicReelsGenerator executable
- **MusicReelsGenerator.xcodeproj** - Xcode project metadata
- **build.sh** - Creates proper .app bundle (required for AVFoundation)
- **setup.sh** - Installs FFmpeg and whisper-cpp
- **Scripts/** - Python alignment pipeline and download helpers

### MusicReelsGenerator/ (Main App)
- **App/MusicReelsGeneratorApp.swift** (165 lines)
  - Entry point with @main struct
  - Sparkle updater integration
  - AppDelegate for native cut/copy/paste support
  - Menu commands (File: New, Open, Save, Save As, Import Video)
  
- **Models/** - Data structures (all Codable for persistence)
  - Project.swift (83 lines) - Main project container with backward compatibility
  - LyricBlock.swift (114 lines) - Single lyric line with timing, confidence, anchor states
  - SubtitleStyle.swift (77 lines) - Font, color, outline, shadow, margin settings
  - CropSettings.swift (46 lines) - Vertical/horizontal crop modes, zoom, blur
  - TrimSettings.swift (35 lines) - In/out trimming for video
  - VideoMetadata.swift (22 lines) - Resolution, duration, FPS
  - MetadataOverlaySettings.swift (40 lines) - Title/artist overlay
  - IgnoreRegion.swift (32 lines) - Time ranges excluded from alignment
  - StylePreset.swift (118 lines) - Reusable style templates
  - AlignmentQualityMode.swift (63 lines) - Legacy vs experimental modes
  - PrimaryLanguage.swift (22 lines) - Japanese, Korean, English, Chinese, Auto
  - UILanguage.swift (16 lines) - English, Japanese, Korean

- **ViewModels/** 
  - ProjectViewModel.swift (1033 lines) - **CORE STATE MANAGER**
    - Published properties: project, player, playback state, UI state
    - Video import/download, alignment, export orchestration
    - PlaybackController integration
    - Tool availability checking

- **Views/** - SwiftUI components
  - ContentView.swift (52 lines) - Main layout (HSplitView: lyrics | preview | inspector)
  - ToolbarView.swift (185 lines) - Top toolbar with language selector, alignment buttons
  - LyricsPanelView.swift (210 lines) - Left panel: lyrics list, editor, block selection
  - VideoPreviewView.swift (258 lines) - Center: AVPlayerLayer, video display, seek
  - PlaybackControlsView.swift (127 lines) - Play/pause, time slider, duration
  - InspectorPanelView.swift (1396 lines) - **MASSIVE**: Right panel with all editing tools
  - StatusBarView.swift (51 lines) - Bottom status/progress messages
  - URLImportSheet.swift (117 lines) - YouTube URL import modal

- **Services/** - Business logic (medium to large, critical paths)
  - WhisperAlignmentService.swift (1462 lines) - **LARGEST FILE**
    - whisper.cpp transcription runner
    - Segment matching algorithm (beam-search DP)
    - Drift detection, boundary snap
    - Confidence scoring
    
  - AdvancedAlignmentService.swift (395 lines) - Experimental Python pipelines
    - Subprocess orchestration for 3 experimental modes
    - Model/method switching
    
  - ExportService.swift (420 lines) - Two-stage video export
    - Stage 1: FFmpeg crop/scale/trim to 1080x1920
    - Stage 2: AVAssetReader/Writer with frame-by-frame subtitle/overlay burn-in
    
  - SubtitleRenderService.swift (88 lines) - ASS format generation for subtitles
  
  - VideoService.swift (54 lines) - AVAsset/AVComposition utilities
  
  - AudioExtractionService.swift (51 lines) - FFmpeg audio extraction for alignment
  
  - LyricsParserService.swift (68 lines) - Parse monolingual/bilingual block format
  
  - ProjectPersistenceService.swift (93 lines) - JSON save/load .mreels files
  
  - StylePresetStore.swift (142 lines) - Load/save presets to ~/Application Support/
  
  - YouTubeDownloadService.swift (82 lines) - Download orchestration
  
  - YouTubeDownloadProvider_Real.swift (72 lines) - yt-dlp subprocess wrapper

- **Utilities/** - Helper functions
  - L10n.swift (873 lines) - **MASSIVE ENUM**: All UI strings (English, Japanese, Korean)
  - ProcessRunner.swift (287 lines) - Subprocess execution for FFmpeg, whisper, Python, yt-dlp
  - SubtitleRenderer.swift (280 lines) - Core Graphics text rendering with outline/shadow
  - JapaneseTextNormalizer.swift (160 lines) - Kanji normalization for alignment
  - TimeFormatter.swift (26 lines) - Format timestamps for UI/ASS/debug
  - FontUtility.swift (39 lines) - Font family enumeration
  - ColorExtension.swift (33 lines) - Hex color helpers
  - NativeTextEditor.swift (86 lines) - NSTextView wrapper for native text editing
  - TrimTimingUtility.swift (42 lines) - Trim range validation

- **Resources/**
  - Info.plist - App metadata, entitlements
  - MusicReelsGenerator.entitlements - Sandbox config

## ARCHITECTURE PATTERNS

### Data Flow
1. **ProjectViewModel** is the single source of truth (@MainActor)
2. **Views** subscribe to @Published properties and update on changes
3. **Services** perform async work (alignment, export, download)
4. **Models** (Project, LyricBlock, etc.) are Codable for JSON persistence

### Key Workflows

**Import Video:**
- User selects file → ProjectViewModel.importVideo()
- AVAsset metadata extracted
- FFmpeg extracts audio to temp location

**Alignment (Production Mode):**
- User clicks "Align" → ProjectViewModel.alignWithWhisper()
- AudioExtractionService extracts audio
- WhisperAlignmentService runs whisper.cpp subprocess
- Parses CSV output → segments
- Applies segment matching DP algorithm
- Sets LyricBlock.startTime/endTime, confidence, isAnchor
- Detects drift, snaps boundaries, applies piecewise correction

**Manual Adjustment:**
- User edits block timing in inspector
- Sets manuallyAdjustedStart/End flags
- isTrustedAnchor = isUserAnchor || (both boundaries adjusted)
- Piecewise correction respects these anchor points

**Export:**
- Stage 1: FFmpeg crops/scales/trims to 1080x1920 H.264 CRF 18
- Stage 2: AVAssetReader/Writer reads frames
  - SubtitleRenderer draws subtitles (Japanese line, Korean line)
  - MetadataOverlay drawn (title/artist box)
  - Frames written back with AAC 192k audio

### UI Layout
```
┌─────────────────────────────────────────────────┐
│  Toolbar (Language, Import, Align, Export)      │
├──────────┬──────────────────────┬───────────────┤
│ Lyrics   │  Video Preview       │  Inspector    │
│ Panel    │  + Playback Controls │  (Styles,    │
│          │  (Play, Slider, etc) │   Crop,      │
│          │                      │   Trim,      │
│          │                      │   Overlay)   │
├──────────┴──────────────────────┴───────────────┤
│ Status Bar (Messages, Progress)                  │
└──────────────────────────────────────────────────┘
```

### Alignment Strategies

**Production (whisper-cpp segment matching):**
- Transcribe audio → list of (startTime, endTime, text) segments
- For each lyric block, find best-matching segment via DP
- Position-aware beam search (prioritizes sequential order)
- Detects runs of systematic drift → re-anchors locally
- Snaps block boundaries to nearest segment edges
- Confidence = textScore (0-1 based on Levenshtein ratio)
- Auto-anchors set for textScore >= 0.6
- User can manually set blue-lock anchors
- Piecewise correction between trusted anchor pairs

**Experimental (Python):**
- Three modes: segment-level Levenshtein, gated refinement, ungated hybrid
- Optional vocal stem separation (demucs)
- Runs as subprocess, output parsed from JSON

### Persistence

**Project Files (.mreels):**
- JSON format, Codable structures
- Backward compatibility: missing fields get defaults
- Stores: video path, metadata, settings, lyric blocks (with timing)
- Loaded via ProjectPersistenceService

**Style Presets:**
- Stored in ~/Library/Application Support/MusicReelsGenerator/StylePresets/
- Captured as StylePreset JSON files
- Can be renamed, duplicated, deleted

**User Preferences:**
- UILanguage saved to UserDefaults

## KEY DESIGN DECISIONS

1. **macOS-only**: Uses AppKit features (NSApplicationDelegate, NSOpenPanel, AVPlayerLayer)
2. **SwiftUI + AppKit hybrid**: SwiftUI for UI, AppKit for system integration
3. **Subprocess orchestration**: All external tools (FFmpeg, whisper, Python) run via ProcessRunner
4. **No external dependencies for core features**: SwiftUI, AVFoundation, Sparkle only
5. **Frame-by-frame subtitle burn-in**: Ensures precise timing, pixel-perfect rendering
6. **Dual alignment modes**: Production (whisper-cpp, built-in) vs Experimental (Python, optional)
7. **Flexible language support**: Any primary language + optional secondary language
8. **Comprehensive manual controls**: Every timing decision can be manually overridden
9. **Backward compatibility**: Custom Decodable initializers for old project formats
10. **Auto-update via Sparkle**: Built-in check for GitHub releases

## REUSABLE PATTERNS FOR COMMUNITY APP

- **Data persistence layer** (ProjectPersistenceService) - adaptable to cloud sync
- **Service architecture** - clean separation of UI and business logic
- **Subprocess orchestration** (ProcessRunner) - framework for external tool integration
- **Multi-language support** (L10n enum) - extensible for more languages
- **Style preset system** - reusable for other styled content
- **Two-stage export** - can be adapted for different output formats
- **Confidence scoring** - good pattern for uncertain data (can reuse for community submissions)
- **HSplitView layout** - multi-panel editor pattern
- **Anchor/bookmark system** - can be adapted for collaborative editing
