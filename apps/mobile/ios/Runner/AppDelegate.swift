import Flutter
import UIKit

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
    // The device's IANA zone for push registration; Dart only sees an
    // abbreviation such as "BST".
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Timezone") {
      FlutterMethodChannel(
        name: "com.helpmebrands.reward/timezone",
        binaryMessenger: registrar.messenger()
      ).setMethodCallHandler { call, result in
        if call.method == "current" {
          result(TimeZone.current.identifier)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }
}
