import Common
import SwiftUI

/// Shared layout primitives for the storyboard tile canvas, used by **both** the editor
/// (`StoryboardEditor`) and the perform surface (`StoryboardPerformView`). Tiles are placed by
/// their relative (0–1) coordinates, and that math — plus the full-canvas pin that makes
/// `.position` behave — lives here in exactly one place. Keeping it shared is deliberate: the two
/// surfaces previously each carried their own copy and drifted apart repeatedly (tap hit-areas,
/// then a layout collapse where every tile after the first piled into a corner).
enum StoryboardCanvas {
    /// Glass-morphing spacing for the tile container.
    static let glassSpacing: CGFloat = 14
    /// Named coordinate space the editor's drag/resize gestures measure against. Defined here so the
    /// canvas that *establishes* it and the gestures that *read* it can never disagree on the name.
    static let coordinateSpace = "storyboardCanvas"
}

/// The tile layer both surfaces drop their tiles into. The positioned tiles live in a top-leading
/// `ZStack` with a `Color.clear` filler that pins the layer to the full canvas — that ZStack is the
/// anchoring parent `.position` resolves against. The whole thing is wrapped in a
/// `GlassEffectContainer` for inter-tile glass morphing.
///
/// Both pieces are load-bearing:
/// - Without the full-canvas pin, the parent shrinks to its content and `.position` collapses tiles
///   into a corner.
/// - Without the explicit `ZStack` parent, `.position`'d tiles placed *directly* inside the
///   `GlassEffectContainer` get vertically re-flowed by it (x stays correct, y is scrambled).
struct StoryboardTileLayer<Content: View>: View {
    let canvasSize: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        GlassEffectContainer(spacing: StoryboardCanvas.glassSpacing) {
            ZStack(alignment: .topLeading) {
                Color.clear
                content
            }
            .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        }
    }
}

extension View {
    /// Sizes a tile to its relative width/height within `canvasSize`, clamped to a minimum so it
    /// stays tappable. Apply this *before* any gestures/overlays and before `storyboardTilePosition`
    /// so those attach to the tile-sized frame rather than the position-expanded one.
    func storyboardTileFrame(_ tile: StoryboardTile, in canvasSize: CGSize, minSide: CGFloat)
        -> some View
    {
        frame(
            width: max(tile.width * canvasSize.width, minSide),
            height: max(tile.height * canvasSize.height, minSide))
    }

    /// Centers a tile at its relative position within `canvasSize`. Apply this **last**: `.position`
    /// expands its subject to fill the parent, so anything attached after it (taps, drag gestures)
    /// would span the whole canvas instead of just the tile.
    func storyboardTilePosition(_ tile: StoryboardTile, in canvasSize: CGSize) -> some View {
        position(
            x: (tile.x + tile.width / 2) * canvasSize.width,
            y: (tile.y + tile.height / 2) * canvasSize.height)
    }
}
