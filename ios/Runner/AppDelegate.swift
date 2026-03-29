import Flutter
import Speech
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Apple Speech Recognition MethodChannel の登録
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "smart_tether/speech",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        guard call.method == "transcribeFile",
              let args = call.arguments as? [String: Any],
              let filePath = args["filePath"] as? String
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.transcribeFile(filePath: filePath, result: result)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// SFSpeechURLRequest でオフライン文字起こしを実行する
  private func transcribeFile(filePath: String, result: @escaping FlutterResult) {
    // パーミッション確認
    SFSpeechRecognizer.requestAuthorization { status in
      guard status == .authorized else {
        result(FlutterError(
          code: "PERMISSION_DENIED",
          message: "音声認識のパーミッションが拒否されました",
          details: nil
        ))
        return
      }

      let fileURL = URL(fileURLWithPath: filePath)
      guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
            recognizer.isAvailable else {
        result(FlutterError(
          code: "RECOGNIZER_UNAVAILABLE",
          message: "日本語音声認識エンジンが利用できません",
          details: nil
        ))
        return
      }

      let request = SFSpeechURLRecognitionRequest(url: fileURL)
      // iOS 13+ でオンデバイス認識を強制（オフライン動作）
      if #available(iOS 13, *) {
        request.requiresOnDeviceRecognition = true
      }

      // FlutterResult は一度しか呼べないため、二重呼び出しをフラグで防ぐ
      var resultCalled = false
      recognizer.recognitionTask(with: request) { recognition, error in
        guard !resultCalled else { return }
        if let error = error {
          resultCalled = true
          result(FlutterError(
            code: "RECOGNITION_FAILED",
            message: error.localizedDescription,
            details: nil
          ))
          return
        }
        guard let recognition = recognition, recognition.isFinal else { return }
        resultCalled = true
        let text = recognition.bestTranscription.formattedString
        result(text.isEmpty ? nil : text)
      }
    }
  }
}
