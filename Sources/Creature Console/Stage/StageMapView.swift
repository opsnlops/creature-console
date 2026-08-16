import Common
import SwiftUI

/// Top-down view of a stage: the ±5 m box with the listener at its centre.
///
/// Shared by the stage editor (where nodes can be dragged) and the Spatial Stage listening window
/// (where they can't, but pulse with live audio). One canvas so the two can't drift into showing
/// the same stage differently.
struct StageMapView: View {

    let placements: [StagePlacement]
    @Binding var selectedCreatureID: CreatureIdentifier?

    /// What to call a placed creature — resolved by the caller, which knows the live creature list.
    var displayName: (StagePlacement) -> String

    /// Called with the new metres-from-listener position when a node is dragged. `nil` makes the
    /// map read-only, which is how the listening window presents it.
    var onMove: ((CreatureIdentifier, Float, Float) -> Void)?

    /// 0...1 audio level for a channel, so nodes can glow while a scene plays. Defaults to silence.
    var signalLevel: (Int) -> Double = { _ in 0 }

    /// Extra help text per channel, for the listening window's packet counters.
    var channelHelp: (Int) -> String = { "Audio channel \($0)" }

    var onRemove: ((CreatureIdentifier) -> Void)?

    /// Creatures to call out on the map — the dialog editor passes the scene's speakers so you can
    /// see at a glance who in the cast actually has lines on this stage. Empty = no emphasis.
    var emphasizedCreatureIDs: Set<CreatureIdentifier> = []

    @Environment(\.colorScheme) private var colorScheme

    private var extent: Float { StageLimits.coordinateLimit }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.indigo.opacity(0.18),
                                Color.black.opacity(0.06),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                grid
                axisLabels
                listener

                ForEach(placements) { placement in
                    StageMapNode(
                        placement: placement,
                        isSelected: selectedCreatureID == placement.creatureID,
                        level: signalLevel(placement.audioChannel),
                        name: displayName(placement),
                        helpText: channelHelp(placement.audioChannel),
                        speaks: emphasizedCreatureIDs.contains(placement.creatureID),
                        onSelect: { selectedCreatureID = placement.creatureID },
                        onRemove: onRemove.map { remove in
                            { remove(placement.creatureID) }
                        }
                    )
                    .equatable()
                    .position(position(for: placement, in: proxy.size))
                    .simultaneousGesture(
                        dragGesture(for: placement, in: proxy.size),
                        // A read-only map (the listening window) still selects on tap, it just
                        // can't move anything.
                        isEnabled: onMove != nil
                    )
                }
            }
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    // Fixed geometry and blur, animated opacity only: a level-driven blur
                    // radius re-renders the blur every frame, which at meter rate kept the
                    // GPU busy whenever audio played (#74). Opacity changes are nearly free.
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.purple, lineWidth: 3)
                        .blur(radius: 6)
                        .opacity(0.5 * signalLevel(17))
                }
            }
            .coordinateSpace(name: "stageMap")
            .animation(.linear(duration: 0.1), value: signalLevel(17))
        }
    }

    private func dragGesture(for placement: StagePlacement, in size: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .named("stageMap"))
            .onChanged { value in
                guard let onMove, size.width > 0, size.height > 0 else { return }
                let clampedX = min(max(value.location.x / size.width, 0), 1)
                let clampedY = min(max(value.location.y / size.height, 0), 1)
                onMove(
                    placement.creatureID,
                    (Float(clampedX) * 2 - 1) * extent,
                    (Float(clampedY) * 2 - 1) * extent)
                selectedCreatureID = placement.creatureID
            }
    }

    private var grid: some View {
        Canvas { context, size in
            var path = Path()
            for index in 1..<10 {
                let x = size.width * CGFloat(index) / 10
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                let y = size.height * CGFloat(index) / 10
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(.secondary.opacity(0.12)), lineWidth: 1)

            // The centre lines are the listener's axes, so draw them heavier than the metre grid.
            var axes = Path()
            axes.move(to: CGPoint(x: size.width / 2, y: 0))
            axes.addLine(to: CGPoint(x: size.width / 2, y: size.height))
            axes.move(to: CGPoint(x: 0, y: size.height / 2))
            axes.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(axes, with: .color(.secondary.opacity(0.28)), lineWidth: 1)
        }
        .padding(1)
        .allowsHitTesting(false)
    }

    /// Which way is which, so nobody has to remember that −z is in front.
    private var axisLabels: some View {
        VStack {
            Text("In front of you  ·  −5 m")
            Spacer()
            Text("Behind you  ·  +5 m")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var listener: some View {
        VStack(spacing: 3) {
            Image(systemName: "headphones")
                .font(.title2)
            Text("You")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .allowsHitTesting(false)
    }

    /// Maps the ±5 m box onto the canvas: x left→right, z top→bottom with −z (in front of the
    /// listener) at the top, which puts the listener dead centre.
    private func position(for placement: StagePlacement, in size: CGSize) -> CGPoint {
        let normalizedX = (CGFloat(placement.x / extent) + 1) / 2
        let normalizedZ = (CGFloat(placement.z / extent) + 1) / 2
        return CGPoint(
            x: min(max(normalizedX, 0.04), 0.96) * size.width,
            y: min(max(normalizedZ, 0.05), 0.95) * size.height
        )
    }
}

/// One creature's card on the map, split out with an `Equatable` gate so a 10 Hz meter tick
/// re-renders only the cards whose (quantized) level actually moved — before this, every
/// diagnostics publish rebuilt every card on the stage (#76). `helpText` is deliberately left
/// out of `==`: it carries live packet counters that change every publish, and comparing it
/// would defeat the gate. A tooltip that lags until the next level change is fine; the
/// counters only tick while audio flows, which is exactly when levels change too.
private struct StageMapNode: View, @MainActor Equatable {
    let placement: StagePlacement
    let isSelected: Bool
    let level: Double
    let name: String
    let helpText: String
    let speaks: Bool
    let onSelect: () -> Void
    let onRemove: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.placement == rhs.placement && lhs.isSelected == rhs.isSelected
            && lhs.level == rhs.level && lhs.name == rhs.name && lhs.speaks == rhs.speaks
            && (lhs.onRemove == nil) == (rhs.onRemove == nil)
    }

    var body: some View {
        card
    }

    /// Which way this creature is pointed, as a compass ring around its icon.
    ///
    /// Earlier attempts drew a gaze cone radiating from the node. It reads beautifully in isolation
    /// and fails here: the card is ~180pt wide, so a cone small enough to feel attached is hidden
    /// behind the label, and one big enough to clear it floats free of the creature it belongs to.
    /// On a map with five creatures you end up guessing which shape is whose. A badge fixed to the
    /// icon can't detach, costs 28pt, and answers the only question being asked.
    private var headingBadge: some View {
        let tint: Color = isSelected ? .accentColor : .teal
        return ZStack {
            Circle().fill(tint.opacity(speaks ? 0.28 : 0.12))
            Circle().stroke(tint.opacity(speaks ? 0.8 : 0.35), lineWidth: speaks ? 1.5 : 1)

            Image(systemName: placement.isMuted ? "speaker.slash.fill" : "bird.fill")
                .font(.system(size: 11, weight: .semibold))

            // The pointer rides the ring: rotating the wrapper orbits it, while the icon inside
            // stays upright. +180 because yaw 0 faces +z, which is *down* on this map.
            ZStack {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(tint)
                    .offset(y: -13)
            }
            .rotationEffect(.degrees(Double(placement.yaw) + 180))

            if speaks {
                Image(systemName: "music.microphone")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tint)
                    .padding(2)
                    .background(Circle().fill(.background))
                    .offset(x: 11, y: 11)
            }
        }
        .frame(width: 28, height: 28)
    }

    private var card: some View {
        VStack(spacing: 2) {
            headingBadge
            Text(name)
                .lineLimit(1)
            Text(
                "CH \(placement.audioChannel)  ·  \(placement.y, specifier: "%+.2f") m  ·  \(placement.yaw, specifier: "%+.0f")°"
            )
            .font(.caption2.monospacedDigit())
            .opacity(0.7)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(placement.isMuted ? Color.secondary : creatureForegroundColor)
        .background {
            ZStack {
                // The audio glow: fixed blur radius, level drives only opacity. The old
                // level-driven shadow radius forced a shadow re-render on every meter tick,
                // which multiplied across cards whenever a scene played (#74).
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green)
                    .blur(radius: 10)
                    .opacity(0.5 * level)
                RoundedRectangle(cornerRadius: 10)
                    .fill(creatureSurfaceColor)
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.accentColor.opacity(0.32))
                }
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.green.opacity(0.3 * level))
            }
        }
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.green, lineWidth: 1.5)
                    .opacity(0.65 * level)
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onSelect() }
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .help(helpText)
        .contextMenu {
            if let onRemove {
                Button("Remove from Stage", systemImage: "minus.circle", role: .destructive) {
                    onRemove()
                }
            }
        }
    }

    private var creatureSurfaceColor: Color {
        switch colorScheme {
        case .dark:
            Color(red: 0.08, green: 0.08, blue: 0.09)
        case .light:
            Color(red: 0.96, green: 0.96, blue: 0.97)
        @unknown default:
            Color(red: 0.08, green: 0.08, blue: 0.09)
        }
    }

    private var creatureForegroundColor: Color {
        colorScheme == .dark ? .white : .black
    }
}
