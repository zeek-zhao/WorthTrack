import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/modules/notes/domain/note_ref.dart';

/// issue #49：弱引用目标的取值与展示。
void main() {
  group('fromQuery', () {
    test('三个参数齐全时还原完整对象', () {
      final ref = NoteRef.fromQuery({
        'refType': 'position',
        'refId': 'sh600519',
        'refLabel': '贵州茅台',
      });
      expect(
        ref,
        const NoteRef(type: 'position', id: 'sh600519', label: '贵州茅台'),
      );
    });

    test('label 可以缺省（显示时退化为 id）', () {
      final ref = NoteRef.fromQuery({'refType': 'account', 'refId': '3'});
      expect(ref!.label, isNull);
      expect(ref.display, '3');
    });

    test('缺 refType 或 refId 时返回 null（退化成全部笔记，不报错）', () {
      expect(NoteRef.fromQuery(const {}), isNull);
      expect(NoteRef.fromQuery({'refType': 'position'}), isNull);
      expect(NoteRef.fromQuery({'refId': 'sh600519'}), isNull);
      expect(NoteRef.fromQuery({'refType': '', 'refId': 'sh600519'}), isNull);
      expect(NoteRef.fromQuery({'refType': 'position', 'refId': ''}), isNull);
    });

    test('空字符串 label 视作没有 label', () {
      final ref = NoteRef.fromQuery({
        'refType': 'position',
        'refId': 'sh600519',
        'refLabel': '',
      });
      expect(ref!.label, isNull);
      expect(ref.display, 'sh600519');
    });
  });

  group('toQuery', () {
    test('有 label 时三个参数都带上', () {
      expect(
        const NoteRef(
          type: 'position',
          id: 'sh600519',
          label: '贵州茅台',
        ).toQuery(),
        {'refType': 'position', 'refId': 'sh600519', 'refLabel': '贵州茅台'},
      );
    });

    test('没有 label 时不写这个键，避免出现 refLabel=', () {
      expect(const NoteRef(type: 'account', id: '3').toQuery(), {
        'refType': 'account',
        'refId': '3',
      });
    });

    test('fromQuery 与 toQuery 可以来回转换', () {
      const ref = NoteRef(type: 'position', id: 'sz000001', label: '平安银行');
      expect(NoteRef.fromQuery(ref.toQuery()), ref);
    });
  });

  group('相等性', () {
    test('同 type/id/label 视为同一个目标（provider family 靠它复用订阅）', () {
      expect(
        const NoteRef(type: 'position', id: 'sh600519', label: '贵州茅台'),
        const NoteRef(type: 'position', id: 'sh600519', label: '贵州茅台'),
      );
      expect(
        const NoteRef(type: 'position', id: 'sh600519').hashCode,
        const NoteRef(type: 'position', id: 'sh600519').hashCode,
      );
    });

    test('type 或 id 不同就是不同目标', () {
      expect(
        const NoteRef(type: 'position', id: 'sh600519'),
        isNot(const NoteRef(type: 'account', id: 'sh600519')),
      );
      expect(
        const NoteRef(type: 'position', id: 'sh600519'),
        isNot(const NoteRef(type: 'position', id: 'sz000001')),
      );
    });
  });
}
