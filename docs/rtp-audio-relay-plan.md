# RTP Audio Relay: live spatial preview without VLAN access

Tracking issue: [#71](https://github.com/opsnlops/creature-console/issues/71). Companion to the
sACN relay (`creature-cli network sacn-listen`) — same trick, audio plane.

## The problem

Live show audio is 17 RTP multicast streams (`239.19.63.1–16` dialog channels + `.17`
background music; RTP on 5004, RTCP on 5005, mono Opus at 48 kHz) that only exist on the
animatronic VLAN. The WiFi laptop and the living-room Apple TV have no route to it — and tvOS
can't join multicast groups at all, so for the TV a relay is the only possible path.

## Architecture: transparent packet relay

A `creature-cli` on a Pi wired to the VLAN joins all the groups and forwards **raw, unmodified
RTP/RTCP datagrams** over TCP. No decode, no timing logic, no re-framing on the Pi — the
console's existing live pipeline (jitter buffer, RTCP playout planning, Opus decode,
diagnostics) consumes relayed packets exactly as it consumes multicast ones. The relay is pure
plumbing, which is why it can stay dumb and reliable.

Bandwidth: 17 mono Opus streams is low single-digit Mbps. (This is why we relay Opus packets,
not decoded PCM — PCM would be ~13 Mbps and would drag timing semantics into the CLI.)

## Wire protocol (`RTPRemoteProtocol` in Common, shared by both ends)

1. Client connects over TCP and sends one JSON line: `RTPRemoteHello { type: "hello",
   viewerName, viewerVersion, channels: [Int] }`. `channels` are the dialog lanes the viewer's
   stage uses; the music lane (17) is always included by the proxy.
2. Server then streams frames: `[u16 big-endian length][u8 channel][u8 kind][payload]` where
   `length` covers channel + kind + payload, and `kind` is 0 = RTP, 1 = RTCP. Length-prefix
   framing and the slow-client disconnect policy mirror the sACN relay.

## CLI: `creature-cli network rtp-listen`

- Default TCP port **1964** (sACN relay took 1963).
- **Apple** impl: `NWConnectionGroup` multicast join (same shape as the console's own
  `SpatialMulticastReceiver`) + `NWListener` fan-out, mirroring `SACNRemoteProxy+Apple`.
- **Linux** impl (the real deployment — the Pi): NIO. One UDP socket per (group, port) pair,
  each **bound to its multicast group address**, so the socket itself identifies the channel
  and kind — no destination-address sniffing needed. Groups are joined once at startup, not
  per client; every viewer wants the same streams.
- Per-client channel filtering from the hello keeps a small stage from receiving all 16 lanes.

## Console side

- Shared packet vocabulary (`SpatialReceivedPacket`, channel + rtp/rtcp kind) moves out of the
  macOS-only `SpatialMulticastReceiver` into the portable layer.
- `SpatialRelayReceiver` (macOS + tvOS): TCP client, hello handshake, frame parser → the same
  packet values.
- `SpatialLiveAudioSource` takes a transport: `.multicast(interface)` (macOS only) or
  `.relay(host, port)` (macOS + tvOS). Everything downstream is untouched.
- **Opus on tvOS**: YbridOpus's xcframework has no tvOS slice, so tvOS decodes with
  `AVAudioConverter` (`kAudioFormatOpus`), same decoder API. It can't do libopus FEC/PLC —
  acceptable, because the relay transport is TCP: packets are never lost, only late, and a
  stall fills with silence.

## UI

- **macOS Spatial Stage window**: input mode gains **Live via Relay** next to Live RTP and
  Simulation, with relay host/port fields (persisted per machine via `@AppStorage`).
- **Creature TV**: a lean "Live Stage Audio" screen — pick a stage from the SwiftData mirror,
  enter/reuse the relay host, listen out HDMI. Builds on #70's widened spatial stack.

## Out of scope

Relay authentication (the animatronic LAN is trusted space), relaying *toward* the VLAN
(monitor-only), and any transcoding on the Pi.
