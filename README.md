<div align="center">

# 🎬 Music Reels Generator

<p>
  <a href="https://developer.apple.com/macos/"><img src="https://img.shields.io/badge/platform-macOS_14.0+-blue?style=for-the-badge&logo=apple&logoColor=white" alt="Platform"></a>
  <a href="https://github.com/developdh/Music-Reels-Generator/releases"><img src="https://img.shields.io/github/v/release/developdh/Music-Reels-Generator?style=for-the-badge&color=green" alt="Release"></a>
  <a href="https://github.com/developdh/Music-Reels-Generator/blob/main/LICENSE"><img src="https://img.shields.io/github/license/developdh/Music-Reels-Generator?style=for-the-badge" alt="License"></a>
  <img src="https://img.shields.io/github/repo-size/developdh/Music-Reels-Generator?style=for-the-badge&color=orange" alt="Repo Size">
</p>

<p>
  <a href="https://skillicons.dev">
    <img src="https://skillicons.dev/icons?i=swift,apple,python,git,github&theme=dark" alt="Tech Stack">
  </a>
</p>

<p><strong>A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.</strong></p>

<p>
  <img src="https://img.shields.io/badge/Swift-5.9+-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/SwiftUI-Framework-007AFF?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/AVFoundation-Media-8B5CF6?style=flat-square&logo=apple&logoColor=white" alt="AVFoundation">
  <img src="https://img.shields.io/badge/FFmpeg-CLI-007808?style=flat-square&logo=ffmpeg&logoColor=white" alt="FFmpeg">
  <img src="https://img.shields.io/badge/whisper.cpp-AI-4B5563?style=flat-square" alt="whisper.cpp">
</p>

</div>

---

An example source video (`GreenlightsSerenade3.mp4`) is included in the repository for testing.

## Features

- **Video Import** — Load any local video file (.mp4, .mov, .avi), extract metadata (dimensions, duration, FPS, file size), preview in-app with AVPlayerLayer
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format (2 lines per block, blank line separator)
- **Production Alignment Engine** — whisper-cpp segment matching with position-aware beam-search DP, drift detection, boundary snap, and multi-pass refinement. Selected as production default for consistently best results on singing audio
- **Experimental Pipelines** — Three additional Python-based alignment modes for A/B comparison: segment-level Levenshtein, gated refinement, and ungated hybrid. These are clearly labeled as experimental and isolated from production output
- **Drift Detection** — Automatically detects runs of blocks with systematic positional drift (e.g., from chorus confusion) and re-anchors them against local segments
- **Boundary Snap** — Post-alignment step that snaps block start/end times to nearest whisper segment edges for tighter subtitle timing
- **Confidence Scoring** — Each block gets a 0–1 confidence score. Low-confidence blocks are visually flagged (orange border) for manual review. Interpolated blocks show ~0.05 confidence
- **Dual Anchor System** — Two anchor types: auto-anchors (grey lock, set by alignment based on textScore ≥ 0.6) and user anchors (blue lock, set manually). Only user anchors and fully manually-adjusted blocks are used as reference points for piecewise correction
- **Piecewise Anchor Correction** — Distributes timing proportionally between trusted anchor pairs (user-set or both start/end manually adjusted) by Japanese text character count. Runs automatically after alignment if user anchors exist. Also available as manual "전체 구간 재보정" and "이전앵커~다음앵커 재보정" operations
- **Local Re-Alignment** — Re-runs whisper-cpp alignment on a bounded region between surrounding anchors using cached transcription segments, without re-transcribing the full audio
- **Manual Timing Correction** — Set start/end times from playback position, shift all following blocks by a delta, fine-grained nudge (+-0.1s / +-0.5s), keyboard shortcuts (Cmd+[ / Cmd+]). Granular tracking of which boundary (start/end) was manually adjusted
- **Video Trimming** — Non-destructive trim in/out to cut intros, outros, or shorten the final reel. Draggable start/end handles on the trim bar for quick visual adjustment, plus precise numeric controls. Trim range is enforced in preview playback (auto-stop at trim end, loop to trim start on play) and applied during export via FFmpeg seek
- **Vertical Reframing** — Crop any aspect ratio video to 9:16 with adjustable horizontal and vertical offset sliders plus 1x–3x zoom slider. Cover-mode scaling ensures no black bars
- **Subtitle Styling** — Independent Japanese/Korean font family selection (with recommended CJK fonts: Hiragino Sans, Apple SD Gothic Neo, etc.), font size (JP: 24–120, KR: 20–100), per-language text color with color pickers and 5 preset swatches, outline width (0–8 px), shadow toggle, bottom margin (50–960, up to screen center), line spacing
- **Metadata Overlay** — Optional top-left title/artist overlay with dark rounded background box. Independent font, size, and color controls for title and artist. Configurable background opacity, corner radius, padding, and position margins
- **Style Presets** — Save, load, rename, duplicate, and delete reusable style presets (subtitle + overlay styling). Presets persist in Application Support and are reusable across all projects. Presets capture visual styling only, excluding song-specific text content (title/artist text)
- **Unified Preview/Export Rendering** — Both preview and export use the same Core Graphics subtitle renderer (`SubtitleRenderer`), rendering at 1080x1920 canvas with multi-pass outline/shadow/fill. Preview displays a scaled-down version, ensuring pixel-identical typography
- **Two-Stage Export** — Stage 1: FFmpeg trim + crop/scale to 1080x1920 (H.264 CRF 18, AAC 192k). Stage 2: AVAssetReader/Writer frame-by-frame burn-in of metadata overlay + subtitle CGImage overlays
- **Project Persistence** — Save/load projects as `.mreels` JSON files with backward compatibility for older formats (missing fields get defaults via custom `Decodable` initializers)

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** — audio extraction, video crop/scale/trim/encode

### For production alignment (Recommended mode)
- **whisper-cpp** — offline Japanese speech recognition (binary: `whisper-cli`)
- **Whisper model file** — e.g., `ggml-medium.bin` (~1.5 GB)

### For experimental pipelines (Exp: Segment / Refined / Hybrid)
- **Python 3** — subprocess host for the alignment pipeline
- **openai-whisper** — word-level speech recognition with cross-attention timestamps
- **pykakasi** — Japanese kanji-to-kana G2P conversion
- **numpy** — audio energy analysis and array operations
- **demucs** (optional) — vocal stem separation

## Quick Setup

```bash
# Install FFmpeg and whisper-cpp (required for production alignment)
./setup.sh

# Optional: install experimental Python pipeline
cd Scripts && ./setup_alignment.sh
```

`setup.sh` installs FFmpeg and whisper-cpp via Homebrew and downloads the whisper medium model.

`setup_alignment.sh` installs `openai-whisper`, `pykakasi`, `numpy`, and optionally `demucs`.

### Manual Setup

```bash
# FFmpeg (required)
brew install ffmpeg

# whisper-cpp (required for production alignment)
brew install whisper-cpp
mkdir -p ~/.local/share/whisper-cpp/models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
  -o ~/.local/share/whisper-cpp/models/ggml-medium.bin

# Experimental Python pipeline (optional)
pip3 install openai-whisper pykakasi numpy
pip3 install demucs  # optional, for vocal separation
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
./setup.sh       # Install FFmpeg, whisper-cpp
./build.sh       # Build the app
open ".build/Music Reels Generator.app"
```

1. Import `GreenlightsSerenade3.mp4` from the project root
2. Paste bilingual lyrics (Japanese + Korean)
3. Keep the default "Recommended" mode and click "Auto-Align"
4. Adjust crop, trim, subtitle styling, and metadata overlay
5. Export the final vertical video

## Usage

### 1. Import Video

File > Import Video (Cmd+I), or click "Import Video" in the toolbar. Supports `.mp4`, `.mov`, `.avi` files. The app extracts metadata (dimensions, duration, FPS, file size) via AVFoundation and initializes the trim range to the full video duration.

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

Select an alignment mode from the toolbar dropdown, then click "Auto-Align". The toolbar shows status badges for FFmpeg (green/red), Whisper (green/red for whisper-cpp), and Python (Exp) (green/red for experimental pipeline availability).

**Alignment Modes:**

| Mode | Label | Pipeline | Status |
|------|-------|----------|--------|
| Recommended | `Recommended` | whisper-cpp (Swift) | **Production default** |
| Exp: Segment | `Exp: Segment` | Python segment-level Levenshtein | Experimental |
| Exp: Refined | `Exp: Refined` | Python baseline + gated DTW refinement | Experimental |
| Exp: Hybrid | `Exp: Hybrid` | Python ungated hybrid pipeline | Experimental |

The **Recommended** mode is selected by default and consistently produces the best alignment quality for singing audio. The experimental Python modes are available for A/B comparison but are not recommended for production use.

**Recommended mode pipeline:**
1. Extract audio as 16kHz mono WAV (FFmpeg)
2. Transcribe with whisper-cpp (`--output-csv`, sentence-level segments)
3. Merge short fragments (<0.3s), filtering non-speech segments (`(拍手)`, `(音楽)`, `[Music]`, etc.)
4. Detect vocal onset from first speech segment
5. Position-aware candidate generation with windowed search (30s radius), skipping non-speech segments
6. Monotonic beam-search DP assignment (beam width 80), preventing combination of speech + non-speech segments
7. Multi-pass refinement of low-confidence regions between anchors
8. Drift detection — identifies runs of 3+ weak blocks with systematic positional shift and re-anchors them
9. Vocal range-aware interpolation — detects speech vs. instrumental ranges from whisper segments, distributes unmatched blocks only into vocal regions (proportional to Japanese text character count)
10. Overlong block capping — trims blocks whose duration far exceeds their text length (~3.5 chars/sec + 1.5s buffer) to prevent subtitles lingering through instrumental gaps
11. Boundary snap — snaps block edges to nearest whisper segment boundaries (within 0.3s)
12. Auto-correct between user anchors (if ≥ 2 exist) — piecewise proportional redistribution

**Experimental Python pipeline (Exp modes):**
1. Extract audio as 16kHz mono WAV (FFmpeg)
2. Transcribe with openai-whisper Python (`word_timestamps=True`, cross-attention weights)
3. Convert Japanese lyrics to hiragana via G2P (pykakasi kanji->kana, katakana->hiragana)
4. Strategy depends on mode:
   - **Exp: Segment** — Groups whisper words into pseudo-segments, applies position-aware Levenshtein matching (mirrors production algorithm)
   - **Exp: Refined** — Segment baseline + gated local DTW refinement with 7 validation gates (shift limits, confidence gain, monotonic order, duration sanity, gap limits)
   - **Exp: Hybrid** — Ungated ASR anchors + character-level DTW (for comparison only)
5. Proportional interpolation for remaining unmatched lines

### 4. Fix Timing

- Click a lyric block in the left panel to select it
- Use playback controls to seek to the right moment
- Click "Set Now" for start/end time, or use Cmd+[ / Cmd+]
- **Shift following blocks**: In the Inspector > Block > Correction section, use "Set Start & Shift Following" to move this block and all subsequent blocks by the same delta
- **Fine-grained nudge**: Use +-0.1s / +-0.5s buttons to shift from the selected block onward
- **Anchor operations**: Mark a block as a user anchor (blue lock) so it becomes a reference point for piecewise correction. Auto-anchors (grey lock) from alignment can be promoted to user anchors
- **Piecewise correction**: Use "전체 앵커 구간 재보정" to redistribute timing between all user anchors, or "이전앵커~다음앵커 재보정" for the region surrounding the selected block
- **Local re-alignment**: Re-run whisper alignment on just the region between surrounding anchors using cached segments
- Manually adjusted blocks show a blue "Manual" badge; confidence is set to 1.0
- When both start and end of a block are manually adjusted, it automatically qualifies as a trusted anchor

### 5. Trim Video

In the Inspector > Trim tab:
- **Draggable trim handles** — Drag the green (start) or red (end) handle on the trim bar to visually adjust the trim range
- Set trim start and end times using "Set to Current" or +-0.1s / +-1s nudge buttons
- The trim bar shows a visual overview of the selected range (accent color indicator under scrubber)
- Playback respects the trim range: stops at trim end, loops to trim start when pressing play at the end
- "Reset Trim" restores the full video duration
- The trimmed duration is shown in the playback controls

### 6. Adjust Crop

In the Inspector > Crop tab:
- Adjust the horizontal offset slider (L-R) to position the vertical crop window
- Adjust the vertical offset slider (T-B) for vertical positioning
- Adjust the zoom slider (1x–3x) to zoom into the source video before cropping
- Click "Center H" / "Center V" to reset offsets, "Reset Zoom" to return to 1x
- The preview shows the 9:16 frame in real-time with cover-mode scaling

### 7. Style Subtitles

In the Inspector > Style tab:
- Choose Japanese and Korean font families independently (recommended CJK fonts listed first: Hiragino Sans, Hiragino Kaku Gothic ProN, Apple SD Gothic Neo, etc.)
- Adjust font sizes (JP: 24–120, KR: 20–100)
- Set per-language text colors using color pickers or preset swatches (White, Cyan, Yellow, Mint, Pink)
- Set outline width (0–8 px), toggle shadow
- Adjust bottom margin (50–960, up to screen center) and line spacing between Japanese/Korean lines
- **Style presets**: Save the current style as a named preset for reuse. Apply presets from the dropdown, or manage (rename, duplicate, delete) in the preset manager. Presets capture subtitle + overlay styling but not song-specific text
- Preview uses the same `SubtitleRenderer` as export — what you see is what you get

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
1. Trim and crop the video to 1080x1920 via FFmpeg (`-ss` seek + `-t` duration, H.264 CRF 18, fast preset, AAC 192k)
2. Remap lyric timing to trim-relative coordinates via `TrimTimingUtility` (blocks outside the range are omitted, overlapping blocks are clamped)
3. Pre-render all subtitle blocks as CGImages via `SubtitleRenderer` (multi-pass outline + shadow + fill)
4. Pre-render the metadata overlay as a single CGImage (composited onto every frame)
5. Read the cropped video frame-by-frame with AVAssetReader (32BGRA pixel format)
6. Composite metadata overlay + active subtitle images onto each frame using Core Graphics
7. Write the final MP4 with AVAssetWriter (H.264 + AAC 192k)
8. Audio is passed through on a background queue
9. Progress is shown in the bottom status bar

### 10. Save & Load

- **Save**: Click "Save" in the toolbar or Cmd+S. If no file exists yet, a Save As dialog appears
- **Open**: Click "Open" in the toolbar or Cmd+O to load a `.mreels` project file
- **Save As**: File > Save Project As (Cmd+Shift+S)
- All settings are preserved: lyrics, timing, crop, trim, subtitle style, metadata overlay, anchors, project title
- Auto-save directory: `~/Library/Application Support/MusicReelsGenerator/`

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
│   └── MusicReelsGeneratorApp     # @main, AppDelegate (key event monitor), window config
├── Models/
│   ├── Project                    # Root aggregate: video, metadata, blocks, styles, trim, overlay
│   ├── LyricBlock                 # JP+KR text, timing, confidence, isAnchor/isUserAnchor, manual flags
│   ├── VideoMetadata              # Dimensions, duration, FPS, file size, aspect ratio detection
│   ├── CropSettings               # 9:16 crop mode, H/V offsets (-1..1), zoom (1x-3x), output resolution (1080x1920)
│   ├── TrimSettings               # Trim in/out times, clamping, validation, duration
│   ├── SubtitleStyle              # Per-language fonts/sizes/colors (hex), outline, shadow, margins
│   ├── MetadataOverlaySettings    # Title/artist text, fonts, colors, background box, position/padding
│   ├── AlignmentQualityMode       # Recommended (production) + 3 experimental modes with parameters
│   └── StylePreset                # Reusable style snapshot (OverlayStyleSnapshot + SubtitleStyle)
├── Services/
│   ├── AudioExtractionService     # FFmpeg -> 16kHz mono PCM WAV
│   ├── WhisperAlignmentService    # Production: whisper-cpp + beam DP + drift detection + boundary snap
│   ├── AdvancedAlignmentService   # Experimental: Python subprocess integration, JSON I/O
│   ├── LyricsParserService        # Block-format bilingual parser (Japanese line, Korean line, blank)
│   ├── ExportService              # Two-stage: FFmpeg trim+crop -> AVFoundation frame-by-frame burn-in
│   ├── SubtitleRenderService      # ASS subtitle file generation with per-language styles
│   ├── VideoService               # AVFoundation metadata extraction (handles rotated videos)
│   ├── ProjectPersistenceService  # JSON save/load (.mreels), backward-compatible Decodable
│   └── StylePresetStore           # Singleton preset library, JSON persistence in App Support
├── ViewModels/
│   └── ProjectViewModel           # @MainActor ObservableObject: playback, alignment, anchors, export
├── Views/
│   ├── ContentView                # 3-panel HSplitView (lyrics | preview | inspector)
│   ├── LyricsPanelView            # Block list with confidence badges, anchor icons (blue/grey lock)
│   ├── VideoPreviewView           # AVPlayerLayer + crop offset + metadata overlay + subtitle overlay
│   ├── PlaybackControlsView       # Scrubber with trim indicator, play/pause, +-1s/+-5s, set timing
│   ├── InspectorPanelView         # 6 tabs: Block / Trim / Crop / Style / Overlay / Info
│   ├── ToolbarView                # Import, mode picker, Align, status badges, Export, Open, Save
│   └── StatusBarView              # Export progress bar, status message, dirty indicator
├── Utilities/
│   ├── SubtitleRenderer           # Shared Core Graphics renderer: renderBlock + renderMetadataOverlay
│   ├── ProcessRunner              # Async Process wrapper, deadlock-free pipe draining, stdin nullDevice
│   ├── NativeTextEditor           # NSTextView wrapper with proper Cmd+V/C/X/A/Z support
│   ├── JapaneseTextNormalizer     # Katakana->hiragana, Levenshtein distance, LCS similarity
│   ├── TrimTimingUtility          # Source-absolute -> trim-relative time conversion + block filtering
│   ├── TimeFormatter              # M:SS.CS, M:SS, H:MM:SS.CS (ASS) formats
│   ├── FontUtility                # System font enumeration, JP/KR recommended font lists
│   └── ColorExtension             # Hex (#RRGGBB) <-> SwiftUI Color conversion
└── Resources/                     # Info.plist, entitlements

Scripts/
├── alignment_pipeline.py          # Experimental Python alignment: G2P, DTW, chunking, DP
├── requirements.txt               # Python dependencies (openai-whisper, pykakasi, numpy)
└── setup_alignment.sh             # One-command setup for experimental pipeline
```

## How Alignment Works

### Production Pipeline (Recommended Mode)

The production alignment engine uses whisper-cpp for segment-level alignment with drift detection and boundary snap:

1. **Transcription** — whisper-cpp transcribes audio into sentence-level segments (~20–30 per song) with start/end timestamps via `--output-csv`

2. **Non-Speech Filtering** — Segments containing non-speech markers (`(拍手)`, `(音楽)`, `[Music]`, `[Applause]`, etc.) are identified and excluded from matching candidates. Fragment merging never combines speech with non-speech segments. This prevents instrumental/applause markers from polluting lyric timing

3. **Fragment Merging** — Very short segments (<0.3s) are merged with adjacent segments to reduce noise, respecting non-speech boundaries

4. **Vocal Onset Detection** — The first whisper segment's start time establishes the vocal onset boundary, preventing intro regions from attracting lyrics

5. **Position-Aware Candidate Generation** — For each lyric block, candidates are generated from segments within a 30s temporal search window around the expected position. Non-speech segments are skipped as starting points, and candidate combination stops at non-speech boundaries. Text similarity is scored via Levenshtein distance and LCS containment. Position is scored via Gaussian falloff from expected time. Combined score = textScore x 0.65 + positionScore x 0.35

6. **Monotonic Beam-Search DP** — Forward beam search (width 80) finds the globally optimal assignment of segments to blocks under strict monotonic constraint (segment indices must increase). Each block can be matched or skipped. Temporal continuity bonuses reward reasonable time gaps between consecutive matches

7. **Multi-Pass Refinement** — After the initial DP pass, low-confidence regions between anchors are re-aligned locally with tighter constraints and lower match thresholds (2 refinement passes)

8. **Drift Detection & Correction** — Scans for runs of 3+ consecutive weak blocks with consistent positional offset (>2s in the same direction). Detected drift regions are re-anchored against local segments, with results applied only if confidence improves

9. **Vocal Range-Aware Interpolation** — Detects vocal vs. instrumental time ranges from whisper segments. Unmatched blocks between anchors are distributed only into vocal ranges, with timing proportional to Japanese text character count. Blocks in purely instrumental gaps receive no timing, preventing subtitles from appearing during interludes

10. **Overlong Block Capping** — Post-processing step that trims blocks whose duration far exceeds their text length (~3.5 characters/second + 1.5s buffer). This prevents subtitles from lingering through instrumental sections when the alignment assigns overly long segments

11. **Boundary Snap** — Snaps block start/end times to the nearest whisper segment edge within 0.3s, aligning subtitle timing to actual speech onset/offset without changing which segment was matched

12. **Auto-Correction** — If user anchors (≥ 2) exist, automatically runs piecewise proportional redistribution between user anchor pairs after alignment completes

### Anchor System

The app distinguishes two types of anchors:

- **Auto-anchors** (grey lock icon) — Set by the alignment service on blocks with textScore ≥ 0.6. Used internally by the alignment service for reference during refinement and drift detection. Visible in the lyrics panel and inspector but not used for piecewise correction.

- **User anchors** (blue lock icon) — Set manually by the user via the inspector's anchor controls. These are the reference points for piecewise correction operations. Auto-anchors can be promoted to user anchors.

- **Trusted anchors** — Blocks that qualify as correction reference points: either user-anchored, or both start and end times manually adjusted. Used by `correctBetweenAllAnchors()` and `correctBetweenSurroundingAnchors()`.

### Experimental Pipelines (Exp: Segment / Refined / Hybrid)

Three experimental Python-based pipelines are available via `Scripts/alignment_pipeline.py` for A/B comparison. These are **not recommended for production** as they consistently underperform the production pipeline on singing audio.

**Exp: Segment** — Groups openai-whisper word-level timestamps into pseudo-segments, then applies position-aware Levenshtein matching (mirrors the production algorithm but using Python whisper instead of whisper-cpp)

**Exp: Refined** — Runs the segment baseline, then applies gated local DTW refinement. Refinement proposals must pass 7 validation gates before overwriting baseline results:
- Maximum start shift (0.40s) and end shift (0.60s)
- Minimum confidence gain (0.10)
- Duration sanity (0.2s–20s)
- Monotonic temporal ordering
- Maximum gap between adjacent blocks
- No regression in already-high-confidence blocks

**Exp: Hybrid** — Ungated character-level DTW alignment with VAD-based chunking, multi-window candidate scoring, and global monotonic DP. Includes collapse detection and recovery. Full pipeline details:
1. Word-level transcription via openai-whisper (`word_timestamps=True`)
2. Japanese G2P via pykakasi (kanji->kana, katakana->hiragana)
3. Character-level expansion (word timing distributed across kana characters)
4. Full-song banded DTW with asymmetric costs
5. VAD-based audio chunking at energy minima
6. Per-chunk DTW alignment against multiple candidate lyric windows
7. Global monotonic DP path selection
8. Collapse detection and re-anchoring with wider search

## How Export Works

The export pipeline uses a two-stage approach because Homebrew's FFmpeg lacks libass for direct subtitle rendering:

**Stage 1: FFmpeg Trim + Crop + Scale**
- Seeks to trim start (`-ss`) and limits duration (`-t`)
- Computes cover-mode scale factor: `max(targetW/srcW, targetH/srcH)`
- Scales and crops to 1080x1920 with user-defined H/V offset
- Encodes H.264 (CRF 18, fast preset) with AAC audio (192k)
- Dimensions rounded up to even numbers (H.264 requirement)
- Output: intermediate cropped MP4

**Stage 2: AVFoundation Frame-by-Frame Burn-In**
- Pre-renders all subtitle blocks as CGImages keyed by block UUID via `SubtitleRenderer.prerenderAll()`
- Pre-renders the metadata overlay as a single CGImage via `SubtitleRenderer.renderMetadataOverlay()`
- Lyric timing is remapped from source-absolute to trim-relative using `TrimTimingUtility.blocksForExport()` — blocks outside trim range are omitted, overlapping blocks are clamped
- Reads each video frame with AVAssetReader (kCVPixelFormatType_32BGRA)
- For each frame: creates CGContext from pixel buffer, draws metadata overlay image, finds active subtitle block by timestamp, draws subtitle image
- Writes composited frames with AVAssetWriter (H.264)
- Audio is read and written on a background DispatchQueue via separate AVAssetReaderTrackOutput/AVAssetWriterInput pair
- Progress reported via callback as fraction (0.0–1.0)

## How Preview/Export Consistency Works

Both preview and export use the same `SubtitleRenderer` — a shared Core Graphics rendering engine:

1. `SubtitleRenderer.renderBlock()` renders subtitle text at the canonical 1080x1920 export canvas
2. `SubtitleRenderer.renderMetadataOverlay()` renders the title/artist overlay with dark rounded background box at the same canvas
3. Font resolution uses `NSFontDescriptor` with `.family` attribute (not `NSFont(name:)` which requires PostScript names)
4. Japanese subtitle font gets bold trait via `NSFontManager.shared.convert(toHaveTrait: .boldFontMask)`
5. Multi-pass subtitle rendering: outline (offset grid from -outlineR to +outlineR) -> shadow (offset 2, -2) -> fill
6. Text layout: Korean at bottom margin, Japanese above with configurable line spacing gap
7. Preview displays the resulting CGImages scaled down to fit the preview container via `resizable(interpolation: .high)`
8. Export composites the same CGImages at full resolution onto video frames via CGContext drawing

This eliminates all mismatch between preview and export: same fonts, same outline, same wrapping, same positioning, same metadata overlay.

## Project File Format

Projects are saved as `.mreels` files (JSON with ISO 8601 dates, pretty-printed, sorted keys). They store:
- Project title, UUID, created/updated timestamps
- Source video path and cached metadata (width, height, duration, FPS, file size)
- Trim settings (start/end times)
- Crop settings (mode, horizontal/vertical offset, zoom level, output resolution)
- Subtitle style (per-language font families, sizes, text colors as hex, outline color/width, shadow, bottom margin, line spacing)
- Metadata overlay settings (enabled flag, title/artist text, fonts, colors, background box opacity/radius, position margins, padding, line spacing)
- All lyric blocks with: UUID, Japanese/Korean text, start/end times, confidence score, manual adjustment flags (per-boundary), isAnchor, isUserAnchor
- Style presets stored separately in `~/Library/Application Support/MusicReelsGenerator/style_presets.json`

Backward compatibility: older project files without `trimSettings`, `isAnchor`, `isUserAnchor`, `metadataOverlay`, per-language text color fields, or granular `manuallyAdjustedStart`/`manuallyAdjustedEnd` are handled via custom `Decodable` initializers that supply default values. Legacy single `textColorHex` is migrated to both `japaneseTextColorHex` and `koreanTextColorHex`. Legacy single `isManuallyAdjusted` is migrated to both per-boundary flags.

## Limitations

- One video per project
- Japanese speech recognition only (whisper language fixed to `ja`)
- Line-level subtitle output (character-level alignment is internal; no word-level karaoke display)
- Whisper alignment quality depends on audio clarity and vocal/accompaniment separation
- Frame-by-frame export is CPU-intensive (processes each video frame individually)
- Experimental pipeline requires Python 3 + ~2 GB of pip packages (torch, whisper)
- Whisper models are downloaded on first use (~1.5 GB for medium, ~3 GB for large-v3)
- No cloud sync or multi-device support
- Development build only (not packaged for App Store, no app sandbox)

## License

This project is licensed under the [MIT License](LICENSE).
