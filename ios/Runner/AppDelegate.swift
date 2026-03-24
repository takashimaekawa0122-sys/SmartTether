import Flutter
import UIKit
import CoreBluetooth

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // ── CoreBluetooth State Restoration ──────────────────────────
  // iOSがバックグラウンドでBLEセントラルを復元するときに呼ばれる。
  // flutter_reactive_ble が CBCentralManager を再接続できるよう
  // アプリを起動状態に保つためだけにハンドルする（処理はFlutter側に委譲）。
  override func application(
    _ application: UIApplication,
    willContinueUserActivityWithType userActivityType: String
  ) -> Bool {
    return false
  }
}
