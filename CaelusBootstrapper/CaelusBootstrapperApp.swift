import SwiftUI
import Cocoa
class BootstrapperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            await bootstrapperview.shared.apponly()
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            CaelusBootstrapperApp.shared?.handleprot(url)
        }
    }
}

@main
struct CaelusBootstrapperApp: App {
    static var shared: CaelusBootstrapperApp?
    @NSApplicationDelegateAdaptor(BootstrapperDelegate.self) var delegate
    init() {
        Self.shared = self
    }

    var body: some Scene {
        Window("Caelus", id: "Bootstrapper") {
            bootview()
                .environmentObject(bootstrapperview.shared)
                .frame(width: 400, height: 200)
                .hideWindowButtons()
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: 400, height: 200)
        .windowStyle(.hiddenTitleBar)
        Settings { EmptyView() }
    }

    func handleprot(_ url: URL) {
        bootstrapperview.shared.preprun(url: url)
    }

    func process(protargs: String) {
        let raw = protargs.replacingOccurrences(of: "caelus-launcher://", with: "")
        guard let tickstart = raw.range(of: "gameinfo:")?.upperBound else {
            errquit(message: "Missing gameinfo. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        let ticksub = raw[tickstart...]
        let tick = ticksub.split(separator: "+").first.map { String($0) } ?? ""
        if tick.isEmpty {
            errquit(message: "Authticket is invalid. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        guard let scriptstart = raw.range(of: "placelauncherurl:")?.upperBound else {
            errquit(message: "Missing placeid. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        let scriptsub = raw[scriptstart...]
        let scriptURL = scriptsub.split(separator: "+").first.map { String($0) } ?? ""
        if scriptURL.isEmpty {
            errquit(message: "Invalid scriptURL. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        launchclient(tick: tick, scriptURL: scriptURL, authURL: "https://www.caelus.lol/Login/Negotiate.ashx")
    }

    private func launchclient(tick: String, scriptURL: String, authURL: String) {
        let clientpath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/RobloxPlayer.app/Contents/MacOS/RobloxPlayer")
            .path
        let task = Process()
        task.executableURL = URL(fileURLWithPath: clientpath)
        task.arguments = ["-authURL", authURL, "-ticket", tick, "-scriptURL", scriptURL]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = nil
        do {
            try task.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } catch {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

@MainActor
class bootstrapperview: ObservableObject {
    static let shared = bootstrapperview()
    @Published var status = "Checking for updates..."
    @Published var checking = true
    private var proturl: URL?

    func apponly() async {
        let updated = await checkupd()
        if !updated && proturl == nil {
            if let gamesURL = URL(string: "https://www.caelus.lol/games") {
                NSWorkspace.shared.open(gamesURL)
            }
            NSApp.terminate(nil)
        }
    }

    func preprun(url: URL) {
        self.proturl = url
        Task {
            let updated = await checkupd()
            status = "Launching Caelus..."
            checking = false
            try? await Task.sleep(nanoseconds: 500_000_000)
            if !updated, let proturl = proturl {
                CaelusBootstrapperApp.shared?.process(protargs: proturl.absoluteString)
            }
        }
    }

    private func checkupd() async -> Bool {
        status = "Checking for updates..."
        checking = true
        let updavail = await gitnew()
        if updavail {
            await downupd()
            return true
        } else {
            return false
        }
    }

    private func gitnew() async -> Bool {
        let currver = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        guard let latest = URL(string: "https://api.github.com/repos/engrv/Caelus-Mac/releases/latest") else {
            return false
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: latest)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                return tag != currver
            }
        } catch {
        }
        return false
    }

    private func downupd() async {
        guard let latest = URL(string: "https://api.github.com/repos/engrv/Caelus-Mac/releases/latest") else {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: latest)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let assets = json["assets"] as? [[String: Any]],
                  let downurl = assets.first?["browser_download_url"] as? String,
                  let down = URL(string: downurl) else {
                return
            }
            let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
            let zip = downloads.appendingPathComponent("Caelus.zip")
            let unzipdir = downloads.appendingPathComponent("Caelus")

            await MainActor.run {
                checking = false
                status = "Downloading update..."
            }

            if FileManager.default.fileExists(atPath: zip.path) {
                try? FileManager.default.removeItem(at: zip)
            }
            let (temp, _) = try await URLSession.shared.download(from: down)
            try FileManager.default.moveItem(at: temp, to: zip)
            await MainActor.run { status = "Installing update..." }
            if FileManager.default.fileExists(atPath: unzipdir.path) {
                try? FileManager.default.removeItem(at: unzipdir)
            }

            try await Task.detached {
                try? FileManager.default.createDirectory(at: unzipdir, withIntermediateDirectories: true)
                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = [zip.path, "-d", unzipdir.path]
                unzip.standardOutput = FileHandle.nullDevice
                unzip.standardError = FileHandle.nullDevice
                try? unzip.run()
                unzip.waitUntilExit()
            }.value

            let appspath = URL(fileURLWithPath: "/Applications")
            if let app = try? FileManager.default.contentsOfDirectory(
                at: unzipdir,
                includingPropertiesForKeys: nil
            ).first(where: { $0.pathExtension == "app" }) {
                let dest = appspath.appendingPathComponent(app.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try? FileManager.default.removeItem(at: dest)
                }
                try? FileManager.default.copyItem(at: app, to: dest)
                try? FileManager.default.removeItem(at: zip)
                try? FileManager.default.removeItem(at: unzipdir)
                NSWorkspace.shared.open(dest)
                NSApp.terminate(nil)
            } else {
            }
        } catch {
            await MainActor.run {
                status = "Update failed."
                checking = false
            }
        }
    }
}

struct bootview: View {
    @EnvironmentObject var bootstrapper: bootstrapperview
    var body: some View {
        VStack(spacing: 20) {
            appimg()
                .resizable()
                .frame(width: 64, height: 64)
            Text(bootstrapper.status)
                .font(.headline)
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
                .frame(width: 300)
            Button("Cancel") {
                NSApp.terminate(nil)
            }
        }
        .padding()
    }
}

func appimg() -> Image {
    if let appicon = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String {
        let icon = (appicon as NSString).deletingPathExtension
        if let nsimg = NSImage(named: icon) {
            return Image(nsImage: nsimg)
        }
    }
    if let nsimg = NSApp.applicationIconImage {
        return Image(nsImage: nsimg)
    }
    return Image(systemName: "app")
}

struct HostingWindowFinder: NSViewRepresentable {
    var callback: (NSWindow?) -> ()
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { self.callback(view.window) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    func hideWindowButtons() -> some View {
        self.background(HostingWindowFinder { window in
            window?.standardWindowButton(.closeButton)?.isHidden = true
            window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window?.standardWindowButton(.zoomButton)?.isHidden = true
        })
    }
}

private func errquit(message: String) {
    let alert = NSAlert()
    alert.messageText = "Error"
    alert.informativeText = message
    alert.alertStyle = .critical
    alert.addButton(withTitle: "Ok")
    alert.runModal()
    NSApp.terminate(nil)
}
