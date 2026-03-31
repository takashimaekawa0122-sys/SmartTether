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

  // ===== 開発用（プレースホルダー設定）=====

  /// 開発用のプレースホルダーを設定する
  /// Band 9到着後に実際の値に置き換える
  static Future<void> setDevelopmentPlaceholders() async {
    await saveBandAuthKey('X'); // TODO: Band 9到着後に実際のAuth Keyに変更
    await saveBandMacAddress('XX:XX:XX:XX:XX:XX'); // TODO: 実際のMACアドレスに変更
    await saveAvalonApiKey('X'); // TODO: 実際のAvalon APIキーに変更
  }
}
