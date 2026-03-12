# Music Reels Generator

A macOS desktop app for generating vertical music lyric videos (Reels / Shorts) from an existing music video file and bilingual (Japanese + Korean) lyrics.

An example source video (`GreenlightsSerenade3.mp4`) is included in the repository for testing.

## Features

- **Video Import** — Load any local video file (.mp4, .mov, .avi), extract metadata (dimensions, duration, FPS, file size), preview in-app with AVPlayerLayer
- **Bilingual Lyrics Parser** — Paste Japanese + Korean lyrics in a simple block format (2 lines per block, blank line separator)
- **Dual Alignment Engine** — Two alignment pipelines with 4 quality modes:
  - **Fast** — whisper-cpp segment matching with position-aware beam-search DP
  - **Balanced / Accurate / Maximum** — Python-based character-level forced alignment with word-level whisper timestamps, banded DTW, VAD-based chunking, global monotonic DP, and collapse detection/recovery
- **Character-Level Forced Alignment** — Advanced modes convert lyrics to hiragana via G2P (pykakasi), expand whisper words to character-level timing, and align via banded DTW. Line boundaries are derived from character matches, not guessed from ASR segments
- **Vocal Separation** — Accurate/Maximum modes optionally use demucs to separate vocals from accompaniment before transcription, significantly improving recognition quality for music
- **Collapse Detection & Recovery** — Detects alignment degradation (sudden confidence drops, impossible durations, backwards time jumps) and re-anchors collapsed regions with wider search windows
- **Confidence Scoring** — Each block gets a 0–1 confidence score. Low-confidence blocks are visually flagged (orange border) for manual review. Interpolated blocks show ~0.05 confidence
- **Anchor System** — High-confidence matches (≥0.5 in advanced, ≥0.6 in legacy) and manually adjusted blocks become anchors. Unmatched blocks are interpolated proportionally between anchors based on kana text length
- **Manual Timing Correction** — Set start/end times from playback position, shift all following blocks by a delta, fine-grained nudge (±0.1s / ±0.5s), keyboard shortcuts (Cmd+[ / Cmd+])
- **Video Trimming** — Non-destructive trim in/out to cut intros, outros, or shorten the final reel. Trim range is enforced in preview playback (auto-stop at trim end, jump to trim start on play) and applied during export via FFmpeg seek
- **Vertical Reframing** — Crop any aspect ratio video to 9:16 with adjustable horizontal and vertical offset sliders. Cover-mode scaling ensures no black bars
- **Subtitle Styling** — Independent Japanese/Korean font family selection (with recommended CJK fonts: Hiragino Sans, Apple SD Gothic Neo, etc.), font size (JP: 24–120, KR: 20–100), per-language text color with color pickers and 5 preset swatches, outline width (0–8 px), shadow toggle, bottom margin (50–960, up to screen center), line spacing
- **Metadata Overlay** — Optional top-left title/artist overlay with dark rounded background box. Independent font, size, and color controls for title and artist. Configurable background opacity, corner radius, padding, and position margins
- **Unified Preview/Export Rendering** — Both preview and export use the same Core Graphics subtitle renderer (`SubtitleRenderer`), rendering at 1080×1920 canvas with multi-pass outline/shadow/fill. Preview displays a scaled-down version, ensuring pixel-identical typography
- **Two-Stage Export** — Stage 1: FFmpeg trim + crop/scale to 1080×1920 (H.264 CRF 18, AAC 192k). Stage 2: AVAssetReader/Writer frame-by-frame burn-in of metadata overlay + subtitle CGImage overlays
- **Project Persistence** — Save/load projects as `.mreels` JSON files with backward compatibility for older formats (missing fields get defaults via custom `Decodable` initializers)

## Requirements

- **macOS 14.0+** (Sonoma or later)
- **Xcode 15+** or Swift 5.9+ toolchain
- **FFmpeg** — audio extraction, video crop/scale/trim/encode

### For Fast mode (legacy)
- **whisper-cpp** — offline Japanese speech recognition (binary: `whisper-cli`)
- **Whisper model file** — e.g., `ggml-medium.bin` (~1.5 GB)

### For Balanced / Accurate / Maximum modes (advanced)
- **Python 3** — subprocess host for the alignment pipeline
- **openai-whisper** — word-level speech recognition with cross-attention timestamps
- **pykakasi** — Japanese kanji-to-kana G2P conversion
- **numpy** — audio energy analysis and array operations
- **demucs** (optional) — vocal stem separation for Accurate/Maximum modes

## Quick Setup

```bash
# Install FFmpeg and whisper-cpp (for Fast mode)
./setup.sh

# Install advanced alignment pipeline (for Balanced+ modes, recommended)
cd Scripts && ./setup_alignment.sh
```

`setup.sh` installs FFmpeg and whisper-cpp via Homebrew and downloads the whisper medium model.

`setup_alignment.sh` installs `openai-whisper`, `pykakasi`, `numpy`, and optionally `demucs`.

### Manual Setup

```bash
# FFmpeg (required)
brew install ffmpeg

# whisper-cpp (Fast mode only)
brew install whisper-cpp
mkdir -p ~/.local/share/whisper-cpp/models
curl -L "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin" \
  -o ~/.local/share/whisper-cpp/models/ggml-medium.bin

# Advanced pipeline (Balanced+ modes)
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
./setup.sh                           # Install FFmpeg, whisper-cpp
cd Scripts && ./setup_alignment.sh   # Install advanced pipeline
cd .. && ./build.sh                  # Build the app
open ".build/Music Reels Generator.app"
```

1. Import `GreenlightsSerenade3.mp4` from the project root
2. Paste bilingual lyrics (Japanese + Korean)
3. Select quality mode (Balanced recommended) and click "Auto-Align"
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

Select a quality mode from the toolbar dropdown, then click "Auto-Align". The toolbar shows status badges for FFmpeg (green/red), Whisper (green/red for whisper-cpp), and Advanced (green/red for Python pipeline).

**Quality Modes:**

| Mode | Pipeline | Whisper | Chunking | DTW | Collapse Detection | Beam Width |
|------|----------|---------|----------|-----|--------------------|------------|
| Fast | whisper-cpp (legacy) | segment-level | position-based windows | line-level text matching | refinement passes | 30 |
| Balanced | Python (advanced) | word-level (medium) | VAD energy-based, 15s target | character-level banded DTW | yes, 1 recovery pass | 80 |
| Accurate | Python (advanced) | word-level (large-v3) + vocal separation | VAD energy-based, 12s target | character-level banded DTW | yes, 2 recovery passes | 200 |
| Maximum | Python (advanced) | word-level (large-v3) + vocal separation | VAD energy-based, 10s target | character-level banded DTW | yes, 3 recovery passes | 500 |

**Fast mode pipeline:**
1. Extract audio as 16kHz mono WAV (FFmpeg)
2. Transcribe with whisper-cpp (`--output-csv`, sentence-level segments)
3. Merge short fragments (<0.3s)
4. Position-aware candidate generation with windowed search
5. Monotonic beam-search DP assignment
6. Multi-pass refinement of low-confidence regions
7. Anchor-based proportional interpolation

**Advanced pipeline (Balanced+):**
1. Extract audio as 16kHz mono WAV (FFmpeg)
2. Optional vocal separation via demucs (Accurate/Maximum)
3. Transcribe with openai-whisper Python (`word_timestamps=True`, cross-attention weights)
4. Convert Japanese lyrics to hiragana via G2P (pykakasi kanji→kana, katakana→hiragana, punctuation removal)
5. Expand whisper words to character-level timing (proportional distribution within each word)
6. Full-song character-level banded DTW as baseline alignment
7. VAD-based chunking at low-energy boundaries (RMS energy analysis, independent of lyric timestamps)
8. Per-chunk character-level DTW alignment against multiple candidate lyric windows
9. Global monotonic DP to select best path across all chunks (continuity bonuses, gap penalties)
10. Collapse detection (sudden confidence drops, impossible durations, backwards time jumps, large gaps)
11. Re-anchoring of collapsed regions with wider search windows
12. Line timing reconstruction from first/last matched character per line
13. Proportional interpolation for remaining unmatched lines by kana length

### 4. Fix Timing

- Click a lyric block in the left panel to select it
- Use playback controls to seek to the right moment
- Click "Set Now" for start/end time, or use Cmd+[ / Cmd+]
- **Shift following blocks**: In the Inspector > Block > Correction section, use "Set Start & Shift Following" to move this block and all subsequent blocks by the same delta
- **Fine-grained nudge**: Use ±0.1s / ±0.5s buttons to shift from the selected block onward
- **Anchor toggle**: Mark a block as an anchor so it stays fixed during re-alignment
- Manually adjusted blocks show a blue "Manual" badge; confidence is set to 1.0

### 5. Trim Video

In the Inspector > Trim tab:
- Set trim start and end times using "Set to Current" or ±0.1s / ±1s nudge buttons
- The trim bar shows a visual overview of the selected range (accent color indicator under scrubber)
- Playback respects the trim range: stops at trim end, jumps to trim start when pressing play
- "Reset Trim" restores the full video duration
- The trimmed duration is shown in the playback controls

### 6. Adjust Crop

In the Inspector > Crop tab:
- Adjust the horizontal offset slider (L–R) to position the vertical crop window
- Adjust the vertical offset slider (T–B) for vertical positioning
- Click "Center H" / "Center V" to reset
- The preview shows the 9:16 frame in real-time with cover-mode scaling

### 7. Style Subtitles

In the Inspector > Style tab:
- Choose Japanese and Korean font families independently (recommended CJK fonts listed first: Hiragino Sans, Hiragino Kaku Gothic ProN, Apple SD Gothic Neo, etc.)
- Adjust font sizes (JP: 24–120, KR: 20–100)
- Set per-language text colors using color pickers or preset swatches (White, Cyan, Yellow, Mint, Pink)
- Set outline width (0–8 px), toggle shadow
- Adjust bottom margin (50–960, up to screen center) and line spacing between Japanese/Korean lines
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
1. Trim and crop the video to 1080×1920 via FFmpeg (`-ss` seek + `-t` duration, H.264 CRF 18, fast preset, AAC 192k)
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
- All settings are preserved: lyrics, timing, crop, trim, subtitle style, metadata overlay, project title
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
│   └── MusicReelsGeneratorApp     # @main, window config (1100×700 min), menu commands
├── Models/
│   ├── Project                    # Root aggregate: video, metadata, blocks, styles, trim, overlay
│   ├── LyricBlock                 # Japanese + Korean text, timing, confidence, anchor/manual flags
│   ├── VideoMetadata              # Dimensions, duration, FPS, file size, aspect ratio detection
│   ├── CropSettings               # 9:16 crop mode, H/V offsets (-1..1), output resolution (1080×1920)
│   ├── TrimSettings               # Trim in/out times, clamping, validation, duration
│   ├── SubtitleStyle              # Per-language fonts/sizes/colors (hex), outline, shadow, margins
│   ├── MetadataOverlaySettings    # Title/artist text, fonts, colors, background box, position/padding
│   └── AlignmentQualityMode       # Fast/Balanced/Accurate/Maximum with tuned parameters per mode
├── Services/
│   ├── AudioExtractionService     # FFmpeg → 16kHz mono PCM WAV
│   ├── WhisperAlignmentService    # Legacy: whisper-cpp transcription + position-aware beam DP (830 lines)
│   ├── AdvancedAlignmentService   # Advanced: Python subprocess integration, JSON I/O, debug reporting
│   ├── LyricsParserService        # Block-format bilingual parser (Japanese line, Korean line, blank)
│   ├── ExportService              # Two-stage: FFmpeg trim+crop → AVFoundation frame-by-frame burn-in
│   ├── SubtitleRenderService      # ASS subtitle file generation with per-language styles
│   ├── VideoService               # AVFoundation metadata extraction (handles rotated videos)
│   └── ProjectPersistenceService  # JSON save/load (.mreels), backward-compatible Decodable
├── ViewModels/
│   └── ProjectViewModel           # @MainActor ObservableObject: playback, alignment, export, persistence
├── Views/
│   ├── ContentView                # 3-panel HSplitView (lyrics | preview | inspector)
│   ├── LyricsPanelView            # Block list with confidence badges (green/orange/red/blue), lyrics input
│   ├── VideoPreviewView           # AVPlayerLayer + crop offset + metadata overlay + subtitle overlay
│   ├── PlaybackControlsView       # Scrubber with trim indicator, play/pause, ±1s/±5s, set timing
│   ├── InspectorPanelView         # 6 tabs: Block / Trim / Crop / Style / Overlay / Info
│   ├── ToolbarView                # Import, mode picker, Align, status badges, Export, Open, Save
│   └── StatusBarView              # Export progress bar, status message, dirty indicator
├── Utilities/
│   ├── SubtitleRenderer           # Shared Core Graphics renderer: renderBlock + renderMetadataOverlay
│   ├── ProcessRunner              # Async Process wrapper, findFFmpeg/findWhisper/findPython
│   ├── JapaneseTextNormalizer     # Katakana→hiragana, Levenshtein distance, LCS similarity
│   ├── TrimTimingUtility          # Source-absolute → trim-relative time conversion + block filtering
│   ├── TimeFormatter              # M:SS.CS, M:SS, H:MM:SS.CS (ASS) formats
│   ├── FontUtility                # System font enumeration, JP/KR recommended font lists
│   └── ColorExtension             # Hex (#RRGGBB) ↔ SwiftUI Color conversion
└── Resources/                     # Info.plist, entitlements

Scripts/
├── alignment_pipeline.py          # Python forced alignment: G2P, DTW, chunking, DP, collapse recovery
├── requirements.txt               # Python dependencies (openai-whisper, pykakasi, numpy)
└── setup_alignment.sh             # One-command setup for advanced pipeline
```

## How Alignment Works

### Legacy Pipeline (Fast Mode)

The Fast mode uses whisper-cpp for segment-level alignment:

1. **Transcription** — whisper-cpp transcribes audio into sentence-level segments (~20–30 per song) with start/end timestamps via `--output-csv`

2. **Fragment Merging** — Very short segments (<0.3s) are merged with adjacent segments to reduce noise

3. **Vocal Onset Detection** — The first whisper segment's start time establishes the vocal onset boundary, preventing intro regions from attracting lyrics

4. **Position-Aware Candidate Generation** — For each lyric block, candidates are generated from segments within a temporal search window around the expected position. Text similarity is scored via Levenshtein distance and LCS containment. Position is scored via Gaussian falloff from expected time. Combined score = textScore × (1 - positionWeight) + positionScore × positionWeight

5. **Monotonic Beam-Search DP** — Forward beam search finds the globally optimal assignment of segments to blocks under strict monotonic constraint (segment indices must increase). Each block can be matched or skipped. Temporal continuity bonuses reward reasonable time gaps between consecutive matches

6. **Multi-Pass Refinement** — After the initial DP pass, low-confidence regions between anchors are re-aligned locally with tighter constraints and lower match thresholds

7. **Anchor-Based Proportional Interpolation** — Unmatched blocks between anchors receive timing proportional to their Japanese text character count. Uses vocal onset (not 0:00) as the earliest valid start boundary

### Advanced Pipeline (Balanced / Accurate / Maximum)

The advanced pipeline uses character-level forced alignment via a Python subprocess (`Scripts/alignment_pipeline.py`):

1. **Word-Level Transcription** — openai-whisper (Python) transcribes with `word_timestamps=True`, producing per-word timing via cross-attention weights. Parameters tuned for singing: `no_speech_threshold=0.3`, `compression_ratio_threshold=2.4`, `initial_prompt="日本語の歌詞。"`. Yields ~200–500 words per song (~10–25× more data points than segment-level)

2. **Optional Vocal Separation** — In Accurate/Maximum modes, demucs (`--two-stems vocals`) separates vocals from accompaniment before transcription. Falls back gracefully if demucs is unavailable

3. **Japanese G2P** — Lyrics are converted to hiragana:
   - pykakasi converts kanji → kana (e.g., 時を越えて → ときをこえて)
   - Katakana → hiragana via Unicode scalar offset (U+30A1–U+30F6 → U+3041–U+3096)
   - Punctuation, prolonged sound marks, full-width characters removed
   - Falls back to character-level matching if pykakasi unavailable

4. **Character-Level Expansion** — Each whisper word's timing is distributed proportionally across its kana characters. A word "ときを" spanning 1.0–1.5s becomes: と(1.0–1.17), き(1.17–1.33), を(1.33–1.5)

5. **Full-Song Banded DTW** — The whisper character stream is aligned to the concatenated lyrics character stream using banded DTW with asymmetric costs:
   - Match: 0.0, Mismatch: 1.0
   - Delete (skip whisper char): 0.5 (whisper may have extra content)
   - Insert (skip lyric char): 1.2 (missing lyric characters are penalized more)
   - Band constraint: Sakoe-Chiba band limits search to O(n × band) instead of O(n × m)
   - Auto-widening: if band is too narrow to reach (n,m), band ratio doubles and retries

6. **VAD-Based Chunking** — Audio RMS energy is computed in 25ms frames with 10ms hop, smoothed with 500ms moving average. Local energy minima are identified as candidate chunk boundaries. Boundaries are selected to target chunk sizes (8–25s depending on mode) with 1s overlap. Chunk boundaries are independent of predicted lyric timestamps

7. **Multi-Window Candidate Scoring** — Each chunk is scored against multiple candidate lyric windows (3–10 depending on mode) around the expected lyric cursor position. For each candidate: character-level DTW alignment, match ratio computation, position bonus, and per-line timing extraction

8. **Global Monotonic DP** — Beam search DP across all chunks selects the globally optimal assignment of lyric windows to audio chunks:
   - Monotonic constraint: lyric windows must progress forward (small overlap allowed for recovery)
   - Scoring: alignment quality + continuity bonus (sequential progression) + temporal continuity - skip penalty - gap penalty
   - Deduplication by lyric cursor position within beam

9. **Baseline Merge** — Chunk-based results are merged with the full-song DTW baseline. Per-line, the higher-confidence result is kept

10. **Collapse Detection** — Scans for degraded regions:
    - 3+ consecutive lines with confidence below threshold (0.15–0.3 depending on mode)
    - Lines with duration <0.2s or >20s
    - Time gaps >10s between adjacent lines
    - Time going backwards (start < previous start)

11. **Recovery** — Collapsed regions are re-aligned with wider DTW band (2× normal) using words from the time range between surrounding anchors. Multiple recovery passes in higher modes

12. **Line Reconstruction** — Final line start/end times = timestamp of first/last DTW-matched character belonging to each line. Confidence = weighted combination of exact match ratio (60%) and coverage ratio (40%)

13. **Proportional Interpolation** — Remaining unmatched lines get timing distributed proportionally by kana character count between surrounding anchored lines

14. **Ordering Fix** — Final pass corrects any temporal ordering violations (backward time jumps) by adjusting the lower-confidence line

15. **Debug Reporting** — Per-region metrics (0–10%, 10–20%, ... 90–100%): mean confidence, anchor count, forced/recovered/interpolated/unmatched counts, collapse count. Full chunk report with chosen windows and alignment scores

## How Export Works

The export pipeline uses a two-stage approach because Homebrew's FFmpeg lacks libass for direct subtitle rendering:

**Stage 1: FFmpeg Trim + Crop + Scale**
- Seeks to trim start (`-ss`) and limits duration (`-t`)
- Computes cover-mode scale factor: `max(targetW/srcW, targetH/srcH)`
- Scales and crops to 1080×1920 with user-defined H/V offset
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

1. `SubtitleRenderer.renderBlock()` renders subtitle text at the canonical 1080×1920 export canvas
2. `SubtitleRenderer.renderMetadataOverlay()` renders the title/artist overlay with dark rounded background box at the same canvas
3. Font resolution uses `NSFontDescriptor` with `.family` attribute (not `NSFont(name:)` which requires PostScript names)
4. Japanese subtitle font gets bold trait via `NSFontManager.shared.convert(toHaveTrait: .boldFontMask)`
5. Multi-pass subtitle rendering: outline (offset grid from -outlineR to +outlineR) → shadow (offset 2, -2) → fill
6. Text layout: Korean at bottom margin, Japanese above with configurable line spacing gap
7. Preview displays the resulting CGImages scaled down to fit the preview container via `resizable(interpolation: .high)`
8. Export composites the same CGImages at full resolution onto video frames via CGContext drawing

This eliminates all mismatch between preview and export: same fonts, same outline, same wrapping, same positioning, same metadata overlay.

## Project File Format

Projects are saved as `.mreels` files (JSON with ISO 8601 dates, pretty-printed, sorted keys). They store:
- Project title, UUID, created/updated timestamps
- Source video path and cached metadata (width, height, duration, FPS, file size)
- Trim settings (start/end times)
- Crop settings (mode, horizontal/vertical offset, output resolution)
- Subtitle style (per-language font families, sizes, text colors as hex, outline color/width, shadow, bottom margin, line spacing)
- Metadata overlay settings (enabled flag, title/artist text, fonts, colors, background box opacity/radius, position margins, padding, line spacing)
- All lyric blocks with: UUID, Japanese/Korean text, start/end times, confidence score, isManuallyAdjusted flag, isAnchor flag

Backward compatibility: older project files without `trimSettings`, `isAnchor`, `metadataOverlay`, or per-language text color fields are handled via custom `Decodable` initializers that supply default values. Legacy single `textColorHex` is migrated to both `japaneseTextColorHex` and `koreanTextColorHex`.

## Limitations

- One video per project
- Japanese speech recognition only (whisper language fixed to `ja`)
- Line-level subtitle output (character-level alignment is internal; no word-level karaoke display)
- Whisper alignment quality depends on audio clarity and vocal/accompaniment separation
- Frame-by-frame export is CPU-intensive (processes each video frame individually)
- Advanced pipeline requires Python 3 + ~2 GB of pip packages (torch, whisper)
- Whisper models are downloaded on first use (~1.5 GB for medium, ~3 GB for large-v3)
- No cloud sync or multi-device support
- Development build only (not packaged for App Store, no app sandbox)
