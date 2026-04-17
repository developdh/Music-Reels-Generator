# COMPLETE FILE MANIFEST - Music Reels Generator

## APP ENTRY POINT
| File | Lines | Purpose |
|------|-------|---------|
| MusicReelsGenerator/App/MusicReelsGeneratorApp.swift | 165 | @main app struct, Sparkle updates, AppDelegate, menu commands, file dialogs |

## MODELS (Data Structures - All Codable)
| File | Lines | Purpose |
|------|-------|---------|
| Project.swift | 83 | Main project container: video path, metadata, crop, trim, styles, lyric blocks, timestamps |
| LyricBlock.swift | 114 | Single lyric line: Japanese/Korean text, timing, confidence, anchor states, manual adjust flags |
| SubtitleStyle.swift | 77 | Typography: font family/size, text color, outline width, shadow, line spacing, bottom margin |
| CropSettings.swift | 46 | Framing: vertical/horizontal mode, aspect ratio, zoom, horizontal/vertical offset, blur radius |
| TrimSettings.swift | 35 | In/out timing: startTime, endTime for non-destructive trimming |
| VideoMetadata.swift | 22 | Video properties: width, height, duration, fps, fileSize |
| MetadataOverlaySettings.swift | 40 | Title/artist overlay: position, opacity, font, color, corner radius, padding |
| IgnoreRegion.swift | 32 | Time ranges to exclude from speech recognition (MC talk, audience noise, etc.) |
| StylePreset.swift | 118 | Reusable templates: save/load subtitle + overlay styling with versioning |
| AlignmentQualityMode.swift | 63 | Enum: legacy (whisper-cpp), segment (Levenshtein), refined (gated), hybrid (ungated) |
| PrimaryLanguage.swift | 22 | Enum: Japanese, Korean, English, Chinese, Auto-detect |
| UILanguage.swift | 16 | Enum: English, Japanese, Korean for app UI strings |

## VIEW MODEL (State Management)
| File | Lines | Purpose |
|------|-------|---------|
| ProjectViewModel.swift | 1033 | **CORE**: Single source of truth, @MainActor, all @Published state, coordinates all async operations |

## VIEWS (SwiftUI Components)
| File | Lines | Purpose |
|------|-------|---------|
| ContentView.swift | 52 | Root view: HSplitView layout (lyrics panel \| video preview \| inspector) |
| ToolbarView.swift | 185 | Top toolbar: language selector, import/align/export buttons, progress display |
| LyricsPanelView.swift | 210 | Left panel: lyric blocks list, text editor, block selection, search/filter |
| VideoPreviewView.swift | 258 | Center: AVPlayerLayer video display, drag-to-seek, frame-accurate preview |
| PlaybackControlsView.swift | 127 | Playback controls: play/pause button, time slider, duration, current time display |
| InspectorPanelView.swift | 1396 | **MASSIVE RIGHT PANEL**: All editing tools (styles, crop, trim, overlay, anchors, timing) |
| StatusBarView.swift | 51 | Bottom status bar: messages, alignment/export progress, error display |
| URLImportSheet.swift | 117 | Modal: YouTube URL input, download progress, error handling |

## SERVICES (Business Logic)
| File | Lines | Purpose |
|------|-------|---------|
| WhisperAlignmentService.swift | 1462 | **LARGEST**: whisper.cpp subprocess, CSV parsing, segment matching DP, drift detection, boundary snap, confidence scoring |
| ExportService.swift | 420 | Two-stage export: Stage 1 FFmpeg crop/scale/trim, Stage 2 frame-by-frame subtitle/overlay burn-in |
| AdvancedAlignmentService.swift | 395 | Python pipeline orchestration: subprocess launch, JSON output parsing, method selection |
| StylePresetStore.swift | 142 | Persistence: load/save StylePreset JSON files to ~/Application Support/ |
| AudioExtractionService.swift | 51 | FFmpeg subprocess: extract audio from video to WAV temp file |
| ProjectPersistenceService.swift | 93 | Codable serialization: save/load .mreels JSON project files |
| YouTubeDownloadService.swift | 82 | Download orchestration: manage download state, error handling, progress |
| YouTubeDownloadProvider_Real.swift | 72 | yt-dlp subprocess wrapper: stream progress to UI in real-time |
| SubtitleRenderService.swift | 88 | ASS subtitle format generation: style definitions, timing, text escaping |
| VideoService.swift | 54 | AVAsset/AVComposition utilities: metadata extraction, asset loading |
| LyricsParserService.swift | 68 | Parser: monolingual (1 line) / bilingual (2 lines) block format from plain text |

## UTILITIES (Helper Functions)
| File | Lines | Purpose |
|------|-------|---------|
| L10n.swift | 873 | **MASSIVE ENUM**: All UI strings (English, Japanese, Korean) - 1000+ strings |
| ProcessRunner.swift | 287 | Unified subprocess runner: FFmpeg, whisper-cli, python, yt-dlp with async/progress |
| SubtitleRenderer.swift | 280 | Core Graphics text rendering: multi-pass outline/shadow/fill with kerning |
| JapaneseTextNormalizer.swift | 160 | Kanji normalization: Unicode composition, ruby text handling for alignment |
| TimeFormatter.swift | 26 | Timestamp formatting: UI display (mm:ss.ms), ASS format (hh:mm:ss.cs) |
| FontUtility.swift | 39 | Font enumeration: all CJK fonts (Hiragino, Apple SD Gothic Neo, etc.) |
| ColorExtension.swift | 33 | Hex↔Color conversion, color picker integration |
| NativeTextEditor.swift | 86 | NSTextView wrapper: native macOS text editing in SwiftUI |
| TrimTimingUtility.swift | 42 | Trim range validation: start < end, within duration bounds |

## RESOURCES
- **Info.plist** - App metadata, bundle identifier, version, copyright, entitlements
- **MusicReelsGenerator.entitlements** - Sandbox configuration, file access permissions
- **Localizable.strings** - (if present) internationalization strings

## CONFIGURATION
| File | Purpose |
|------|---------|
| Package.swift | SPM manifest: Sparkle dependency, executable target definition |
| MusicReelsGenerator.xcodeproj | Xcode project metadata |
| build.sh | Creates proper .app bundle with Info.plist and app icon |
| setup.sh | Installs FFmpeg and whisper-cpp via Homebrew |

## SUPPORTING SCRIPTS (in Scripts/ directory)
- alignment_pipeline.py - Python pipeline for experimental alignment modes
- yt_download.sh - yt-dlp wrapper for YouTube downloading
- setup_alignment.sh - Installs Python dependencies (whisper, pykakasi, numpy, demucs)

---

## FILE ORGANIZATION BY ROLE

### CRITICAL FLOW (Must Understand)
1. MusicReelsGeneratorApp.swift - Entry point
2. ProjectViewModel.swift - State management hub
3. ContentView.swift - Layout structure
4. Project.swift + LyricBlock.swift - Core data model
5. WhisperAlignmentService.swift - Alignment engine
6. ExportService.swift - Video export pipeline
7. ProcessRunner.swift - Subprocess orchestration

### STYLING & UI
- SubtitleStyle.swift, MetadataOverlaySettings.swift, StylePreset.swift
- InspectorPanelView.swift - All style editing UI
- SubtitleRenderer.swift, SubtitleRenderService.swift - Text rendering
- L10n.swift - All UI strings

### VIDEO HANDLING
- VideoMetadata.swift, VideoService.swift, CropSettings.swift, TrimSettings.swift
- VideoPreviewView.swift - Video display
- AudioExtractionService.swift - Audio prep
- ExportService.swift - Final video output

### ALIGNMENT & TIMING
- LyricBlock.swift, IgnoreRegion.swift
- WhisperAlignmentService.swift - Production alignment
- AdvancedAlignmentService.swift - Experimental pipelines
- LyricsParserService.swift - Input parsing
- TimeFormatter.swift, JapaneseTextNormalizer.swift - Text utilities

### PERSISTENCE
- Project.swift (Codable), LyricBlock.swift (Codable), StylePreset.swift (Codable)
- ProjectPersistenceService.swift - Project JSON serialization
- StylePresetStore.swift - Preset file management
- UserDefaults - UI language preference

### EXTERNAL INTEGRATION
- ProcessRunner.swift - All subprocess calls
- WhisperAlignmentService.swift - whisper-cpp integration
- AdvancedAlignmentService.swift - Python integration
- YouTubeDownloadService.swift, YouTubeDownloadProvider_Real.swift - yt-dlp integration
- ExportService.swift - FFmpeg integration

