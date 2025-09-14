import SwiftUI
import Cocoa

class BootstrapperDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.count == 1 {
            CaelusBootstrapperApp.showNoProtocolError()
        }
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            CaelusBootstrapperApp.shared?.process(protargs: url.absoluteString)
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
        Settings {
            EmptyView()
        }
    }

    static func showNoProtocolError() {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = "Please launch Caelus via the website."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
        NSApp.terminate(nil)
    }
    
    func process(protargs: String) {
        let raw = protargs.replacingOccurrences(of: "caelus-launcher://", with: "")
        
        guard let tickstart = raw.range(of: "gameinfo:")?.upperBound else {
            showErrorAndExit(message: "Missing gameinfo. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        let ticksub = raw[tickstart...]
        let tick = ticksub.split(separator: "+").first.map { String($0) } ?? ""
        if tick.isEmpty {
            showErrorAndExit(message: "Authticket is invalid. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        
        guard let scriptstart = raw.range(of: "placelauncherurl:")?.upperBound else {
            showErrorAndExit(message: "Missing placeid. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
            return
        }
        let scriptsub = raw[scriptstart...]
        let scriptURL = scriptsub.split(separator: "+").first.map { String($0) } ?? ""
        if scriptURL.isEmpty {
            showErrorAndExit(message: "Invalid scriptURL. Please try and rejoin, if that does not help make a ticket with this error on our Discord.")
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
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            print("Client failed to launch, please make a ticket and show the following error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
    }
    
    private func showErrorAndExit(message: String) {
        let alert = NSAlert()
        alert.messageText = "Error"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Ok")
        alert.runModal()
        NSApp.terminate(nil)
    }
}
