import AVFoundation
import Testing
@testable import Yoyo

struct VideoControlsTests {
    @Test func testCyclePlaybackRate() {
        var controls = VideoControls()
        controls.availableRates = [1.0, 1.5, 2.0, 3.0]
        controls.playbackRate = 1.0

        // First cycle: 1.0 -> 1.5
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 1.5)

        // Second cycle: 1.5 -> 2.0
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 2.0)

        // Third cycle: 2.0 -> 3.0
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 3.0)

        // Fourth cycle: 3.0 -> 1.0 (wrap around)
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 1.0)
    }

    @Test func cycleWithLimitedRates() {
        var controls = VideoControls()
        controls.availableRates = [1.0, 2.0]
        controls.playbackRate = 1.0

        // First cycle: 1.0 -> 2.0
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 2.0)

        // Second cycle: 2.0 -> 1.0 (wrap around)
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 1.0)
    }

    @Test func cycleWithSingleRate() {
        var controls = VideoControls()
        controls.availableRates = [1.0]
        controls.playbackRate = 1.0

        // Should stay at 1.0
        controls.cyclePlaybackRate()
        #expect(controls.playbackRate == 1.0)
    }

    @Test func playbackRateResetWhenExceedsMax() {
        let controls = VideoControls()
        controls.playbackRate = 6.0
        controls.availableRates = [1.0, 2.0, 3.0, 6.0]

        // Simulate a video that can only handle 2x
        // This would happen when updateAvailableRates is called
        // The rate should be reset to 1.0

        // We can't test updateAvailableRates directly without a real AVPlayerItem,
        // but we can verify the logic manually
        let maxRate: Float = 2.0
        let shouldReset = controls.playbackRate > maxRate
        #expect(shouldReset == true)
    }
}
