import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_tether/core/zone/safe_zone_detector.dart';

void main() {
  group('SafeZoneDetector', () {
    late SafeZoneDetector detector;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      detector = SafeZoneDetector();
    });

    // -------------------------------------------------------------------------
    // 初期状態
    // -------------------------------------------------------------------------

    test('初期状態では safeZoneSsid が null', () {
      expect(detector.safeZoneSsid, isNull);
    });

    test('SSID 未登録のとき isInSafeZone() は false を返す', () async {
      // SSID が登録されていないため false になる（安全側フェイルセーフ）
      final result = await detector.isInSafeZone();
      expect(result, isFalse);
    });

    // -------------------------------------------------------------------------
    // initialize() で SharedPreferences からSSIDを読み込む
    // -------------------------------------------------------------------------

    test('initialize() で保存済み SSID を読み込む', () async {
      // SharedPreferences に直接 SSID を書き込んでおく
      SharedPreferences.setMockInitialValues({
        'safe_zone_ssid': 'MyHomeWifi',
      });

      final detectorWithPrefs = SafeZoneDetector();
      await detectorWithPrefs.initialize();

      expect(detectorWithPrefs.safeZoneSsid, equals('MyHomeWifi'));
    });

    test('initialize() 後に SSID が未設定のとき safeZoneSsid は null のまま', () async {
      SharedPreferences.setMockInitialValues({});

      await detector.initialize();

      expect(detector.safeZoneSsid, isNull);
    });

    // -------------------------------------------------------------------------
    // clearSafeZone()
    // -------------------------------------------------------------------------

    test('clearSafeZone() 後は safeZoneSsid が null になる', () async {
      SharedPreferences.setMockInitialValues({
        'safe_zone_ssid': 'MyHomeWifi',
      });

      final detectorWithPrefs = SafeZoneDetector();
      await detectorWithPrefs.initialize();
      await detectorWithPrefs.clearSafeZone();

      expect(detectorWithPrefs.safeZoneSsid, isNull);
    });

    test('clearSafeZone() 後は isInSafeZone() が false を返す', () async {
      SharedPreferences.setMockInitialValues({
        'safe_zone_ssid': 'MyHomeWifi',
      });

      final detectorWithPrefs = SafeZoneDetector();
      await detectorWithPrefs.initialize();
      await detectorWithPrefs.clearSafeZone();

      final result = await detectorWithPrefs.isInSafeZone();
      expect(result, isFalse);
    });

    test('clearSafeZone() 後に SharedPreferences からも SSID が削除されている', () async {
      SharedPreferences.setMockInitialValues({
        'safe_zone_ssid': 'MyHomeWifi',
      });

      final detectorWithPrefs = SafeZoneDetector();
      await detectorWithPrefs.initialize();
      await detectorWithPrefs.clearSafeZone();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('safe_zone_ssid'), isNull);
    });

    // -------------------------------------------------------------------------
    // isInSafeZone() の動作確認
    // - NetworkInfo は実機依存のため直接呼ぶテストは行わない
    // - SSID 未登録時の false 返却（フェイルセーフ）のみをユニットテストで確認
    // -------------------------------------------------------------------------

    test('SSID 未登録のとき isInSafeZone() は必ず false（フェイルセーフ）', () async {
      // initialize() を呼ばずに（未登録状態）
      final result = await detector.isInSafeZone();
      expect(result, isFalse);
    });

    // -------------------------------------------------------------------------
    // _stripQuotes の動作確認（間接テスト）
    // registerCurrentSsid() は NetworkInfo 実機依存のため直接テスト不可。
    // initialize() でダブルクォート付きSSIDを読み込ませることで
    // _stripQuotes が呼ばれないパスの確認のみ行う。
    // -------------------------------------------------------------------------

    test('initialize() で読み込んだ SSID がそのまま safeZoneSsid に格納される', () async {
      const testSsid = 'OfficeNetwork';
      SharedPreferences.setMockInitialValues({
        'safe_zone_ssid': testSsid,
      });

      final detectorWithPrefs = SafeZoneDetector();
      await detectorWithPrefs.initialize();

      expect(detectorWithPrefs.safeZoneSsid, equals(testSsid));
    });
  });
}
