import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worthtrack/core/module/app_module.dart';
import 'package:worthtrack/core/module/module_state_repository.dart';
import 'package:worthtrack/data/db/app_database.dart';

import '../helpers/sqlite3_loader.dart';

/// 只用来验证「未注册的 id 不该出现在启用集合里」的最小模块。
class _StubModule extends AppModule {
  const _StubModule(this.id, this.order);

  @override
  final ModuleId id;

  final int order;

  @override
  String get name => id;

  @override
  IconData get icon => Icons.widgets;

  @override
  int get defaultOrder => order;
}

/// issue #44：模块开关状态仓储。
///
/// 核心语义只有一条——**表里没记录的模块视为启用**。
/// 这条一旦写反，新装用户会看到空 launcher。
void main() {
  setUpAll(setupSqlite3ForTests);

  late AppDatabase db;
  late ModuleStateRepository repo;

  const modules = <AppModule>[
    _StubModule('finance', 10),
    _StubModule('notes', 20),
  ];

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = ModuleStateRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('默认全开', () {
    test('空表时所有注册模块都算启用', () async {
      expect(await repo.enabledIds(modules), {'finance', 'notes'});
    });

    test('watchEnabledIds 首帧就给出全部模块', () async {
      expect(await repo.watchEnabledIds(modules).first, {'finance', 'notes'});
    });

    test('表里有未注册的 id 时，它不会混进启用集合', () async {
      await repo.setEnabled('ghost', false);
      expect(await repo.enabledIds(modules), {'finance', 'notes'});
    });
  });

  group('启用 / 停用', () {
    test('停用后从启用集合消失，其余模块不受影响', () async {
      await repo.setEnabled('finance', false);
      expect(await repo.enabledIds(modules), {'notes'});
    });

    test('重新启用后回到集合', () async {
      await repo.setEnabled('finance', false);
      await repo.setEnabled('finance', true);
      expect(await repo.enabledIds(modules), {'finance', 'notes'});
    });

    test('全部停用时启用集合为空（launcher 显示空态）', () async {
      await repo.setEnabled('finance', false);
      await repo.setEnabled('notes', false);
      expect(await repo.enabledIds(modules), isEmpty);
    });

    test('重复开关只留一行记录', () async {
      await repo.setEnabled('finance', false);
      await repo.setEnabled('finance', true);
      await repo.setEnabled('finance', false);

      final rows = await db.select(db.moduleStates).get();
      expect(rows.where((r) => r.moduleId == 'finance'), hasLength(1));
      expect(rows.single.enabled, isFalse);
    });

    test('停用不删业务数据（账户仍在）', () async {
      await db
          .into(db.accounts)
          .insert(
            AccountsCompanion.insert(name: '工资卡', type: AccountType.bank),
          );

      await repo.setEnabled('finance', false);

      final accounts = await db.select(db.accounts).get();
      expect(accounts, hasLength(1));
      expect(accounts.single.name, '工资卡');
    });

    test('firstEnabledAt 记第一次启用的时间，重复开关不刷新', () async {
      await repo.setEnabled('finance', true);
      final first =
          (await db.select(db.moduleStates).getSingle()).firstEnabledAt;
      expect(first, isNotNull);

      // 时间必然前进，若实现改成「每次覆盖」这里就会不等。
      await repo.setEnabled('finance', false);
      await repo.setEnabled('finance', true);

      final after =
          (await db.select(db.moduleStates).getSingle()).firstEnabledAt;
      expect(after, first);
    });

    test('从未启用过就被停用：firstEnabledAt 保持 null', () async {
      await repo.setEnabled('finance', false);
      final row = await db.select(db.moduleStates).getSingle();
      expect(row.firstEnabledAt, isNull);
    });
  });

  group('排序', () {
    test('setSortOrder 落库后 watchSortOrders 能读到', () async {
      await repo.setSortOrder('finance', 30);
      expect(await repo.watchSortOrders().first, {'finance': 30});
    });

    test('排序不影响启用状态', () async {
      await repo.setSortOrder('finance', 30);
      expect(await repo.enabledIds(modules), {'finance', 'notes'});
    });

    test('设置排序不会把已停用的模块重新打开', () async {
      await repo.setEnabled('finance', false);
      await repo.setSortOrder('finance', 30);
      expect(await repo.enabledIds(modules), {'notes'});
    });
  });
}
