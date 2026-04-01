/// 置き忘れ確定時に表示する全画面警告オーバーレイ
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/tether/alert_sound_player.dart';
import '../../core/tether/alert_state.dart';
import '../../services/background_service.dart';

// ============================================================
// 層1: 状態監視コントローラー（Riverpod統合）
// ============================================================

/// `tetherStateStreamProvider` を監視してオーバーレイの表示を自動制御するウィジェット
///
/// このウィジェットを `Stack` の最前面に配置することで、
/// `TetherState.warning` / `TetherState.confirmed` になると自動的に全画面アラートを表示する。
/// 状態が解消された場合、またはユーザーが「解除する」を押した場合に非表示となる。
///
/// 使い方:
/// ```dart
/// Stack(
///   children: [
///     const TimelinePage(),
///     const AlertOverlayController(),
///   ],
/// )
/// ```
class AlertOverlayController extends ConsumerStatefulWidget {
  const AlertOverlayController({super.key});

  @override
  ConsumerState<AlertOverlayController> createState() =>
      _AlertOverlayControllerState();
}

class _AlertOverlayControllerState
    extends ConsumerState<AlertOverlayController> {
  /// ユーザーが手動で「解除する」を押したかどうか
  bool _dismissedByUser = false;

  /// 直前に確認した TetherState（再表示判定に使う）
  TetherState? _lastState;

  /// エスケープタイマー残り秒数を流すStreamController
  final StreamController<int> _timerStreamController =
      StreamController<int>.broadcast();

  /// 内部カウントダウンタイマー（自動解除用）
  Timer? _countdownTimer;

  /// 自動解除カウントダウンの残り秒数
  int _remainingSeconds = 30;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    if (!_timerStreamController.isClosed) {
      _timerStreamController.close();
    }
    super.dispose();
  }

  /// アラートを表示開始する（カウントダウン・アラート音を起動）
  void _startAlert() {
    _remainingSeconds = 30;
    _countdownTimer?.cancel();

    if (!_timerStreamController.isClosed) {
      _timerStreamController.add(_remainingSeconds);
    }

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _remainingSeconds--;
      if (!_timerStreamController.isClosed) {
        _timerStreamController.add(_remainingSeconds);
      }
      if (_remainingSeconds <= 0) {
        timer.cancel();
        _handleDismiss();
      }
    });

    // アラート音を開始
    ref.read(alertSoundPlayerProvider).startAlert();
  }

  /// アラートを停止する（カウントダウン・アラート音を停止）
  void _stopAlert() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    ref.read(alertSoundPlayerProvider).stopAlert();
  }

  /// ユーザーが「解除する」を押したときの処理
  void _handleDismiss() {
    if (!mounted) return;
    _stopAlert();
    setState(() {
      _dismissedByUser = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tetherStateAsync = ref.watch(tetherStateStreamProvider);
    final tetherState = tetherStateAsync.valueOrNull;

    // 警告圏に入ったとき（かつユーザーがまだ解除していないとき）にアラートを開始する
    final shouldShow =
        tetherState != null && tetherState.isAlerting && !_dismissedByUser;

    // 状態が変化したときのみ副作用を実行する（毎ビルドで積まれないよう条件を絞る）
    if (tetherState != _lastState) {
      final previousState = _lastState;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // build() の外で _lastState を更新する
        _lastState = tetherState;

        if (tetherState != null && tetherState.isAlerting && !_dismissedByUser) {
          // 警告圏に入った瞬間にアラートを起動
          _startAlert();
        } else if (previousState?.isAlerting == true &&
            (tetherState == null || !tetherState.isAlerting)) {
          // 警告圏から安全圏に戻った → アラート停止 + 解除フラグをリセット
          _stopAlert();
          if (_dismissedByUser) {
            setState(() {
              _dismissedByUser = false;
            });
          }
        }
      });
    }

    if (!shouldShow) return const SizedBox.shrink();

    return AlertOverlay(
      state: tetherState,
      onDismiss: _handleDismiss,
      remainingStream: _timerStreamController.stream,
      showTimer: true,
    );
  }
}

// ============================================================
// 層2: 全画面オーバーレイウィジェット
// ============================================================

/// 置き忘れ確定時に画面全体を覆う警告オーバーレイ
///
/// [state]            : 現在の TetherState（warning / confirmed で外観が変わる）
/// [onDismiss]        : 「解除する」ボタンが押されたときのコールバック
/// [remainingStream]  : エスケープタイマーの残り秒数を流すStream
/// [showTimer]        : タイマー残り秒数を表示するかどうか
class AlertOverlay extends StatefulWidget {
  /// 現在の TetherState（warning / confirmed で色が変わる）
  final TetherState state;

  /// 「解除する」ボタンが押されたときのコールバック
  final VoidCallback onDismiss;

  /// エスケープタイマーの残り秒数Stream（StreamBuilderで購読）
  final Stream<int> remainingStream;

  /// タイマー残り秒数を表示するかどうか
  final bool showTimer;

  const AlertOverlay({
    super.key,
    required this.state,
    required this.onDismiss,
    required this.remainingStream,
    this.showTimer = true,
  });

  @override
  State<AlertOverlay> createState() => _AlertOverlayState();
}

class _AlertOverlayState extends State<AlertOverlay>
    with SingleTickerProviderStateMixin {
  /// 警告アイコンの点滅アニメーション制御
  late AnimationController _blinkController;

  /// 不透明度アニメーション（0.4 〜 1.0 を行き来する）
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();

    // confirmed（確定）のときは速く点滅、warning（警告）はゆっくり点滅
    final duration = widget.state == TetherState.confirmed
        ? const Duration(milliseconds: 600)
        : const Duration(seconds: 1);

    _blinkController = AnimationController(
      vsync: this,
      duration: duration,
    )..repeat(reverse: true);

    _blinkAnimation = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(AlertOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 状態が変わったら点滅速度を更新する
    if (oldWidget.state != widget.state) {
      final duration = widget.state == TetherState.confirmed
          ? const Duration(milliseconds: 600)
          : const Duration(seconds: 1);
      _blinkController.duration = duration;
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  /// 状態に応じたテーマカラーを返す
  Color get _themeColor => widget.state == TetherState.confirmed
      ? const Color(0xFFFF6B6B) // 赤（確定）
      : const Color(0xFFFF9F43); // オレンジ（警告）

  /// 状態に応じたサブメッセージを返す
  String get _subMessage => widget.state == TetherState.confirmed
      ? 'Band 9 との接続が10秒以上途切れています'
      : 'Band 9 が離れています（4〜9秒）';

  @override
  Widget build(BuildContext context) {
    final themeColor = _themeColor;

    return Material(
      // システムの背景色に依存しないよう Material で明示的に指定
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── 背景レイヤー ──────────────────────────
          // 深い黒から状態色へ上→下グラデーション
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  themeColor.withValues(alpha: 0.30),
                  const Color(0xFF0A0A0F),
                ],
              ),
            ),
          ),
          // 半透明オーバーレイで全体を薄く染める
          Container(
            color: themeColor.withValues(alpha: 0.08),
          ),

          // ── メインコンテンツ ───────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),

                  // 点滅する警告アイコン
                  _BlinkingWarningIcon(
                    animation: _blinkAnimation,
                    color: themeColor,
                  ),

                  const SizedBox(height: 32),

                  // メインメッセージ
                  const Text(
                    'Band 9 が離れています',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
                  ),

                  const SizedBox(height: 12),

                  // サブメッセージ（状態によって変わる）
                  Text(
                    _subMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8B8B9E),
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),

                  // エスケープタイマー残り秒数（showTimer=true のときのみ表示）
                  if (widget.showTimer) ...[
                    const SizedBox(height: 24),
                    _TimerDisplay(
                      remainingStream: widget.remainingStream,
                      themeColor: themeColor,
                    ),
                  ],

                  const Spacer(flex: 2),

                  // 解除ボタン
                  _DismissButton(
                    onDismiss: widget.onDismiss,
                    themeColor: themeColor,
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// プライベートウィジェット
// ─────────────────────────────────────────────────────

/// 点滅する警告アイコン
///
/// AnimationController から受け取ったアニメーション値で
/// Icons.warning_rounded の不透明度を制御する。
class _BlinkingWarningIcon extends StatelessWidget {
  final Animation<double> animation;
  final Color color;

  const _BlinkingWarningIcon({
    required this.animation,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value,
        child: child,
      ),
      child: Icon(
        Icons.warning_rounded,
        size: 120,
        color: color,
      ),
    );
  }
}

/// タイマー残り秒数表示
///
/// StreamBuilder で remainingStream を購読し、
/// 「自動解除まで XX 秒」という形式でリアルタイム表示する。
class _TimerDisplay extends StatelessWidget {
  final Stream<int> remainingStream;
  final Color themeColor;

  const _TimerDisplay({
    required this.remainingStream,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: remainingStream,
      builder: (context, snapshot) {
        // データが来ていない間は何も表示しない
        if (!snapshot.hasData) return const SizedBox.shrink();

        final seconds = snapshot.data!;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: themeColor.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            '自動解除まで $seconds 秒',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: themeColor,
              fontSize: 15,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
      },
    );
  }
}

/// 解除ボタン
///
/// タップすると [onDismiss] コールバックを呼び出す。
/// 幅いっぱいに伸び、テーマカラーで塗りつぶす。
class _DismissButton extends StatelessWidget {
  final VoidCallback onDismiss;
  final Color themeColor;

  const _DismissButton({
    required this.onDismiss,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onDismiss,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF7C3AED),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 8,
          shadowColor: const Color(0xFF7C3AED).withValues(alpha: 0.5),
        ),
        child: const Text(
          '安全です、解除する',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
