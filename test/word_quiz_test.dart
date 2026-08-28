import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wordn/models/word_item.dart';
import 'package:wordn/services/dict_service.dart';


void main() {
  group('WordItem matching test', () {
    test('Basic definition match', () {
      const item = WordItem(
        word: 'influence',
        phonetic: "'ɪnfluəns",
        definition: 'n. 影响；势力；感化；有影响的人或事；v. 影响；改变',
        exampleEn: 'As a scientist, his influence was immense.',
        exampleCn: '身为一名科学家，他的影响力极大。',
      );

      // Positive matches
      expect(item.checkAnswer('影响'), isTrue);
      expect(item.checkAnswer('势力'), isTrue);
      expect(item.checkAnswer('改变'), isTrue);
      expect(item.checkAnswer('感化'), isTrue);
      expect(item.checkAnswer('有影响的人'), isTrue);
      expect(item.checkAnswer(' 影响 '), isTrue); // Whitespace trimming

      // Negative matches
      expect(item.checkAnswer('苹果'), isFalse);
      expect(item.checkAnswer('计算机'), isFalse);
      expect(item.checkAnswer(''), isFalse);
      expect(item.checkAnswer('   '), isFalse);
    });

    test('Complex POS and symbols matching', () {
      const item = WordItem(
        word: 'intellectual',
        phonetic: ",ɪntə'lɛktʃuəl",
        definition: 'adj. 智力的；聪明的；理智的；n. 知识分子；凭理智做事者',
        exampleEn: "Mark's very intellectual.",
        exampleCn: '马克很聪明。',
      );

      expect(item.checkAnswer('智力'), isTrue);
      expect(item.checkAnswer('智力的'), isTrue);
      expect(item.checkAnswer('聪明'), isTrue);
      expect(item.checkAnswer('聪明的'), isTrue);
      expect(item.checkAnswer('知识分子'), isTrue);
      expect(item.checkAnswer('笨拙'), isFalse);
    });

    test('Parentheses and special grammar tokens', () {
      const item = WordItem(
        word: 'power',
        phonetic: "'paʊɚ",
        definition: 'n. 力量，能力；电力，功率；政权，势力；[数] 幂；v. 激励；供以动力；使…有力量；adj. 借影响有权势人物以操纵权力的',
        exampleEn: 'They seized power in a military coup.',
        exampleCn: '他们在一场军事政变中夺取了政权。',
      );

      expect(item.checkAnswer('力量'), isTrue);
      expect(item.checkAnswer('能力'), isTrue);
      expect(item.checkAnswer('电力'), isTrue);
      expect(item.checkAnswer('政权'), isTrue);
      expect(item.checkAnswer('激励'), isTrue);
      expect(item.checkAnswer('动力'), isTrue);
      expect(item.checkAnswer('香蕉'), isFalse);
    });
  });

  group('DictService CSV parsing test', () {
    test('Parses CSV rows correctly with quotes and commas', () {
      const sampleCsv = '''paragraph,'pærəɡræf,n. 段落；短评；段落符号；v. 将…分段,the opening paragraphs of the novel,小说开篇的几个段落
influence,'ɪnfluəns,n. 影响；势力；感化；有影响的人或事；v. 影响；改变,"As a scientist, his influence was immense.",身为一名科学家，他的影响力极大。
intellectual,",ɪntə'lɛktʃuəl",adj. 智力的；聪明的；理智的；n. 知识分子；凭理智做事者,Mark’s very intellectual.,马克很聪明。
''';

      final words = DictService.parseCsv(sampleCsv);
      expect(words.length, equals(3));

      expect(words[0].word, equals('paragraph'));
      expect(words[0].phonetic, equals("'pærəɡræf"));
      expect(words[0].definition, contains('段落'));
      expect(words[0].exampleEn, equals('the opening paragraphs of the novel'));
      expect(words[0].exampleCn, equals('小说开篇的几个段落'));

      expect(words[1].word, equals('influence'));
      expect(words[1].exampleEn, equals('As a scientist, his influence was immense.'));

      expect(words[2].word, equals('intellectual'));
      expect(words[2].phonetic, equals(",ɪntə'lɛktʃuəl"));
    });

    test('Parses full kaoyan4533.csv asset file without error', () {

      final file = File('assets/dict/kaoyan4533.csv');

      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      final words = DictService.parseCsv(content);
      expect(words.length, greaterThanOrEqualTo(4500));
      // Verify first and last words
      expect(words.first.word, equals('paragraph'));
      expect(words.first.definition, contains('段落'));
    });
  });
}

