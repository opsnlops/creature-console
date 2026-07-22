/// Rendering layer for the sACN universe monitor: the 32x16 slot grid, the Canvas-backed
/// iOS/tvOS fast path with a cached grid-line image, and the per-slot cell view.
/// Extracted from SACNUniverseMonitorView.swift (Phase 5 decomposition, issue #35).

import SwiftUI

#if os(iOS) || os(tvOS)
    import UIKit
#endif

struct SACNUniverseGridView: View {
    let slots: [UInt8]
    let slotOwners: [Int: [SlotOwner]]
    private let columnsCount = 32
    private let rowsCount = 16
    private let gridPadding: CGFloat = 32

    var body: some View {
        #if os(iOS) || os(tvOS)
            SACNUniverseCanvasGridView(
                slots: slots,
                slotOwners: slotOwners,
                columnsCount: columnsCount,
                rowsCount: rowsCount,
                gridPadding: gridPadding
            )
        #else
            GeometryReader { geometry in
                let spacing: CGFloat = 2
                let availableWidth = geometry.size.width - spacing * CGFloat(columnsCount - 1)
                let availableHeight = geometry.size.height - spacing * CGFloat(rowsCount - 1)
                let cellWidth = max(8, min(40, availableWidth / CGFloat(columnsCount)))
                let cellHeight = max(6, min(28, availableHeight / CGFloat(rowsCount)))
                let cellSize = CGSize(width: cellWidth, height: cellHeight)
                let backgroundColor = gridBackgroundColor

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(backgroundColor)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(cellSize.width), spacing: spacing),
                            count: columnsCount
                        ),
                        spacing: spacing
                    ) {
                        ForEach(0..<512, id: \.self) { index in
                            let slotIndex = index + 1
                            let rowIndex = index / columnsCount
                            let columnIndex = index % columnsCount
                            SACNSlotCellView(
                                slotIndex: slotIndex,
                                rowIndex: rowIndex,
                                columnIndex: columnIndex,
                                rowsCount: rowsCount,
                                columnsCount: columnsCount,
                                value: slots[safe: index] ?? 0,
                                owners: slotOwners[slotIndex, default: []],
                                size: cellSize
                            )
                        }
                    }
                }
            }
        #endif
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
}

#if os(iOS) || os(tvOS)
    private struct SACNUniverseCanvasGridView: View {
        let slots: [UInt8]
        let slotOwners: [Int: [SlotOwner]]
        let columnsCount: Int
        let rowsCount: Int
        let gridPadding: CGFloat
        @Environment(\.colorScheme) private var colorScheme
        @State private var gridImage: Image?
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
                            let slotIndex = index + 1
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

                            if let owner = slotOwners[slotIndex]?.first {
                                context.fill(Path(rect), with: .color(owner.color.opacity(0.28)))
                                let outlineWidth =
                                    max(1, min(layout.cellSize.width, layout.cellSize.height) / 12)
                                context.stroke(
                                    Path(rect),
                                    with: .color(owner.color.opacity(0.65)),
                                    lineWidth: outlineWidth
                                )
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
                                        context.fill(
                                            Path(ellipseIn: dotRect), with: .color(owner.color))
                                        dotX += dotSize + dotSpacing
                                    }
                                }
                            }

                            if (slotIndex - 1) % 16 == 0 {
                                let fontSize = max(8, min(12, layout.minDimension * 0.35))
                                let label = Text("\(slotIndex)")
                                    .font(
                                        .system(
                                            size: fontSize, weight: .semibold, design: .monospaced)
                                    )
                                    .foregroundStyle(.white.opacity(0.85))
                                let textPoint = CGPoint(
                                    x: rect.minX + 2,
                                    y: rect.minY + 1
                                )
                                context.draw(label, at: textPoint, anchor: .topLeading)
                            }
                        }
                    }
                }
                .onAppear {
                    updateGridImage(for: geometry.size)
                }
                .onChange(of: geometry.size) { _, newValue in
                    updateGridImage(for: newValue)
                }
                .onChange(of: colorScheme) { _, _ in
                    updateGridImage(for: geometry.size)
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

        private func updateGridImage(for size: CGSize) {
            guard size != .zero else {
                return
            }
            if size == cachedSize, gridImage != nil {
                return
            }
            cachedSize = size
            let layout = GridLayout(
                size: CGSize(
                    width: max(0, size.width - gridPadding * 2),
                    height: max(0, size.height - gridPadding * 2)
                ),
                columnsCount: columnsCount,
                rowsCount: rowsCount
            )
            let image = renderGridImage(layout: layout)
            gridImage = Image(uiImage: image)
        }

        private func renderGridImage(layout: GridLayout) -> UIImage {
            let renderer = UIGraphicsImageRenderer(size: layout.totalSize)
            return renderer.image { context in
                let cgContext = context.cgContext
                let lineColor =
                    (colorScheme == .dark)
                    ? UIColor(white: 1.0, alpha: 0.18)
                    : UIColor(white: 0.0, alpha: 0.2)
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
                        let fontSize = max(6, min(10, layout.minDimension * 0.35))
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .semibold),
                            .foregroundColor: UIColor.label.withAlphaComponent(0.7),
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
#endif

private struct SACNSlotCellView: View {
    let slotIndex: Int
    let rowIndex: Int
    let columnIndex: Int
    let rowsCount: Int
    let columnsCount: Int
    let value: UInt8
    let owners: [SlotOwner]
    let size: CGSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shade = slotShade
        Rectangle()
            .fill(Color(white: shade))
            .frame(width: size.width, height: size.height)
            .overlay(overlayTint)
            .overlay(ownerOutline)
            .overlay(slotLabel)
            .overlay(ownerDots, alignment: .bottomTrailing)
            .overlay(gridLines)
            .accessibilityLabel("Slot \(slotIndex) value \(value)")
            .help(ownersHelpText)
    }

    private var overlayTint: some View {
        Group {
            if let owner = owners.first {
                Rectangle()
                    .fill(owner.color.opacity(0.28))
            }
        }
    }

    private var ownerOutline: some View {
        Group {
            if let owner = owners.first {
                Rectangle()
                    .stroke(owner.color.opacity(0.65), lineWidth: max(1, minDimension / 12))
            }
        }
    }

    private var slotLabel: some View {
        Group {
            if (slotIndex - 1) % 16 == 0 {
                Text("\(slotIndex)")
                    .font(
                        .system(
                            size: max(6, min(10, minDimension * 0.35)),
                            weight: .semibold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var ownerDots: some View {
        HStack(spacing: 1) {
            ForEach(owners.prefix(3)) { owner in
                Circle()
                    .fill(owner.color)
                    .frame(width: minDimension / 3.5, height: minDimension / 3.5)
            }
        }
        .padding(1)
    }

    private var gridLines: some View {
        let width = size.width
        let height = size.height
        return Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: width, y: 0))
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 0, y: height))

            if columnIndex == columnsCount - 1 {
                path.move(to: CGPoint(x: width, y: 0))
                path.addLine(to: CGPoint(x: width, y: height))
            }
            if rowIndex == rowsCount - 1 {
                path.move(to: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: width, y: height))
            }
        }
        .stroke(gridLineColor, lineWidth: 0.8)
    }

    private var ownersHelpText: String {
        guard !owners.isEmpty else {
            return ""
        }
        return
            owners
            .map { "\($0.creatureName) · \($0.label)" }
            .joined(separator: "\n")
    }

    private var minDimension: CGFloat {
        min(size.width, size.height)
    }

    private var slotShade: Double {
        let normalized = Double(value) / 255.0
        if colorScheme == .dark {
            // In dark mode, keep the grid legible by mapping 0->dark, 255->light.
            return 0.005 + (normalized * 0.88)
        }
        return 1.0 - normalized
    }

    private var gridLineColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.2)
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
