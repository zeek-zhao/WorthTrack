/// 轻量流组合工具：drift 的 watch 流没有内建 combineLatest，手写最小实现。
library;

import 'dart:async';

/// 合并两条流：两边都至少发出过一条数据后，任一方更新就发出 [combine] 结果。
/// 任一方完成即关闭输出流。
Stream<R> combineLatest2<A, B, R>(
  Stream<A> a,
  Stream<B> b,
  R Function(A, B) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  A? valueA;
  B? valueB;
  var hasA = false;
  var hasB = false;

  void emit() {
    if (hasA && hasB && !controller.isClosed) {
      controller.add(combine(valueA as A, valueB as B));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          valueA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          subB?.cancel();
          controller.close();
        },
        cancelOnError: true,
      );
      subB = b.listen(
        (v) {
          valueB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: () {
          subA?.cancel();
          controller.close();
        },
        cancelOnError: true,
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );
  return controller.stream;
}

/// 合并三条流：三方都至少发出过一条数据后，任一方更新就发出 [combine] 结果。
/// 任一方完成即关闭输出流。
Stream<R> combineLatest3<A, B, C, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  R Function(A, B, C) combine,
) {
  late StreamController<R> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;
  StreamSubscription<C>? subC;
  A? valueA;
  B? valueB;
  C? valueC;
  var hasA = false;
  var hasB = false;
  var hasC = false;

  void emit() {
    if (hasA && hasB && hasC && !controller.isClosed) {
      controller.add(combine(valueA as A, valueB as B, valueC as C));
    }
  }

  void closeAll() {
    subA?.cancel();
    subB?.cancel();
    subC?.cancel();
    if (!controller.isClosed) {
      controller.close();
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subA = a.listen(
        (v) {
          valueA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
        onDone: closeAll,
        cancelOnError: true,
      );
      subB = b.listen(
        (v) {
          valueB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
        onDone: closeAll,
        cancelOnError: true,
      );
      subC = c.listen(
        (v) {
          valueC = v;
          hasC = true;
          emit();
        },
        onError: controller.addError,
        onDone: closeAll,
        cancelOnError: true,
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
      subC?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
      subC?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
      await subC?.cancel();
    },
  );
  return controller.stream;
}
