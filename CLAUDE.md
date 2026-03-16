# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
swift build                    # Compile to .build/debug/MusicReelsGenerator
./build.sh                     # Build + create .app bundle with Info.plist
open ".build/Music Reels Generator.app"  # Launch app bundle
```

The bare executable (`swift build` output) works for quick iteration but the `.app` bundle is required for proper window management and AVFoundation behavior.

**Dependencies** (no SPM packages — system frameworks only):
- FFmpeg, whisper-cpp: `./setup.sh`
- Python experimental pipeline: `cd Scripts && ./setup_alignment.sh`

## Architecture

**Single ViewModel pattern**: `ProjectViewModel` (@MainActor ObservableObject) owns all app state. Services are stateless — they take input, return output, no retained state. Views observe ProjectViewModel via `@EnvironmentObject`.

**Three-panel layout**: `ContentView` is an HSplitView — LyricsPanelView (left) | VideoPreviewView (center) | InspectorPanelView (right, 7 tabs: Block/Trim/Crop/Style/Overlay/Ignore/Info).

### Rendering Pipeline (Preview/Export Unification)

`SubtitleRenderer` is the single source of truth for all visual output. It renders at the canonical 1080×1920 export canvas using Core Graphics. Both preview and export use the same renderer:
- **Preview**: Renders at full resolution, displays scaled down via `resizable(interpolation: .high)`
- **Export**: Composites the same CGImages onto video frames via AVAssetReader/Writer

This eliminates preview/export mismatch. Any rendering change must go through SubtitleRenderer.

### Two-Stage Export

Homebrew FFmpeg lacks libass, so export is split:
1. **FFmpeg**: trim + crop + scale to 1080×1920 intermediate MP4
2. **AVFoundation**: frame-by-frame read → composite subtitle/overlay CGImages → write

### Dual Alignment Pipeline

Two completely separate alignment paths selected at runtime in `runAutoAlignment()`:
- **Production** (`WhisperAlignmentService`): whisper-cpp CLI → CSV parsing → position-aware beam-search DP (Swift). Language flag from `PrimaryLanguage` (ja/ko/en/auto). Ignore regions filter out segments before alignment. Cached segments enable fast local re-alignment.
- **Experimental** (`AdvancedAlignmentService`): Python subprocess → `Scripts/alignment_pipeline.py` → JSON I/O. Three sub-modes (Segment/Refined/Hybrid).

### Dual Anchor System

- **`isAnchor`**: Set by alignment service (textScore ≥ 0.6). Used for alignment internal logic. Grey lock icon.
- **`isUserAnchor`**: Set only by user via `setAnchor()`. Blue lock icon.
- **`isTrustedAnchor`** (computed): `isUserAnchor || (manuallyAdjustedStart && manuallyAdjustedEnd)`. Only trusted anchors are used for piecewise correction.

After alignment, `isUserAnchor` flags are restored because the alignment service overwrites `isAnchor` but doesn't know about user anchors.

### Language & Lyrics Model

`PrimaryLanguage` enum (ja/ko/en/auto) stored in `Project.primaryLanguage`. Determines the whisper `-l` flag; `auto` omits it for auto-detection.

`LyricBlock` has `japanese` and `korean` fields (legacy names kept for Codable backward compat). These are semantically "primary text" and "secondary text". Secondary text can be empty — the parser accepts 1-line blocks (primary only) or 2-line blocks (primary + secondary). `SubtitleRenderer` skips Line 2 rendering when `korean` is empty.

### Ignore Regions

`IgnoreRegion` (start/end/label) stored in `Project.ignoreRegions`. `WhisperAlignmentService.filterIgnoredSegments()` removes whisper segments overlapping any ignore region. Applied in `align()`, `realignRegion()`, and piecewise correction.

### Timing Coordinate Spaces

Three coordinate systems exist:
1. **Source-absolute**: Times in the original video (what user edits)
2. **Trim-relative**: After trim applied (trimStart becomes 0)
3. **Export-relative**: Written to final video

`TrimTimingUtility.blocksForExport()` converts source→export coordinates, clamping and filtering blocks.

### Subprocess Execution

`ProcessRunner` drains stdout/stderr on background threads continuously (not in terminationHandler) to prevent pipe-buffer deadlock on >64KB output. `standardInput` is set to `FileHandle.nullDevice` to prevent subprocesses hanging on stdin.

Two variants: `run()` (collect all output) and `runStreaming()` (line-by-line stderr for progress UI).

## Key Conventions

**Backward-compatible Codable**: All models use `decodeIfPresent` with `??` defaults. Legacy fields are migrated in custom `init(from:)` (e.g., single `isManuallyAdjusted` → granular `manuallyAdjustedStart`/`manuallyAdjustedEnd`; single `textColorHex` → per-language colors; missing `primaryLanguage` → `.japanese`; missing `ignoreRegions` → `[]`).

**Error handling**: Each service has its own `LocalizedError` enum. ProcessRunner failures are wrapped in service-level errors.

**Computed over cached state**: `currentBlock`, `selectedBlock`, `anchorCount`, `isTrimActive` are computed properties derived from `project`, not stored.

**App activation**: The app uses `NSApp.setActivationPolicy(.regular)` + `NSApp.activate()` because debug builds are bare executables, not proper .app bundles. A local NSEvent key monitor handles Cmd+V/C/X/A/Z because SwiftUI's Edit menu doesn't reliably connect to the responder chain.

## Gotchas

- Local re-alignment requires cached whisper segments from a prior full alignment run
- Export throws if trim range contains no lyric blocks with timing data
- Whisper model is searched across multiple fallback paths (homebrew, `~/.local/share/whisper-cpp/models/`, etc.)
- No app sandbox — required for launching external processes (FFmpeg, whisper-cpp, Python)
- Style presets persist separately from projects in `~/Library/Application Support/MusicReelsGenerator/style_presets.json`
- Piecewise correction weights by primary text (`japanese` field) character count (min 1 to avoid division by zero)
- `LyricBlock.japanese`/`korean` field names are kept for Codable backward compat — they mean "primary"/"secondary", not literally Japanese/Korean
- Non-speech segments (`(拍手)`, `[Music]`, etc.) are filtered from DP candidates and fragment merging to prevent instrumental markers from polluting lyric timing
