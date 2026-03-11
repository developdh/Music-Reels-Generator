# Music Reels Generator

A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.

## Features

- **Video Import** — Load any local video file (.mp4, .mov, .avi), extract metadata, preview in-app
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format
- **Auto-Alignment (Monotonic DP)** — Uses whisper.cpp to transcribe Japanese audio and aligns to lyric blocks via beam-search DP with monotonic constraint. Prevents cascading drift that worsens toward the end of a song
- **Confidence Scoring** — Each block gets a 0–1 confidence score. Low-confidence blocks are visually flagged (orange border) for manual review. Interpolated blocks show ~0.05 confidence
- **Anchor System** — High-confidence matches (>0.6) and manually adjusted blocks become anchors. Unmatched blocks are interpolated proportionally between anchors based on text length
- **Manual Timing Correction** — Set start/end times from playback position, shift all following blocks by a delta, fine-grained nudge (±0.1s / ±0.5s), keyboard shortcuts (Cmd+[ / Cmd+])
- **Video Trimming** — Non-destructive trim in/out to cut intros, outros, or shorten the final reel. Trim range is enforced in preview playback (auto-stop at trim end, jump to trim start on play) and applied during export via FFmpeg seek
- **Vertical Reframing** — Crop any aspect ratio video to 9:16 with adjustable horizontal and vertical offset sliders
- **Subtitle Styling** — Independent Japanese/Korean font family selection (with recommended CJK fonts), font size, outline width, shadow, bottom margin, line spacing
- **Unified Preview/Export Rendering** — Both preview and export use the same Core Graphics subtitle renderer (`SubtitleRenderer`), rendering at 1080x1920 canvas. Preview displays a scaled-down version, ensuring pixel-identical typography
- **Two-Stage Export** — Stage 1: FFmpeg trim + crop/scale to 1080x1920. Stage 2: AVAssetReader/Writer frame-by-frame subtitle burn-in with pre-rendered CGImage overlays
- **Project Persistence** — Save/load projects as `.mreels` JSON files with backward compatibility for older formats

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** — audio extraction, video crop/scale/trim/encode
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

The build script creates a proper `.app` bundle with Info.plist and app icon, which is required for AVFoundation and window management to work correctly. Running the bare SPM executable without the bundle will crash.

### Option 2: Xcode

```bash
open MusicReelsGenerator.xcodeproj
```

Then press Cmd+R to build and run.

## Usage

### 1. Import Video

File > Import Video (Cmd+I), or click "Import Video" in the toolbar. Supports `.mp4`, `.mov`, `.avi` files. The app extracts metadata (dimensions, duration, FPS) and initializes the trim range to the full video duration.

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

### 5. Trim Video

In the Inspector > Trim tab:
- Set trim start and end times using "Set to Current" or ±0.1s / ±1s nudge buttons
- The trim bar shows a visual overview of the selected range (green start marker, red end marker)
- Playback respects the trim range: stops at trim end, jumps to trim start when pressing play
- "Reset Trim" restores the full video duration
- The trimmed duration is shown in the playback controls

### 6. Adjust Crop

In the Inspector > Crop tab:
- Adjust the horizontal offset slider (L–R) to position the vertical crop window
- Adjust the vertical offset slider (T–B) for vertical positioning
- Click "Center H" / "Center V" to reset
- The preview shows the 9:16 frame in real-time

### 7. Style Subtitles

In the Inspector > Style tab:
- Choose Japanese and Korean font families independently (recommended CJK fonts listed first)
- Adjust font sizes (JP: 24–120, KR: 20–100)
- Set outline width (0–8 px), toggle shadow
- Adjust bottom margin and line spacing between Japanese/Korean lines
- Preview uses the same renderer as export, so what you see is what you get

### 8. Export

Click "Export" in the toolbar. Choose a save location. The app will:
1. Trim and crop the video to 1080x1920 via FFmpeg (`-ss` seek + `-t` duration, H.264 CRF 18, AAC 192k)
2. Remap lyric timing to trim-relative coordinates (blocks outside the range are omitted, overlapping blocks are clamped)
3. Read the cropped video frame-by-frame with AVAssetReader
4. Composite pre-rendered subtitle images onto each frame using Core Graphics
5. Write the final MP4 with AVAssetWriter
6. Progress is shown in the bottom status bar

### 9. Save & Load

- **Save**: Click "Save" in the toolbar or Cmd+S. If no file exists yet, a Save As dialog appears
- **Open**: Click "Open" in the toolbar or Cmd+O to load a `.mreels` project file
- **Save As**: File > Save Project As (Cmd+Shift+S)
- All settings are preserved: lyrics, timing, crop, trim, subtitle style, project title

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
├── App/
│   └── MusicReelsGeneratorApp     # @main entry point, window config, menu commands
├── Models/
│   ├── Project                    # Root aggregate (video, metadata, blocks, styles, trim)
│   ├── LyricBlock                 # Japanese + Korean text, timing, confidence, anchor flag
│   ├── VideoMetadata              # Dimensions, duration, FPS, file size
│   ├── CropSettings               # 9:16 crop mode, H/V offsets, output resolution
│   ├── TrimSettings               # Trim in/out times, validation, duration
│   └── SubtitleStyle              # Fonts, sizes, colors, outline, shadow, margins
├── Services/
│   ├── AudioExtractionService     # FFmpeg → 16kHz mono WAV for whisper
│   ├── WhisperAlignmentService    # Transcription + monotonic DP beam-search alignment
│   ├── LyricsParserService        # Block-format bilingual parser
│   ├── ExportService              # Two-stage pipeline (FFmpeg trim+crop → AVFoundation burn-in)
│   ├── SubtitleRenderService      # ASS subtitle file generation
│   ├── VideoService               # AVFoundation metadata extraction
│   └── ProjectPersistenceService  # JSON save/load (.mreels), backward compatibility
├── ViewModels/
│   └── ProjectViewModel           # @MainActor central state hub, playback, trim enforcement
├── Views/
│   ├── ContentView                # 3-panel HSplitView layout
│   ├── LyricsPanelView            # Left: block list with confidence badges, lyrics input
│   ├── VideoPreviewView           # Center: AVPlayerLayer + crop + shared-renderer subtitles
│   ├── PlaybackControlsView       # Scrubber with trim indicator, play/pause, timing setters
│   ├── InspectorPanelView         # Right: Block / Trim / Crop / Style / Info tabs
│   ├── ToolbarView                # Import, Align, Export, Open, Save buttons
│   └── StatusBarView              # Export progress bar, status message, dirty indicator
├── Utilities/
│   ├── SubtitleRenderer           # Shared Core Graphics renderer (preview + export identical)
│   ├── ProcessRunner              # Async Process wrapper, FFmpeg/Whisper path detection
│   ├── JapaneseTextNormalizer     # Katakana→hiragana, Levenshtein + LCS similarity
│   ├── TrimTimingUtility          # Source-absolute → trim-relative time conversion
│   ├── TimeFormatter              # Time display (MM:SS.CS, ASS timestamp format)
│   ├── FontUtility                # System font enumeration, JP/KR font recommendations
│   └── ColorExtension             # Hex ↔ Color conversion
└── Resources/                     # Info.plist, entitlements
```

## How Alignment Works

The alignment algorithm matches whisper-cpp speech segments to user-provided lyric blocks:

1. **Candidate Generation** — For each lyric block, try matching against every whisper segment (and combinations of 2–3 consecutive segments). Score using normalized Levenshtein distance and LCS-based containment. Keep candidates with score ≥ 0.25.

2. **Text Normalization** — Before comparison, both texts are normalized: katakana → hiragana, remove punctuation/music symbols, normalize full-width characters, strip prolonged sound marks, lowercase.

3. **Monotonic DP** — Forward beam search (width 50) finds the best assignment of segments to blocks under the constraint that segment indices must be strictly increasing. Each block can be matched or skipped. This prevents one bad match from corrupting all later blocks.

4. **Anchor Marking** — Blocks matched with confidence ≥ 0.6, or manually adjusted by the user, are marked as anchors.

5. **Proportional Interpolation** — Unmatched blocks between anchors receive interpolated timing proportional to their Japanese text length (longer lines get more time). These blocks get confidence ~0.05.

## How Export Works

The export pipeline uses a two-stage approach because Homebrew's FFmpeg lacks libass for direct subtitle rendering:

**Stage 1: FFmpeg Trim + Crop + Scale**
- Seeks to trim start (`-ss`) and limits duration (`-t`)
- Scales source to cover 1080x1920 (fill mode), then crops with user-defined H/V offset
- Encodes H.264 (CRF 18, fast preset) with AAC audio (192k)
- Output: intermediate cropped MP4

**Stage 2: AVFoundation Frame-by-Frame Burn-In**
- Pre-renders all subtitle blocks as CGImages via `SubtitleRenderer` (multi-pass outline + shadow + fill)
- Lyric timing is remapped from source-absolute to trim-relative using `TrimTimingUtility`
- Reads each frame with AVAssetReader, composites active subtitle CGImage, writes with AVAssetWriter
- Audio is passed through on a background queue

## How Preview/Export Consistency Works

Both preview and export use the same `SubtitleRenderer` — a shared Core Graphics rendering engine:

1. `SubtitleRenderer.renderBlock()` renders subtitle text at the canonical 1080x1920 export canvas
2. Font resolution uses `NSFontDescriptor` with `.family` attribute (not `NSFont(name:)` which requires PostScript names)
3. Japanese font gets bold trait via `NSFontManager`
4. Multi-pass rendering: outline (offset grid) → shadow → fill
5. Preview displays the resulting CGImage scaled down to fit the preview container
6. Export composites the same CGImage at full resolution onto video frames

This eliminates all mismatch between preview and export: same fonts, same outline, same wrapping, same positioning.

## Project File Format

Projects are saved as `.mreels` files (JSON with ISO 8601 dates). They store:
- Source video path and cached metadata (dimensions, duration, FPS, file size)
- Trim settings (start/end times)
- Crop settings (horizontal/vertical offset, output resolution)
- Subtitle style (fonts, sizes, colors, outline, shadow, margin, line spacing)
- All lyric blocks with timing, confidence scores, anchor/manual flags
- Project title and created/updated timestamps

Backward compatibility: older project files without `trimSettings` or `isAnchor` fields are handled via custom `Decodable` initializers that supply default values.

## Limitations

- One video per project
- Japanese speech recognition only (whisper language fixed to `ja`)
- Line-level timing only (no word-level karaoke)
- Whisper alignment quality depends on audio clarity and vocal separation
- Frame-by-frame export is CPU-intensive (processes each video frame individually)
- No cloud sync or multi-device support
- Development build only (not packaged for App Store)
