import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Wi-Fi SSIDを使って「セーフゾーン（自宅・職場など）」を判定するクラス
///
/// セーフゾーン内では置き忘れアラートを抑制する。
/// SSID未登録の場合は常にfalseを返し、アラートを有効にする（安全側フェイルセーフ）。
class SafeZoneDetector {
  /// SharedPreferencesへの保存キー
  static const _kPrefsKey = 'safe_zone_ssid';

  /// Wi-Fi情報の取得に使うパッケージインスタンス
  final NetworkInfo _networkInfo;

  /// 現在登録中のセーフゾーンSSID（未登録はnull）
  String? _safeZoneSsid;

  SafeZoneDetector({NetworkInfo? networkInfo})
      : _networkInfo = networkInfo ?? NetworkInfo();

  /// 保存済みのSSIDをSharedPreferencesから読み込む
  ///
  /// アプリ起動時に一度呼ぶ。
  /// 読み込みに失敗しても安全側（未登録）のまま動作継続する。
  Future<void> initialize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _safeZoneSsid = prefs.getString(_kPrefsKey);
    } catch (e) {
      // 読み込みエラーはnull（未登録）のまま継続
      // ignore: avoid_print
      print('[SafeZoneDetector] initialize error: $e');
    }
  }

  /// 現在のWi-FiがセーフゾーンSSIDと一致するか判定する
  ///
  /// 判定ロジック:
  ///   1. SSIDが未登録 → false（安全側）
  ///   2. Wi-Fi SSID取得に失敗 → false（安全側）
  ///   3. 取得したSSIDが登録済みSSIDと一致 → true
  ///
  /// Androidではnetwork_info_plusがSSIDを `"MySSID"` のように
  /// ダブルクォート付きで返す場合があるため、比較前に除去する。
  Future<bool> isInSafeZone() async {
    // SSIDが未登録なら常にfalse
    if (_safeZoneSsid == null) return false;

    try {
      final rawSsid = await _networkInfo.getWifiName();
      if (rawSsid == null) return false;

      // Androidのダブルクォートを除去して正規化する
      final normalizedSsid = _stripQuotes(rawSsid);

      return normalizedSsid == _safeZoneSsid;
    } catch (e) {
      // 例外時は安全側（false）を返す
      // ignore: avoid_print
      print('[SafeZoneDetector] isInSafeZone error: $e');
      return false;
    }
  }

  /// 現在接続中のWi-Fi SSIDをセーフゾーンとして登録・保存する
  ///
  /// 戻り値:
  ///   - 登録成功: 登録したSSID文字列
  ///   - Wi-Fi未接続 / 取得失敗 / 例外: null
  Future<String?> registerCurrentSsid() async {
    try {
      final rawSsid = await _networkInfo.getWifiName();
      if (rawSsid == null) return null;

      final normalizedSsid = _stripQuotes(rawSsid);
      if (normalizedSsid.isEmpty) return null;

      // メモリとSharedPreferences両方に保存する
      _safeZoneSsid = normalizedSsid;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kPrefsKey, normalizedSsid);

      return normalizedSsid;
    } catch (e) {
      // ignore: avoid_print
      print('[SafeZoneDetector] registerCurrentSsid error: $e');
      return null;
    }
  }

  /// 登録中のSSIDを解除し、SharedPreferencesから削除する
  Future<void> clearSafeZone() async {
    try {
      _safeZoneSsid = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kPrefsKey);
    } catch (e) {
      // ignore: avoid_print
      print('[SafeZoneDetector] clearSafeZone error: $e');
    }
  }

  /// 現在登録中のSSID（未登録はnull）
  String? get safeZoneSsid => _safeZoneSsid;

  // ---------------------------------------------------------------------------
  // 内部処理
  // ---------------------------------------------------------------------------

  /// SSID文字列の前後のダブルクォートを除去して返す
  ///
  /// Android環境では `"MyHome"` のようにクォート付きで返ることがある。
  String _stripQuotes(String ssid) {
    if (ssid.length >= 2 && ssid.startsWith('"') && ssid.endsWith('"')) {
      return ssid.substring(1, ssid.length - 1);
    }
    return ssid;
  }
}

/// Riverpodプロバイダー
///
/// アプリ全体で単一インスタンスを共有する。
/// initialize()の呼び出しはアプリ起動シーケンスで行うこと。
final safeZoneDetectorProvider =
    Provider<SafeZoneDetector>((ref) => SafeZoneDetector());
