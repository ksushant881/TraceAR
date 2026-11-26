import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, FlutterStreamHandler {
  private var progressSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let methodChannel = FlutterMethodChannel(
      name: "com.sushant.tracear/native",
      binaryMessenger: messenger
    )
    let progressChannel = FlutterEventChannel(
      name: "com.sushant.tracear/native/timelapse_progress",
      binaryMessenger: messenger
    )
    progressChannel.setStreamHandler(self)

    methodChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "getVideoThumbnail" {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String else {
          result(nil)
          return
        }
        let asset = AVAsset(url: URL(fileURLWithPath: videoPath))
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 400, height: 400)
        if let cgImage = try? gen.copyCGImage(at: .zero, actualTime: nil),
           let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.75) {
          result(FlutterStandardTypedData(bytes: data))
        } else {
          result(nil)
        }
        return
      }
      guard call.method == "encodeTimelapse" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let frameDir = args["frameDir"] as? String,
            let outPath = args["outPath"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "frameDir and outPath are required", details: nil))
        return
      }
      let fps = args["fps"] as? Int ?? 24
      TimelapseEncoder.encode(
        frameDir: frameDir,
        outPath: outPath,
        fps: fps,
        onProgress: { progress in
          self?.progressSink?(progress)
        },
        onSuccess: { path in
          result(path)
        },
        onError: { code, message in
          result(FlutterError(code: code, message: message, details: nil))
        }
      )
    }
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    progressSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    progressSink = nil
    return nil
  }
}
