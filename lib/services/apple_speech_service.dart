import 'dart:io';
import 'package:flutter/services.dart';

/// Apple Speech Recognition（iOS SFSpeechURLRequest）へのブリッジ
///
/// MethodChannel 経由で iOS ネイティブに音声ファイルを渡し、
/// オフラインで文字起こしする。Android では null を返す。
class AppleSpeechService {
  static const MethodChannel _channel = MethodChannel('smart_tether/speech');

  /// 音声ファイルを Apple Speech Recognition でオフライン文字起こしする
  ///
  /// - iOS のみ動作。Android では即 null を返す。
  /// - requiresOnDeviceRecognition = true（iOS 13+）でオフライン強制。
  /// - [filePath]: 文字起こし対象の m4a ファイルパス
  /// - 成功時: 文字起こしテキスト
  /// - 失敗時: null
  static Future<String?> transcribeFile(String filePath) async {
    if (!Platform.isIOS) return null;

    try {
      final result = await _channel.invokeMethod<String>(
        'transcribeFile',
        {'filePath': filePath},
      );
      return result?.isNotEmpty == true ? result : null;
    } on PlatformException catch (e) {
      // ignore: avoid_print
      print('[AppleSpeechService] PlatformException: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // ignore: avoid_print
      print('[AppleSpeechService] エラー: $e');
      return null;
    }
  }
}
