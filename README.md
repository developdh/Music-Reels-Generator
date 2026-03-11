# Music Reels Generator

A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.

## Features

- **Video Import** — Load any local video file (.mp4, .mov, .avi), extract metadata, preview in-app
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format
- **Auto-Alignment (Monotonic DP)** — Uses whisper.cpp to transcribe Japanese audio and aligns to lyric blocks via beam-search DP with monotonic constraint. Prevents cascading drift that worsens toward the end of a song
- **Confidence Scoring** — Each block gets a 0–1 confidence score. Low-confidence blocks are visually flagged (orange border) for manual review. Interpolated blocks show ~0.05 confidence
- **Anchor System** — High-confidence matches (>0.6) and manually adjusted blocks become anchors. Unmatched blocks are interpolated proportionally between anchors based on text length
- **Manual Timing Correction** — Set start/end times from playback position, shift all following blocks by a delta, fine-grained nudge (±0.1s / ±0.5s), keyboard shortcuts (Cmd+[ / Cmd+])
- **Vertical Reframing** — Crop any aspect ratio video to 9:16 with adjustable horizontal and vertical offset sliders
- **Subtitle Styling** — Independent Japanese/Korean font family selection (with recommended CJK fonts), font size, outline width, shadow, bottom margin, line spacing — all with live preview
- **Two-Stage Export** — Stage 1: FFmpeg crop/scale to 1080x1920. Stage 2: AVAssetReader/Writer frame-by-frame subtitle burn-in with Core Graphics rendering (multi-pass outline for crisp CJK text)
- **Project Persistence** — Save/load projects as `.mreels` JSON files. Open from toolbar or menu (Cmd+O)

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** — audio extraction, video crop/scale/encode
- **whisper-cpp** — offline Japanese speech recognition (binary: `whisper-cli`)
- **Whisper model file** — e.g., `ggml-medium.bin` (~1.5 GB)

## Quick Setup

```bash
./setup.sh
```

This will install FFmpeg and whisper-cpp via Homebrew and download the whisper medium model.

### Manual Setup

```bash
# Install tools
brew install ffmpeg
brew install whisper-cpp

# Download a whisper model
mkdir -p ~/.local/share/whisper-cpp/models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
  -o ~/.local/share/whisper-cpp/models/ggml-medium.bin
```

## Build & Run

### Option 1: Build Script (Recommended)

```bash
./build.sh
open ".build/Music Reels Generator.app"
```

The build script creates a proper `.app` bundle with Info.plist, which is required for AVFoundation and window management to work correctly. Running the bare SPM executable without the bundle will crash.

### Option 2: Xcode

```bash
open MusicReelsGenerator.xcodeproj
```

Then press Cmd+R to build and run.

## Usage

### 1. Import Video

File > Import Video (Cmd+I), or click "Import Video" in the toolbar. Supports `.mp4`, `.mov`, `.avi` files.

### 2. Paste Lyrics

Click the "+" button in the Lyrics panel. Paste lyrics in this format:

```
こんにちは
안녕하세요

ハロー
헬로

さようなら
안녕히 가세요
```

Rules:
- 2 lines per block (Japanese, then Korean)
- Blank line between blocks
- Extra blank lines are ignored

### 3. Auto-Align

Click "Auto-Align" in the toolbar. This will:
1. Extract audio from the video as 16kHz mono WAV (FFmpeg)
2. Transcribe Japanese speech (whisper-cpp with `--output-csv`)
3. Build candidate matches for each lyric block (1–3 consecutive whisper segments, fuzzy similarity ≥ 0.25)
4. Run monotonic beam-search DP (beam width 50) to find the globally optimal segment-to-block assignment
5. Mark high-confidence matches as anchors, interpolate unmatched blocks proportionally by text length

### 4. Fix Timing

- Click a lyric block in the left panel to select it
- Use playback controls to seek to the right moment
- Click "Set Now" for start/end time, or use Cmd+[ / Cmd+]
- **Shift following blocks**: In the Inspector > Block > Correction section, use "Set Start & Shift Following" to move this block and all subsequent blocks by the same delta
- **Fine-grained nudge**: Use ±0.1s / ±0.5s buttons to shift from the selected block onward
- **Anchor toggle**: Mark a block as an anchor so it stays fixed during re-alignment
- Manually adjusted blocks show a blue "Manual" badge

### 5. Adjust Crop

In the Inspector > Crop tab:
- Adjust the horizontal offset slider (L–R) to position the vertical crop window
- Adjust the vertical offset slider (T–B) for vertical positioning
- Click "Center H" / "Center V" to reset
- The preview shows the 9:16 frame in real-time

### 6. Style Subtitles

In the Inspector > Style tab:
- Choose Japanese and Korean font families independently (recommended CJK fonts listed first)
- Adjust font sizes (JP: 24–120, KR: 20–100)
- Set outline width (0–8 px), toggle shadow
- Adjust bottom margin and line spacing between Japanese/Korean lines
- All changes preview live on the video

### 7. Export

Click "Export" in the toolbar. Choose a save location. The app will:
1. Crop and scale the video to 1080x1920 via FFmpeg (H.264, CRF 18, AAC 192k)
2. Read the cropped video frame-by-frame with AVAssetReader
3. Composite pre-rendered subtitle images onto each frame using Core Graphics
4. Write the final MP4 with AVAssetWriter
5. Progress is shown in the bottom status bar

### 8. Save & Load

- **Save**: Click "Save" in the toolbar or Cmd+S. If no file exists yet, a Save As dialog appears
- **Open**: Click "Open" in the toolbar or Cmd+O to load a `.mreels` project file
- **Save As**: File > Save Project As (Cmd+Shift+S)

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Play/Pause | Space |
| Back 5s | Cmd+Left |
| Forward 5s | Cmd+Right |
| Back 1s | Left |
| Forward 1s | Right |
| Set Block Start | Cmd+[ |
| Set Block End | Cmd+] |
| New Project | Cmd+N |
| Open Project | Cmd+O |
| Save Project | Cmd+S |
| Save As | Cmd+Shift+S |
| Import Video | Cmd+I |

## Architecture

```
MusicReelsGenerator/
├── App/                        # @main entry point, menu commands
├── Models/                     # Domain models
│   ├── Project                 #   Root model (video path, metadata, blocks, styles)
│   ├── LyricBlock              #   Japanese + Korean text, timing, confidence, anchor
│   ├── VideoMetadata            #   Dimensions, duration, FPS, file size
│   ├── CropSettings             #   9:16 crop offsets, output resolution
│   └── SubtitleStyle            #   Fonts, colors, outline, shadow, positioning
├── Services/                   # Business logic
│   ├── AudioExtractionService  #   FFmpeg → 16kHz mono WAV
│   ├── WhisperAlignmentService #   whisper-cpp transcription + monotonic DP alignment
│   ├── LyricsParserService     #   Block-format bilingual parser
│   ├── ExportService           #   Two-stage export (FFmpeg crop → AVFoundation burn-in)
│   ├── SubtitleRenderService   #   ASS subtitle file generation
│   ├── VideoService            #   AVFoundation metadata extraction
│   └── ProjectPersistenceService # JSON save/load (.mreels files)
├── ViewModels/                 # State management
│   └── ProjectViewModel        #   Central @MainActor hub for all app state
├── Views/                      # SwiftUI UI layer
│   ├── ContentView             #   3-panel HSplitView layout
│   ├── LyricsPanelView         #   Left: block list, lyrics input sheet
│   ├── VideoPreviewView        #   Center: AVPlayerLayer + crop overlay + subtitles
│   ├── PlaybackControlsView    #   Timeline scrubber, play/pause, ±1s/±5s
│   ├── InspectorPanelView      #   Right: Block/Crop/Style/Info tabs
│   ├── ToolbarView             #   Top: Import, Align, Export, Open, Save
│   └── StatusBarView           #   Bottom: export progress, status message
├── Utilities/                  # Helpers
│   ├── ProcessRunner           #   Async Process wrapper, FFmpeg/Whisper detection
│   ├── JapaneseTextNormalizer  #   Katakana→hiragana, Levenshtein, LCS similarity
│   ├── TimeFormatter           #   Time display (MM:SS.CS, ASS format)
│   ├── FontUtility             #   System font enumeration, JP/KR recommendations
│   └── ColorExtension          #   Hex ↔ Color conversion
└── Resources/                  # Info.plist, entitlements
```

## How Alignment Works

The alignment algorithm matches whisper-cpp speech segments to user-provided lyric blocks:

1. **Candidate Generation** — For each lyric block, try matching against every whisper segment (and combinations of 2–3 consecutive segments). Score using normalized Levenshtein distance and LCS-based containment. Keep candidates with score ≥ 0.25.

2. **Text Normalization** — Before comparison, both texts are normalized: katakana → hiragana, remove punctuation/music symbols, normalize full-width characters, strip prolonged sound marks, lowercase.

3. **Monotonic DP** — Forward beam search (width 50) finds the best assignment of segments to blocks under the constraint that segment indices must be strictly increasing. Each block can be matched or skipped. This prevents one bad match from corrupting all later blocks.

4. **Anchor Marking** — Blocks matched with confidence ≥ 0.6, or manually adjusted by the user, are marked as anchors.

5. **Proportional Interpolation** — Unmatched blocks between anchors receive interpolated timing proportional to their Japanese text length (longer lines get more time). These blocks get confidence ~0.05.

## Project File Format

Projects are saved as `.mreels` files (JSON). They store:
- Source video path and cached metadata
- Crop settings (horizontal/vertical offset)
- Subtitle style (fonts, sizes, colors, outline, shadow, positioning)
- All lyric blocks with timing, confidence scores, anchor/manual flags
- Project title and timestamps

## Limitations

- One video per project
- Japanese speech recognition only (whisper language fixed to `ja`)
- Line-level timing only (no word-level karaoke)
- Whisper alignment quality depends on audio clarity and vocal separation
- Frame-by-frame export is CPU-intensive (processes each frame individually)
- No cloud sync or multi-device support
- Development build only (not packaged for App Store)
