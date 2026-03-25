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

  /// Band 9 の設定（MACアドレス・Auth Key）が実際の値かどうか確認する
  ///
  /// プレースホルダー（'XX:XX:XX:XX:XX:XX' / 'X'）は未設定とみなす。
  static Future<bool> isBandConfigured() async {
    final mac = await getBandMacAddress();
    final authKey = await getBandAuthKey();
    return mac != null &&
        mac != 'XX:XX:XX:XX:XX:XX' &&
        authKey != null &&
        authKey != 'X';
  }

  // ===== デバイス認証情報シード（実機セットアップ）=====

  /// 実機の認証情報をKeychain/Keystoreに書き込む（未設定時のみ）
  ///
  /// 既に設定されている場合は上書きしない。
  /// 設定画面から変更した値を起動のたびにリセットしないようにするため。
  static Future<void> setDevelopmentPlaceholders() async {
    // 未設定の場合のみ書き込む（設定画面での変更を保護する）
    final existingMac = await getBandMacAddress();
    if (existingMac == null) {
      await saveBandMacAddress('XX:XX:XX:XX:XX:XX');
    }
    final existingAuthKey = await getBandAuthKey();
    if (existingAuthKey == null) {
      await saveBandAuthKey('X');
    }
    final existingApiKey = await getAvalonApiKey();
    if (existingApiKey == null) {
      await saveAvalonApiKey('X');
    }
  }
}
