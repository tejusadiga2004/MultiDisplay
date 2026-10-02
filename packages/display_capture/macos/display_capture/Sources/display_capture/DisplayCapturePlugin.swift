import AppKit
import CoreGraphics
import CoreMedia
import CoreVideo
import FlutterMacOS
import Metal
@preconcurrency import ScreenCaptureKit
import os

private let captureLogger = Logger(subsystem: "com.virtualmonitor", category: "capture")
private let permissionRequestedKey = "dc.permissionRequested"

public final class DisplayCapturePlugin: NSObject, FlutterPlugin, @unchecked Sendable {
    private static let methodChannelName = "com.virtualmonitor/display_capture"
    private static let displaysChannelName = "com.virtualmonitor/display_capture/displays"
    private static let chromeChannelName = "com.virtualmonitor/display_capture/chrome"

    private let textureRegistry: FlutterTextureRegistry
    private let messenger: FlutterBinaryMessenger
    private var sessions: [Int64: CaptureRecord] = [:]
    private var nextSessionId: Int64 = 1
    private var displaysSink: FlutterEventSink?
    private var chromeSink: FlutterEventSink?
    private var closeObservers: [Int: NSObjectProtocol] = [:]
    private var displayChangeWork: DispatchWorkItem?
    private var permissionNeedsRelaunch = false

    private var methodChannel: FlutterMethodChannel!
    private var displaysChannel: FlutterEventChannel!
    private var chromeChannel: FlutterEventChannel!

    public static func register(with registrar: FlutterPluginRegistrar) {
        let plugin = DisplayCapturePlugin(
            textureRegistry: registrar.textures,
            messenger: registrar.messenger
        )
        plugin.registerChannels()
        registrar.addApplicationDelegate(plugin)
    }

    private init(textureRegistry: FlutterTextureRegistry, messenger: FlutterBinaryMessenger) {
        self.textureRegistry = textureRegistry
        self.messenger = messenger
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        displayChangeWork?.cancel()
        for observer in closeObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
        for id in Array(sessions.keys) {
            stopCapture(id)
        }
    }

    private func registerChannels() {
        methodChannel = FlutterMethodChannel(
            name: Self.methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [self] call, result in
            handle(call, result: result)
        }

        displaysChannel = FlutterEventChannel(
            name: Self.displaysChannelName,
            binaryMessenger: messenger
        )
        displaysChannel.setStreamHandler(
            EventStreamHandler(onListen: { [weak self] sink in
                self?.displaysSink = sink
                self?.sendDisplaysChanged()
            }, onCancel: { [weak self] in
                self?.displaysSink = nil
            })
        )

        chromeChannel = FlutterEventChannel(
            name: Self.chromeChannelName,
            binaryMessenger: messenger
        )
        chromeChannel.setStreamHandler(
            EventStreamHandler(onListen: { [weak self] sink in
                self?.chromeSink = sink
            }, onCancel: { [weak self] in
                self?.chromeSink = nil
            })
        )
    }

    private func streamConfiguration(
        width: Int,
        height: Int,
        fps: Int,
        showCursor: Bool
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = showCursor
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.queueDepth = 4
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.capturesAudio = false
        return configuration
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "listDisplays":
            listDisplays { result($0) }
        case "startCapture":
            startCapture(call, result: result)
        case "stopCapture":
            let args = call.arguments as? [String: Any]
            stopCapture((args?["sessionId"] as? NSNumber)?.int64Value ?? 0)
            result(nil)
        case "permissionState":
            let granted = CGPreflightScreenCaptureAccess()
            let requested = UserDefaults.standard.bool(forKey: permissionRequestedKey)
            result(
                granted && !permissionNeedsRelaunch
                    ? "granted"
                    : (requested || permissionNeedsRelaunch ? "denied" : "notDetermined")
            )
        case "requestPermission":
            UserDefaults.standard.set(true, forKey: permissionRequestedKey)
            permissionNeedsRelaunch = true
            _ = CGRequestScreenCaptureAccess()
            result(nil)
        case "openPermissionSettings":
            guard let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            ) else {
                result(FlutterError(code: "INTERNAL", message: "Invalid Screen Recording settings URL", details: nil))
                return
            }
            NSWorkspace.shared.open(
                settingsURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error {
                    result(FlutterError(
                        code: "PERMISSION_SETTINGS",
                        message: "Could not open Screen Recording settings",
                        details: error.localizedDescription
                    ))
                } else {
                    result(nil)
                }
            }
        case "setupDisplayWindow":
            setupDisplayWindow(call, result: result)
        case "diagnostics":
            result(diagnostics())
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func listDisplays(completion: @escaping ([[String: Any]]) -> Void) {
        let onlineIds = onlineDisplayIds()
        guard CGPreflightScreenCaptureAccess(), !permissionNeedsRelaunch else {
            completion(displayInfos(onlineIds, shareableIds: [], denied: true))
            return
        }

        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                DispatchQueue.main.async {
                    guard let self else {
                        completion([])
                        return
                    }
                    let shareableIds = Set(content.displays.map(\.displayID))
                    completion(self.displayInfos(onlineIds, shareableIds: shareableIds, denied: false))
                }
            } catch {
                captureLogger.error("Failed to enumerate ScreenCaptureKit displays: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async {
                    guard let self else {
                        completion([])
                        return
                    }
                    completion(self.displayInfos(onlineIds, shareableIds: [], denied: false))
                }
            }
        }
    }

    private func displayInfos(
        _ ids: [CGDirectDisplayID],
        shareableIds: Set<CGDirectDisplayID>,
        denied: Bool
    ) -> [[String: Any]] {
        ids.enumerated()
            .map { displayInfo(id: $0.element, index: $0.offset, shareableIds: shareableIds, denied: denied) }
            .sorted { lhs, rhs in
                let leftPrimary = lhs["isPrimary"] as? Bool ?? false
                let rightPrimary = rhs["isPrimary"] as? Bool ?? false
                if leftPrimary != rightPrimary { return leftPrimary }
                let leftX = lhs["originX"] as? Int ?? 0
                let rightX = rhs["originX"] as? Int ?? 0
                if leftX != rightX { return leftX < rightX }
                let leftY = lhs["originY"] as? Int ?? 0
                let rightY = rhs["originY"] as? Int ?? 0
                if leftY != rightY { return leftY < rightY }
                return (lhs["id"] as? String ?? "") < (rhs["id"] as? String ?? "")
            }
    }

    private func onlineDisplayIds() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else {
            return []
        }
        var ids = Array(repeating: CGDirectDisplayID(0), count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else {
            return []
        }
        return Array(ids.prefix(Int(count)))
    }

    private func displayInfo(
        id displayId: CGDirectDisplayID,
        index: Int,
        shareableIds: Set<CGDirectDisplayID>,
        denied: Bool
    ) -> [String: Any] {
        let screen = NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayId
        }
        let displayName = screen?.localizedName.nonEmpty ?? "Display \(index + 1)"
        let mode = CGDisplayCopyDisplayMode(displayId)
        let width = mode.map(\.pixelWidth) ?? Int(CGDisplayPixelsWide(displayId))
        let height = mode.map(\.pixelHeight) ?? Int(CGDisplayPixelsHigh(displayId))
        let scale = screen?.backingScaleFactor ?? 1
        let frame = screen?.frame ?? CGRect(
            x: CGDisplayBounds(displayId).origin.x,
            y: CGDisplayBounds(displayId).origin.y,
            width: CGFloat(width) / scale,
            height: CGFloat(height) / scale
        )
        let visible = screen?.visibleFrame ?? frame
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "display-\(displayId)"
        let kind: String = if displayName.localizedCaseInsensitiveContains("virtual")
            || CGDisplayVendorNumber(displayId) == 0 {
            "virtual"
        } else if CGDisplayIsBuiltin(displayId) != 0 {
            "builtIn"
        } else {
            "physical"
        }
        let capturable = shareableIds.contains(displayId)
        let captureStatus = denied ? "permissionDenied" : (capturable ? "available" : "unsupported")
        let detail: Any = if denied {
            "Screen Recording permission required"
        } else if capturable {
            NSNull()
        } else {
            "Not available to ScreenCaptureKit (mirrored or asleep)"
        }

        return [
            "id": "mac:\(uuid)",
            "name": displayName,
            "widthPx": width,
            "heightPx": height,
            "scaleFactor": scale,
            "refreshRateHz": mode?.refreshRate ?? 0,
            "originX": Int((screen?.frame.minX ?? frame.minX) * scale),
            "originY": Int((screen?.frame.minY ?? frame.minY) * scale),
            "workX": Int(visible.minX * scale),
            "workY": Int(visible.minY * scale),
            "workWidth": Int(visible.width * scale),
            "workHeight": Int(visible.height * scale),
            "isPrimary": CGDisplayIsMain(displayId) != 0,
            "kind": kind,
            "captureStatus": captureStatus,
            "captureStatusDetail": detail,
        ]
    }

    private func startCapture(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let displayId = args["displayId"] as? String else {
            result(FlutterError(code: "INTERNAL", message: "displayId is required", details: nil))
            return
        }
        guard CGPreflightScreenCaptureAccess(), !permissionNeedsRelaunch else {
            result(FlutterError(
                code: "PERMISSION_DENIED",
                message: "Screen Recording permission required. Grant access and relaunch the app.",
                details: nil
            ))
            return
        }

        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                DispatchQueue.main.async {
                    guard let self else {
                        result(FlutterError(
                            code: "INTERNAL",
                            message: "The capture plugin stopped during startup",
                            details: nil
                        ))
                        return
                    }
                    guard let display = content.displays.first(where: {
                        Self.displayIdentifier($0.displayID) == displayId
                    }) else {
                        result(FlutterError(
                            code: "DISPLAY_NOT_FOUND",
                            message: "Display is not available to ScreenCaptureKit",
                            details: nil
                        ))
                        return
                    }
                    self.createCapture(display: display, content: content, args: args, result: result)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    if let self {
                        self.finishStartError(error, result: result)
                    } else {
                        result(FlutterError(
                            code: "INTERNAL",
                            message: "The capture plugin stopped during startup",
                            details: nil
                        ))
                    }
                }
            }
        }
    }

    private func createCapture(
        display: SCDisplay,
        content: SCShareableContent,
        args: [String: Any],
        result: @escaping FlutterResult
    ) {
        let pixelWidth = Int(CGDisplayPixelsWide(display.displayID))
        let pixelHeight = Int(CGDisplayPixelsHigh(display.displayID))
        guard pixelWidth > 0, pixelHeight > 0 else {
            result(FlutterError(
                code: "DISPLAY_NOT_FOUND",
                message: "The display has no available pixel dimensions",
                details: nil
            ))
            return
        }
        let maxWidth = (args["maxWidthPx"] as? NSNumber)?.intValue ?? 0
        let maxHeight = (args["maxHeightPx"] as? NSNumber)?.intValue ?? 0
        let (width, height) = outputSize(
            sourceWidth: pixelWidth,
            sourceHeight: pixelHeight,
            maxWidth: maxWidth,
            maxHeight: maxHeight
        )
        let requestedFPS = (args["fps"] as? NSNumber)?.intValue ?? 60
        let reportedRefreshRate = CGDisplayCopyDisplayMode(display.displayID).map {
            $0.refreshRate
        } ?? 0
        let refreshRate = reportedRefreshRate > 0 ? reportedRefreshRate : 60
        let fps = max(1, min(requestedFPS > 0 ? requestedFPS : 60, Int(refreshRate.rounded())))

        let showCursor = (args["showCursor"] as? Bool) ?? true
        let configuration = streamConfiguration(
            width: width,
            height: height,
            fps: fps,
            showCursor: showCursor
        )

        let excludedWindows = NSApp.windows
            .filter { $0.isVisible && $0.windowNumber > 0 }
            .compactMap { displayWindow(windowNumber: $0.windowNumber, in: content) }
        let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
        let sessionId = nextSessionId
        nextSessionId += 1
        let ownerHandle = (args["ownerWindowHandle"] as? NSNumber)?.intValue
        let frameTexture: FrameTexture
        let pipeline: MetalFramePipeline
        do {
            pipeline = try MetalFramePipeline(width: width, height: height)
            frameTexture = FrameTexture()
        } catch {
            result(FlutterError(code: "GPU_ERROR", message: error.localizedDescription, details: nil))
            return
        }
        let textureId = textureRegistry.register(frameTexture)
        guard textureId != 0 else {
            result(FlutterError(code: "GPU_ERROR", message: "Flutter could not register the capture texture", details: nil))
            return
        }

        let output = CaptureOutput(pipeline: pipeline, texture: frameTexture) { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                self.textureRegistry.textureFrameAvailable(textureId)
            }
        } event: { [weak self] type, code, message in
            guard let self else { return }
            DispatchQueue.main.async {
                self.sendEvent(
                    sessionId: sessionId,
                    ["type": type, "code": code, "message": message]
                )
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        } catch {
            textureRegistry.unregisterTexture(textureId)
            result(FlutterError(code: "CAPTURE_FAILED", message: error.localizedDescription, details: nil))
            return
        }

        let record = CaptureRecord(
            id: sessionId,
            textureId: textureId,
            ownerHandle: ownerHandle,
            stream: stream,
            output: output,
            texture: frameTexture,
            pipeline: pipeline,
            configuration: configuration,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            fps: fps,
            showCursor: showCursor,
            width: width,
            height: height
        )
        record.displayId = Self.displayIdentifier(display.displayID)
        let eventChannel = FlutterEventChannel(
            name: "com.virtualmonitor/display_capture/session/\(sessionId)",
            binaryMessenger: messenger
        )
        record.eventChannel = eventChannel
        eventChannel.setStreamHandler(EventStreamHandler(onListen: { [weak self, weak record] sink in
            guard let self, let record, self.sessions[sessionId] === record else { return }
            record.eventSink = sink
            record.pendingEvents.forEach(sink)
            record.pendingEvents.removeAll()
        }, onCancel: { [weak record] in
            record?.eventSink = nil
        }))
        sessions[sessionId] = record
        updateContentFilters()

        stream.startCapture { [weak self, weak record] error in
            DispatchQueue.main.async {
                guard let self else {
                    result(FlutterError(code: "INTERNAL", message: "The capture plugin stopped during startup", details: nil))
                    return
                }
                guard let record, self.sessions[sessionId] === record else {
                    result(FlutterError(code: "CAPTURE_FAILED", message: "The display window closed while capture was starting", details: nil))
                    return
                }
                if let error {
                    self.stopCapture(sessionId)
                    self.finishStartError(error, result: result)
                    return
                }
                result([
                    "sessionId": sessionId,
                    "textureId": textureId,
                    "widthPx": width,
                    "heightPx": height,
                ])
            }
        }
    }

    private func finishStartError(_ error: Error?, result: @escaping FlutterResult) {
        let nsError = error as NSError?
        let code = nsError?.domain == SCStreamErrorDomain
            && nsError?.code == SCStreamError.userDeclined.rawValue
            ? "PERMISSION_DENIED"
            : "CAPTURE_FAILED"
        result(FlutterError(
            code: code,
            message: error?.localizedDescription ?? "ScreenCaptureKit could not enumerate displays",
            details: nil
        ))
    }

    private func stopCapture(_ sessionId: Int64) {
        guard let record = sessions.removeValue(forKey: sessionId) else { return }
        record.output.stop()
        record.stream.stopCapture { error in
            if let error {
                captureLogger.error("Stopping capture session \(sessionId) failed: \(error.localizedDescription, privacy: .public)")
            }
            DispatchQueue.main.async {
                do {
                    try record.stream.removeStreamOutput(record.output, type: .screen)
                } catch {
                    captureLogger.error("Removing capture output failed: \(error.localizedDescription, privacy: .public)")
                }
                record.eventChannel?.setStreamHandler(nil)
                self.textureRegistry.unregisterTexture(record.textureId)
            }
        }
        record.output.stop()
    }

    private func setupDisplayWindow(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let nativeHandle = (args["nativeHandle"] as? NSNumber)?.intValue,
              let window = window(for: nativeHandle) else {
            result(FlutterError(code: "INTERNAL", message: "nativeHandle is not a valid NSWindow", details: nil))
            return
        }
        let frame = window.frame
        let origin = appKitOrigin(
            physicalX: (args["x"] as? NSNumber)?.doubleValue ?? 0,
            physicalY: (args["y"] as? NSNumber)?.doubleValue ?? 0
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.level = .floating
        window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.isMovableByWindowBackground = false
        window.setFrame(
            CGRect(origin: origin, size: frame.size),
            display: true,
            animate: false
        )
        registerCloseObserver(for: window, handle: nativeHandle)
        updateContentFilters()
        result(nil)
    }

    private func appKitOrigin(physicalX: Double, physicalY: Double) -> CGPoint {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let display = number.uint32Value
            let scale = screen.backingScaleFactor
            let originX = screen.frame.minX * scale
            let originY = screen.frame.minY * scale
            let width = CGFloat(CGDisplayPixelsWide(display))
            let height = CGFloat(CGDisplayPixelsHigh(display))
            if physicalX >= originX && physicalX < originX + width
                && physicalY >= originY && physicalY < originY + height {
                return CGPoint(
                    x: screen.frame.minX + (physicalX - originX) / scale,
                    y: screen.frame.minY + (physicalY - originY) / scale
                )
            }
        }
        let scale = NSScreen.main?.backingScaleFactor ?? 1
        return CGPoint(x: physicalX / scale, y: physicalY / scale)
    }

    private func window(for handle: Int) -> NSWindow? {
        guard handle != 0,
              let pointer = UnsafeRawPointer(bitPattern: UInt(handle)) else { return nil }
        return NSApp.windows.first {
            Unmanaged.passUnretained($0).toOpaque() == pointer
        }
    }

    private func registerCloseObserver(for window: NSWindow, handle: Int) {
        if let observer = closeObservers.removeValue(forKey: handle) {
            NotificationCenter.default.removeObserver(observer)
        }
        closeObservers[handle] = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.closeObservers.removeValue(forKey: handle)
            let sessionsToStop = self.sessions.values
                .filter { $0.ownerHandle == handle }
                .map(\.id)
            sessionsToStop.forEach(self.stopCapture)
        }
    }

    private func updateContentFilters() {
        guard !sessions.isEmpty else { return }
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: false
                )
                DispatchQueue.main.async {
                    guard let self else { return }
                    let windows = NSApp.windows
                        .filter { $0.isVisible && $0.windowNumber > 0 }
                        .compactMap { self.displayWindow(windowNumber: $0.windowNumber, in: content) }
                    for record in self.sessions.values {
                        guard let displayId = record.displayId,
                              let display = content.displays.first(where: {
                                  Self.displayIdentifier($0.displayID) == displayId
                              }) else { continue }
                        let filter = SCContentFilter(display: display, excludingWindows: windows)
                        record.stream.updateContentFilter(filter) { error in
                            if let error {
                                captureLogger.error("Updating capture filter failed: \(error.localizedDescription, privacy: .public)")
                            }
                        }
                    }
                }
            } catch {
                captureLogger.error("Updating capture exclusions failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func displayWindow(windowNumber: Int, in content: SCShareableContent?) -> SCWindow? {
        content?.windows.first(where: { $0.windowID == CGWindowID(windowNumber) })
    }

    private func sendDisplaysChanged() {
        guard displaysSink != nil else { return }
        listDisplays { [weak self] displays in
            guard let self, let sink = self.displaysSink else { return }
            sink(displays)
            let activeSessions = Array(self.sessions.values)
            let displayById = Dictionary(
                uniqueKeysWithValues: displays.compactMap { display in
                    (display["id"] as? String).map { ($0, display) }
                }
            )
            for record in activeSessions {
                guard let displayId = record.displayId,
                      let display = displayById[displayId] else {
                    self.sendEvent(sessionId: record.id, ["type": "displayLost"])
                    self.stopCapture(record.id)
                    continue
                }
                self.updateCaptureResolution(record, displayInfo: display)
            }
            self.updateContentFilters()
        }
    }

    private func updateCaptureResolution(_ record: CaptureRecord, displayInfo: [String: Any]) {
        guard let sourceWidth = displayInfo["widthPx"] as? Int,
              let sourceHeight = displayInfo["heightPx"] as? Int else { return }
        let (width, height) = outputSize(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            maxWidth: record.maxWidth,
            maxHeight: record.maxHeight
        )
        guard width != record.width || height != record.height else { return }

        let pipeline: MetalFramePipeline
        do {
            pipeline = try MetalFramePipeline(width: width, height: height)
        } catch {
            sendEvent(
                sessionId: record.id,
                ["type": "failed", "code": "GPU_ERROR", "message": error.localizedDescription]
            )
            return
        }

        let oldPipeline = record.pipeline
        record.output.updatePipeline(pipeline)
        let configuration = streamConfiguration(
            width: width,
            height: height,
            fps: record.fps,
            showCursor: record.showCursor
        )
        record.stream.updateConfiguration(configuration) { [weak self, weak record] error in
            DispatchQueue.main.async {
                guard let self, let record, self.sessions[record.id] === record else { return }
                if let error {
                    record.output.updatePipeline(oldPipeline)
                    captureLogger.error("Updating capture resolution failed: \(error.localizedDescription, privacy: .public)")
                    self.sendEvent(
                        sessionId: record.id,
                        ["type": "failed", "code": "CAPTURE_FAILED", "message": error.localizedDescription]
                    )
                    return
                }
                record.configuration = configuration
                record.width = width
                record.height = height
                record.pipeline = pipeline
                self.sendEvent(
                    sessionId: record.id,
                    ["type": "frameSize", "widthPx": width, "heightPx": height]
                )
            }
        }
    }

    private func outputSize(
        sourceWidth: Int,
        sourceHeight: Int,
        maxWidth: Int,
        maxHeight: Int
    ) -> (Int, Int) {
        let widthRatio = maxWidth > 0 ? Double(maxWidth) / Double(sourceWidth) : 1
        let heightRatio = maxHeight > 0 ? Double(maxHeight) / Double(sourceHeight) : 1
        let ratio = min(widthRatio, heightRatio, 1)
        return (
            max(1, Int((Double(sourceWidth) * ratio).rounded())),
            max(1, Int((Double(sourceHeight) * ratio).rounded()))
        )
    }

    private func sendEvent(sessionId: Int64, _ event: [String: Any]) {
        guard let record = sessions[sessionId] else { return }
        if let sink = record.eventSink {
            sink(event)
        } else {
            record.pendingEvents.append(event)
        }
    }

    private func diagnostics() -> [String: Any] {
        let device = MTLCreateSystemDefaultDevice()
        return [
            "renderPath": "metal-iosurface",
            "backend": "screencapturekit-metal",
            "gpuName": device?.name ?? "Metal",
            "driver": ProcessInfo.processInfo.operatingSystemVersionString,
        ]
    }

    private func scheduleDisplayChange() {
        displayChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sendDisplaysChanged() }
        displayChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
    }

    @objc private func screenParametersChanged() {
        scheduleDisplayChange()
    }

    func onDisplayReconfigured(_ display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        scheduleDisplayChange()
    }

    private static func displayIdentifier(_ displayId: CGDirectDisplayID) -> String {
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayId)
            .map { CFUUIDCreateString(nil, $0.takeRetainedValue()) as String } ?? "display-\(displayId)"
        return "mac:\(uuid)"
    }
}

private let displayReconfigured: CGDisplayReconfigurationCallBack = { display, flags, userInfo in
    guard let userInfo else { return }
    let plugin = Unmanaged<DisplayCapturePlugin>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async {
        plugin.onDisplayReconfigured(display, flags: flags)
    }
}

private final class CaptureRecord {
    let id: Int64
    let textureId: Int64
    let ownerHandle: Int?
    let stream: SCStream
    let output: CaptureOutput
    let texture: FrameTexture
    var pipeline: MetalFramePipeline
    var configuration: SCStreamConfiguration
    let maxWidth: Int
    let maxHeight: Int
    let fps: Int
    let showCursor: Bool
    var width: Int
    var height: Int
    var displayId: String?
    var eventChannel: FlutterEventChannel?
    var eventSink: FlutterEventSink?
    var pendingEvents: [[String: Any]] = []

    init(
        id: Int64,
        textureId: Int64,
        ownerHandle: Int?,
        stream: SCStream,
        output: CaptureOutput,
        texture: FrameTexture,
        pipeline: MetalFramePipeline,
        configuration: SCStreamConfiguration,
        maxWidth: Int,
        maxHeight: Int,
        fps: Int,
        showCursor: Bool,
        width: Int,
        height: Int
    ) {
        self.id = id
        self.textureId = textureId
        self.ownerHandle = ownerHandle
        self.stream = stream
        self.output = output
        self.texture = texture
        self.pipeline = pipeline
        self.configuration = configuration
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.fps = fps
        self.showCursor = showCursor
        self.width = width
        self.height = height
    }
}

final class EventStreamHandler: NSObject, FlutterStreamHandler {
    typealias ListenHandler = (@escaping FlutterEventSink) -> Void
    private let onListen: ListenHandler
    private let onCancel: () -> Void

    init(onListen: @escaping ListenHandler, onCancel: @escaping () -> Void) {
        self.onListen = onListen
        self.onCancel = onCancel
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListen(events)
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onCancel()
        return nil
    }
}

private final class FrameTexture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func publish(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        latest = pixelBuffer
        lock.unlock()
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        let pixelBuffer = latest
        lock.unlock()
        guard let pixelBuffer else { return nil }
        return Unmanaged.passRetained(pixelBuffer)
    }
}

private final class CaptureOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "dc.capture", qos: .userInteractive)
    private let pipelineLock = NSLock()
    private var pipeline: MetalFramePipeline
    private weak var texture: FrameTexture?
    private let frameAvailable: () -> Void
    private let event: (String, String, String) -> Void
    private let stateLock = NSLock()
    private var stopping = false

    init(
        pipeline: MetalFramePipeline,
        texture: FrameTexture,
        frameAvailable: @escaping () -> Void,
        event: @escaping (String, String, String) -> Void
    ) {
        self.pipeline = pipeline
        self.texture = texture
        self.frameAvailable = frameAvailable
        self.event = event
    }

    func updatePipeline(_ pipeline: MetalFramePipeline) {
        pipelineLock.lock()
        self.pipeline = pipeline
        pipelineLock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        stateLock.lock()
        let shouldProcess = !stopping
        stateLock.unlock()
        guard type == .screen,
              shouldProcess,
              CMSampleBufferIsValid(sampleBuffer),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer,
                createIfNecessary: false
              ) as? [[SCStreamFrameInfo: Any]],
              let statusValue = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: statusValue) == .complete,
              let source = CMSampleBufferGetImageBuffer(sampleBuffer),
              let texture else { return }
        pipelineLock.lock()
        let pipeline = self.pipeline
        pipelineLock.unlock()
        do {
            let output = try pipeline.render(source)
            texture.publish(output)
            frameAvailable()
        } catch {
            if case CapturePipelineError.outputBuffersBusy = error {
                return
            }
            event("failed", "GPU_ERROR", error.localizedDescription)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        stateLock.lock()
        let shouldReport = !stopping
        stateLock.unlock()
        guard shouldReport else { return }
        let nsError = error as NSError
        let code = nsError.domain == SCStreamErrorDomain
            && nsError.code == SCStreamError.userDeclined.rawValue
            ? "PERMISSION_DENIED"
            : "CAPTURE_FAILED"
        event("failed", code, error.localizedDescription)
    }

    func stop() {
        stateLock.lock()
        stopping = true
        stateLock.unlock()
    }
}

private final class MetalFramePipeline {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState
    private let textureCache: CVMetalTextureCache
    private let pixelBufferPool: CVPixelBufferPool
    private let width: Int
    private let height: Int

    init(width: Int, height: Int) throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            throw CapturePipelineError.noMetalDevice
        }
        self.device = device
        self.commandQueue = commandQueue
        self.width = width
        self.height = height

        var cache: CVMetalTextureCache?
        let cacheStatus = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &cache
        )
        guard cacheStatus == kCVReturnSuccess, let cache else {
            throw CapturePipelineError.metalTextureCache(cacheStatus)
        }
        textureCache = cache

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferCGImageCompatibilityKey as String: true,
        ]
        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            [kCVPixelBufferPoolMinimumBufferCountKey as String: 3] as CFDictionary,
            pixelBufferAttributes as CFDictionary,
            &pool
        )
        guard poolStatus == kCVReturnSuccess, let pool else {
            throw CapturePipelineError.pixelBufferPool(poolStatus)
        }
        pixelBufferPool = pool

        #if SWIFT_PACKAGE
        let shaderBundle = Bundle.module
        #else
        let shaderBundle = Bundle(for: DisplayCapturePlugin.self)
        #endif
        let library = try device.makeDefaultLibrary(bundle: shaderBundle)
        guard let vertex = library.makeFunction(name: "dc_vertex"),
              let fragment = library.makeFunction(name: "dc_fragment") else {
            throw CapturePipelineError.metalShaders
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func render(_ sourceBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let sourceWidth = CVPixelBufferGetWidth(sourceBuffer)
        let sourceHeight = CVPixelBufferGetHeight(sourceBuffer)
        var sourceTextureRef: CVMetalTexture?
        var destinationTextureRef: CVMetalTexture?
        let sourceStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            sourceBuffer,
            nil,
            .bgra8Unorm,
            sourceWidth,
            sourceHeight,
            0,
            &sourceTextureRef
        )
        guard sourceStatus == kCVReturnSuccess,
              let sourceTexture = sourceTextureRef.flatMap(CVMetalTextureGetTexture) else {
            throw CapturePipelineError.metalTexture(sourceStatus)
        }

        var destinationBuffer: CVPixelBuffer?
        let threshold: [String: Any] = [
            kCVPixelBufferPoolAllocationThresholdKey as String: 4,
        ]
        let allocationStatus = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault,
            pixelBufferPool,
            threshold as CFDictionary,
            &destinationBuffer
        )
        guard allocationStatus == kCVReturnSuccess, let destinationBuffer else {
            if allocationStatus == kCVReturnWouldExceedAllocationThreshold {
                throw CapturePipelineError.outputBuffersBusy
            }
            throw CapturePipelineError.pixelBuffer(allocationStatus)
        }

        let destinationStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            destinationBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &destinationTextureRef
        )
        guard destinationStatus == kCVReturnSuccess,
              let destinationTexture = destinationTextureRef.flatMap(CVMetalTextureGetTexture),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let sampler = device.makeSamplerState(descriptor: samplerDescriptor()),
              let renderPass = MTLRenderPassDescriptor() as MTLRenderPassDescriptor? else {
            throw CapturePipelineError.metalTexture(destinationStatus)
        }

        renderPass.colorAttachments[0].texture = destinationTexture
        renderPass.colorAttachments[0].loadAction = .dontCare
        renderPass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            throw CapturePipelineError.metalEncoder
        }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else {
            throw commandBuffer.error ?? CapturePipelineError.metalCommand
        }
        return destinationBuffer
    }

    private func samplerDescriptor() -> MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return descriptor
    }
}

private enum CapturePipelineError: LocalizedError {
    case noMetalDevice
    case metalTextureCache(CVReturn)
    case pixelBufferPool(CVReturn)
    case metalShaders
    case metalTexture(CVReturn)
    case pixelBuffer(CVReturn)
    case outputBuffersBusy
    case metalEncoder
    case metalCommand

    var errorDescription: String? {
        switch self {
        case .noMetalDevice:
            return "No Metal device or command queue is available"
        case .metalTextureCache(let status):
            return "Could not create the Metal texture cache (\(status))"
        case .pixelBufferPool(let status):
            return "Could not create the IOSurface pixel buffer pool (\(status))"
        case .metalShaders:
            return "Could not compile the Metal frame shaders"
        case .metalTexture(let status):
            return "Could not create a Metal texture from a frame (\(status))"
        case .pixelBuffer(let status):
            return "Could not allocate a frame pixel buffer (\(status))"
        case .outputBuffersBusy:
            return "All IOSurface output buffers are in use; dropping this frame"
        case .metalEncoder:
            return "Could not create a Metal render encoder"
        case .metalCommand:
            return "The Metal frame command failed"
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
