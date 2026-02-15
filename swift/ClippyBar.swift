import AppKit
import SwiftUI
import Foundation

// MARK: - IPC Types

struct HistoryItem: Codable {
    let id: Int
    let preview: String
    let contentLength: Int
    let createdAt: String
    let accessedAt: String

    enum CodingKeys: String, CodingKey {
        case id, preview
        case contentLength = "contentLength"
        case createdAt = "createdAt"
        case accessedAt = "accessedAt"
    }
}

struct StateUpdate: Codable {
    let type: String
    let countdown: Int?
    let paused: Bool
    let history: [HistoryItem]
    let entryCount: Int
}

struct HelloMessage: Codable {
    let type: String
    let version: String
}

struct ClippyConfig: Codable {
    var wipeDelay: Int
    var maxContentLength: Int
    var maxHistoryEntries: Int
    var maxHistoryAge: Int
    var pollInterval: Int
    var historyDisplayCount: Int
    var previewLength: Int

    static let defaults = ClippyConfig(
        wipeDelay: 5, maxContentLength: 10000, maxHistoryEntries: 1000,
        maxHistoryAge: 30, pollInterval: 500, historyDisplayCount: 20,
        previewLength: 50
    )
}

struct ConfigResponse: Codable {
    let type: String
    let config: ClippyConfig
}

struct Command: Codable {
    let type: String
    let action: String
    var id: Int?
    var config: ClippyConfig?
}

// MARK: - Socket Client

class SocketClient: NSObject, StreamDelegate {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private var buffer = ""
    private let socketPath: String
    private var connected = false
    private var reconnectTimer: Timer?
    var onState: ((StateUpdate) -> Void)?
    var onConfig: ((ClippyConfig) -> Void)?
    var onConnect: (() -> Void)?
    var onDisconnect: (() -> Void)?

    init(socketPath: String) {
        self.socketPath = socketPath
        super.init()
    }

    func connect() {
        disconnect()

        var readStream: Unmanaged<CFReadStream>?
        var writeStream: Unmanaged<CFWriteStream>?

        CFStreamCreatePairWithSocketToHost(nil, socketPath as CFString, 0, &readStream, &writeStream)

        let sockFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard sockFd >= 0 else {
            scheduleReconnect()
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            close(sockFd)
            scheduleReconnect()
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                for i in 0..<pathBytes.count {
                    dest[i] = pathBytes[i]
                }
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Foundation.connect(sockFd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            close(sockFd)
            scheduleReconnect()
            return
        }

        CFStreamCreatePairWithSocket(nil, sockFd, &readStream, &writeStream)
        if let rs = readStream, let ws = writeStream {
            inputStream = rs.takeRetainedValue() as InputStream
            outputStream = ws.takeRetainedValue() as OutputStream

            CFReadStreamSetProperty(rs.takeUnretainedValue(), CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanFalse)
            CFWriteStreamSetProperty(ws.takeUnretainedValue(), CFStreamPropertyKey(rawValue: kCFStreamPropertyShouldCloseNativeSocket), kCFBooleanFalse)
        } else {
            close(sockFd)
            scheduleReconnect()
            return
        }

        inputStream?.delegate = self
        inputStream?.schedule(in: .main, forMode: .common)
        inputStream?.open()
        outputStream?.open()

        connected = true
        onConnect?()
    }

    func disconnect() {
        connected = false
        inputStream?.close()
        outputStream?.close()
        inputStream?.remove(from: .main, forMode: .common)
        inputStream = nil
        outputStream = nil
        buffer = ""
    }

    func send(_ command: Command) {
        guard connected, let stream = outputStream else { return }
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(command) else { return }
        var line = data
        line.append(contentsOf: "\n".utf8)
        _ = line.withUnsafeBytes { ptr in
            stream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: line.count)
        }
    }

    func sendRaw(_ json: String) {
        guard connected, let stream = outputStream else { return }
        let line = (json + "\n").data(using: .utf8)!
        _ = line.withUnsafeBytes { ptr in
            stream.write(ptr.bindMemory(to: UInt8.self).baseAddress!, maxLength: line.count)
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .hasBytesAvailable:
            guard let input = aStream as? InputStream else { return }
            var buf = [UInt8](repeating: 0, count: 4096)
            while input.hasBytesAvailable {
                let read = input.read(&buf, maxLength: buf.count)
                if read > 0 {
                    buffer += String(bytes: buf[0..<read], encoding: .utf8) ?? ""
                    processBuffer()
                }
            }
        case .errorOccurred, .endEncountered:
            disconnect()
            onDisconnect?()
            scheduleReconnect()
        default:
            break
        }
    }

    private func processBuffer() {
        let decoder = JSONDecoder()
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            guard !line.isEmpty, let data = line.data(using: .utf8) else { continue }

            // Try parsing as each known message type
            if let state = try? decoder.decode(StateUpdate.self, from: data), state.type == "state" {
                onState?(state)
            } else if let cfg = try? decoder.decode(ConfigResponse.self, from: data), cfg.type == "config" {
                onConfig?(cfg.config)
            }
        }
    }

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            self?.connect()
        }
    }
}

// MARK: - Settings View Model

class SettingsViewModel: ObservableObject {
    @Published var wipeDelay: String = "5"
    @Published var maxContentLength: String = "10000"
    @Published var maxHistoryEntries: String = "1000"
    @Published var maxHistoryAge: String = "30"
    @Published var pollInterval: String = "500"
    @Published var historyDisplayCount: String = "20"
    @Published var previewLength: String = "50"

    func load(from config: ClippyConfig) {
        wipeDelay = "\(config.wipeDelay)"
        maxContentLength = "\(config.maxContentLength)"
        maxHistoryEntries = "\(config.maxHistoryEntries)"
        maxHistoryAge = "\(config.maxHistoryAge)"
        pollInterval = "\(config.pollInterval)"
        historyDisplayCount = "\(config.historyDisplayCount)"
        previewLength = "\(config.previewLength)"
    }

    func toConfig() -> ClippyConfig {
        ClippyConfig(
            wipeDelay: Int(wipeDelay) ?? 5,
            maxContentLength: Int(maxContentLength) ?? 10000,
            maxHistoryEntries: Int(maxHistoryEntries) ?? 1000,
            maxHistoryAge: Int(maxHistoryAge) ?? 30,
            pollInterval: Int(pollInterval) ?? 500,
            historyDisplayCount: Int(historyDisplayCount) ?? 20,
            previewLength: Int(previewLength) ?? 50
        )
    }
}

// MARK: - Numeric Text Field

struct NumericField: View {
    let label: String
    @Binding var text: String
    let unit: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .frame(width: 140, alignment: .trailing)
            TextField("", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
                .onReceive(text.publisher.collect()) { chars in
                    let filtered = String(chars.filter { $0.isNumber })
                    if filtered != text { text = filtered }
                }
            Text(unit)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .leading)
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    var onSave: (ClippyConfig) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Clipboard") {
                VStack(spacing: 10) {
                    NumericField(label: "Auto-wipe delay", text: $viewModel.wipeDelay, unit: "seconds")
                    NumericField(label: "Poll interval", text: $viewModel.pollInterval, unit: "ms")
                    NumericField(label: "Max content length", text: $viewModel.maxContentLength, unit: "chars")
                }
                .padding(6)
            }

            GroupBox("History") {
                VStack(spacing: 10) {
                    NumericField(label: "Max entries", text: $viewModel.maxHistoryEntries, unit: "entries")
                    NumericField(label: "Max age", text: $viewModel.maxHistoryAge, unit: "days")
                    NumericField(label: "Menu items shown", text: $viewModel.historyDisplayCount, unit: "items")
                    NumericField(label: "Preview length", text: $viewModel.previewLength, unit: "chars")
                }
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Cancel") { onClose() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(viewModel.toConfig())
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Settings Window Controller

class SettingsWindowController {
    private var window: NSWindow?
    private let viewModel = SettingsViewModel()
    private var onSave: ((ClippyConfig) -> Void)?

    func show(config: ClippyConfig, onSave: @escaping (ClippyConfig) -> Void) {
        self.onSave = onSave
        viewModel.load(from: config)

        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(
            viewModel: viewModel,
            onSave: { [weak self] config in self?.onSave?(config) },
            onClose: { [weak self] in self?.window?.close() }
        )

        let hostingView = NSHostingView(rootView: settingsView)
        let fittingSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: fittingSize)

        let w = NSWindow(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        w.title = "Clippy Settings"
        w.contentView = hostingView
        w.center()
        w.isReleasedWhenClosed = false
        w.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        window = w
    }
}

// MARK: - Status Bar App

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var client: SocketClient!
    private var currentState: StateUpdate?
    private var currentConfig: ClippyConfig?
    private let clippyDir: String
    private let settingsController = SettingsWindowController()

    init(clippyDir: String) {
        self.clippyDir = clippyDir
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateTitle(nil)

        let socketPath = (clippyDir as NSString).appendingPathComponent("clippy.sock")
        client = SocketClient(socketPath: socketPath)

        client.onState = { [weak self] state in
            DispatchQueue.main.async {
                self?.currentState = state
                self?.updateTitle(state.countdown)
                self?.rebuildMenu(state)
            }
        }

        client.onConfig = { [weak self] config in
            DispatchQueue.main.async {
                self?.currentConfig = config
            }
        }

        client.onConnect = { [weak self] in
            DispatchQueue.main.async {
                self?.updateTitle(nil)
                // Request config on connect
                self?.client.send(Command(type: "command", action: "get_config"))
            }
        }

        client.onDisconnect = { [weak self] in
            DispatchQueue.main.async {
                self?.statusItem.button?.title = "✂ ?"
                self?.statusItem.menu = self?.buildDisconnectedMenu()
            }
        }

        client.connect()
        rebuildMenu(nil)
    }

    private func updateTitle(_ countdown: Int?) {
        if let cd = countdown, cd > 0 {
            statusItem.button?.title = "✂ \(cd)s"
        } else {
            statusItem.button?.title = "✂"
        }
    }

    private func rebuildMenu(_ state: StateUpdate?) {
        let menu = NSMenu()

        if let state = state {
            if state.history.isEmpty {
                let item = NSMenuItem(title: "No clipboard history", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            } else {
                for entry in state.history {
                    let preview = entry.preview.count > 50
                        ? String(entry.preview.prefix(50)) + "..."
                        : entry.preview
                    let item = NSMenuItem(title: preview, action: #selector(copyEntry(_:)), keyEquivalent: "")
                    item.target = self
                    item.tag = entry.id
                    menu.addItem(item)
                }
            }

            menu.addItem(NSMenuItem.separator())

            if state.countdown != nil {
                if state.paused {
                    let item = NSMenuItem(title: "Resume Countdown", action: #selector(resumeCountdown), keyEquivalent: "")
                    item.target = self
                    menu.addItem(item)
                } else {
                    let item = NSMenuItem(title: "Pause Countdown", action: #selector(pauseCountdown), keyEquivalent: "")
                    item.target = self
                    menu.addItem(item)
                }
            }

            let countLabel = NSMenuItem(title: "\(state.entryCount) entries stored", action: nil, keyEquivalent: "")
            countLabel.isEnabled = false
            menu.addItem(countLabel)
        } else {
            let item = NSMenuItem(title: "Connecting...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let clearClip = NSMenuItem(title: "Clear Clipboard", action: #selector(clearClipboard), keyEquivalent: "")
        clearClip.target = self
        menu.addItem(clearClip)

        let clearHist = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clearHist.target = self
        menu.addItem(clearHist)

        menu.addItem(NSMenuItem.separator())

        let settings = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func buildDisconnectedMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Disconnected - reconnecting...", action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        menu.addItem(NSMenuItem.separator())
        let quit = NSMenuItem(title: "Quit Clippy", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    @objc private func copyEntry(_ sender: NSMenuItem) {
        client.send(Command(type: "command", action: "copy_entry", id: sender.tag))
    }

    @objc private func pauseCountdown() {
        client.send(Command(type: "command", action: "pause_countdown"))
    }

    @objc private func resumeCountdown() {
        client.send(Command(type: "command", action: "resume_countdown"))
    }

    @objc private func clearClipboard() {
        client.send(Command(type: "command", action: "clear_clipboard"))
    }

    @objc private func clearHistory() {
        client.send(Command(type: "command", action: "clear_history"))
    }

    @objc private func openSettings() {
        // Request fresh config before opening
        client.send(Command(type: "command", action: "get_config"))

        let config = currentConfig ?? ClippyConfig.defaults
        settingsController.show(config: config) { [weak self] updatedConfig in
            self?.currentConfig = updatedConfig
            self?.client.send(Command(type: "command", action: "update_config", config: updatedConfig))
        }
    }

    @objc private func quitApp() {
        client.send(Command(type: "command", action: "quit"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count > 1 else {
    fputs("Usage: ClippyBar <clippy-dir>\n", stderr)
    exit(1)
}

let clippyDir = args[1]
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(clippyDir: clippyDir)
app.delegate = delegate
app.run()
