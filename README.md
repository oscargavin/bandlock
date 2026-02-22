# bandlock

Force your Mac onto the 5GHz WiFi band.

## The problem

macOS has no way to force a specific WiFi band when your router uses a single SSID for both 2.4GHz and 5GHz. Apple removed the `airport` CLI tool, and routers with "smart" band steering (BT Smart Hub, Sky Q, Virgin Media, etc.) often push devices onto the slower 2.4GHz band.

The result: you're stuck at 50-150 Mbps when your router supports 500+ Mbps on 5GHz.

## How it works

bandlock is a tiny Cocoa app that uses Apple's CoreWLAN framework to:

1. Scan for your WiFi network across all bands
2. Find the 5GHz access point (by BSSID or channel)
3. Associate directly to the 5GHz radio

It runs once at login (via LaunchAgent), connects you to 5GHz, then exits. No background process, no menu bar icon, no resource usage.

### Why an app bundle?

Since macOS 13, Apple requires Location Services permission for any WiFi scanning. Location Services auth only works for `.app` bundles — plain CLI binaries and scripts can't request it. bandlock packages itself as a proper app bundle so macOS grants the permission.

## Requirements

- macOS 13 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Quick start

```bash
git clone https://github.com/oscargavin/bandlock.git
cd bandlock
make install
```

Then run setup:

```bash
/Applications/bandlock.app/Contents/MacOS/bandlock setup
```

This will:
- Ask for your WiFi network name and password
- Scan for 5GHz access points
- Save your config to `~/.config/bandlock/config.toml`
- On first run, macOS will prompt you to grant Location Services access

That's it. bandlock will auto-connect to 5GHz every time you log in.

## Usage

```bash
# Connect to 5GHz now
bandlock

# Interactive setup (SSID, password, BSSID discovery)
bandlock setup

# Check current band and connection info
bandlock status

# Show help
bandlock help
```

After `make install`, you can also run it directly:

```bash
/Applications/bandlock.app/Contents/MacOS/bandlock status
```

Or create a shell alias:

```bash
alias bandlock='/Applications/bandlock.app/Contents/MacOS/bandlock'
```

## Configuration

Config lives at `~/.config/bandlock/config.toml`:

```toml
ssid = "MyNetwork"
password = "MyPassword"
bssid = "aa:bb:cc:dd:ee:ff"  # optional
```

- **ssid** — your WiFi network name
- **password** — your WiFi password
- **bssid** — (optional) the specific 5GHz access point MAC address. Discovered automatically during `bandlock setup`. If not set, bandlock scans for any 5GHz radio matching the SSID.

The config file is created with `600` permissions (owner read/write only).

## LaunchAgent

`make install` creates a LaunchAgent at `~/Library/LaunchAgents/dev.bandlock.app.plist` that runs bandlock at login. To manage it:

```bash
# Disable auto-start
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/dev.bandlock.app.plist

# Re-enable
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.bandlock.app.plist
```

## Uninstall

```bash
cd bandlock
make uninstall
```

This removes the app from `/Applications` and the LaunchAgent. Your config at `~/.config/bandlock/` is preserved — delete it manually if needed.

## Troubleshooting

### "5GHz BSSID not found in scan"

Some routers hide the 5GHz BSSID when band steering is active. Workaround:

1. Temporarily disable 2.4GHz on your router
2. Run `bandlock setup` — with only 5GHz available, the BSSID will be visible
3. Re-enable 2.4GHz — the router remembers your band preference

### "Location DENIED" or scan returns 0 networks

macOS requires Location Services for WiFi scanning. Enable it at:

**System Settings > Privacy & Security > Location Services > bandlock**

### Logs

bandlock logs to `/tmp/bandlock.log` with timestamps. Check it if connections fail:

```bash
cat /tmp/bandlock.log
```

## How is this different from airport-bssid?

[airport-bssid](https://github.com/nickoala/airport-bssid) connects to a BSSID but:
- Doesn't handle Location Services (broken on macOS 13+)
- No config file — requires passing BSSID as CLI argument
- No setup wizard to discover 5GHz BSSIDs
- No LaunchAgent for auto-connection at login

## License

MIT
