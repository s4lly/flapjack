import Foundation
import Testing

@testable import Flapjack

/// The drain's redraw rate and its animate-or-step decision, which together are
/// what keep an idle clock off the CPU. The rule under test is "one point of
/// travel per redraw": the tick follows the speed of the edge, and an animation
/// is only bought when a single step would be too coarse to pass for motion.
@Suite("DrainCadence")
struct DrainCadenceTests {

    private func cadence(minutes: Int, width: Double) -> DrainCadence {
        DrainCadence(spanSeconds: TimeInterval(minutes) * 60, width: width)
    }

    // MARK: - The tick follows the speed of the edge

    @Test("A quarter-hour across 900 points moves a point a second, so it ticks once a second")
    func quarterHourOnATypicalWindow() {
        let c = cadence(minutes: 15, width: 900)
        #expect(c.tick == 1)
        #expect(abs(c.stepPoints - 1) < 0.001)
        #expect(!c.animates)
    }

    @Test("An hour across the same window moves four times slower, so it ticks four times less often")
    func hourlyOnATypicalWindow() {
        let c = cadence(minutes: 60, width: 900)
        #expect(c.tick == 4)
        #expect(abs(c.stepPoints - 1) < 0.001)
        #expect(!c.animates)
    }

    @Test("A wider window moves the edge faster, so it ticks more often rather than animating")
    func wideWindowTicksFasterInsteadOfAnimating() {
        let c = cadence(minutes: 15, width: 1800)
        #expect(c.tick == 0.5)
        #expect(abs(c.stepPoints - 1) < 0.001)
        #expect(!c.animates,
                "a wide window is exactly the case the animation cost was measured on")
    }

    // MARK: - The clamps

    @Test("Never redraws faster than the floor")
    func floor() {
        // One minute across a very wide window would want ~0.07s.
        let c = cadence(minutes: 1, width: 1800)
        #expect(c.tick == DrainCadence.minimumTick)
    }

    @Test("Never redraws slower than the ceiling, however lazy the cadence")
    func ceiling() {
        // An hour across the minimum window width would want ~12.9s.
        let c = cadence(minutes: 60, width: 280)
        #expect(c.tick == DrainCadence.maximumTick)
        #expect(c.stepPoints < 1, "a slow drain still steps less than a point")
    }

    // MARK: - Animate only when a step would be too coarse to read as motion

    @Test("A step of two points or more is animated")
    func coarseStepsAnimate() {
        // A one-minute cadence really does race across the window; at the
        // floor tick that is several points a step.
        let c = cadence(minutes: 1, width: 900)
        #expect(c.stepPoints >= DrainCadence.animationThreshold)
        #expect(c.animates)
    }

    @Test("The real settings never animate at any window size the app allows")
    func shippedCadencesStepRatherThanAnimate() {
        for minutes in [15, 30, 60] {
            for width in stride(from: 280.0, through: 3200.0, by: 20) {
                let c = cadence(minutes: minutes, width: width)
                #expect(!c.animates,
                        "\(minutes)min on \(width)pt stepped \(c.stepPoints)pt")
            }
        }
    }

    // MARK: - Degenerate inputs

    @Test("A zero span or zero width falls back to the floor without dividing by zero")
    func degenerate() {
        for c in [cadence(minutes: 0, width: 900), cadence(minutes: 15, width: 0)] {
            #expect(c.tick == DrainCadence.minimumTick)
            #expect(c.stepPoints == 0)
            #expect(!c.animates)
        }
    }
}
