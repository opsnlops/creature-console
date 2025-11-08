# Lightweight Console User Guide

Lightweight Console is a macOS 15+ menu bar companion for the main Creature Console. It provides quick access to ad-hoc animations, playlists, and basic health telemetry when you’re away from your macOS 26 workstation.

## Requirements

- macOS 15.6 or later
- Network reachability to the proxy or Creature server
- API token issued by your proxy (if using the relay)

## First Launch

1. Run **Lightweight Console**. A pawprint icon will appear in the menu bar.
2. Click the icon and choose **Settings…** (or open from the app menu).
3. Configure the following:
   - **Hostname**: Proxy hostname or direct server address (`proxy.prod.chirpchirp.dev` by default)
   - **Backend Host (optional)**: Direct server host when tunneling through the proxy
   - **Port / TLS**: Port (default 443) and TLS toggle
   - **Default Creature**: Selected from the live list once connected
   - **Universe**: DMX/Universe value used for ad-hoc playback
   - **Auth Token**: Paste the proxy API key (stored in `UserDefaults`)
4. Click **Save**, then return to the menu bar popover. You should see the connection indicator turn green once the server handshake succeeds.

## Using the Menubar

The popover is organized top-down:

- **Connection**: Status light plus current creature name. Click the circular arrows to reconnect.
- **Ad-hoc Animation**
  - Text box placeholder personalizes with the creature name.
  - `Play Now` sends instant speech; `Cue` prepares a job for later.
  - “Resume playlist after playback” now uses the shared `PlaylistRuntime` preference (also honored by the main app).
- **Prepared Animations**
  - Shows the five most recent entries; use **Show All** to expand/hide the rest.
  - `Trigger` starts the selected prepared animation.
- **Playlists**
  - Use **Start Playlist** menu to run any stored playlist.
  - `Stop Active Playlist` halts playback immediately.
- **Creature Health**
  - Displays latest motor-in power and voltage plus last update time.
- **Jobs**
  - Shows ad-hoc prepare jobs, including progress.
- **Quit** closes the companion app.

## Tips

- If you see a red status light, open Settings to verify host/port/token, then press the reconnect button.
- Prepared animations refresh automatically when an ad-hoc prepare job completes, but you can force a reload with the ↻ button in the Ad-hoc section.
- Playlists fetched from the server may take a second on first connect; use the ↻ button in the Playlists header if you add new ones elsewhere.
- The app stores all preferences locally. Clearing the auth token simply empties the field—no keychain is involved.

## Recent Changes

- 2025-11-08 06:54:39 UTC — Added PlaylistRuntime shared store/bindings. Ad-hoc Animation list now offers Play context menu on all platforms, and playback uses the runtime helpers.

## Troubleshooting

- **401 from proxy**: Confirm the auth token in Settings matches the proxy dashboard; re-save to overwrite the cached value.
- **Cannot resolve hostname**: Ensure the proxy address is reachable from the current network (try `ping proxy.prod.chirpchirp.dev`).
- **No creatures listed**: The list populates once the websocket connects; check status indicator or press reconnect.
- **Prepared animation missing**: Wait for the ad-hoc job to reach “complete” or hit the refresh icon.

For deeper diagnostics (logs, advanced caching), use the full Creature Console app on macOS 26.
