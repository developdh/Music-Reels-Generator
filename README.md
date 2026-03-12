# Music Reels Generator

A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.

An example source video (`GreenlightsSerenade3.mp4`) is included in the repository for testing.

## Features

- **Video Import** — Load any local video file (.mp4, .mov, .avi), extract metadata (dimensions, duration, FPS, file size), preview in-app
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format (2 lines per block, blank line separator)
- **Auto-Alignment (Monotonic DP)** — Uses whisper.cpp to transcribe Japanese audio and aligns to lyric blocks via beam-search DP (width 50) with monotonic constraint. Prevents cascading drift that worsens toward the end of a song
- **Confidence Scoring** — Each block gets a 0–1 confidence score. Low-confidence blocks are visually flagged (orange border) for manual review. Interpolated blocks show ~0.05 confidence
- **Anchor System** — High-confidence matches (>0.6) and manually adjusted blocks become anchors. Unmatched blocks are interpolated proportionally between anchors based on text length
- **Manual Timing Correction** — Set start/end times from playback position, shift all following blocks by a delta, fine-grained nudge (±0.1s / ±0.5s), keyboard shortcuts (Cmd+[ / Cmd+])
- **Video Trimming** — Non-destructive trim in/out to cut intros, outros, or shorten the final reel. Trim range is enforced in preview playback (auto-stop at trim end, jump to trim start on play) and applied during export via FFmpeg seek
- **Vertical Reframing** — Crop any aspect ratio video to 9:16 with adjustable horizontal and vertical offset sliders
- **Subtitle Styling** — Independent Japanese/Korean font family selection (with recommended CJK fonts), font size, per-language text color with color pickers and preset swatches, outline width, shadow, bottom margin (up to screen center), line spacing
- **Metadata Overlay** — Optional top-left title/artist overlay with dark rounded background box. Independent font, size, and color controls for title and artist. Configurable background opacity, corner radius, padding, and position
- **Unified Preview/Export Rendering** — Both preview and export use the same Core Graphics subtitle renderer (`SubtitleRenderer`), rendering at 1080x1920 canvas. Preview displays a scaled-down version, ensuring pixel-identical typography for both subtitles and metadata overlay
- **Two-Stage Export** — Stage 1: FFmpeg trim + crop/scale to 1080x1920. Stage 2: AVAssetReader/Writer frame-by-frame burn-in of metadata overlay + subtitle CGImage overlays
- **Project Persistence** — Save/load projects as `.mreels` JSON files with backward compatibility for older formats

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** — audio extraction, video crop/scale/trim/encode
- **whisper-cpp** — offline Japanese speech recognition (binary: `whisper-cli`) — for Fast mode
- **Python 3 + openai-whisper** — for Balanced/Accurate/Maximum modes (word-level forced alignment)
- **pykakasi** — Japanese kanji-to-kana conversion for alignment
- **demucs** (optional) — vocal separation for Accurate/Maximum modes

## Quick Setup

```bash
./setup.sh
```

This will install FFmpeg and whisper-cpp via Homebrew and download the whisper medium model.

### Advanced Alignment Setup (Recommended)

For significantly better alignment accuracy, install the Python-based forced alignment pipeline:

```bash
cd Scripts && ./setup_alignment.sh
```

This installs `openai-whisper`, `pykakasi`, and optionally `demucs` for vocal separation.

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

## Quick Start with Example Video

```bash
./setup.sh       # Install FFmpeg, whisper-cpp, download model
./build.sh       # Build the app
open ".build/Music Reels Generator.app"
```

1. Import `GreenlightsSerenade3.mp4` from the project root
2. Paste bilingual lyrics (Japanese + Korean)
3. Click "Auto-Align" to match lyrics to audio
4. Adjust crop, trim, subtitle styling, and metadata overlay
5. Export the final vertical video

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

Select a quality mode from the toolbar dropdown, then click "Auto-Align".

**Quality Modes:**
- **Fast** — Legacy whisper-cpp segment matching (requires whisper-cpp only)
- **Balanced** — Word-level forced alignment with character-level DTW + global DP (requires Python pipeline)
- **Accurate** — + Vocal separation (demucs) + collapse detection + recovery passes
- **Maximum** — + Extended search windows + deeper beam search + full recovery

**Advanced pipeline (Balanced+) performs:**
1. Extract audio from the video as 16kHz mono WAV (FFmpeg)
2. Optional vocal separation to isolate singing from accompaniment (demucs)
3. Transcribe with word-level timestamps (openai-whisper Python with cross-attention)
4. Convert Japanese lyrics to hiragana via G2P (pykakasi)
5. Expand whisper words to character-level timing
6. VAD-based chunking at low-energy boundaries (8–25 second chunks)
7. Per-chunk character-level DTW alignment against multiple candidate lyric windows
8. Global monotonic DP to select best path across all chunks
9. Collapse detection and re-anchoring of degraded regions
10. Line timing reconstruction from character-level alignment
11. Proportional interpolation for remaining unmatched lines

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
- Set per-language text colors using color pickers or preset swatches (White, Cyan, Yellow, Mint, Pink)
- Set outline width (0–8 px), toggle shadow
- Adjust bottom margin (50–960, up to screen center) and line spacing between Japanese/Korean lines
- Preview uses the same renderer as export, so what you see is what you get

### 8. Title / Artist Overlay

In the Inspector > Overlay tab:
- Toggle the overlay on/off
- Enter song title and artist name
- Choose independent fonts, sizes, and colors for title and artist
- Adjust background box opacity (0–100%) and corner radius
- Set top and left margins to position the overlay
- Configure horizontal/vertical padding and line spacing
- The overlay appears in the top-left area with a dark rounded background box
- Preview and export render identically using the shared `SubtitleRenderer`

### 9. Export

Click "Export" in the toolbar. Choose a save location. The app will:
1. Trim and crop the video to 1080x1920 via FFmpeg (`-ss` seek + `-t` duration, H.264 CRF 18, AAC 192k)
2. Remap lyric timing to trim-relative coordinates (blocks outside the range are omitted, overlapping blocks are clamped)
3. Pre-render the metadata overlay as a single CGImage (composited onto every frame)
4. Read the cropped video frame-by-frame with AVAssetReader
5. Composite metadata overlay + active subtitle images onto each frame using Core Graphics
6. Write the final MP4 with AVAssetWriter
7. Progress is shown in the bottom status bar

### 10. Save & Load

- **Save**: Click "Save" in the toolbar or Cmd+S. If no file exists yet, a Save As dialog appears
- **Open**: Click "Open" in the toolbar or Cmd+O to load a `.mreels` project file
- **Save As**: File > Save Project As (Cmd+Shift+S)
- All settings are preserved: lyrics, timing, crop, trim, subtitle style, metadata overlay, project title

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
│   ├── Project                    # Root aggregate (video, metadata, blocks, styles, trim, overlay)
│   ├── LyricBlock                 # Japanese + Korean text, timing, confidence, anchor flag
│   ├── VideoMetadata              # Dimensions, duration, FPS, file size
│   ├── CropSettings               # 9:16 crop mode, H/V offsets, output resolution
│   ├── TrimSettings               # Trim in/out times, validation, duration
│   ├── SubtitleStyle              # Per-language fonts, sizes, colors, outline, shadow, margins
│   └── MetadataOverlaySettings    # Title/artist text, fonts, colors, background box, position
├── Services/
│   ├── AudioExtractionService     # FFmpeg → 16kHz mono WAV for whisper
│   ├── WhisperAlignmentService    # Legacy: whisper-cpp segment matching (Fast mode)
│   ├── AdvancedAlignmentService   # Advanced: Python subprocess forced alignment (Balanced+)
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
│   ├── VideoPreviewView           # Center: AVPlayerLayer + crop + metadata overlay + subtitles
│   ├── PlaybackControlsView       # Scrubber with trim indicator, play/pause, timing setters
│   ├── InspectorPanelView         # Right: Block / Trim / Crop / Style / Overlay / Info tabs
│   ├── ToolbarView                # Import, Align, Export, Open, Save buttons
│   └── StatusBarView              # Export progress bar, status message, dirty indicator
├── Utilities/
│   ├── SubtitleRenderer           # Shared Core Graphics renderer (subtitles + metadata overlay)
│   ├── ProcessRunner              # Async Process wrapper, FFmpeg/Whisper path detection
│   ├── JapaneseTextNormalizer     # Katakana→hiragana, Levenshtein + LCS similarity
│   ├── TrimTimingUtility          # Source-absolute → trim-relative time conversion
│   ├── TimeFormatter              # Time display (MM:SS.CS, ASS timestamp format)
│   ├── FontUtility                # System font enumeration, JP/KR font recommendations
│   └── ColorExtension             # Hex ↔ Color conversion
├── Resources/                     # Info.plist, entitlements
Scripts/
├── alignment_pipeline.py          # Python forced alignment: DTW, chunking, DP, recovery
├── requirements.txt               # Python dependencies
└── setup_alignment.sh             # One-command setup for advanced pipeline
```

## How Alignment Works

### Legacy (Fast Mode)

The Fast mode uses whisper-cpp for segment-level alignment:
1. Whisper-cpp transcribes audio into sentence-level segments with timestamps
2. Each lyric block is matched against whisper segments using text similarity (Levenshtein + LCS)
3. Monotonic beam-search DP finds the best assignment under monotonic constraint
4. High-confidence matches become anchors; unmatched blocks are interpolated

### Advanced (Balanced / Accurate / Maximum)

The advanced pipeline uses character-level forced alignment for dramatically better accuracy:

1. **Word-Level Transcription** — openai-whisper (Python) transcribes with `word_timestamps=True`, producing per-word timing via cross-attention weights (~10-25x more data points than segment-level)

2. **Optional Vocal Separation** — In Accurate/Maximum modes, demucs separates vocals from accompaniment before transcription, significantly improving recognition quality for music

3. **Japanese G2P** — Lyrics are converted to hiragana using pykakasi (kanji→kana), then normalized (remove punctuation, katakana→hiragana). This creates alignment-friendly character units

4. **Character-Level Expansion** — Whisper words are expanded into character-level timing (proportional distribution within each word). This gives ~500-1500 character timestamps per song

5. **Banded DTW Alignment** — The whisper character stream is aligned to the concatenated lyric character stream using banded Dynamic Time Warping with asymmetric costs (missing lyric chars penalized more than extra whisper chars)

6. **VAD-Based Chunking** — Audio is chunked at low-energy boundaries (8-25 second chunks) using RMS energy analysis, independent of lyric timestamps. This prevents alignment drift from affecting chunk boundaries

7. **Multi-Window Candidate Scoring** — Each chunk is aligned against multiple candidate lyric windows around the expected position. Character-level DTW scores each candidate

8. **Global Monotonic DP** — Beam search DP across all chunks selects the globally optimal monotonic assignment of lyric windows to audio chunks, with continuity bonuses and gap penalties

9. **Collapse Detection** — After alignment, the system scans for collapse signals: sudden confidence drops, impossible durations, backwards time jumps, large gaps. Collapsed regions are re-aligned with wider search windows

10. **Line Reconstruction** — Final line start/end times are derived from the first/last matched character of each line in the DTW alignment, not from direct ASR timestamps

## How Export Works

The export pipeline uses a two-stage approach because Homebrew's FFmpeg lacks libass for direct subtitle rendering:

**Stage 1: FFmpeg Trim + Crop + Scale**
- Seeks to trim start (`-ss`) and limits duration (`-t`)
- Scales source to cover 1080x1920 (fill mode), then crops with user-defined H/V offset
- Encodes H.264 (CRF 18, fast preset) with AAC audio (192k)
- Output: intermediate cropped MP4

**Stage 2: AVFoundation Frame-by-Frame Burn-In**
- Pre-renders all subtitle blocks as CGImages via `SubtitleRenderer` (multi-pass outline + shadow + fill)
- Pre-renders the metadata overlay as a single CGImage (title/artist with background box)
- Lyric timing is remapped from source-absolute to trim-relative using `TrimTimingUtility`
- Reads each frame with AVAssetReader, composites metadata overlay + active subtitle CGImage, writes with AVAssetWriter
- Audio is passed through on a background queue

## How Preview/Export Consistency Works

Both preview and export use the same `SubtitleRenderer` — a shared Core Graphics rendering engine:

1. `SubtitleRenderer.renderBlock()` renders subtitle text at the canonical 1080x1920 export canvas
2. `SubtitleRenderer.renderMetadataOverlay()` renders the title/artist overlay with background box at the same canvas
3. Font resolution uses `NSFontDescriptor` with `.family` attribute (not `NSFont(name:)` which requires PostScript names)
4. Japanese subtitle font gets bold trait via `NSFontManager`
5. Multi-pass subtitle rendering: outline (offset grid) → shadow → fill
6. Preview displays the resulting CGImages scaled down to fit the preview container
7. Export composites the same CGImages at full resolution onto video frames

This eliminates all mismatch between preview and export: same fonts, same outline, same wrapping, same positioning, same metadata overlay.

## Project File Format

Projects are saved as `.mreels` files (JSON with ISO 8601 dates). They store:
- Source video path and cached metadata (dimensions, duration, FPS, file size)
- Trim settings (start/end times)
- Crop settings (horizontal/vertical offset, output resolution)
- Subtitle style (per-language fonts, sizes, colors, outline, shadow, margin, line spacing)
- Metadata overlay settings (title/artist text, fonts, colors, background box, position, padding)
- All lyric blocks with timing, confidence scores, anchor/manual flags
- Project title and created/updated timestamps

Backward compatibility: older project files without `trimSettings`, `isAnchor`, `metadataOverlay`, or per-language text color fields are handled via custom `Decodable` initializers that supply default values.

## Limitations

- One video per project
- Japanese speech recognition only (whisper language fixed to `ja`)
- Line-level timing only (no word-level karaoke)
- Whisper alignment quality depends on audio clarity and vocal separation
- Frame-by-frame export is CPU-intensive (processes each video frame individually)
- No cloud sync or multi-device support
- Development build only (not packaged for App Store)
