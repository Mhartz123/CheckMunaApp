import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// What the fusion did, for the confirmation sheet, logs and the thesis
/// evaluation.
class FusionReport {
  /// Frames that produced any text and took part in the vote.
  final int framesUsed;

  /// Index (into the list passed to [OcrFusion.fuse]) of the frame whose
  /// layout the fused result is built on. Its photo is the one to keep.
  final int pivotIndex;

  /// Words in the fused result.
  final int words;

  /// Words where the fused text differs from what the pivot frame read,
  /// i.e. the other frames out-voted it.
  final int corrected;

  /// Words the pivot read that the other frames outvoted as noise.
  final int dropped;

  /// Words the pivot missed that a majority of the other frames read.
  final int inserted;

  /// Frames that support at least [kFrameAgreement] of the fused words.
  final int framesAgreeing;

  /// Mean share of frames that read each fused word exactly as it came out.
  /// 1.0 means every frame read every word identically.
  final double agreement;

  const FusionReport({
    required this.framesUsed,
    required this.pivotIndex,
    required this.words,
    required this.corrected,
    required this.dropped,
    required this.inserted,
    required this.framesAgreeing,
    required this.agreement,
  });

  /// Anything was changed relative to the pivot frame on its own.
  int get repairs => corrected + dropped + inserted;

  @override
  String toString() => 'FusionReport(frames $framesUsed, pivot $pivotIndex, '
      'words $words, corrected $corrected, dropped $dropped, '
      'inserted $inserted, framesAgreeing $framesAgreeing, '
      'agreement ${agreement.toStringAsFixed(2)})';
}

/// The fused reading plus how it was reached.
class FusionResult {
  /// A [RecognizedText] with the pivot frame's layout (blocks, lines, boxes)
  /// and the voted text. Everything downstream — the date-code parser, the
  /// product-name picker, the reading score — keeps working on it unchanged.
  final RecognizedText text;
  final FusionReport report;

  const FusionResult({required this.text, required this.report});
}

/// A frame supports the consensus when it read at least this share of the
/// fused words exactly.
const double kFrameAgreement = 0.8;

/// Multi-frame OCR fusion: combines several independent readings of the same
/// label so a word one frame misread is repaired by the frames that read it
/// correctly.
///
/// The approach follows ROVER (Recognizer Output Voting Error Reduction,
/// Fiscus 1997), which does the same for speech recognisers, applied at two
/// levels:
///
///  1. **Pivot.** The frame that is closest to all the others (the medoid,
///     by word-level edit distance) is the backbone. Its layout is kept.
///  2. **Word alignment.** Every other frame is aligned to the pivot word by
///     word with a weighted edit distance whose substitution cost is itself a
///     character edit distance, folded over the characters OCR confuses
///     (0/O, 1/l/I, 5/S, 8/B …). "Paracetam0l" therefore lines up with
///     "Paracetamol", while an unrelated word becomes an insertion/deletion.
///  3. **Word vote.** Each pivot position collects one candidate per frame
///     (or a gap). A word read identically by a majority wins; a word most
///     frames don't have at all is dropped as noise; words the pivot missed
///     but a majority of the other frames read are inserted.
///  4. **Character vote.** When no spelling has a majority, the candidate
///     spellings are aligned character by character and each position is
///     voted. So "Parac3tamol", "Paracetamo1" and "Paracetam0l" — three
///     wrong reads — fuse to "Paracetamol". Ties go to the character that
///     fits the word (a letter inside a word of letters, a digit inside a
///     number), then to the pivot.
///
/// Pure Dart with no platform calls, so it is unit-tested directly.
class OcrFusion {
  const OcrFusion._();

  /// Cost of skipping a word in one sequence. Two gaps (0.9) are cheaper
  /// than substituting two unrelated words (1.0), and more expensive than
  /// substituting two words that are the same word misread.
  static const double _wordGap = 0.45;

  /// Same idea at character level.
  static const double _charGap = 0.6;

  /// Fuses [frames] (null or empty ones are ignored). [weights], if given,
  /// is one weight per frame — e.g. lower for a frame that failed the blur
  /// gate — and defaults to equal weights.
  ///
  /// Returns null when no frame read anything.
  static FusionResult? fuse(List<RecognizedText?> frames,
      {List<double>? weights}) {
    final seqs = <_Frame>[];
    for (var i = 0; i < frames.length; i++) {
      final f = frames[i];
      if (f == null) continue;
      final tokens = _tokenize(f);
      if (tokens.isEmpty) continue;
      final w = weights != null && i < weights.length ? weights[i] : 1.0;
      seqs.add(_Frame(i, f, tokens, w <= 0 ? 0.01 : w));
    }
    if (seqs.isEmpty) return null;

    if (seqs.length == 1) {
      final only = seqs.first;
      return FusionResult(
        text: only.source,
        report: FusionReport(
          framesUsed: 1,
          pivotIndex: only.index,
          words: only.tokens.length,
          corrected: 0,
          dropped: 0,
          inserted: 0,
          framesAgreeing: 1,
          agreement: 1,
        ),
      );
    }

    final pivot = _pickPivot(seqs);
    final others = [
      for (final s in seqs)
        if (!identical(s, pivot)) s
    ];
    final totalWeight = seqs.fold<double>(0, (a, s) => a + s.weight);

    // Align every other frame to the pivot.
    final alignments = [
      for (final o in others) _alignWords(pivot.tokens, o.tokens),
    ];

    // Per pivot word: vote.
    final fused = <_FusedToken>[];
    var corrected = 0, dropped = 0, inserted = 0;
    // Per frame (in seqs order): how many fused words it read exactly.
    final support = {for (final s in seqs) s: 0};
    var agreementSum = 0.0;

    void emitInsertions(int gapIndex) {
      final seqsHere = <List<_Token>>[];
      final owners = <_Frame>[];
      for (var k = 0; k < others.length; k++) {
        final ins = alignments[k].insertions[gapIndex];
        if (ins != null && ins.isNotEmpty) {
          seqsHere.add(ins);
          owners.add(others[k]);
        }
      }
      if (seqsHere.isEmpty) return;
      final words = _voteInsertions(seqsHere, owners, totalWeight);
      for (final w in words) {
        // Attach to the line of the neighbouring pivot word.
        final anchor = gapIndex >= 0
            ? pivot.tokens[gapIndex]
            : pivot.tokens[math.min(0, pivot.tokens.length - 1)];
        fused.add(_FusedToken(w.text, anchor, inserted: true));
        inserted++;
        for (final f in w.supporters) {
          support[f] = support[f]! + 1;
        }
        agreementSum += w.supportWeight / totalWeight;
      }
    }

    emitInsertions(-1);
    for (var i = 0; i < pivot.tokens.length; i++) {
      final pTok = pivot.tokens[i];
      final candidates = <_Candidate>[
        _Candidate(pivot, pTok.text),
        for (var k = 0; k < others.length; k++)
          _Candidate(others[k], alignments[k].matches[i]?.text),
      ];

      final gapWeight = candidates
          .where((c) => c.text == null)
          .fold<double>(0, (a, c) => a + c.frame.weight);
      if (gapWeight > totalWeight / 2) {
        // Most frames saw no word here: the pivot's word is noise.
        dropped++;
        for (final c in candidates.where((c) => c.text == null)) {
          support[c.frame] = support[c.frame]! + 1;
        }
      } else {
        final text = _voteWord(candidates, totalWeight);
        if (text != pTok.text) corrected++;
        var agreeWeight = 0.0;
        for (final c in candidates) {
          if (c.text == text) {
            support[c.frame] = support[c.frame]! + 1;
            agreeWeight += c.frame.weight;
          }
        }
        agreementSum += agreeWeight / totalWeight;
        fused.add(_FusedToken(text, pTok));
      }
      emitInsertions(i);
    }

    final words = fused.length;
    final framesAgreeing = words == 0
        ? seqs.length
        : support.values.where((n) => n / words >= kFrameAgreement).length;

    return FusionResult(
      text: _rebuild(pivot.source, fused),
      report: FusionReport(
        framesUsed: seqs.length,
        pivotIndex: pivot.index,
        words: words,
        corrected: corrected,
        dropped: dropped,
        inserted: inserted,
        framesAgreeing: framesAgreeing,
        agreement: words == 0 ? 1 : agreementSum / words,
      ),
    );
  }

  // ── Tokenizing ───────────────────────────────────────────────────────────

  static List<_Token> _tokenize(RecognizedText text) {
    final out = <_Token>[];
    for (var b = 0; b < text.blocks.length; b++) {
      final block = text.blocks[b];
      for (var l = 0; l < block.lines.length; l++) {
        final line = block.lines[l];
        final parts = line.elements.isNotEmpty
            ? [
                for (var e = 0; e < line.elements.length; e++)
                  (line.elements[e].text.trim(), e)
              ]
            : [
                for (final w in line.text.split(RegExp(r'\s+'))) (w.trim(), -1)
              ];
        for (final (word, e) in parts) {
          if (word.isEmpty) continue;
          out.add(_Token(word, b, l, e));
        }
      }
    }
    return out;
  }

  // ── Pivot ────────────────────────────────────────────────────────────────

  /// The frame with the smallest total alignment cost to the others. Ties go
  /// to the heavier frame, then the one with more words.
  static _Frame _pickPivot(List<_Frame> seqs) {
    _Frame? best;
    var bestCost = double.infinity;
    for (final a in seqs) {
      var cost = 0.0;
      for (final b in seqs) {
        if (identical(a, b)) continue;
        cost += _alignWords(a.tokens, b.tokens).cost * b.weight;
      }
      cost /= a.weight;
      final better = cost < bestCost - 1e-9 ||
          (best != null &&
              (cost - bestCost).abs() <= 1e-9 &&
              (a.weight > best.weight ||
                  (a.weight == best.weight &&
                      a.tokens.length > best.tokens.length)));
      if (best == null || better) {
        best = a;
        bestCost = cost;
      }
    }
    return best!;
  }

  // ── Word alignment ───────────────────────────────────────────────────────

  /// Needleman–Wunsch alignment of [other] onto [pivot].
  static _Alignment _alignWords(List<_Token> pivot, List<_Token> other) {
    final n = pivot.length, m = other.length;
    final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    final move = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      cost[i][0] = i * _wordGap;
      move[i][0] = 1; // pivot word unmatched
    }
    for (var j = 1; j <= m; j++) {
      cost[0][j] = j * _wordGap;
      move[0][j] = 2; // other word inserted
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final sub = cost[i - 1][j - 1] +
            wordDistance(pivot[i - 1].text, other[j - 1].text);
        final del = cost[i - 1][j] + _wordGap;
        final ins = cost[i][j - 1] + _wordGap;
        if (sub <= del && sub <= ins) {
          cost[i][j] = sub;
          move[i][j] = 0;
        } else if (del <= ins) {
          cost[i][j] = del;
          move[i][j] = 1;
        } else {
          cost[i][j] = ins;
          move[i][j] = 2;
        }
      }
    }

    final matches = List<_Token?>.filled(n, null);
    // insertions[g] = other-frame words that fall after pivot word g
    // (g = -1: before the first pivot word).
    final insertions = <int, List<_Token>>{};
    var i = n, j = m;
    while (i > 0 || j > 0) {
      final mv = move[i][j];
      if (i > 0 && j > 0 && mv == 0) {
        matches[i - 1] = other[j - 1];
        i--;
        j--;
      } else if (i > 0 && (j == 0 || mv == 1)) {
        i--;
      } else {
        (insertions[i - 1] ??= []).insert(0, other[j - 1]);
        j--;
      }
    }
    return _Alignment(matches, insertions, cost[n][m]);
  }

  /// 0 for the same word (up to case and OCR look-alikes), 1 for unrelated
  /// words; the normalised character edit distance in between.
  static double wordDistance(String a, String b) {
    if (a == b) return 0;
    final fa = _fold(a), fb = _fold(b);
    if (fa == fb) return 0.05; // same word, different glyph choice
    final longest = math.max(fa.length, fb.length);
    if (longest == 0) return 0;
    return _levenshtein(fa, fb) / longest;
  }

  /// Lower-cases and maps characters OCR commonly confuses onto one
  /// representative, so they don't count as differences when aligning.
  static String _fold(String s) {
    final buf = StringBuffer();
    for (final ch in s.toLowerCase().split('')) {
      buf.write(_confusable[ch] ?? ch);
    }
    return buf.toString();
  }

  static const Map<String, String> _confusable = {
    '0': 'o',
    '1': 'l',
    'i': 'l',
    '|': 'l',
    '!': 'l',
    '5': 's',
    '8': 'b',
    '6': 'b',
    '2': 'z',
    '9': 'g',
    ',': '.',
  };

  static int _levenshtein(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (j) => j);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final c = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + c);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  // ── Word vote ────────────────────────────────────────────────────────────

  /// Picks the spelling for one position from the frames' candidates (null =
  /// that frame has no word here; the caller has already ruled out a gap
  /// majority).
  static String _voteWord(List<_Candidate> candidates, double totalWeight) {
    final byText = <String, double>{};
    for (final c in candidates) {
      if (c.text == null) continue;
      byText[c.text!] = (byText[c.text!] ?? 0) + c.frame.weight;
    }
    // A spelling read by a majority of all frames wins outright.
    for (final e in byText.entries) {
      if (e.value > totalWeight / 2) return e.key;
    }
    if (byText.length == 1) return byText.keys.first;

    // No majority spelling: vote character by character.
    final present = candidates.where((c) => c.text != null).toList();
    return fuseCharacters(
      [for (final c in present) c.text!],
      weights: [for (final c in present) c.frame.weight],
    );
  }

  /// Character-level vote over several spellings of the same word. The first
  /// spelling is the backbone (the pivot's).
  static String fuseCharacters(List<String> spellings, {List<double>? weights}) {
    if (spellings.isEmpty) return '';
    if (spellings.length == 1) return spellings.first;
    final w = weights ?? List<double>.filled(spellings.length, 1);
    final total = w.fold<double>(0, (a, b) => a + b);
    final base = spellings.first;
    final shape = _wordShape(spellings);

    // For each base position, the character every spelling put there (or
    // null for a gap), plus characters spellings put between positions.
    final columns = List.generate(base.length, (_) => <(String?, double)>[]);
    final between = <int, List<(String, double)>>{};
    for (var s = 0; s < spellings.length; s++) {
      final (aligned, ins) = _alignChars(base, spellings[s]);
      for (var p = 0; p < base.length; p++) {
        columns[p].add((aligned[p], w[s]));
      }
      ins.forEach((gap, chars) {
        for (final ch in chars) {
          (between[gap] ??= []).add((ch, w[s]));
        }
      });
    }

    final out = StringBuffer();
    void emitBetween(int gap) {
      final chars = between[gap];
      if (chars == null) return;
      final tally = <String, double>{};
      for (final (ch, wt) in chars) {
        tally[ch] = (tally[ch] ?? 0) + wt;
      }
      for (final e in tally.entries) {
        if (e.value > total / 2) out.write(e.key);
      }
    }

    emitBetween(-1);
    for (var p = 0; p < base.length; p++) {
      final tally = <String?, double>{};
      for (final (ch, wt) in columns[p]) {
        tally[ch] = (tally[ch] ?? 0) + wt;
      }
      if ((tally[null] ?? 0) > total / 2) {
        emitBetween(p);
        continue; // most spellings don't have this character
      }
      tally.remove(null);
      final best = _bestChar(tally, base[p], shape);
      out.write(best);
      emitBetween(p);
    }
    return out.toString();
  }

  /// Highest-weighted character; ties go to the one that fits the word's
  /// shape (letter vs digit), then to the backbone's character.
  static String _bestChar(
      Map<String?, double> tally, String baseChar, _Shape shape) {
    String? best;
    var bestScore = -1.0;
    for (final e in tally.entries) {
      final ch = e.key!;
      // Tiny bonuses only break ties; they never outweigh a real vote.
      var score = e.value;
      if (_fitsShape(ch, shape)) score += 1e-3;
      if (ch == baseChar) score += 1e-6;
      if (score > bestScore) {
        best = ch;
        bestScore = score;
      }
    }
    return best ?? baseChar;
  }

  static (List<String?>, Map<int, List<String>>) _alignChars(
      String base, String other) {
    final n = base.length, m = other.length;
    final cost = List.generate(n + 1, (_) => List<double>.filled(m + 1, 0));
    final move = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = 1; i <= n; i++) {
      cost[i][0] = i * _charGap;
      move[i][0] = 1;
    }
    for (var j = 1; j <= m; j++) {
      cost[0][j] = j * _charGap;
      move[0][j] = 2;
    }
    for (var i = 1; i <= n; i++) {
      for (var j = 1; j <= m; j++) {
        final a = base[i - 1], b = other[j - 1];
        final c = a == b
            ? 0.0
            : _fold(a) == _fold(b)
                ? 0.3 // a look-alike: a likely misread of the same glyph
                : 1.0;
        final sub = cost[i - 1][j - 1] + c;
        final del = cost[i - 1][j] + _charGap;
        final ins = cost[i][j - 1] + _charGap;
        if (sub <= del && sub <= ins) {
          cost[i][j] = sub;
          move[i][j] = 0;
        } else if (del <= ins) {
          cost[i][j] = del;
          move[i][j] = 1;
        } else {
          cost[i][j] = ins;
          move[i][j] = 2;
        }
      }
    }
    final aligned = List<String?>.filled(n, null);
    final ins = <int, List<String>>{};
    var i = n, j = m;
    while (i > 0 || j > 0) {
      final mv = move[i][j];
      if (i > 0 && j > 0 && mv == 0) {
        aligned[i - 1] = other[j - 1];
        i--;
        j--;
      } else if (i > 0 && (j == 0 || mv == 1)) {
        i--;
      } else {
        (ins[i - 1] ??= []).insert(0, other[j - 1]);
        j--;
      }
    }
    return (aligned, ins);
  }

  static _Shape _wordShape(List<String> spellings) {
    var letters = 0, digits = 0;
    for (final s in spellings) {
      for (final u in s.codeUnits) {
        if ((u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A)) letters++;
        if (u >= 0x30 && u <= 0x39) digits++;
      }
    }
    if (letters > digits * 2) return _Shape.alpha;
    if (digits > letters * 2) return _Shape.numeric;
    return _Shape.mixed;
  }

  static bool _fitsShape(String ch, _Shape shape) {
    final u = ch.codeUnitAt(0);
    final isLetter = (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
    final isDigit = u >= 0x30 && u <= 0x39;
    return switch (shape) {
      _Shape.alpha => isLetter,
      _Shape.numeric => isDigit,
      _Shape.mixed => false,
    };
  }

  // ── Insertions ───────────────────────────────────────────────────────────

  /// Words the pivot missed. Each run of inserted words comes from one frame;
  /// a word survives only if frames carrying a majority of the total weight
  /// read it (the pivot, which has nothing here, counts against it).
  static List<_Inserted> _voteInsertions(
      List<List<_Token>> runs, List<_Frame> owners, double totalWeight) {
    // The longest run is the local backbone; the others are aligned to it.
    var b = 0;
    for (var k = 1; k < runs.length; k++) {
      if (runs[k].length > runs[b].length) b = k;
    }
    final backbone = runs[b];
    final columns = [
      for (final t in backbone) <_Candidate>[_Candidate(owners[b], t.text)]
    ];
    for (var k = 0; k < runs.length; k++) {
      if (k == b) continue;
      final al = _alignWords(backbone, runs[k]);
      for (var p = 0; p < backbone.length; p++) {
        final t = al.matches[p];
        if (t != null) columns[p].add(_Candidate(owners[k], t.text));
      }
    }
    final out = <_Inserted>[];
    for (final col in columns) {
      final weight = col.fold<double>(0, (a, c) => a + c.frame.weight);
      if (weight <= totalWeight / 2) continue;
      final text = _voteWord(col, weight);
      final supporters = [
        for (final c in col)
          if (c.text == text) c.frame
      ];
      out.add(_Inserted(
        text,
        supporters,
        supporters.fold<double>(0, (a, f) => a + f.weight),
      ));
    }
    return out;
  }

  // ── Rebuilding a RecognizedText ──────────────────────────────────────────

  /// The pivot's blocks and lines, each line's text replaced by its fused
  /// words. Elements keep the geometry of the pivot word they replace; an
  /// inserted word borrows its neighbour's box. Lines left with no words are
  /// dropped, as are blocks left with no lines.
  static RecognizedText _rebuild(RecognizedText pivot, List<_FusedToken> fused) {
    final byLine = <(int, int), List<_FusedToken>>{};
    for (final t in fused) {
      (byLine[(t.anchor.block, t.anchor.line)] ??= []).add(t);
    }

    final blocks = <TextBlock>[];
    for (var b = 0; b < pivot.blocks.length; b++) {
      final block = pivot.blocks[b];
      final lines = <TextLine>[];
      for (var l = 0; l < block.lines.length; l++) {
        final tokens = byLine[(b, l)];
        if (tokens == null || tokens.isEmpty) continue;
        final line = block.lines[l];
        final elements = <TextElement>[];
        for (final t in tokens) {
          final src = t.anchor.element >= 0 &&
                  t.anchor.element < line.elements.length
              ? line.elements[t.anchor.element]
              : null;
          elements.add(TextElement(
            text: t.text,
            symbols: const [],
            boundingBox: src?.boundingBox ?? line.boundingBox,
            recognizedLanguages: src?.recognizedLanguages ?? line.recognizedLanguages,
            cornerPoints: src?.cornerPoints ?? line.cornerPoints,
            confidence: t.inserted ? null : src?.confidence,
            angle: src?.angle ?? line.angle,
          ));
        }
        lines.add(TextLine(
          text: tokens.map((t) => t.text).join(' '),
          elements: elements,
          boundingBox: line.boundingBox,
          recognizedLanguages: line.recognizedLanguages,
          cornerPoints: line.cornerPoints,
          confidence: line.confidence,
          angle: line.angle,
        ));
      }
      if (lines.isEmpty) continue;
      blocks.add(TextBlock(
        text: lines.map((l) => l.text).join('\n'),
        lines: lines,
        boundingBox: _union(lines.map((l) => l.boundingBox)) ?? block.boundingBox,
        recognizedLanguages: block.recognizedLanguages,
        cornerPoints: block.cornerPoints,
      ));
    }
    return RecognizedText(
      text: blocks.map((b) => b.text).join('\n'),
      blocks: blocks,
    );
  }

  static Rect? _union(Iterable<Rect> rects) {
    Rect? out;
    for (final r in rects) {
      out = out == null ? r : out.expandToInclude(r);
    }
    return out;
  }
}

enum _Shape { alpha, numeric, mixed }

class _Token {
  final String text;
  final int block;
  final int line;

  /// Index of the source element within its line, or -1 when the line had
  /// no elements and was split on whitespace.
  final int element;

  const _Token(this.text, this.block, this.line, this.element);
}

class _Frame {
  final int index;
  final RecognizedText source;
  final List<_Token> tokens;
  final double weight;

  _Frame(this.index, this.source, this.tokens, this.weight);
}

class _Alignment {
  /// For each pivot word, the other frame's word aligned to it (null = gap).
  final List<_Token?> matches;

  /// Other-frame words with no pivot counterpart, keyed by the pivot index
  /// they follow (-1 = before the first).
  final Map<int, List<_Token>> insertions;
  final double cost;

  const _Alignment(this.matches, this.insertions, this.cost);
}

class _Candidate {
  final _Frame frame;
  final String? text;

  const _Candidate(this.frame, this.text);
}

class _Inserted {
  final String text;
  final List<_Frame> supporters;
  final double supportWeight;

  const _Inserted(this.text, this.supporters, this.supportWeight);
}

class _FusedToken {
  final String text;

  /// The pivot word this came from (or, for an insertion, sits next to);
  /// decides which line it lands on and whose box it borrows.
  final _Token anchor;
  final bool inserted;

  const _FusedToken(this.text, this.anchor, {this.inserted = false});
}
