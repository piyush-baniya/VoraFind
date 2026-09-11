import 'package:diacritic/diacritic.dart';

import 'semantic_models.dart' show SemanticDefaults;

/// BERT special-token ids. Resolved from the model's `vocab.txt` so the port
/// never assumes a fixed integer layout beyond "BertTokenizer uses the five
/// special names".
final class BertSpecialTokens {
  BertSpecialTokens({
    required this.pad,
    required this.unk,
    required this.cls,
    required this.sep,
    required this.mask,
  });

  factory BertSpecialTokens.fromVocab(Map<String, int> vocab) {
    final pad = vocab['[PAD]'];
    final unk = vocab['[UNK]'];
    final cls = vocab['[CLS]'];
    final sep = vocab['[SEP]'];
    final mask = vocab['[MASK]'];
    if (pad == null ||
        unk == null ||
        cls == null ||
        sep == null ||
        mask == null) {
      throw const FormatException('vocab is missing a BERT special token');
    }
    return BertSpecialTokens(
      pad: pad,
      unk: unk,
      cls: cls,
      sep: sep,
      mask: mask,
    );
  }

  final int pad;
  final int unk;
  final int cls;
  final int sep;
  final int mask;
}

/// One tokenized, truncation-bounded sequence ready to feed the model.
///
/// Mirrors `transformers.BertTokenizer.__call__` for single sequences: a
/// BERT sequence is exactly `[CLS] … tokens … [SEP]` with an all-ones
/// attention mask and all-zero segment ids (there is never a real padding
/// batch at inference time — inputs are variable length and padded only when
/// a consumer builds a batch).
final class BertEncoding {
  const BertEncoding({
    required this.inputIds,
    required this.attentionMask,
    required this.tokenTypeIds,
    required this.truncated,
  });

  final List<int> inputIds;
  final List<int> attentionMask;
  final List<int> tokenTypeIds;

  /// True when input tokens exceeded [BertTokenizer.maxTokens] and the
  /// trailing tokens were dropped ([CLS]/[SEP] are always preserved).
  final bool truncated;

  int get length => inputIds.length;
}

/// A faithful Dart port of the HuggingFace `BertTokenizer` (slow/legacy
/// implementation) for the bundled `all-MiniLM-L6-v2` tokenizer, targeting
/// `transformers` word-piece behavior so token ids are byte-for-byte
/// compatible with the Python reference implementation.
///
/// Pipeline (in exact upstream order):
///
/// 1. `_clean_text` — drop control characters and U+FFFD, normalize every
///    whitespace character to a single ASCII space.
/// 2. `_tokenize_chinese_chars` — surround each CJK character with spaces so
///    every CJK character is its own WordPiece candidate.
/// 3. lowercase + accent stripping (`removeDiacritics`).
/// 4. punctuation splitting (`_run_split_on_punc`).
/// 5. WordPiece longest-match with `##` continuation prefixes.
/// 6. truncation to [maxTokens] (reserving [BertSpecialTokens.cls] and
///    [BertSpecialTokens.sep]) and wrap in `[CLS] … [SEP]`.
///
/// See `docs/semantic-search.md` §Tokenizer for the compatibility arguments
/// and the reference data used by `test/semantic/bert_tokenizer_test.dart`.
final class BertTokenizer {
  BertTokenizer(
    Map<String, int> vocab, {
    required BertSpecialTokens specialTokens,
    this.maxTokens = SemanticDefaults.neuralMaxTokens,
  }) : _vocab = Map.unmodifiable(vocab),
       _specialTokens = specialTokens,
       _unkToken = vocab.entries
           .firstWhere(
             (e) => e.value == specialTokens.unk,
             orElse: () => throw ArgumentError('vocab has no [UNK] entry'),
           )
           .key;

  /// Parses a standard HuggingFace `vocab.txt` (one token per line, where the
  /// line index is the token id — the same layout
  /// `transformers.load_vocab` reads).
  factory BertTokenizer.fromVocabText(
    String vocabText, {
    int maxTokens = SemanticDefaults.neuralMaxTokens,
  }) {
    final vocab = <String, int>{};
    var id = 0;
    for (final line in vocabText.split('\n')) {
      final token = line.trim();
      if (token.isEmpty) continue;
      vocab[token] = id;
      id += 1;
    }
    return BertTokenizer(
      vocab,
      specialTokens: BertSpecialTokens.fromVocab(vocab),
      maxTokens: maxTokens,
    );
  }

  final Map<String, int> _vocab;
  final BertSpecialTokens _specialTokens;
  final String _unkToken;

  /// Maximum total sequence length including [CLS] and [SEP].
  final int maxTokens;

  /// Hard cap on WordPiece search length per word (mirrors
  /// `max_input_chars_per_word=100` in transformers); longer words become
  /// [BertSpecialTokens.unk]. Not to be confused with
  /// [SemanticDefaults.maxInputChars], the embedding-side representation cap.
  static const int maxInputCharsPerWord = 100;

  int get vocabSize => _vocab.length;

  /// WordPiece tokens (before [CLS]/[SEP] wrapping and truncation).
  List<String> tokenize(String text) {
    final clean = _cleanText(text);
    final chineseSpaced = _tokenizeChineseChars(clean);
    final tokens = <String>[];
    for (final word in _whitespaceTokenize(chineseSpaced)) {
      final stripped = removeDiacritics(word.toLowerCase());
      for (final piece in _splitOnPunctuation(stripped)) {
        tokens.addAll(_wordPiece(piece));
      }
    }
    return tokens;
  }

  /// Encodes a single sequence: `[CLS] … [SEP]`, truncated to [maxTokens].
  BertEncoding encode(String text) {
    final tokens = tokenize(text);
    final truncated = tokens.length > maxTokens - 2;
    final body = truncated ? tokens.sublist(0, maxTokens - 2) : tokens;
    final inputIds = <int>[
      _specialTokens.cls,
      for (final token in body) _vocab[token] ?? _specialTokens.unk,
      _specialTokens.sep,
    ];
    final attentionMask = List<int>.filled(inputIds.length, 1);
    final tokenTypeIds = List<int>.filled(inputIds.length, 0);
    return BertEncoding(
      inputIds: inputIds,
      attentionMask: attentionMask,
      tokenTypeIds: tokenTypeIds,
      truncated: truncated,
    );
  }

  // ---------------------------------------------------------------------
  // BERT basic-tokenizer primitives (slow/legacy implementation semantics).
  // ---------------------------------------------------------------------

  static String _cleanText(String text) {
    final output = StringBuffer();
    for (final rune in text.runes) {
      if (rune == 0 || rune == 0xFFFD || _isControl(rune)) continue;
      if (_isWhitespace(rune)) {
        output.write(' ');
      } else {
        output.writeCharCode(rune);
      }
    }
    return output.toString();
  }

  static bool _isControl(int cp) => cp == 0x7F || (cp >= 0x00 && cp <= 0x1F);

  static bool _isWhitespace(int cp) {
    if (cp == 0x20 || cp == 0xA0 || cp == 0x1680) return true;
    if (cp >= 0x09 && cp <= 0x0D) return true;
    if (cp >= 0x2000 && cp <= 0x200A) return true;
    return cp == 0x2028 ||
        cp == 0x2029 ||
        cp == 0x202F ||
        cp == 0x205F ||
        cp == 0x3000;
  }

  static List<String> _whitespaceTokenize(String text) {
    return text
        .split(RegExp(r'\s+'))
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static String _tokenizeChineseChars(String text) {
    final output = StringBuffer();
    for (final rune in text.runes) {
      if (_isChineseChar(rune)) {
        output.write(' ');
        output.writeCharCode(rune);
        output.write(' ');
      } else {
        output.writeCharCode(rune);
      }
    }
    return output.toString();
  }

  /// The CJK ranges ported from `transformers.tokenization_bert._is_chinese_char`.
  static bool _isChineseChar(int cp) {
    return (cp >= 0x3400 && cp <= 0x4DBF) || // CJK Ext A
        (cp >= 0x4E00 && cp <= 0x9FFF) || // CJK Unified
        (cp >= 0x20000 && cp <= 0x2A6DF) || // CJK Ext B
        (cp >= 0x2A700 && cp <= 0x2B73F) || // CJK Ext C
        (cp >= 0x2B740 && cp <= 0x2B81F) || // CJK Ext D
        (cp >= 0x2B820 && cp <= 0x2CEAF) || // CJK Ext E
        (cp >= 0xF900 && cp <= 0xFAFF) || // CJK Compatibility
        (cp >= 0x2F800 && cp <= 0x2FA1F); // CJK Compatibility Ideographs
  }

  static List<String> _splitOnPunctuation(String text) {
    final runes = text.runes.toList(growable: false);
    if (runes.isEmpty) return const [];
    if (!_isPunctuation(runes.first) && !runes.any(_isPunctuation)) {
      return [text];
    }
    final tokens = <String>[];
    final current = <int>[];
    for (final rune in runes) {
      if (_isPunctuation(rune)) {
        if (current.isNotEmpty) {
          tokens.add(String.fromCharCodes(current));
          current.clear();
        }
        tokens.add(String.fromCharCode(rune));
      } else {
        current.add(rune);
      }
    }
    if (current.isNotEmpty) {
      tokens.add(String.fromCharCodes(current));
    }
    return tokens;
  }

  static bool _isPunctuation(int cp) {
    if (cp >= 0x21 && cp <= 0x2F) return true; // ! " # $ % & ' ( ) * + , - . /
    if (cp >= 0x3A && cp <= 0x40) return true; // : ; < = > ? @
    if (cp >= 0x5B && cp <= 0x60) return true; // [ \ ] ^ _ `
    if (cp >= 0x7B && cp <= 0x7E) return true; // { | } ~
    return (cp >= 0x00A1 && cp <= 0x00BF) ||
        (cp >= 0x2000 && cp <= 0x206F) ||
        (cp >= 0x3001 && cp <= 0x303F);
  }

  // ---------------------------------------------------------------------
  // WordPiece.
  // ---------------------------------------------------------------------

  List<String> _wordPiece(String text) {
    if (_vocab.containsKey(text)) return [text];
    if (text.runes.length > maxInputCharsPerWord) {
      return [_unkToken];
    }
    final chars = text.runes.toList(growable: false);
    final output = <String>[];
    var start = 0;
    while (start < chars.length) {
      var end = chars.length;
      String? currentPiece;
      while (start < end) {
        final base = String.fromCharCodes(chars.sublist(start, end));
        final candidate = start > 0 ? '##$base' : base;
        if (_vocab.containsKey(candidate)) {
          currentPiece = candidate;
          break;
        }
        end -= 1;
      }
      if (currentPiece == null) {
        output.add(_unkToken);
        break;
      }
      output.add(currentPiece);
      start = end;
    }
    return output;
  }
}
