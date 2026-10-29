import Foundation

/// The crawl cycle that makes a worm look alive.
///
/// A worm does not slide across the floor: it bunches up, then stretches out after
/// its head. The cycle is driven by the distance travelled rather than by the clock,
/// so the squirming always matches how fast the worm is really going, keeps step
/// with its speed, and stops when it stops.
public struct WormCrawl: Sendable, Equatable {
    /// How far a worm travels to complete one full bunch-and-stretch, in tiles.
    public static let stride: Double = 1.4
    /// Speed at which the worm squirms at full amplitude, in tiles per second.
    public static let fullSpeed: Double = 2.0
    /// How much shorter the worm gets at the tightest point of the cycle.
    public static let contraction: Double = 0.16
    /// How much fatter it gets while bunched, so it reads as a squash and not a
    /// sprite that shrank.
    public static let thickening: Double = 0.12
    /// How quickly the worm eases into and out of squirming, per second.
    private static let easeRate: Double = 8

    /// Position in the cycle, in turns; wraps at 1.
    public private(set) var phase: Double = 0
    /// How hard the worm is squirming: 0 still, 1 at full speed.
    public private(set) var effort: Double = 0

    public init() {}

    /// Feeds one frame of movement in.
    ///
    /// - Parameters:
    ///   - distance: ground covered this frame, in tiles. A jump - walking out of
    ///     a doorway, or respawning - is not a crawl and is ignored.
    ///   - deltaTime: frame time, in seconds.
    public mutating func advance(distance: Double, deltaTime: Double) {
        guard deltaTime > 0, deltaTime.isFinite else { return }
        let travel = distance.isFinite && distance < 1 ? distance : 0
        phase = (phase + travel / Self.stride).truncatingRemainder(dividingBy: 1)

        let target = min(1, travel / deltaTime / Self.fullSpeed)
        effort += (target - effort) * min(1, deltaTime * Self.easeRate)
    }

    /// 0 at full stretch, 1 at the tightest bunch of the cycle.
    public var bunch: Double {
        0.5 - 0.5 * cos(2 * .pi * phase)
    }

    /// Horizontal scale to draw the worm at.
    public var stretch: Double { 1 - Self.contraction * effort * bunch }

    /// Vertical scale to draw the worm at, which keeps it from looking shrunken.
    public var thickness: Double { 1 + Self.thickening * effort * bunch }
}
