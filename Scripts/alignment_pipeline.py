#!/usr/bin/env python3
"""
Advanced Forced Alignment Pipeline for Japanese Lyrics
------------------------------------------------------
Called by Music Reels Generator app as a subprocess.

Pipeline:
  1. Audio preprocessing (optional vocal separation via demucs)
  2. VAD-based chunking with low-energy boundary detection
  3. Whisper transcription with word-level timestamps
  4. Japanese G2P normalization (kanji -> kana)
  5. Character-level DTW alignment between transcript and lyrics
  6. Multi-window candidate scoring per chunk
  7. Global monotonic DP path selection
  8. Collapse detection and re-anchoring
  9. Line timing reconstruction from character-level alignment
  10. Debug report generation

Usage:
    python3 alignment_pipeline.py \
        --audio /path/to/audio.wav \
        --lyrics /path/to/lyrics.json \
        --mode balanced \
        --output /path/to/result.json

Dependencies:
    Required:  openai-whisper (brings torch, numpy)
    Optional:  pykakasi (kanji->kana), demucs (vocal separation)
"""

# Fix SSL certificate issue on macOS Python installations
import os
import ssl
try:
    import certifi
    os.environ.setdefault('SSL_CERT_FILE', certifi.where())
    ssl._create_default_https_context = ssl.create_default_context
except ImportError:
    pass

import argparse
import json
import sys
import os
import subprocess
import tempfile
import wave
import struct
import math
import time as time_module
from dataclasses import dataclass, field, asdict
from typing import List, Optional, Tuple, Dict, Any


# ============================================================
# Progress / debug helpers
# ============================================================

def progress(msg):
    print(f"[PROGRESS] {msg}", file=sys.stderr, flush=True)

def debug(msg):
    print(f"[DEBUG] {msg}", file=sys.stderr, flush=True)

def error_exit(msg):
    result = {"error": msg, "lines": []}
    json.dump(result, sys.stdout)
    sys.exit(1)


# ============================================================
# Dependency checking
# ============================================================

def check_dependencies(mode):
    missing = []
    try:
        import whisper  # noqa: F401
    except ImportError:
        missing.append("openai-whisper")
    try:
        import numpy  # noqa: F401
    except ImportError:
        missing.append("numpy")
    if missing:
        error_exit(
            f"Missing required packages: {', '.join(missing)}. "
            f"Install with: pip3 install {' '.join(missing)}"
        )


# ============================================================
# Data classes
# ============================================================

@dataclass
class Word:
    text: str
    start: float
    end: float
    probability: float = 1.0
    kana: str = ""  # hiragana-normalized form

@dataclass
class LyricLine:
    index: int
    japanese: str
    korean: str
    kana: str = ""  # hiragana-normalized form

@dataclass
class CharTiming:
    char: str
    start: float
    end: float
    word_idx: int = -1

@dataclass
class AlignedLine:
    index: int
    start_time: float
    end_time: float
    confidence: float
    is_anchor: bool
    method: str  # forced, interpolated, recovered, unmatched

@dataclass
class Chunk:
    index: int
    start_time: float
    end_time: float
    word_indices: List[int] = field(default_factory=list)

@dataclass
class CandidateWindow:
    line_start: int  # inclusive lyric line index
    line_end: int    # exclusive lyric line index
    alignment_score: float = 0.0
    char_match_ratio: float = 0.0
    line_timings: List[AlignedLine] = field(default_factory=list)


# ============================================================
# Mode configuration
# ============================================================

MODE_CONFIG = {
    'fast': {
        'use_vocal_separation': False,
        'chunk_target_seconds': 20,
        'chunk_min_seconds': 10,
        'chunk_max_seconds': 35,
        'beam_width': 30,
        'max_candidate_windows': 3,
        'window_overlap_lines': 2,
        'enable_collapse_detection': False,
        'dtw_band_ratio': 0.3,
        'whisper_model': 'base',
        'collapse_threshold': 0.15,
        'recovery_passes': 0,
    },
    'balanced': {
        'use_vocal_separation': False,
        'chunk_target_seconds': 15,
        'chunk_min_seconds': 8,
        'chunk_max_seconds': 25,
        'beam_width': 80,
        'max_candidate_windows': 5,
        'window_overlap_lines': 3,
        'enable_collapse_detection': True,
        'dtw_band_ratio': 0.25,
        'whisper_model': 'medium',
        'collapse_threshold': 0.2,
        'recovery_passes': 1,
    },
    'accurate': {
        'use_vocal_separation': True,
        'chunk_target_seconds': 12,
        'chunk_min_seconds': 8,
        'chunk_max_seconds': 20,
        'beam_width': 200,
        'max_candidate_windows': 7,
        'window_overlap_lines': 4,
        'enable_collapse_detection': True,
        'dtw_band_ratio': 0.2,
        'whisper_model': 'large-v3',
        'collapse_threshold': 0.25,
        'recovery_passes': 2,
    },
    'maximum': {
        'use_vocal_separation': True,
        'chunk_target_seconds': 10,
        'chunk_min_seconds': 8,
        'chunk_max_seconds': 20,
        'beam_width': 500,
        'max_candidate_windows': 10,
        'window_overlap_lines': 5,
        'enable_collapse_detection': True,
        'dtw_band_ratio': 0.15,
        'whisper_model': 'large-v3',
        'collapse_threshold': 0.3,
        'recovery_passes': 3,
    },
}


# ============================================================
# Japanese text normalization / G2P
# ============================================================

def katakana_to_hiragana(text):
    """Convert katakana to hiragana."""
    result = []
    for ch in text:
        cp = ord(ch)
        if 0x30A1 <= cp <= 0x30F6:
            result.append(chr(cp - 0x60))
        else:
            result.append(ch)
    return ''.join(result)


def normalize_japanese(text):
    """Normalize Japanese text: remove punctuation, katakana->hiragana."""
    remove_chars = set(
        "。、！？「」『』（）…・　.,!?\"' \t\n♪～〜()[]【】―—-♫♩※×ー"
    )
    result = ''.join(ch for ch in text if ch not in remove_chars)
    result = katakana_to_hiragana(result)

    # Full-width -> half-width digits and letters
    normalized = []
    for ch in result:
        cp = ord(ch)
        if 0xFF10 <= cp <= 0xFF19:  # full-width digits
            normalized.append(chr(cp - 0xFEE0))
        elif 0xFF21 <= cp <= 0xFF3A:  # full-width upper
            normalized.append(chr(cp - 0xFEE0))
        elif 0xFF41 <= cp <= 0xFF5A:  # full-width lower
            normalized.append(chr(cp - 0xFEE0))
        else:
            normalized.append(ch)

    return ''.join(normalized).lower()


_kakasi = None

def kanji_to_kana(text):
    """Convert kanji to hiragana using pykakasi if available."""
    global _kakasi
    try:
        import pykakasi
        if _kakasi is None:
            _kakasi = pykakasi.kakasi()
        items = _kakasi.convert(text)
        return ''.join(item['hira'] for item in items)
    except ImportError:
        # Fallback: just normalize without kanji conversion
        return normalize_japanese(text)
    except Exception:
        return normalize_japanese(text)


def text_to_kana(text):
    """Full G2P pipeline: text -> normalized hiragana."""
    # First try kanji->kana conversion
    kana = kanji_to_kana(text)
    # Then normalize (remove punctuation, katakana->hiragana)
    return normalize_japanese(kana)


# ============================================================
# Audio I/O
# ============================================================

def read_wav_energy(path, frame_ms=25, hop_ms=10):
    """Read WAV file and compute frame-level RMS energy."""
    import numpy as np

    with wave.open(path, 'rb') as wf:
        sr = wf.getframerate()
        n_channels = wf.getnchannels()
        sampwidth = wf.getsampwidth()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)

    if sampwidth == 2:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0
    elif sampwidth == 4:
        samples = np.frombuffer(raw, dtype=np.int32).astype(np.float32) / 2147483648.0
    else:
        samples = np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0

    if n_channels > 1:
        samples = samples.reshape(-1, n_channels).mean(axis=1)

    frame_len = int(frame_ms / 1000.0 * sr)
    hop_len = int(hop_ms / 1000.0 * sr)
    duration = len(samples) / sr

    rms = []
    for i in range(0, len(samples) - frame_len, hop_len):
        frame = samples[i:i + frame_len]
        rms.append(float(np.sqrt(np.mean(frame ** 2))))

    return rms, sr, hop_ms / 1000.0, duration


# ============================================================
# VAD-based chunking
# ============================================================

def create_chunks_from_energy(
    rms, hop_seconds, total_duration,
    target_seconds=15, min_seconds=8, max_seconds=25,
    overlap_seconds=1.0
):
    """
    Create audio chunks at low-energy boundaries.
    Boundaries come from vocal energy, not from predicted lyric timestamps.
    """
    import numpy as np
    rms = np.array(rms)

    # Smooth energy with moving average
    window = max(1, int(0.5 / hop_seconds))  # 500ms window
    if len(rms) > window:
        kernel = np.ones(window) / window
        smoothed = np.convolve(rms, kernel, mode='same')
    else:
        smoothed = rms

    # Find local energy minima (candidate boundaries)
    search_radius = max(1, int(1.0 / hop_seconds))  # 1 second radius
    minima = []
    for i in range(search_radius, len(smoothed) - search_radius):
        local = smoothed[max(0, i - search_radius):i + search_radius + 1]
        if smoothed[i] <= np.min(local) + 1e-6:
            t = i * hop_seconds
            minima.append((t, float(smoothed[i])))

    # Sort minima by energy (prefer quieter boundaries)
    minima.sort(key=lambda x: x[1])

    # Greedily select boundaries that create valid chunk sizes
    boundaries = [0.0]
    used_times = {0.0}

    for t, energy in minima:
        if t <= 2.0 or t >= total_duration - 2.0:
            continue
        # Check that this boundary creates valid chunks with neighbors
        valid = True
        for bt in sorted(used_times):
            dist = abs(t - bt)
            if dist < min_seconds:
                valid = False
                break
        if valid:
            used_times.add(t)
            boundaries.append(t)

    boundaries.append(total_duration)
    boundaries.sort()

    # Merge chunks that are too small, split chunks that are too large
    final_boundaries = [boundaries[0]]
    for i in range(1, len(boundaries)):
        chunk_dur = boundaries[i] - final_boundaries[-1]
        if chunk_dur < min_seconds and i < len(boundaries) - 1:
            continue  # skip this boundary (merge with next)
        elif chunk_dur > max_seconds:
            # Split at midpoint or nearest minimum
            mid = (final_boundaries[-1] + boundaries[i]) / 2
            best_split = mid
            best_energy = float('inf')
            for t, e in minima:
                if final_boundaries[-1] + min_seconds < t < boundaries[i] - min_seconds:
                    if abs(t - mid) < max_seconds / 2 and e < best_energy:
                        best_split = t
                        best_energy = e
            final_boundaries.append(best_split)
        final_boundaries.append(boundaries[i])

    # Remove duplicates and sort
    final_boundaries = sorted(set(final_boundaries))

    # Create chunk objects
    chunks = []
    for i in range(len(final_boundaries) - 1):
        start = max(0, final_boundaries[i] - overlap_seconds if i > 0 else 0)
        end = min(total_duration, final_boundaries[i + 1] + overlap_seconds
                  if i < len(final_boundaries) - 2 else total_duration)
        chunks.append(Chunk(index=i, start_time=start, end_time=end))

    if not chunks:
        chunks = [Chunk(index=0, start_time=0, end_time=total_duration)]

    return chunks


# ============================================================
# Vocal separation (demucs)
# ============================================================

def separate_vocals(audio_path, output_dir):
    """
    Use demucs to separate vocals from accompaniment.
    Returns path to vocal stem WAV, or None if demucs unavailable.
    """
    # Check if demucs CLI is available
    demucs_bin = None
    for path in ['/opt/homebrew/bin/demucs', '/usr/local/bin/demucs']:
        if os.path.exists(path):
            demucs_bin = path
            break
    if demucs_bin is None:
        try:
            result = subprocess.run(['which', 'demucs'], capture_output=True, text=True)
            if result.returncode == 0:
                demucs_bin = result.stdout.strip()
        except Exception:
            pass

    if demucs_bin is None:
        # Try running as Python module
        try:
            result = subprocess.run(
                [sys.executable, '-m', 'demucs', '--help'],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                demucs_bin = 'module'
        except Exception:
            pass

    if demucs_bin is None:
        debug("Demucs not found, skipping vocal separation")
        return None

    progress("Separating vocals with demucs (this may take a few minutes)...")

    try:
        if demucs_bin == 'module':
            cmd = [sys.executable, '-m', 'demucs']
        else:
            cmd = [demucs_bin]

        cmd += [
            '--two-stems', 'vocals',
            '-o', output_dir,
            '--filename', '{stem}.{ext}',
            audio_path
        ]

        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600
        )

        if result.returncode != 0:
            debug(f"Demucs failed: {result.stderr[:500]}")
            return None

        # Find the vocal output
        vocals_path = os.path.join(output_dir, 'htdemucs', 'vocals.wav')
        if not os.path.exists(vocals_path):
            # Try alternative paths
            for root, dirs, files in os.walk(output_dir):
                for f in files:
                    if 'vocal' in f.lower() and f.endswith('.wav'):
                        vocals_path = os.path.join(root, f)
                        break

        if os.path.exists(vocals_path):
            progress("Vocal separation complete.")
            return vocals_path
        else:
            debug("Vocal stem not found in demucs output")
            return None

    except subprocess.TimeoutExpired:
        debug("Demucs timed out after 10 minutes")
        return None
    except Exception as e:
        debug(f"Demucs error: {e}")
        return None


# ============================================================
# Whisper transcription with word-level timestamps
# ============================================================

def transcribe_with_words(audio_path, model_size='medium', whisper_model_override=None):
    """
    Transcribe audio using openai-whisper with word-level timestamps.
    Returns list of Word objects with per-word timing.
    """
    import whisper
    import numpy as np

    # Determine model to load
    if whisper_model_override:
        model_name = whisper_model_override
    else:
        model_name = model_size

    progress(f"Loading whisper model '{model_name}'...")
    model = whisper.load_model(model_name)

    progress("Transcribing with word-level timestamps...")
    result = model.transcribe(
        audio_path,
        language="ja",
        word_timestamps=True,
        condition_on_previous_text=True,
        initial_prompt="日本語の歌詞。",
        no_speech_threshold=0.3,
        compression_ratio_threshold=2.4,
        logprob_threshold=-1.0,
    )

    words = []
    for segment in result.get("segments", []):
        for w in segment.get("words", []):
            text = w.get("word", "").strip()
            if not text:
                continue
            words.append(Word(
                text=text,
                start=w["start"],
                end=w["end"],
                probability=w.get("probability", 1.0),
            ))

    progress(f"Transcribed {len(words)} words.")

    # Convert words to kana
    for w in words:
        w.kana = text_to_kana(w.text)

    return words


# ============================================================
# Character-level DTW alignment
# ============================================================

def expand_words_to_chars(words):
    """
    Expand words into character-level timing.
    Each character within a word gets proportional timing.
    """
    chars = []
    for wi, w in enumerate(words):
        kana = w.kana
        if not kana:
            continue
        n = len(kana)
        dur = w.end - w.start
        char_dur = dur / max(n, 1)
        for ci, ch in enumerate(kana):
            chars.append(CharTiming(
                char=ch,
                start=w.start + ci * char_dur,
                end=w.start + (ci + 1) * char_dur,
                word_idx=wi,
            ))
    return chars


def banded_dtw(seq1, seq2, band_ratio=0.2, match_cost=0.0, mismatch_cost=1.0,
               delete_cost=0.5, insert_cost=1.2):
    """
    Banded DTW alignment between two character sequences.

    Returns: (total_cost, alignment_path)
    alignment_path = list of (i, j) pairs where seq1[i] matched seq2[j]

    Band constraint ensures O(n * band) time instead of O(n * m).
    Asymmetric costs:
      - delete (skip seq1 char) = 0.5  (whisper may have extra text)
      - insert (skip seq2 char) = 1.2  (missing lyric char is worse)
    """
    n = len(seq1)
    m = len(seq2)
    if n == 0 or m == 0:
        return float('inf'), []

    band = max(int(max(n, m) * band_ratio), abs(n - m) + 10, 20)

    INF = float('inf')
    # dp[i][j] = cost to align seq1[:i] to seq2[:j]
    # Use dict for sparse storage within band
    dp = {}
    dp[(0, 0)] = 0.0

    # Fill first column (deletions from seq1)
    for i in range(1, n + 1):
        if i <= band:
            dp[(i, 0)] = i * delete_cost

    # Fill first row (insertions into seq2)
    for j in range(1, m + 1):
        if j <= band:
            dp[(0, j)] = j * insert_cost

    for i in range(1, n + 1):
        j_center = int(i * m / n)
        j_start = max(1, j_center - band)
        j_end = min(m, j_center + band)

        for j in range(j_start, j_end + 1):
            cost = match_cost if seq1[i - 1] == seq2[j - 1] else mismatch_cost

            candidates = []
            if (i - 1, j - 1) in dp:
                candidates.append(dp[(i - 1, j - 1)] + cost)
            if (i - 1, j) in dp:
                candidates.append(dp[(i - 1, j)] + delete_cost)
            if (i, j - 1) in dp:
                candidates.append(dp[(i, j - 1)] + insert_cost)

            if candidates:
                dp[(i, j)] = min(candidates)

    # Check if we reached the end
    if (n, m) not in dp:
        # Widen band and retry
        return banded_dtw(seq1, seq2, band_ratio=min(band_ratio * 2, 1.0),
                          match_cost=match_cost, mismatch_cost=mismatch_cost,
                          delete_cost=delete_cost, insert_cost=insert_cost)

    total_cost = dp[(n, m)]

    # Backtrace
    path = []
    i, j = n, m
    while i > 0 and j > 0:
        cost = match_cost if seq1[i - 1] == seq2[j - 1] else mismatch_cost

        diag = dp.get((i - 1, j - 1), INF) + cost
        up = dp.get((i - 1, j), INF) + delete_cost
        left = dp.get((i, j - 1), INF) + insert_cost

        current = dp.get((i, j), INF)

        if abs(current - diag) < 1e-9:
            path.append((i - 1, j - 1))
            i -= 1
            j -= 1
        elif abs(current - up) < 1e-9:
            i -= 1  # skip whisper char (deletion)
        else:
            j -= 1  # skip lyric char (insertion)

    path.reverse()
    return total_cost, path


def align_chars_to_lyrics(
    whisper_chars, lyric_kana_concat, lyric_line_offsets,
    lyrics, band_ratio=0.2
):
    """
    Align whisper character stream to concatenated lyric kana stream via DTW.
    Then extract per-line timings from the character alignment.

    Args:
        whisper_chars: List[CharTiming] from whisper words
        lyric_kana_concat: str, concatenation of all lyric lines' kana
        lyric_line_offsets: List[Tuple[int, int]], (start, end) char offsets per line
        lyrics: List[LyricLine]
        band_ratio: DTW band width ratio

    Returns:
        List[AlignedLine]
    """
    if not whisper_chars or not lyric_kana_concat:
        return [AlignedLine(
            index=l.index, start_time=0, end_time=0,
            confidence=0, is_anchor=False, method='unmatched'
        ) for l in lyrics]

    w_chars = [c.char for c in whisper_chars]
    l_chars = list(lyric_kana_concat)

    cost, path = banded_dtw(w_chars, l_chars, band_ratio=band_ratio)

    # Normalize cost
    norm_cost = cost / max(len(l_chars), 1)
    debug(f"DTW cost: {cost:.1f}, normalized: {norm_cost:.3f}, "
          f"path length: {len(path)}, w_chars: {len(w_chars)}, l_chars: {len(l_chars)}")

    # Extract per-line timings from DTW path
    results = []
    for line in lyrics:
        line_start_offset, line_end_offset = lyric_line_offsets[line.index]
        line_char_count = line_end_offset - line_start_offset

        if line_char_count == 0:
            results.append(AlignedLine(
                index=line.index, start_time=0, end_time=0,
                confidence=0, is_anchor=False, method='unmatched'
            ))
            continue

        # Find all DTW matches for this line's characters
        matched_w_indices = []
        matched_count = 0
        for w_idx, l_idx in path:
            if line_start_offset <= l_idx < line_end_offset:
                matched_w_indices.append(w_idx)
                if w_chars[w_idx] == l_chars[l_idx]:
                    matched_count += 1

        if matched_w_indices:
            first_w = min(matched_w_indices)
            last_w = max(matched_w_indices)

            start_time = whisper_chars[first_w].start
            end_time = whisper_chars[last_w].end

            # Confidence: ratio of exactly matched characters
            match_ratio = matched_count / max(line_char_count, 1)
            # Also consider coverage
            coverage = len(set(matched_w_indices)) / max(line_char_count, 1)
            confidence = min(1.0, (match_ratio * 0.6 + min(coverage, 1.0) * 0.4))

            results.append(AlignedLine(
                index=line.index,
                start_time=start_time,
                end_time=end_time,
                confidence=confidence,
                is_anchor=confidence >= 0.5,
                method='forced',
            ))
        else:
            results.append(AlignedLine(
                index=line.index, start_time=0, end_time=0,
                confidence=0, is_anchor=False, method='unmatched'
            ))

    return results


# ============================================================
# Chunk-based candidate alignment
# ============================================================

def assign_words_to_chunks(words, chunks):
    """Assign word indices to chunks based on word timestamps."""
    for chunk in chunks:
        chunk.word_indices = []
        for wi, w in enumerate(words):
            # Word overlaps with chunk if word midpoint is in chunk range
            mid = (w.start + w.end) / 2
            if chunk.start_time <= mid <= chunk.end_time:
                chunk.word_indices.append(wi)


def score_chunk_candidates(
    chunk, words, whisper_chars, lyrics,
    expected_line_cursor, max_windows, window_overlap, band_ratio
):
    """
    For a chunk, generate and score multiple candidate lyric windows.
    Each window is a contiguous range of lyric lines that might correspond to this chunk.

    Returns list of CandidateWindow objects sorted by score.
    """
    n_lines = len(lyrics)
    if not chunk.word_indices:
        return []

    # Get whisper chars for this chunk
    chunk_char_indices = []
    for ct_idx, ct in enumerate(whisper_chars):
        if ct.word_idx in set(chunk.word_indices):
            chunk_char_indices.append(ct_idx)

    if not chunk_char_indices:
        return []

    chunk_chars = [whisper_chars[i] for i in chunk_char_indices]
    chunk_w_chars = [c.char for c in chunk_chars]

    # Estimate how many lines this chunk might contain
    chunk_duration = chunk.end_time - chunk.start_time
    avg_line_duration = 3.0  # rough estimate
    est_lines = max(1, int(chunk_duration / avg_line_duration))
    window_size = min(n_lines, max(est_lines, 3))

    # Generate candidate windows around expected position
    candidates = []
    search_radius = max_windows * 2

    for offset in range(-search_radius, search_radius + 1):
        win_start = max(0, expected_line_cursor + offset)
        win_end = min(n_lines, win_start + window_size)
        if win_start >= n_lines or win_end <= win_start:
            continue

        # Avoid duplicate windows
        key = (win_start, win_end)
        if any(c.line_start == win_start and c.line_end == win_end for c in candidates):
            continue

        # Build lyric kana for this window
        window_lyrics = lyrics[win_start:win_end]
        window_kana = ''.join(l.kana for l in window_lyrics)
        if not window_kana:
            continue

        window_l_chars = list(window_kana)

        # Quick score using character overlap ratio before expensive DTW
        w_set = set(chunk_w_chars)
        l_set = set(window_l_chars)
        char_overlap = len(w_set & l_set) / max(len(l_set), 1)
        if char_overlap < 0.1:
            continue

        # Character-level DTW for this window
        cost, path = banded_dtw(chunk_w_chars, window_l_chars, band_ratio=band_ratio)
        norm_cost = cost / max(len(window_l_chars), 1)

        # Count matches
        match_count = sum(1 for wi, li in path if chunk_w_chars[wi] == window_l_chars[li])
        match_ratio = match_count / max(len(window_l_chars), 1)

        # Alignment score: high match ratio, low normalized cost
        score = match_ratio * 0.7 + max(0, 1.0 - norm_cost) * 0.3

        # Position bonus: windows closer to expected cursor score higher
        pos_distance = abs(win_start - expected_line_cursor)
        pos_bonus = max(0, 1.0 - pos_distance / max(n_lines / 4, 1))
        score += pos_bonus * 0.1

        # Build line offsets within this window
        offsets = []
        cursor = 0
        for l in window_lyrics:
            end = cursor + len(l.kana)
            offsets.append((cursor, end))
            cursor = end

        # Extract per-line timings from the DTW path
        line_timings = []
        for li, line in enumerate(window_lyrics):
            l_start, l_end = offsets[li]
            matched_w = []
            exact_matches = 0
            for wi, lci in path:
                if l_start <= lci < l_end:
                    matched_w.append(wi)
                    if chunk_w_chars[wi] == window_l_chars[lci]:
                        exact_matches += 1

            if matched_w:
                first_ci = min(matched_w)
                last_ci = max(matched_w)
                st = chunk_chars[first_ci].start
                et = chunk_chars[last_ci].end
                line_conf = exact_matches / max(l_end - l_start, 1)
                line_timings.append(AlignedLine(
                    index=line.index,
                    start_time=st, end_time=et,
                    confidence=min(line_conf, 1.0),
                    is_anchor=line_conf >= 0.5,
                    method='forced',
                ))
            else:
                line_timings.append(AlignedLine(
                    index=line.index,
                    start_time=0, end_time=0,
                    confidence=0, is_anchor=False, method='unmatched',
                ))

        candidates.append(CandidateWindow(
            line_start=win_start,
            line_end=win_end,
            alignment_score=score,
            char_match_ratio=match_ratio,
            line_timings=line_timings,
        ))

    # Sort by score descending, keep top candidates
    candidates.sort(key=lambda c: c.alignment_score, reverse=True)
    return candidates[:max_windows]


# ============================================================
# Global monotonic DP across chunks
# ============================================================

def global_monotonic_dp(chunks, chunk_candidates, n_lines, beam_width=80):
    """
    Find the globally optimal monotonic assignment of lyric windows to chunks.

    State: (chunk_index, lyric_cursor)
    Constraint: lyric windows must progress forward (monotonic)
    Score: sum of alignment scores + continuity bonuses

    Returns: list of chosen CandidateWindow per chunk (or None if skipped)
    """
    n_chunks = len(chunks)

    @dataclass
    class DPState:
        score: float
        lyric_cursor: int  # next expected lyric line index
        choices: list  # index into chunk_candidates[ci] or -1 for skip
        last_end_time: float = 0.0

    beam = [DPState(score=0.0, lyric_cursor=0, choices=[], last_end_time=0.0)]

    for ci in range(n_chunks):
        next_beam = []
        candidates = chunk_candidates[ci]

        for state in beam:
            # Option 1: Skip this chunk
            skip = DPState(
                score=state.score - 0.1,  # small penalty for skipping
                lyric_cursor=state.lyric_cursor,
                choices=state.choices + [-1],
                last_end_time=state.last_end_time,
            )
            next_beam.append(skip)

            # Option 2: Assign a candidate window
            for wi, cand in enumerate(candidates):
                # Monotonic constraint
                if cand.line_start < state.lyric_cursor:
                    # Allow small overlap for recovery
                    if cand.line_start < state.lyric_cursor - 2:
                        continue

                # Compute transition score
                trans_score = cand.alignment_score

                # Continuity bonus: reward sequential progression
                gap = cand.line_start - state.lyric_cursor
                if 0 <= gap <= 2:
                    trans_score += 0.15  # good continuity
                elif gap < 0:
                    trans_score -= 0.1 * abs(gap)  # overlap penalty
                else:
                    trans_score -= 0.02 * gap  # gap penalty

                # Temporal continuity
                if state.last_end_time > 0:
                    time_gap = chunks[ci].start_time - state.last_end_time
                    if 0 <= time_gap < 5:
                        trans_score += 0.05
                    elif time_gap < 0:
                        trans_score -= 0.1

                new_cursor = max(state.lyric_cursor, cand.line_end)

                matched = DPState(
                    score=state.score + trans_score,
                    lyric_cursor=new_cursor,
                    choices=state.choices + [wi],
                    last_end_time=chunks[ci].end_time,
                )
                next_beam.append(matched)

        # Prune beam
        next_beam.sort(key=lambda s: s.score, reverse=True)

        # Deduplicate by lyric_cursor (keep best score for each cursor)
        seen = {}
        deduped = []
        for s in next_beam:
            key = s.lyric_cursor
            if key not in seen:
                seen[key] = True
                deduped.append(s)
                if len(deduped) >= beam_width:
                    break
        beam = deduped

    if not beam:
        return [None] * n_chunks

    best = beam[0]

    # Bonus for covering more lyrics
    coverage_bonus = best.lyric_cursor / max(n_lines, 1)
    debug(f"Global DP: best score={best.score:.2f}, "
          f"lyric coverage={best.lyric_cursor}/{n_lines} ({coverage_bonus:.0%})")

    result = []
    for ci, choice in enumerate(best.choices):
        if choice == -1 or choice >= len(chunk_candidates[ci]):
            result.append(None)
        else:
            result.append(chunk_candidates[ci][choice])

    return result


# ============================================================
# Collapse detection and re-anchoring
# ============================================================

def detect_collapse(aligned_lines, total_duration, threshold=0.2):
    """
    Detect regions where alignment has collapsed.

    Collapse signals:
    - 3+ consecutive lines with confidence < threshold
    - Lines with duration < 0.2s or > 20s
    - Large time gap (> 10s) between adjacent lines
    - Time going backwards

    Returns: list of (start_line_idx, end_line_idx) collapsed regions
    """
    n = len(aligned_lines)
    collapsed = []
    i = 0

    while i < n:
        line = aligned_lines[i]

        # Check for collapse start
        is_suspicious = False

        if line.confidence < threshold and line.method != 'interpolated':
            is_suspicious = True
        elif line.start_time > 0 and line.end_time > 0:
            dur = line.end_time - line.start_time
            if dur < 0.2 or dur > 20:
                is_suspicious = True
            if i > 0 and aligned_lines[i - 1].end_time > 0:
                gap = line.start_time - aligned_lines[i - 1].end_time
                if gap > 10 or gap < -1:
                    is_suspicious = True
                # Time going backwards
                if line.start_time < aligned_lines[i - 1].start_time - 0.5:
                    is_suspicious = True

        if is_suspicious:
            # Find extent of collapsed region
            region_start = i
            region_end = i + 1
            while region_end < n:
                next_line = aligned_lines[region_end]
                next_sus = (next_line.confidence < threshold * 1.5
                            or next_line.method == 'unmatched')
                if not next_sus and next_line.is_anchor:
                    break
                region_end += 1
                if region_end - region_start >= 3:
                    break

            if region_end - region_start >= 2:
                collapsed.append((region_start, region_end))
                i = region_end
                continue

        i += 1

    return collapsed


def recover_collapsed_regions(
    collapsed_regions, aligned_lines, words, whisper_chars, lyrics,
    chunks, band_ratio, recovery_passes
):
    """
    Re-align collapsed regions with wider search.
    Uses surrounding anchors to constrain the search.
    """
    if not collapsed_regions:
        return aligned_lines

    result = list(aligned_lines)
    reanchor_count = 0

    for pass_num in range(recovery_passes):
        for region_start, region_end in collapsed_regions:
            # Find time bounds from surrounding good lines
            time_before = 0.0
            for i in range(region_start - 1, -1, -1):
                if result[i].is_anchor and result[i].end_time > 0:
                    time_before = result[i].end_time
                    break

            time_after = words[-1].end if words else 0
            for i in range(region_end, len(result)):
                if result[i].is_anchor and result[i].start_time > 0:
                    time_after = result[i].start_time
                    break

            # Get words in this time range
            region_word_indices = [
                wi for wi, w in enumerate(words)
                if time_before - 1 <= (w.start + w.end) / 2 <= time_after + 1
            ]

            if not region_word_indices:
                continue

            # Get corresponding chars
            region_chars = [
                ct for ct in whisper_chars
                if ct.word_idx in set(region_word_indices)
            ]

            if not region_chars:
                continue

            # Build lyric kana for this region
            region_lyrics = lyrics[region_start:region_end]
            region_kana = ''.join(l.kana for l in region_lyrics)
            if not region_kana:
                continue

            # Build offsets
            offsets = []
            cursor = 0
            for l in region_lyrics:
                end = cursor + len(l.kana)
                offsets.append((cursor, end))
                cursor = end

            # Re-align with wider band
            r_w_chars = [c.char for c in region_chars]
            r_l_chars = list(region_kana)

            cost, path = banded_dtw(
                r_w_chars, r_l_chars,
                band_ratio=min(band_ratio * 2, 0.5)
            )

            # Extract line timings
            for li, line in enumerate(region_lyrics):
                l_start, l_end = offsets[li]
                matched_w = []
                exact = 0
                for wi, lci in path:
                    if l_start <= lci < l_end:
                        matched_w.append(wi)
                        if r_w_chars[wi] == r_l_chars[lci]:
                            exact += 1

                if matched_w:
                    first = min(matched_w)
                    last = max(matched_w)
                    st = region_chars[first].start
                    et = region_chars[last].end
                    conf = exact / max(l_end - l_start, 1)

                    old = result[region_start + li]
                    if conf > old.confidence:
                        result[region_start + li] = AlignedLine(
                            index=line.index,
                            start_time=st, end_time=et,
                            confidence=min(conf, 1.0),
                            is_anchor=conf >= 0.5,
                            method='recovered',
                        )
                        reanchor_count += 1

    debug(f"Recovery: re-anchored {reanchor_count} lines")
    return result


# ============================================================
# Interpolation for remaining unmatched lines
# ============================================================

def interpolate_unmatched(aligned_lines, total_duration, vocal_onset, lyrics=None):
    """
    Fill in timing for unmatched lines using surrounding anchors.
    Uses proportional spacing based on kana length when lyrics are available.
    """
    n = len(aligned_lines)
    result = list(aligned_lines)
    i = 0

    while i < n:
        if result[i].start_time > 0 and result[i].confidence > 0:
            i += 1
            continue

        # Find run of unmatched lines
        run_start = i
        run_end = i
        while run_end < n and (result[run_end].start_time <= 0 or result[run_end].confidence <= 0):
            run_end += 1

        # Find bounding times
        time_before = vocal_onset
        if run_start > 0 and result[run_start - 1].end_time > 0:
            time_before = result[run_start - 1].end_time

        time_after = total_duration
        if run_end < n and result[run_end].start_time > 0:
            time_after = result[run_end].start_time

        available = time_after - time_before
        run_length = run_end - run_start

        if available > 0 and run_length > 0:
            # Distribute proportionally by kana length if lyrics available
            if lyrics and run_end <= len(lyrics):
                weights = [max(len(lyrics[j].kana), 1) for j in range(run_start, run_end)]
            else:
                weights = [1] * run_length
            total_weight = sum(weights)

            cursor = time_before
            for k in range(run_length):
                j = run_start + k
                proportion = weights[k] / total_weight
                block_dur = available * proportion
                result[j] = AlignedLine(
                    index=result[j].index,
                    start_time=cursor,
                    end_time=cursor + block_dur,
                    confidence=0.05,
                    is_anchor=False,
                    method='interpolated',
                )
                cursor += block_dur

        i = run_end

    return result


# ============================================================
# Fallback: full-song character-level alignment (no chunking)
# ============================================================

def full_song_character_alignment(words, lyrics, band_ratio=0.2):
    """
    Simple full-song character-level DTW alignment.
    Used as primary alignment for fast mode and as sanity check.
    """
    # Expand words to character timings
    whisper_chars = expand_words_to_chars(words)

    if not whisper_chars:
        return [AlignedLine(
            index=l.index, start_time=0, end_time=0,
            confidence=0, is_anchor=False, method='unmatched'
        ) for l in lyrics]

    # Build concatenated lyric kana
    lyric_kana_parts = []
    lyric_line_offsets = []
    offset = 0
    for l in lyrics:
        kana = l.kana
        lyric_kana_parts.append(kana)
        lyric_line_offsets.append((offset, offset + len(kana)))
        offset += len(kana)
    lyric_kana_concat = ''.join(lyric_kana_parts)

    return align_chars_to_lyrics(
        whisper_chars, lyric_kana_concat, lyric_line_offsets,
        lyrics, band_ratio
    )


# ============================================================
# Debug reporting
# ============================================================

def generate_debug_report(aligned_lines, chunks, chunk_choices,
                          collapsed_regions, vocal_onset, total_duration,
                          words, mode, whisper_model):
    """Generate detailed debug information by song progress bins."""
    n = len(aligned_lines)
    bin_count = 10

    bin_metrics = []
    for b in range(bin_count):
        pct_start = b * 10
        pct_end = (b + 1) * 10
        t_start = vocal_onset + (total_duration - vocal_onset) * (pct_start / 100)
        t_end = vocal_onset + (total_duration - vocal_onset) * (pct_end / 100)

        bin_lines = [l for l in aligned_lines
                     if l.start_time > 0 and t_start <= l.start_time < t_end]

        if bin_lines:
            mean_conf = sum(l.confidence for l in bin_lines) / len(bin_lines)
            n_anchors = sum(1 for l in bin_lines if l.is_anchor)
            n_forced = sum(1 for l in bin_lines if l.method == 'forced')
            n_recovered = sum(1 for l in bin_lines if l.method == 'recovered')
            n_interp = sum(1 for l in bin_lines if l.method == 'interpolated')
        else:
            mean_conf = 0
            n_anchors = 0
            n_forced = 0
            n_recovered = 0
            n_interp = 0

        # Collapse score: proportion of lines in collapsed regions in this bin
        collapse_count = 0
        for cs, ce in collapsed_regions:
            for idx in range(cs, ce):
                if idx < len(aligned_lines):
                    al = aligned_lines[idx]
                    if al.start_time > 0 and t_start <= al.start_time < t_end:
                        collapse_count += 1

        bin_metrics.append({
            "bin": f"{pct_start}-{pct_end}%",
            "line_count": len(bin_lines),
            "mean_confidence": round(mean_conf, 3),
            "anchors": n_anchors,
            "forced": n_forced,
            "recovered": n_recovered,
            "interpolated": n_interp,
            "collapse_count": collapse_count,
        })

    method_counts = {}
    for l in aligned_lines:
        method_counts[l.method] = method_counts.get(l.method, 0) + 1

    chunk_info = []
    if chunks:
        for ci, chunk in enumerate(chunks):
            choice = chunk_choices[ci] if ci < len(chunk_choices) else None
            chunk_info.append({
                "index": ci,
                "start": round(chunk.start_time, 2),
                "end": round(chunk.end_time, 2),
                "words": len(chunk.word_indices),
                "chosen_window": (
                    f"lines {choice.line_start}-{choice.line_end}"
                    if choice else "skipped"
                ),
                "alignment_score": round(choice.alignment_score, 3) if choice else 0,
            })

    return {
        "vocal_onset": round(vocal_onset, 2),
        "total_duration": round(total_duration, 2),
        "total_words": len(words),
        "mode": mode,
        "whisper_model": whisper_model,
        "method_counts": method_counts,
        "bin_metrics": bin_metrics,
        "chunks": chunk_info,
        "collapse_regions": [
            {"start_line": s, "end_line": e} for s, e in collapsed_regions
        ],
    }


# ============================================================
# Main pipeline
# ============================================================

class AlignmentPipeline:
    def __init__(self, audio_path, lyrics_data, mode='balanced',
                 whisper_model_override=None):
        self.audio_path = audio_path
        self.mode = mode
        self.config = MODE_CONFIG.get(mode, MODE_CONFIG['balanced'])
        self.whisper_model = whisper_model_override or self.config['whisper_model']

        # Parse lyrics
        self.lyrics = []
        for i, item in enumerate(lyrics_data):
            ja = item.get('japanese', '')
            ko = item.get('korean', '')
            kana = text_to_kana(ja)
            self.lyrics.append(LyricLine(index=i, japanese=ja, korean=ko, kana=kana))

        progress(f"Loaded {len(self.lyrics)} lyric lines, mode={mode}")

    def run(self):
        start_time = time_module.time()

        # --- Step 1: Audio preprocessing ---
        audio_for_whisper = self.audio_path
        vocal_separation_used = False

        if self.config['use_vocal_separation']:
            tmp_dir = tempfile.mkdtemp(prefix='mreels_demucs_')
            vocals_path = separate_vocals(self.audio_path, tmp_dir)
            if vocals_path:
                audio_for_whisper = vocals_path
                vocal_separation_used = True
            else:
                debug("Proceeding without vocal separation")

        # --- Step 2: Whisper transcription with word timestamps ---
        words = transcribe_with_words(
            audio_for_whisper,
            model_size=self.whisper_model,
            whisper_model_override=None,
        )

        if not words:
            error_exit("No words found in transcription")

        # Detect vocal onset
        vocal_onset = max(0, words[0].start - 0.5) if words else 0
        total_duration = words[-1].end if words else 0
        debug(f"Vocal onset: {vocal_onset:.2f}s, total: {total_duration:.2f}s")

        # --- Step 3: VAD-based chunking ---
        progress("Computing vocal activity and creating chunks...")
        try:
            rms, sr, hop_sec, audio_duration = read_wav_energy(self.audio_path)
            total_duration = max(total_duration, audio_duration)
            chunks = create_chunks_from_energy(
                rms, hop_sec, total_duration,
                target_seconds=self.config['chunk_target_seconds'],
                min_seconds=self.config['chunk_min_seconds'],
                max_seconds=self.config['chunk_max_seconds'],
            )
        except Exception as e:
            debug(f"Chunking failed ({e}), using single chunk")
            chunks = [Chunk(index=0, start_time=0, end_time=total_duration)]

        debug(f"Created {len(chunks)} chunks")

        # Assign words to chunks
        assign_words_to_chunks(words, chunks)

        # --- Step 4: Expand words to character timings ---
        whisper_chars = expand_words_to_chars(words)
        debug(f"Expanded to {len(whisper_chars)} character timings")

        # --- Step 5: Full-song character DTW as baseline ---
        progress("Running character-level forced alignment...")
        baseline_aligned = full_song_character_alignment(
            words, self.lyrics,
            band_ratio=self.config['dtw_band_ratio']
        )

        # --- Step 6: Chunk-based candidate alignment ---
        chunk_candidates = []
        chunk_choices = []

        if len(chunks) > 1:
            progress("Scoring chunk candidates...")
            line_cursor = 0
            for ci, chunk in enumerate(chunks):
                if ci % 3 == 0:
                    progress(f"Processing chunk {ci + 1}/{len(chunks)}...")

                candidates = score_chunk_candidates(
                    chunk, words, whisper_chars, self.lyrics,
                    expected_line_cursor=line_cursor,
                    max_windows=self.config['max_candidate_windows'],
                    window_overlap=self.config['window_overlap_lines'],
                    band_ratio=self.config['dtw_band_ratio'],
                )
                chunk_candidates.append(candidates)

                # Advance cursor estimate based on best candidate
                if candidates:
                    best = candidates[0]
                    line_cursor = best.line_end

            # --- Step 7: Global monotonic DP ---
            progress("Running global monotonic DP across chunks...")
            chunk_choices = global_monotonic_dp(
                chunks, chunk_candidates, len(self.lyrics),
                beam_width=self.config['beam_width'],
            )

            # --- Step 8: Merge chunk results with baseline ---
            aligned = self._merge_chunk_and_baseline(
                baseline_aligned, chunk_choices, chunks
            )
        else:
            aligned = baseline_aligned
            chunk_choices = [None]

        # --- Step 9: Collapse detection ---
        collapsed_regions = []
        if self.config['enable_collapse_detection']:
            progress("Detecting alignment collapse...")
            collapsed_regions = detect_collapse(
                aligned, total_duration,
                threshold=self.config['collapse_threshold']
            )
            if collapsed_regions:
                debug(f"Found {len(collapsed_regions)} collapsed regions")
                progress("Recovering collapsed regions...")
                aligned = recover_collapsed_regions(
                    collapsed_regions, aligned, words, whisper_chars,
                    self.lyrics, chunks,
                    band_ratio=self.config['dtw_band_ratio'],
                    recovery_passes=max(1, self.config['recovery_passes']),
                )

        # --- Step 10: Interpolate remaining unmatched ---
        aligned = interpolate_unmatched(aligned, total_duration, vocal_onset, self.lyrics)

        # --- Step 11: Sanity check and fix ordering ---
        aligned = self._fix_ordering(aligned)

        # --- Step 12: Generate debug report ---
        debug_info = generate_debug_report(
            aligned, chunks, chunk_choices,
            collapsed_regions, vocal_onset, total_duration,
            words, self.mode, self.whisper_model,
        )

        elapsed = time_module.time() - start_time
        progress(f"Alignment complete in {elapsed:.1f}s")

        # Build output
        lines_out = []
        for al in aligned:
            lines_out.append({
                "index": al.index,
                "start_time": round(al.start_time, 3),
                "end_time": round(al.end_time, 3),
                "confidence": round(al.confidence, 3),
                "is_anchor": al.is_anchor,
                "method": al.method,
            })

        return {
            "version": 1,
            "lines": lines_out,
            "debug": debug_info,
        }

    def _merge_chunk_and_baseline(self, baseline, chunk_choices, chunks):
        """
        Merge chunk-based alignment with baseline full-song alignment.
        Prefer chunk results when they have higher confidence.
        """
        result = list(baseline)

        for ci, choice in enumerate(chunk_choices):
            if choice is None:
                continue
            for lt in choice.line_timings:
                idx = lt.index
                if idx < len(result):
                    if lt.confidence > result[idx].confidence:
                        result[idx] = lt

        return result

    def _fix_ordering(self, aligned):
        """Fix any temporal ordering violations in the final alignment."""
        result = list(aligned)

        for i in range(1, len(result)):
            if result[i].start_time > 0 and result[i - 1].end_time > 0:
                if result[i].start_time < result[i - 1].start_time:
                    # Time went backwards - use later value
                    if result[i].confidence >= result[i - 1].confidence:
                        result[i - 1] = AlignedLine(
                            index=result[i - 1].index,
                            start_time=result[i - 1].start_time,
                            end_time=min(result[i - 1].end_time, result[i].start_time),
                            confidence=result[i - 1].confidence * 0.5,
                            is_anchor=False,
                            method=result[i - 1].method,
                        )
                    else:
                        result[i] = AlignedLine(
                            index=result[i].index,
                            start_time=max(result[i].start_time, result[i - 1].end_time),
                            end_time=max(result[i].end_time, result[i - 1].end_time + 0.1),
                            confidence=result[i].confidence * 0.5,
                            is_anchor=False,
                            method=result[i].method,
                        )

        return result


# ============================================================
# Entry point
# ============================================================

def main():
    parser = argparse.ArgumentParser(
        description="Advanced forced alignment for Japanese lyrics"
    )
    parser.add_argument('--audio', required=True, help="Path to audio WAV file")
    parser.add_argument('--lyrics', required=True, help="Path to lyrics JSON file")
    parser.add_argument('--mode', default='balanced',
                        choices=['fast', 'balanced', 'accurate', 'maximum'])
    parser.add_argument('--output', required=True, help="Path to output JSON file")
    parser.add_argument('--whisper-model', default=None,
                        help="Override whisper model name")
    args = parser.parse_args()

    # Check dependencies
    check_dependencies(args.mode)

    # Load lyrics
    try:
        with open(args.lyrics, 'r', encoding='utf-8') as f:
            lyrics_data = json.load(f)
    except Exception as e:
        error_exit(f"Failed to load lyrics: {e}")

    # Run pipeline
    pipeline = AlignmentPipeline(
        args.audio, lyrics_data, args.mode,
        whisper_model_override=args.whisper_model,
    )
    result = pipeline.run()

    # Write output
    try:
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=2)
        progress(f"Output written to {args.output}")
    except Exception as e:
        error_exit(f"Failed to write output: {e}")

    # Also print summary to stderr
    n_lines = len(result.get('lines', []))
    methods = result.get('debug', {}).get('method_counts', {})
    progress(f"Summary: {n_lines} lines — "
             f"forced={methods.get('forced', 0)}, "
             f"recovered={methods.get('recovered', 0)}, "
             f"interpolated={methods.get('interpolated', 0)}, "
             f"unmatched={methods.get('unmatched', 0)}")

    # Print bin metrics
    for bm in result.get('debug', {}).get('bin_metrics', []):
        debug(f"  {bm['bin']}: conf={bm['mean_confidence']:.2f}, "
              f"anchors={bm['anchors']}, collapse={bm['collapse_count']}")


if __name__ == '__main__':
    main()
