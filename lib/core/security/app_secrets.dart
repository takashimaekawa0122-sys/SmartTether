import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// アプリの機密情報をKeychain/Keystoreで管理するクラス
///
/// 【重要】Auth KeyやAPIキーをソースコードに直接書かない。
/// 必ずこのクラスを通してKeychain/Keystoreに保存・取得する。
class AppSecrets {
  AppSecrets._();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  // ストレージキー定数
  static const _keyBandAuthKey = 'band_auth_key';
  static const _keyBandMacAddress = 'band_mac_address';
  static const _keyAvalonApiKey = 'avalon_api_key';

  // ===== Band 9 Auth Key =====

  /// Auth Keyを保存する（初回セットアップ時）
  static Future<void> saveBandAuthKey(String authKey) async {
    await _storage.write(key: _keyBandAuthKey, value: authKey);
  }

  /// Auth Keyを取得する
  /// 未設定の場合はnullを返す
  static Future<String?> getBandAuthKey() async {
    return _storage.read(key: _keyBandAuthKey);
  }

  // ===== Band 9 MACアドレス =====

  /// MACアドレスを保存する
  static Future<void> saveBandMacAddress(String macAddress) async {
    await _storage.write(key: _keyBandMacAddress, value: macAddress);
  }

  /// MACアドレスを取得する
  static Future<String?> getBandMacAddress() async {
    return _storage.read(key: _keyBandMacAddress);
  }

  // ===== Avalon APIキー =====

  /// Avalon APIキーを保存する
  static Future<void> saveAvalonApiKey(String apiKey) async {
    await _storage.write(key: _keyAvalonApiKey, value: apiKey);
  }

  /// Avalon APIキーを取得する
  static Future<String?> getAvalonApiKey() async {
    return _storage.read(key: _keyAvalonApiKey);
  }

  // ===== 初期設定確認 =====

  /// 必要な設定がすべて完了しているか確認する
  static Future<bool> isSetupComplete() async {
    final authKey = await getBandAuthKey();
    final macAddress = await getBandMacAddress();
    final apiKey = await getAvalonApiKey();
    return authKey != null && macAddress != null && apiKey != null;
  }

  // ===== デバイス認証情報シード（実機セットアップ）=====

  /// 実機の認証情報をKeychain/Keystoreに書き込む（強制上書き）
  /// 設定画面からも同じ値を変更できる。
  static Future<void> setDevelopmentPlaceholders() async {
    // Xiaomi Smart Band 9 実機の認証情報
    await saveBandMacAddress('04:34:C3:23:38:E3');
    await saveBandAuthKey('872a5ccb7c1f7ec0310ee04b091135c6');
    await saveAvalonApiKey('BIKE');
  }
}
