import AppKit
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

struct Command: Codable {
    let type: String
    let action: String
    var id: Int?
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

        // Use Unix domain socket via file path
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

        inputStream = InputStream(fileAtPath: "/dev/fd/\(sockFd)")
        outputStream = OutputStream(toFileAtPath: "/dev/fd/\(sockFd)", append: true)

        // Use CFSocket-based streams for the file descriptor
        CFStreamCreatePairWithSocket(nil, sockFd, &readStream, &writeStream)
        if let rs = readStream, let ws = writeStream {
            inputStream = rs.takeRetainedValue() as InputStream
            outputStream = ws.takeRetainedValue() as OutputStream

            // Prevent closing the socket when streams are deallocated — we manage it
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
        while let range = buffer.range(of: "\n") {
            let line = String(buffer[buffer.startIndex..<range.lowerBound])
            buffer = String(buffer[range.upperBound...])
            guard !line.isEmpty else { continue }
            guard let data = line.data(using: .utf8) else { continue }
            let decoder = JSONDecoder()
            if let state = try? decoder.decode(StateUpdate.self, from: data), state.type == "state" {
                onState?(state)
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

// MARK: - Status Bar App

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var client: SocketClient!
    private var currentState: StateUpdate?
    private let clippyDir: String

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

        client.onConnect = { [weak self] in
            DispatchQueue.main.async {
                self?.updateTitle(nil)
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

            // Countdown controls
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
