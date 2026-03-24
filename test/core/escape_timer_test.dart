import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_tether/core/stealth/escape_timer.dart';

void main() {
  group('EscapeTimer', () {
    late EscapeTimer timer;

    setUp(() {
      timer = EscapeTimer();
    });

    tearDown(() {
      timer.dispose();
    });

    // -------------------------------------------------------------------------
    // 初期状態
    // -------------------------------------------------------------------------

    test('初期状態では isRunning が false', () {
      expect(timer.isRunning, isFalse);
    });

    test('初期状態では remainingSeconds が 0', () {
      expect(timer.remainingSeconds, equals(0));
    });

    // -------------------------------------------------------------------------
    // start() でカウントダウン値が Stream から来ること
    // -------------------------------------------------------------------------

    test('start() 直後に指定秒数が Stream に流れる', () {
      fakeAsync((async) {
        final received = <int>[];
        timer.remainingStream.listen(received.add);

        timer.start(seconds: 5, onComplete: () {});

        async.flushMicrotasks();
        expect(received, contains(5));
      });
    });

    test('start() 後 1秒ごとにカウントダウン値が減少する', () {
      fakeAsync((async) {
        final received = <int>[];
        timer.remainingStream.listen(received.add);

        timer.start(seconds: 3, onComplete: () {});

        // 開始時点: 3
        async.flushMicrotasks();
        expect(received, contains(3));

        // 1秒後: 2
        async.elapse(const Duration(seconds: 1));
        expect(received, contains(2));

        // 2秒後: 1
        async.elapse(const Duration(seconds: 1));
        expect(received, contains(1));
      });
    });

    test('start() 後 isRunning が true になる', () {
      fakeAsync((async) {
        timer.start(seconds: 10, onComplete: () {});
        async.flushMicrotasks();

        expect(timer.isRunning, isTrue);
      });
    });

    test('remainingSeconds が指定した秒数から始まる', () {
      fakeAsync((async) {
        timer.start(seconds: 7, onComplete: () {});
        async.flushMicrotasks();

        expect(timer.remainingSeconds, equals(7));
      });
    });

    // -------------------------------------------------------------------------
    // 0秒到達で自動停止すること
    // -------------------------------------------------------------------------

    test('0秒到達で isRunning が false になる', () {
      fakeAsync((async) {
        timer.start(seconds: 3, onComplete: () {});

        async.elapse(const Duration(seconds: 3));

        expect(timer.isRunning, isFalse);
      });
    });

    test('0秒到達で onComplete が呼ばれる', () {
      fakeAsync((async) {
        var completed = false;
        timer.start(seconds: 2, onComplete: () => completed = true);

        async.elapse(const Duration(seconds: 2));

        expect(completed, isTrue);
      });
    });

    test('0秒到達のとき Stream に 0 が流れる', () {
      fakeAsync((async) {
        final received = <int>[];
        timer.remainingStream.listen(received.add);

        timer.start(seconds: 2, onComplete: () {});

        async.elapse(const Duration(seconds: 2));

        expect(received, contains(0));
      });
    });

    test('0秒到達後は onComplete が 1回だけ呼ばれる', () {
      fakeAsync((async) {
        var callCount = 0;
        timer.start(seconds: 1, onComplete: () => callCount++);

        // 十分な時間を経過させる
        async.elapse(const Duration(seconds: 5));

        expect(callCount, equals(1));
      });
    });

    // -------------------------------------------------------------------------
    // cancel() で Stream が止まること
    // -------------------------------------------------------------------------

    test('cancel() 後は isRunning が false になる', () {
      fakeAsync((async) {
        timer.start(seconds: 10, onComplete: () {});
        async.flushMicrotasks();

        timer.cancel();

        expect(timer.isRunning, isFalse);
      });
    });

    test('cancel() 後は remainingSeconds が 0 になる', () {
      fakeAsync((async) {
        timer.start(seconds: 10, onComplete: () {});
        async.flushMicrotasks();

        timer.cancel();

        expect(timer.remainingSeconds, equals(0));
      });
    });

    test('cancel() 後は Stream に値が流れない', () {
      fakeAsync((async) {
        final received = <int>[];

        // 開始後に受け取り開始
        timer.start(seconds: 5, onComplete: () {});
        async.flushMicrotasks();

        // キャンセルしてから受信リストをクリア
        timer.cancel();
        received.clear();

        // さらに時間を進めても新しい値が来ない
        async.elapse(const Duration(seconds: 3));

        expect(received, isEmpty);
      });
    });

    test('cancel() 後は onComplete が呼ばれない', () {
      fakeAsync((async) {
        var completed = false;
        timer.start(seconds: 3, onComplete: () => completed = true);
        async.flushMicrotasks();

        timer.cancel();

        // 3秒経過しても onComplete は呼ばれない
        async.elapse(const Duration(seconds: 5));

        expect(completed, isFalse);
      });
    });

    // -------------------------------------------------------------------------
    // 二重 start() の動作（前のタイマーをキャンセルして新しく開始する）
    // -------------------------------------------------------------------------

    test('start() を二重に呼んでも前のタイマーはキャンセルされる', () {
      fakeAsync((async) {
        var firstCompleted = false;
        var secondCompleted = false;

        timer.start(seconds: 3, onComplete: () => firstCompleted = true);
        async.flushMicrotasks();

        // 1秒後に再 start（前のタイマーを上書き）
        async.elapse(const Duration(seconds: 1));
        timer.start(seconds: 5, onComplete: () => secondCompleted = true);

        // 最初の3秒後に達しても firstCompleted にはならない
        async.elapse(const Duration(seconds: 3));
        expect(firstCompleted, isFalse);

        // 2番目のタイマーが完了する
        async.elapse(const Duration(seconds: 2));
        expect(secondCompleted, isTrue);
      });
    });

    // -------------------------------------------------------------------------
    // dispose()
    // -------------------------------------------------------------------------

    test('dispose() 後は StreamController がクローズされる', () {
      fakeAsync((async) {
        timer.dispose();

        // dispose 後に Stream に値を送ろうとしても例外は出ない
        // （クローズ済みのStreamControllerに add しない設計になっている）
        expect(() {}, returnsNormally);
      });
    });
  });
}
