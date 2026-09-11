import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:vorafind/core/semantic/bert_tokenizer.dart';
import 'package:vorafind/core/semantic/semantic_models.dart';

/// Byte-for-byte parity with the HuggingFace reference implementation.
///
/// The expected id arrays below were produced by the Python
/// `transformers` slow BertTokenizer plus the exact truncation/pooling the
/// bundled `all-MiniLM-L6-v2` uses (see `docs/semantic-search.md`
/// §Tokenizer for the fixture provenance and regeneration command). If the
/// model is ever swapped, regenerate those fixtures and update this file
/// together with `SemanticDefaults.neuralModelId`.
void main() {
  late BertTokenizer tokenizer;

  setUpAll(() {
    final vocab = File('assets/models/vocab.txt').readAsStringSync();
    tokenizer = BertTokenizer.fromVocabText(vocab);
  });

  group('BertTokenizer reference parity', () {
    test('hello world', () {
      expect(tokenizer.encode('hello world').inputIds, [101, 7592, 2088, 102]);
    });

    test('sentence with punctuation', () {
      expect(
        tokenizer
            .encode(
              'Machine Learning Fundamentals Computers can learn patterns from data.',
            )
            .inputIds,
        [
          101,
          3698,
          4083,
          8050,
          2015,
          7588,
          2064,
          4553,
          7060,
          2013,
          2951,
          1012,
          102,
        ],
      );
    });

    test('uppercase keyword and question mark', () {
      expect(tokenizer.encode('cafe AND tea?').inputIds, [
        101,
        7668,
        1998,
        5572,
        1029,
        102,
      ]);
    });

    test('exclamation runs stay as single tokens', () {
      expect(tokenizer.encode('CARS TRUCKS!!!').inputIds, [
        101,
        3765,
        9322,
        999,
        999,
        999,
        102,
      ]);
    });

    test('accent stripping folds é and Í into plain letters', () {
      expect(tokenizer.encode('café ÜNÍST').inputIds, [
        101,
        7668,
        4895,
        2923,
        102,
      ]);
    });

    test('filename normalized like a real document name', () {
      expect(tokenizer.encode('Résumé v2.1 - final_report.pdf').inputIds, [
        101,
        13746,
        1058,
        2475,
        1012,
        1015,
        1011,
        2345,
        1035,
        3189,
        1012,
        11135,
        102,
      ]);
    });

    test('emoji splits into word pieces', () {
      expect(tokenizer.encode('smiley :) emoji éé').inputIds, [
        101,
        27420,
        1024,
        1007,
        7861,
        29147,
        2072,
        25212,
        102,
      ]);
    });

    test('U+FFFD is dropped (slow and fast agree)', () {
      expect(tokenizer.encode('\uFFFD unknown token test').inputIds, [
        101,
        4242,
        19204,
        3231,
        102,
      ]);
    });

    test('ideographic space and CJK punctuation normalize', () {
      expect(tokenizer.encode('IMF is a very special\u3000token 、').inputIds, [
        101,
        10047,
        2546,
        2003,
        1037,
        2200,
        2569,
        19204,
        1635,
        102,
      ]);
    });

    test('real screenshot string', () {
      expect(
        tokenizer.encode('chat screenshot november 2024 grocery list').inputIds,
        [101, 11834, 12117, 12326, 2281, 16798, 2549, 13025, 2862, 102],
      );
    });

    test('truncation aligns with the Python 256-token reference', () {
      final phrase = 'pattern from data classification regression neural';
      final text = List.filled(60, phrase).join(' ');
      final encoding = tokenizer.encode(text);
      // 101 + 254 body + 102 = 256 total, exactly the position-embedding cap.
      expect(encoding.inputIds, hasLength(256));
      expect(encoding.truncated, isTrue);
      expect(encoding.inputIds.first, 101);
      expect(encoding.inputIds.last, 102);
      // Phrase cycles (6 tokens each) fill 42 full cycles = 252 tokens, then
      // "pattern from" close the 254-token body — matching the Python output.
      const cycle = [5418, 2013, 2951, 5579, 26237, 15756];
      final expected = [
        101,
        for (var i = 0; i < 42; i++) ...cycle,
        5418,
        2013,
        102,
      ];
      expect(encoding.inputIds, expected);
    });
  });

  group('BertTokenizer structure', () {
    test('every encoding is a complete BERT sequence', () {
      for (final text in ['hello', 'a b c', 'word']) {
        final encoding = tokenizer.encode(text);
        expect(encoding.inputIds.first, tokenizer.encode('').inputIds.first);
        expect(encoding.inputIds.last, 102);
        expect(encoding.attentionMask, everyElement(1));
        expect(encoding.tokenTypeIds, everyElement(0));
        expect(encoding.truncated, isFalse);
      }
    });

    test('short inputs are never truncated', () {
      final encoding = tokenizer.encode('hello world');
      expect(encoding.truncated, isFalse);
      expect(encoding.length, lessThan(SemanticDefaults.neuralMaxTokens));
    });

    test('exactly maxTokens length is preserved, one over is truncated', () {
      // 256 single-token words would exceed the 254-token body: build exactly
      // maxTokens-2 words and verify borders.
      final near = List.filled(
        SemanticDefaults.neuralMaxTokens - 2,
        'a',
      ).join(' ');
      expect(tokenizer.encode(near).truncated, isFalse);
      final over = List.filled(
        SemanticDefaults.neuralMaxTokens - 1,
        'a',
      ).join(' ');
      expect(tokenizer.encode(over).truncated, isTrue);
    });

    test('unknown script maps to [UNK]', () {
      // Deseret is not in the BERT vocabulary and is not escaped to CJK —
      // WordPiece cannot break it, so it becomes [UNK]=100.
      expect(tokenizer.encode('hello \u{10400} world').inputIds, [
        101,
        7592,
        100,
        2088,
        102,
      ]);
    });

    test('Chinese characters tokenize as individual pieces', () {
      // Each CJK character becomes its own WordPiece candidate (they are
      // space-surrounded before splitting). This model's vocabulary only
      // contains 学: the other three fall back to [UNK] — matching the Python
      // fast-tokenizer reference exactly.
      expect(tokenizer.encode('机器学习').inputIds, [
        101,
        100,
        100,
        1817,
        100,
        102,
      ]);
    });

    test('control characters are removed', () {
      expect(
        tokenizer.encode('a\u0000b\u0007c').inputIds,
        tokenizer.encode('abc').inputIds,
      );
    });

    test('vocabSize reflects the bundled vocabulary', () {
      expect(tokenizer.vocabSize, 30522);
    });
  });

  group('BertTokenizer robustness', () {
    test('vocab missing special tokens throws', () {
      // A valid token list that lacks [PAD]/[UNK]/[CLS]/[SEP]/[MASK] must be
      // rejected so an off-spec vocabulary can never produce a broken
      // encoder.
      expect(
        () => BertTokenizer.fromVocabText('word\nother\nthing\n'),
        throwsFormatException,
      );
    });

    test('extreme punctuation-heavy input stays bounded', () {
      final encoding = tokenizer.encode('!!!!!' * 200 + ' emoji 😀😀😀');
      expect(encoding.attentionMask, everyElement(1));
      expect(encoding.inputIds.length, lessThanOrEqualTo(256));
      expect(encoding.inputIds.contains(100), isFalse); // '!' is in the vocab.
    });

    test('deterministic across calls', () {
      final text = 'Machine Learning Fundamentals computers learn from data';
      expect(tokenizer.encode(text).inputIds, tokenizer.encode(text).inputIds);
    });
  });
}
