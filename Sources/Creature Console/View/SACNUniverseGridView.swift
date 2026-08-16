/// Rendering layer for the sACN universe monitor: the 32x16 slot grid, drawn as a single
/// Canvas pass with a cached grid-line image on every platform. macOS originally used a
/// LazyVGrid of 512 cell views here; at the monitor's ~50 Hz publish rate that meant
/// thousands of view updates a second and dragged the whole app (#74). The Canvas redraws
/// once per frame no matter how many slots changed, and a hover readout replaces the old
/// per-cell tooltips.
/// Extracted from SACNUniverseMonitorView.swift (Phase 5 decomposition, issue #35).

import Common
import SwiftUI

#if os(iOS) || os(tvOS)
    import UIKit
#else
    import AppKit
#endif

/// Turns the hues handed out by `SACNUniverseOverlayBuilder` into colors. Everything that
/// draws overlay owners — grid cells and legend swatches alike — goes through here so a
/// creature or fixture is the same color everywhere on screen.
enum SACNOverlayPalette {
    static let saturation: Double = 0.7
    static let brightness: Double = 0.9

    static func color(hue: Double) -> Color {
        Color(hue: hue, saturation: saturation, brightness: brightness)
    }
}

extension SACNSlotOwner {
    var color: Color { SACNOverlayPalette.color(hue: hue) }
}

extension SACNOverlayLegendEntry {
    var color: Color { SACNOverlayPalette.color(hue: hue) }
}

extension SACNSlotOwnerKind {
    /// Corner radius as a fraction of the marker's size: creatures are drawn round, fixtures
    /// square. Shape says *what kind* of thing owns the slot, color says *which one* — so a
    /// slot reads correctly even before you look at the legend.
    var markerCornerFraction: CGFloat {
        switch self {
        case .creature: return 0.5
        case .fixture: return 0.15
        }
    }
}

struct SACNUniverseGridView: View {
    let slots: [UInt8]
    let slotOwners: [Int: [SACNSlotOwner]]
    private let columnsCount = 32
    private let rowsCount = 16
    private let gridPadding: CGFloat = 32

    var body: some View {
        SACNUniverseCanvasGridView(
            slots: slots,
            slotOwners: slotOwners,
            columnsCount: columnsCount,
            rowsCount: rowsCount,
            gridPadding: gridPadding
        )
    }
}

private struct SACNUniverseCanvasGridView: View {
    let slots: [UInt8]
    let slotOwners: [Int: [SACNSlotOwner]]
    let columnsCount: Int
    let rowsCount: Int
    let gridPadding: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var gridImage: Image?
    // Owner tints, marker dots, and slot labels only change when the patch or geometry
    // does, so they render into a cached image layered above the live Canvas. Resolving
    // them (Text especially) inside the 50 Hz Canvas pass was a top CPU cost (#76).
    @State private var overlayImage: Image?
    @State private var cachedSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let layout = GridLayout(
                size: CGSize(
                    width: max(0, geometry.size.width - gridPadding * 2),
                    height: max(0, geometry.size.height - gridPadding * 2)
                ),
                columnsCount: columnsCount,
                rowsCount: rowsCount
            )
            let gridBackground = gridBackgroundColor

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(gridBackground)
                if let gridImage {
                    gridImage
                        .resizable()
                        .frame(width: layout.totalSize.width, height: layout.totalSize.height)
                        .position(
                            x: gridPadding + layout.origin.x + layout.totalSize.width / 2,
                            y: gridPadding + layout.origin.y + layout.totalSize.height / 2
                        )
                }
                Canvas { context, _ in
                    for index in 0..<512 {
                        let rowIndex = index / columnsCount
                        let columnIndex = index % columnsCount
                        let x =
                            gridPadding + layout.origin.x
                            + CGFloat(columnIndex) * (layout.cellSize.width + layout.spacing)
                        let y =
                            gridPadding + layout.origin.y
                            + CGFloat(rowIndex) * (layout.cellSize.height + layout.spacing)
                        let rect = CGRect(
                            x: x,
                            y: y,
                            width: layout.cellSize.width,
                            height: layout.cellSize.height
                        )

                        context.fill(
                            Path(rect),
                            with: .color(slotFill(for: slots[safe: index] ?? 0))
                        )
                    }
                }
                if let overlayImage {
                    overlayImage
                        .resizable()
                        .frame(width: layout.totalSize.width, height: layout.totalSize.height)
                        .position(
                            x: gridPadding + layout.origin.x + layout.totalSize.width / 2,
                            y: gridPadding + layout.origin.y + layout.totalSize.height / 2
                        )
                        .allowsHitTesting(false)
                }
                #if os(macOS)
                    SACNGridHoverReadout(
                        slots: slots,
                        slotOwners: slotOwners,
                        layout: layout,
                        gridPadding: gridPadding,
                        columnsCount: columnsCount,
                        rowsCount: rowsCount
                    )
                #endif
            }
            .onAppear {
                updateCachedImages(for: geometry.size)
            }
            .onChange(of: geometry.size) { _, newValue in
                updateCachedImages(for: newValue)
            }
            .onChange(of: colorScheme) { _, _ in
                updateCachedImages(for: geometry.size, forceGrid: true)
            }
            .onChange(of: slotOwners) { _, _ in
                updateCachedImages(for: geometry.size)
            }
        }
    }

    private func slotFill(for value: UInt8) -> Color {
        let normalized = Double(value) / 255.0
        if colorScheme == .dark {
            return Color(white: 0.005 + (normalized * 0.88))
        }
        return Color(white: 1.0 - normalized)
    }

    private var gridBackgroundColor: Color {
        #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
        #elseif os(tvOS)
            return Color(white: 0.16)
        #else
            return Color(.secondarySystemBackground)
        #endif
    }

    private func updateCachedImages(for size: CGSize, forceGrid: Bool = false) {
        guard size != .zero else {
            return
        }
        let layout = GridLayout(
            size: CGSize(
                width: max(0, size.width - gridPadding * 2),
                height: max(0, size.height - gridPadding * 2)
            ),
            columnsCount: columnsCount,
            rowsCount: rowsCount
        )
        if forceGrid || size != cachedSize || gridImage == nil {
            gridImage = renderGridImage(layout: layout)
        }
        overlayImage = renderOverlayImage(layout: layout)
        cachedSize = size
    }

    #if os(iOS) || os(tvOS)
        private func renderGridImage(layout: GridLayout) -> Image {
            let renderer = UIGraphicsImageRenderer(size: layout.totalSize)
            let image = renderer.image { context in
                drawGridLines(
                    into: context.cgContext,
                    layout: layout,
                    labelFont: UIFont.monospacedSystemFont(
                        ofSize: gridLabelFontSize(layout: layout), weight: .semibold),
                    labelColor: UIColor.label.withAlphaComponent(0.7),
                    lineColor: (colorScheme == .dark)
                        ? UIColor(white: 1.0, alpha: 0.18)
                        : UIColor(white: 0.0, alpha: 0.2)
                )
            }
            return Image(uiImage: image)
        }
    #else
        private func renderGridImage(layout: GridLayout) -> Image {
            let scheme = colorScheme
            let labelFontSize = gridLabelFontSize(layout: layout)
            let image = NSImage(size: layout.totalSize, flipped: true) { _ in
                guard let cgContext = NSGraphicsContext.current?.cgContext else {
                    return false
                }
                drawGridLines(
                    into: cgContext,
                    layout: layout,
                    labelFont: NSFont.monospacedSystemFont(
                        ofSize: labelFontSize, weight: .semibold),
                    labelColor: NSColor.labelColor.withAlphaComponent(0.7),
                    lineColor: (scheme == .dark)
                        ? NSColor(white: 1.0, alpha: 0.18)
                        : NSColor(white: 0.0, alpha: 0.2)
                )
                return true
            }
            return Image(nsImage: image)
        }
    #endif

    private func gridLabelFontSize(layout: GridLayout) -> CGFloat {
        max(6, min(10, layout.minDimension * 0.35))
    }

    #if os(iOS) || os(tvOS)
        private func renderOverlayImage(layout: GridLayout) -> Image {
            let renderer = UIGraphicsImageRenderer(size: layout.totalSize)
            let image = renderer.image { context in
                drawOverlay(into: context.cgContext, layout: layout)
            }
            return Image(uiImage: image)
        }
    #else
        private func renderOverlayImage(layout: GridLayout) -> Image {
            let image = NSImage(size: layout.totalSize, flipped: true) { _ in
                guard let cgContext = NSGraphicsContext.current?.cgContext else {
                    return false
                }
                drawOverlay(into: cgContext, layout: layout)
                return true
            }
            return Image(nsImage: image)
        }
    #endif

    private func platformColor(hue: Double, alpha: CGFloat) -> PlatformColor {
        PlatformColor(
            hue: hue,
            saturation: SACNOverlayPalette.saturation,
            brightness: SACNOverlayPalette.brightness,
            alpha: alpha
        )
    }

    /// Everything that sits on top of the live value fills but changes only with the patch:
    /// owner tints and outlines, marker dots, and the slot-number labels.
    private func drawOverlay(into cgContext: CGContext, layout: GridLayout) {
        let labelFontSize = max(8, min(12, layout.minDimension * 0.35))
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: PlatformFont.monospacedSystemFont(ofSize: labelFontSize, weight: .semibold),
            .foregroundColor: PlatformColor.white.withAlphaComponent(0.85),
        ]

        for index in 0..<512 {
            let slotIndex = index + 1
            let rowIndex = index / columnsCount
            let columnIndex = index % columnsCount
            let x = CGFloat(columnIndex) * (layout.cellSize.width + layout.spacing)
            let y = CGFloat(rowIndex) * (layout.cellSize.height + layout.spacing)
            let rect = CGRect(
                x: x,
                y: y,
                width: layout.cellSize.width,
                height: layout.cellSize.height
            )

            if let owner = slotOwners[slotIndex]?.first {
                cgContext.setFillColor(platformColor(hue: owner.hue, alpha: 0.28).cgColor)
                cgContext.fill(rect)
                let outlineWidth =
                    max(1, min(layout.cellSize.width, layout.cellSize.height) / 12)
                cgContext.setStrokeColor(platformColor(hue: owner.hue, alpha: 0.65).cgColor)
                cgContext.setLineWidth(outlineWidth)
                cgContext.stroke(rect)
            }

            if let owners = slotOwners[slotIndex] {
                let dotOwners = owners.prefix(3)
                if !dotOwners.isEmpty {
                    let dotSize = layout.minDimension / 3.5
                    let dotSpacing: CGFloat = 1
                    let totalDotsWidth =
                        CGFloat(dotOwners.count) * dotSize
                        + CGFloat(max(0, dotOwners.count - 1)) * dotSpacing
                    var dotX = rect.maxX - 1 - totalDotsWidth
                    let dotY = rect.maxY - 1 - dotSize
                    for owner in dotOwners {
                        let dotRect = CGRect(
                            x: dotX,
                            y: dotY,
                            width: dotSize,
                            height: dotSize
                        )
                        cgContext.setFillColor(platformColor(hue: owner.hue, alpha: 1).cgColor)
                        cgContext.addPath(
                            Path(
                                roundedRect: dotRect,
                                cornerRadius: dotSize * owner.kind.markerCornerFraction
                            ).cgPath
                        )
                        cgContext.fillPath()
                        dotX += dotSize + dotSpacing
                    }
                }
            }

            if (slotIndex - 1) % 16 == 0 {
                let label = "\(slotIndex)" as NSString
                label.draw(
                    at: CGPoint(x: rect.minX + 2, y: rect.minY + 1),
                    withAttributes: labelAttributes
                )
            }
        }
    }

    #if os(iOS) || os(tvOS)
        private typealias PlatformFont = UIFont
        private typealias PlatformColor = UIColor
    #else
        private typealias PlatformFont = NSFont
        private typealias PlatformColor = NSColor
    #endif

    private func drawGridLines(
        into cgContext: CGContext,
        layout: GridLayout,
        labelFont: PlatformFont,
        labelColor: PlatformColor,
        lineColor: PlatformColor
    ) {
        cgContext.setStrokeColor(lineColor.cgColor)
        cgContext.setLineWidth(0.8)

        for index in 0..<512 {
            let slotIndex = index + 1
            let rowIndex = index / columnsCount
            let columnIndex = index % columnsCount
            let x = CGFloat(columnIndex) * (layout.cellSize.width + layout.spacing)
            let y = CGFloat(rowIndex) * (layout.cellSize.height + layout.spacing)
            let rect = CGRect(
                x: x,
                y: y,
                width: layout.cellSize.width,
                height: layout.cellSize.height
            )
            let path = gridLinePath(
                rect: rect,
                rowIndex: rowIndex,
                columnIndex: columnIndex,
                rowsCount: rowsCount,
                columnsCount: columnsCount
            )
            cgContext.addPath(path.cgPath)

            if (slotIndex - 1) % 16 == 0 {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: labelFont,
                    .foregroundColor: labelColor,
                ]
                let label = "\(slotIndex)" as NSString
                label.draw(
                    at: CGPoint(x: rect.minX + 1, y: rect.minY + 1),
                    withAttributes: attributes
                )
            }
        }
        cgContext.strokePath()
    }

    private func gridLinePath(
        rect: CGRect,
        rowIndex: Int,
        columnIndex: Int,
        rowsCount: Int,
        columnsCount: Int
    ) -> Path {
        Path { path in
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.move(to: rect.origin)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))

            if columnIndex == columnsCount - 1 {
                path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
            if rowIndex == rowsCount - 1 {
                path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            }
        }
    }
}

#if os(macOS)
    /// The Canvas draws all 512 slots in one pass, so there is no per-cell view to hang a
    /// `.help` tooltip on. This overlay recovers that information — hover any cell and a chip
    /// shows the slot number, its live value, and who owns it.
    private struct SACNGridHoverReadout: View {
        let slots: [UInt8]
        let slotOwners: [Int: [SACNSlotOwner]]
        let layout: GridLayout
        let gridPadding: CGFloat
        let columnsCount: Int
        let rowsCount: Int

        @State private var hoverPoint: CGPoint?

        var body: some View {
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point):
                        hoverPoint = point
                    case .ended:
                        hoverPoint = nil
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if let slotIndex = hoveredSlotIndex {
                        readoutChip(for: slotIndex)
                            .padding(6)
                    }
                }
                .allowsHitTesting(true)
        }

        private var hoveredSlotIndex: Int? {
            guard let hoverPoint else { return nil }
            let localX = hoverPoint.x - gridPadding - layout.origin.x
            let localY = hoverPoint.y - gridPadding - layout.origin.y
            let strideX = layout.cellSize.width + layout.spacing
            let strideY = layout.cellSize.height + layout.spacing
            guard localX >= 0, localY >= 0, strideX > 0, strideY > 0 else { return nil }
            let column = Int(localX / strideX)
            let row = Int(localY / strideY)
            guard column < columnsCount, row < rowsCount else { return nil }
            return row * columnsCount + column + 1
        }

        private func readoutChip(for slotIndex: Int) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text("Slot \(slotIndex) · \(slots[safe: slotIndex - 1] ?? 0)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                ForEach(slotOwners[slotIndex, default: []]) { owner in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 8 * owner.kind.markerCornerFraction)
                            .fill(owner.color)
                            .frame(width: 8, height: 8)
                        Text("\(owner.ownerName) · \(owner.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .rect(cornerRadius: 8))
            .allowsHitTesting(false)
        }
    }
#endif

private struct GridLayout {
    let spacing: CGFloat = 2
    let cellSize: CGSize
    let origin: CGPoint
    let totalSize: CGSize
    let minDimension: CGFloat

    init(size: CGSize, columnsCount: Int, rowsCount: Int) {
        let availableWidth = size.width - spacing * CGFloat(columnsCount - 1)
        let availableHeight = size.height - spacing * CGFloat(rowsCount - 1)
        let cellWidth = max(8, availableWidth / CGFloat(columnsCount))
        let cellHeight = max(6, availableHeight / CGFloat(rowsCount))
        cellSize = CGSize(width: cellWidth, height: cellHeight)
        totalSize = CGSize(
            width: cellWidth * CGFloat(columnsCount) + spacing * CGFloat(columnsCount - 1),
            height: cellHeight * CGFloat(rowsCount) + spacing * CGFloat(rowsCount - 1)
        )
        origin = CGPoint(
            x: max(0, (size.width - totalSize.width) / 2),
            y: max(0, (size.height - totalSize.height) / 2)
        )
        minDimension = min(cellWidth, cellHeight)
    }
}

extension Array where Element == UInt8 {
    fileprivate subscript(safe index: Int) -> UInt8? {
        guard indices.contains(index) else {
            return nil
        }
        return self[index]
    }
}
