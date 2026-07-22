import Common
import OSLog
import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Live slider control for a fixture. Each value change throttles a `POST /live` call
/// to the server with a short timeout (so the server auto-blacks out shortly after
/// the user stops interacting). Holds local per-channel state independently of any
/// pattern values — this UI is purely for ad-hoc lighting, not persisted config.
///
/// While a live session is in flight (within `liveTimeoutMs` of the most recent send),
/// the panel notifies the parent via `onLiveActiveUntil` so the pattern fire buttons
/// can disable themselves — the server would refuse pattern triggers anyway, but
/// disabling the buttons surfaces the precedence rule clearly in the UI.
struct LiveControlPanel: View {

    let fixture: Common.DmxFixture
    /// Reports the local "live is active until" deadline so the parent can disable
    /// pattern fire buttons. Cleared (with `nil`) when the user explicitly stops.
    let onLiveActiveUntil: (Date?) -> Void

    private let logger = Logger(
        subsystem: "io.opsnlops.CreatureConsole", category: "LiveControlPanel")
    private let server = CreatureServerClient.shared

    /// How long the server should hold each live update before blacking out. Configured
    /// via Settings → Interface → "DMX Live Control → Hold Seconds" so users can tune
    /// it for their workflow (long for slow scrub-and-think; short for quick blackout
    /// when releasing a slider). Clamped to a sane range; the server hard-caps at 600s.
    @AppStorage("dmxLiveHoldSeconds") private var liveHoldSeconds: Int = 3
    private var liveTimeoutMs: UInt32 {
        UInt32(clamping: max(1, min(600, liveHoldSeconds)) * 1000)
    }
    /// Minimum spacing between live POSTs. Slider drag events fire dozens of times per
    /// second; this caps us at ~12 sends/s — plenty for a smooth visual, easy on the
    /// server, well under the timeout window.
    private let minSendIntervalMs: Double = 80

    @State private var values: [String: UInt8] = [:]
    @State private var lastSendAt: Date = .distantPast
    @State private var pendingSend: Task<Void, Never>? = nil

    @State private var statusMessage: String = "Idle — move a slider to start a live session."
    @State private var lastError: String? = nil
    @State private var isSessionActive: Bool = false
    /// The color picker's own state — seeded from the channels once, then one-way into them.
    @State private var pickedColor: Color = .black

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Live Control").font(.headline)
                Spacer()
                if isSessionActive {
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .glassEffect(.regular.tint(.red), in: .capsule)
                }
                Button {
                    blackout()
                } label: {
                    Label("Blackout", systemImage: "lightbulb.slash")
                }
                .disabled(fixture.assignedUniverse == nil)
            }

            if fixture.assignedUniverse == nil {
                Label(
                    "Assign a universe before live control will reach hardware.",
                    systemImage: "exclamationmark.circle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lastError {
                Label(lastError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if showColorPicker {
                colorSection
                Divider()
            }

            channelSlidersSection
        }
        .padding()
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
        .onAppear {
            seedValuesIfNeeded()
            pickedColor = currentColor()
        }
        .onDisappear {
            pendingSend?.cancel()
            onLiveActiveUntil(nil)
        }
    }

    // MARK: - Color picker (light fixtures)

    private var showColorPicker: Bool {
        fixture.type == .light
            && (redChannel != nil || greenChannel != nil || blueChannel != nil)
    }

    @ViewBuilder
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Color (writes all color channels live — red/green/blue plus white/lime/amber)")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                // The picker owns its color; channel writes are one-way. Echoing the
                // reconstructed channel state back through the binding's `get` re-derives the
                // picker's HSB sliders from 8-bit-quantized RGB, which makes them wiggle as
                // you drag. The hex label below stays the truth from the channels.
                ColorPicker(
                    "Color",
                    selection: Binding<Color>(
                        get: { pickedColor },
                        set: { newColor in
                            pickedColor = newColor
                            writeColor(newColor)
                        }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()

                Text(currentHex())
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Raw sliders

    @ViewBuilder
    private var channelSlidersSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("All channels (raw 0–255)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if fixture.channels.isEmpty {
                Text("Define channels on the fixture before driving live.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            ForEach(fixture.channels, id: \.name) { channel in
                FixtureChannelSliderRow(
                    channel: channel,
                    value: Binding(
                        get: { currentValue(for: channel.name) },
                        set: { setValue($0, for: channel.name) }
                    ))
            }
        }
    }

    // MARK: - State helpers

    private func seedValuesIfNeeded() {
        guard values.isEmpty else { return }
        for channel in fixture.channels {
            values[channel.name] = 0
        }
    }

    private func currentValue(for channelName: String) -> UInt8 {
        values[channelName] ?? 0
    }

    private func setValue(_ value: UInt8, for channelName: String) {
        guard values[channelName] != value else { return }
        values[channelName] = value
        scheduleLiveSend()
    }

    // MARK: - Color round-trip

    private var redChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorRed }
    }
    private var greenChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorGreen }
    }
    private var blueChannel: FixtureChannel? {
        fixture.channels.first { $0.kind == FixtureChannelKind.colorBlue }
    }

    private func currentColor() -> Color {
        let r = redChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        let g = greenChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        let b = blueChannel.map { Double(currentValue(for: $0.name)) / 255.0 } ?? 0
        return Color(red: r, green: g, blue: b)
    }

    private func currentHex() -> String {
        let r = redChannel.map { currentValue(for: $0.name) } ?? 0
        let g = greenChannel.map { currentValue(for: $0.name) } ?? 0
        let b = blueChannel.map { currentValue(for: $0.name) } ?? 0
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func writeColor(_ color: Color) {
        // Single source of truth for the color → channel mapping (FixtureColorMixer via
        // FixtureControlService) — drives white/lime/amber emitters too, not just RGB.
        for patternValue in FixtureControlService.colorValues(color, channels: fixture.channels) {
            setValue(patternValue.value, for: patternValue.channel)
        }
    }

    // MARK: - Throttled send

    private func scheduleLiveSend() {
        guard fixture.assignedUniverse != nil else {
            lastError = "Fixture has no assigned universe — cannot send live values."
            return
        }

        pendingSend?.cancel()
        let now = Date()
        let elapsedMs = now.timeIntervalSince(lastSendAt) * 1000
        let delayMs = max(0, minSendIntervalMs - elapsedMs)

        pendingSend = Task {
            if delayMs > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delayMs)))
            }
            guard !Task.isCancelled else { return }
            await sendLiveNow()
        }
    }

    @MainActor
    private func sendLiveNow() async {
        lastSendAt = Date()
        let snapshot = values.map { FixturePatternValue(channel: $0.key, value: $0.value) }
        let id = fixture.id

        let result = await server.setFixtureLive(
            id: id, values: snapshot, timeoutMs: liveTimeoutMs)
        // If this send was superseded mid-flight (a newer slider value cancelled us) or the
        // view is tearing down, the transport reports "cancelled" — that's the throttle
        // working as designed, not an error the user can act on. Say nothing.
        guard !Task.isCancelled else { return }
        switch result {
        case .success(let updated):
            logger.debug("live ok on \(updated.id)")
            lastError = nil
            isSessionActive = true
            let deadline = Date().addingTimeInterval(Double(liveTimeoutMs) / 1000.0)
            statusMessage =
                "Live — sent \(snapshot.count) channel(s), server holds for \(liveTimeoutMs)ms."
            onLiveActiveUntil(deadline)
        case .failure(let error):
            let detailed = ServerError.detailedMessage(from: error)
            logger.warning("live failed: \(detailed)")
            lastError = detailed
        }
    }

    private func blackout() {
        pendingSend?.cancel()
        // Setting to 1ms forces the server to drop the values almost immediately.
        let id = fixture.id
        Task { @MainActor in
            for key in values.keys { values[key] = 0 }
            let snapshot = values.map { FixturePatternValue(channel: $0.key, value: $0.value) }
            let result = await server.setFixtureLive(id: id, values: snapshot, timeoutMs: 1)
            switch result {
            case .success:
                statusMessage = "Blackout sent. Patterns can fire again immediately."
                isSessionActive = false
                onLiveActiveUntil(nil)
            case .failure(let error):
                lastError = ServerError.detailedMessage(from: error)
            }
        }
    }
}
