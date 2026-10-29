import Foundation
import Testing
import WrigglerCore

@Suite("Worm crawl")
struct WormCrawlTests {
    /// Walks a worm at a fixed speed for a while and collects the shapes it takes.
    private func shapes(
        steps: Int,
        distance: Double,
        deltaTime: Double = 1.0 / 60.0
    ) -> [(stretch: Double, thickness: Double)] {
        var crawl = WormCrawl()
        var shapes: [(Double, Double)] = []
        for _ in 0..<steps {
            crawl.advance(distance: distance, deltaTime: deltaTime)
            shapes.append((crawl.stretch, crawl.thickness))
        }
        return shapes
    }

    @Test("A worm that is not going anywhere keeps its full length")
    func stillWormIsStill() {
        var crawl = WormCrawl()
        for _ in 0..<120 {
            crawl.advance(distance: 0, deltaTime: 1.0 / 60.0)
            #expect(crawl.stretch == 1)
            #expect(crawl.thickness == 1)
        }
    }

    @Test("A crawling worm bunches up and stretches back out")
    func crawlingWormSquirms() {
        // 3.9 tiles/s at 60 Hz, which is a rival at full speed.
        let distance = 3.9 / 60.0
        let walk = shapes(steps: 120, distance: distance)
        let shortest = walk.map(\.stretch).min() ?? 1
        let longest = walk.map(\.stretch).max() ?? 1
        let fattest = walk.map(\.thickness).max() ?? 1

        #expect(shortest < 0.9, "the worm never contracted")
        #expect(longest > 0.99, "the worm never stretched out again")
        #expect(fattest > 1.05, "the worm never fattened as it bunched up")
    }

    @Test("The cycle follows distance, not the clock")
    func crawlIsFrameRateIndependent() {
        var coarse = WormCrawl()
        coarse.advance(distance: 1.0 / 60.0, deltaTime: 1.0 / 60.0)
        var fine = WormCrawl()
        for _ in 0..<1 {
            fine.advance(distance: 1.0 / 60.0, deltaTime: 1.0 / 60.0)
        }
        #expect(abs(coarse.phase - fine.phase) < 1e-12)

        // The same ground covered in one step or in ten lands on the same phase.
        var single = WormCrawl()
        single.advance(distance: 0.5, deltaTime: 0.5)
        var many = WormCrawl()
        for _ in 0..<10 {
            many.advance(distance: 0.05, deltaTime: 0.05)
        }
        #expect(abs(single.phase - many.phase) < 1e-12)
    }

    @Test("A doorway jump is not a crawl")
    func teleportsAreIgnored() {
        var crawl = WormCrawl()
        crawl.advance(distance: 0.2, deltaTime: 1.0 / 60.0)
        let phase = crawl.phase
        let effort = crawl.effort

        // Walking out of a doorway moves the worm most of a screen at once.
        crawl.advance(distance: 20, deltaTime: 1.0 / 60.0)

        #expect(crawl.phase == phase)
        #expect(crawl.effort < effort, "a jump must not read as a burst of speed")
    }

    @Test("A worm eases to a stop instead of snapping")
    func stoppingIsSmooth() {
        var crawl = WormCrawl()
        for _ in 0..<120 { crawl.advance(distance: 3.9 / 60, deltaTime: 1.0 / 60) }
        #expect(crawl.effort > 0.9)

        var previous = crawl.effort
        var drops: [Double] = []
        for _ in 0..<20 {
            crawl.advance(distance: 0, deltaTime: 1.0 / 60)
            drops.append(previous - crawl.effort)
            previous = crawl.effort
        }
        #expect(crawl.effort < 0.3, "the worm is still squirming after stopping")
        #expect((drops.max() ?? 0) < 0.3, "the effort fell off a cliff")
    }
}
