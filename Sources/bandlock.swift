import Cocoa
import CoreWLAN
import CoreLocation

// MARK: - Config

let configDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".config/bandlock")
let configPath = configDir.appendingPathComponent("config.toml")
let logPath = "/tmp/bandlock.log"

struct Config {
    var ssid: String
    var password: String
    var bssid: String?

    static func load() -> Config? {
        guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
            return nil
        }
        var ssid: String?
        var password: String?
        var bssid: String?
        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count != 2 { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let val = parts[1].trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            switch key {
            case "ssid": ssid = val
            case "password": password = val
            case "bssid": bssid = val.isEmpty ? nil : val
            default: break
            }
        }
        guard let s = ssid, let p = password else { return nil }
        return Config(ssid: s, password: p, bssid: bssid)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        var lines = [
            "ssid = \"\(ssid)\"",
            "password = \"\(password)\"",
        ]
        if let b = bssid {
            lines.append("bssid = \"\(b)\"")
        }
        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: configPath, atomically: true, encoding: .utf8)

        // Restrict permissions — config contains WiFi password
        let attrs: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        try FileManager.default.setAttributes(attrs, ofItemAtPath: configPath.path)
    }
}

// MARK: - Logging

func log(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)"
    print(line)
    if let data = (line + "\n").data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logPath) {
            if let fh = FileHandle(forWritingAtPath: logPath) {
                fh.seekToEndOfFile()
                fh.write(data)
                fh.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logPath, contents: data)
        }
    }
}

// MARK: - Status

func showStatus() {
    let client = CWWiFiClient.shared()
    guard let iface = client.interface() else {
        print("No WiFi interface found")
        exit(1)
    }
    let ch = iface.wlanChannel()?.channelNumber ?? 0
    let band = ch >= 36 ? "5GHz" : (ch > 0 ? "2.4GHz" : "unknown")
    let ssid = iface.ssid() ?? "not connected"
    let bssid = iface.bssid() ?? "unknown"
    let rssi = iface.rssiValue()
    let rate = iface.transmitRate()

    print("Network:    \(ssid)")
    print("Band:       \(band)")
    print("Channel:    \(ch)")
    print("BSSID:      \(bssid)")
    print("RSSI:       \(rssi) dBm")
    print("Link speed: \(Int(rate)) Mbps")
}

// MARK: - Setup

class SetupDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global().async { self.runSetup() }
    }

    func runSetup() {
        print("bandlock setup")
        print("==============\n")

        // Prompt for SSID
        print("Enter your WiFi network name (SSID): ", terminator: "")
        guard let ssid = readLine()?.trimmingCharacters(in: .whitespaces), !ssid.isEmpty else {
            print("No SSID entered, aborting.")
            exit(1)
        }

        // Prompt for password (note: still visible in terminal, but safe from shell history)
        print("Enter your WiFi password: ", terminator: "")
        guard let password = readLine(), !password.isEmpty else {
            print("No password entered, aborting.")
            exit(1)
        }

        print("\nScanning for 5GHz networks matching '\(ssid)'...")

        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else {
            print("No WiFi interface found.")
            exit(1)
        }

        var discoveredBSSID: String?

        do {
            let networks = try iface.scanForNetworks(withSSID: nil, includeHidden: true)
            let matches = networks.filter { net in
                let ch = net.wlanChannel?.channelNumber ?? 0
                return ch >= 36 && (net.ssid == ssid || net.bssid != nil)
            }

            let ssidMatches = matches.filter { $0.ssid == ssid }

            if ssidMatches.isEmpty {
                print("\nNo 5GHz radio found broadcasting '\(ssid)'.")
                print("Your router may hide the 5GHz BSSID via band steering.")
                print("")
                print("Try this workaround:")
                print("  1. Temporarily disable 2.4GHz on your router")
                print("  2. Run 'bandlock setup' again")
                print("  3. Re-enable 2.4GHz — the router will remember your band preference")
                print("")

                // Show all 5GHz networks in case user can identify their router
                let all5g = networks.filter { ($0.wlanChannel?.channelNumber ?? 0) >= 36 }
                if !all5g.isEmpty {
                    print("All 5GHz networks visible:")
                    for net in all5g.sorted(by: { ($0.wlanChannel?.channelNumber ?? 0) < ($1.wlanChannel?.channelNumber ?? 0) }) {
                        let ch = net.wlanChannel?.channelNumber ?? 0
                        let name = net.ssid ?? "(hidden)"
                        let bssid = net.bssid ?? "??"
                        print("  Ch \(ch) | \(name) | BSSID: \(bssid) | RSSI: \(net.rssiValue) dBm")
                    }
                }
            } else {
                print("\nFound 5GHz radio(s) for '\(ssid)':")
                for net in ssidMatches {
                    let ch = net.wlanChannel?.channelNumber ?? 0
                    let bssid = net.bssid ?? "??"
                    print("  Channel \(ch), BSSID: \(bssid), RSSI: \(net.rssiValue) dBm")
                }
                discoveredBSSID = ssidMatches.first?.bssid
            }
        } catch {
            print("Scan failed: \(error)")
            print("Make sure Location Services is enabled for bandlock in:")
            print("  System Settings > Privacy & Security > Location Services")
            exit(1)
        }

        // Write config
        let config = Config(ssid: ssid, password: password, bssid: discoveredBSSID)
        do {
            try config.save()
            print("\nConfig saved to \(configPath.path)")
            if let bssid = discoveredBSSID {
                print("Locked to BSSID: \(bssid)")
            } else {
                print("No BSSID locked — will scan for any 5GHz match at connect time.")
            }
        } catch {
            print("Failed to write config: \(error)")
            exit(1)
        }

        print("\nSetup complete! Run 'bandlock' to connect to 5GHz.")

        // Check Location Services
        let status: CLAuthorizationStatus
        if #available(macOS 11.0, *) {
            status = CLLocationManager().authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }
        if status != .authorizedAlways && status != .authorized {
            print("")
            print("NOTE: Location Services may not be authorized yet.")
            print("On first run, macOS will prompt you to grant location access.")
            print("This is required for WiFi scanning — Apple enforces it since macOS 13.")
        }

        NSApplication.shared.terminate(nil)
    }
}

// MARK: - Connect

class ConnectDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("bandlock — connecting to 5GHz")
        DispatchQueue.global().async { self.lockTo5GHz() }
    }

    func lockTo5GHz() {
        guard let config = Config.load() else {
            log("No config found. Run 'bandlock setup' first.")
            log("Config expected at: \(configPath.path)")
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }

        let client = CWWiFiClient.shared()
        guard let iface = client.interface() else {
            log("No WiFi interface found")
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }

        let currentCh = iface.wlanChannel()?.channelNumber ?? 0
        log("Current: channel \(currentCh) (\(currentCh >= 36 ? "5GHz" : "2.4GHz")), SSID: \(iface.ssid() ?? "none")")

        if currentCh >= 36 && iface.ssid() == config.ssid {
            log("Already on 5GHz — nothing to do!")
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
            return
        }

        log("Scanning for 5GHz radio...")

        do {
            let networks = try iface.scanForNetworks(withSSID: nil, includeHidden: true)

            // Priority: exact BSSID match > any 5GHz with matching SSID
            let target: CWNetwork?
            if let bssid = config.bssid {
                target = networks.first { $0.bssid == bssid }
                    ?? networks.first { $0.ssid == config.ssid && ($0.wlanChannel?.channelNumber ?? 0) >= 36 }
            } else {
                target = networks.first { $0.ssid == config.ssid && ($0.wlanChannel?.channelNumber ?? 0) >= 36 }
            }

            if let target = target {
                let ch = target.wlanChannel?.channelNumber ?? 0
                log("Found: Ch \(ch), BSSID: \(target.bssid ?? "??"), RSSI: \(target.rssiValue) dBm")
                log("Connecting...")
                try iface.associate(to: target, password: config.password)
                log("Connected to 5GHz on channel \(ch)!")
            } else {
                log("5GHz radio not found for '\(config.ssid)'.")
                if config.bssid != nil {
                    log("BSSID \(config.bssid!) not visible — router may be hiding it.")
                }
                log("Tip: temporarily disable 2.4GHz on your router, then re-enable it.")
            }
        } catch {
            log("Error: \(error)")
        }

        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }
}

// MARK: - Main

let args = CommandLine.arguments
let command = args.count > 1 ? args[1] : nil

let app = NSApplication.shared
let delegate: NSApplicationDelegate

switch command {
case "setup":
    delegate = SetupDelegate()
case "status":
    showStatus()
    exit(0)
case "help", "--help", "-h":
    print("bandlock — force macOS onto 5GHz WiFi\n")
    print("Usage:")
    print("  bandlock          Connect to 5GHz (reads ~/.config/bandlock/config.toml)")
    print("  bandlock setup    Interactive setup — enter SSID, password, discover 5GHz BSSID")
    print("  bandlock status   Show current WiFi band, channel, and link speed")
    print("  bandlock help     Show this message")
    exit(0)
default:
    delegate = ConnectDelegate()
}

app.delegate = delegate
app.run()
