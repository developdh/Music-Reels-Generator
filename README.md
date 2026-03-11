# Music Reels Generator

A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.

## Features

- **Video Import** — Load any local video file, extract metadata, preview in-app
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format
- **Auto-Alignment** — Uses whisper.cpp to transcribe Japanese audio and fuzzy-match to lyric blocks
- **Confidence Scoring** — Low-confidence alignments are visually flagged for manual review
- **Manual Timing Editor** — Set start/end times from playback position, seek to blocks, keyboard shortcuts
- **Vertical Reframing** — Crop 16:9 video to 9:16 with adjustable horizontal offset
- **Subtitle Rendering** — Bilingual lyrics overlaid on video preview, burned into export via ASS + FFmpeg
- **Export** — Produce a 1080x1920 MP4 with H.264 video and AAC audio
- **Project Persistence** — Save/load projects as `.mreels` JSON files

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Apple Silicon** (runs on Intel too, but optimized for ARM)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** (for audio extraction, reframing, subtitle burn-in, export)
- **whisper-cpp** (for offline speech recognition / timing alignment)
- **Whisper model file** (e.g., `ggml-medium.bin`)

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

### Option 1: Xcode

```bash
open MusicReelsGenerator.xcodeproj
```

Then press Cmd+R to build and run.

### Option 2: Swift CLI

```bash
swift build
.build/debug/MusicReelsGenerator
```

## Usage

### 1. Import Video

File > Import Video (Cmd+I), or click "Import Video" in the toolbar.

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
1. Extract audio from the video (FFmpeg)
2. Transcribe Japanese speech (whisper.cpp)
3. Fuzzy-match transcription to your lyric blocks
4. Assign timing and confidence scores

### 4. Fix Timing

- Click a lyric block in the left panel to select it
- Use playback controls to seek to the right moment
- Click "Set Now" for start/end time, or use Cmd+[ / Cmd+]
- Manually adjusted blocks show a blue "Manual" badge

### 5. Adjust Crop

In the Inspector > Crop tab:
- Adjust the horizontal offset slider to position the vertical crop window
- The crop preview overlay shows the output frame on the video

### 6. Style Subtitles

In the Inspector > Style tab:
- Adjust font sizes, outline width, shadow, bottom margin
- Changes preview live on the video

### 7. Export

Click "Export" in the toolbar. Choose a save location. The app will:
- Crop the video to 9:16
- Scale to 1080x1920
- Burn in ASS subtitles
- Encode H.264 + AAC
- Output to the chosen MP4 file

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Play/Pause | Space |
| Back 5s | Cmd+Left |
| Forward 5s | Cmd+Right |
| Set Block Start | Cmd+[ |
| Set Block End | Cmd+] |
| New Project | Cmd+N |
| Open Project | Cmd+O |
| Save Project | Cmd+S |
| Import Video | Cmd+I |

## Project Structure

```
MusicReelsGenerator/
├── App/                    # App entry point
├── Models/                 # Domain models (Project, LyricBlock, etc.)
├── Services/               # Business logic
│   ├── AudioExtractionService    # FFmpeg audio extraction
│   ├── ExportService             # FFmpeg export pipeline
│   ├── LyricsParserService       # Bilingual lyrics parsing
│   ├── ProjectPersistenceService # JSON project save/load
│   ├── SubtitleRenderService     # ASS subtitle generation
│   ├── VideoService              # AVFoundation metadata
│   └── WhisperAlignmentService   # whisper.cpp transcription + alignment
├── ViewModels/             # State management
├── Views/                  # SwiftUI views
│   ├── ContentView               # Main layout
│   ├── LyricsPanelView           # Left panel
│   ├── VideoPreviewView          # Center preview
│   ├── PlaybackControlsView      # Bottom controls
│   ├── InspectorPanelView        # Right panel (Block/Crop/Style/Info)
│   ├── ToolbarView               # Top toolbar
│   └── StatusBarView             # Bottom status
├── Utilities/              # Helpers
│   ├── ColorExtension
│   ├── JapaneseTextNormalizer
│   ├── ProcessRunner
│   └── TimeFormatter
└── Resources/              # Info.plist, entitlements
```

## Project File Format

Projects are saved as `.mreels` files (JSON). They store:
- Source video path
- Video metadata
- Crop settings
- Subtitle style
- All lyric blocks with timing data
- Project metadata

## Limitations

- One video per project
- No word-level karaoke timing (line-level only)
- Whisper alignment quality depends on audio clarity
- No cloud sync or multi-device support
- No App Store packaging (runs as development build)
