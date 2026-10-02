import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  private var engine: FlutterEngine?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let flutterEngine = FlutterEngine(name: "DisplayController", project: nil)
    engine = flutterEngine
    flutterEngine.run(withEntrypoint: nil)
    RegisterGeneratedPlugins(registry: flutterEngine)
  }
}
