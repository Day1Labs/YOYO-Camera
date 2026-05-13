import AVFoundation
import Testing
@testable import Yoyo

struct VideoPlaybackCapabilityTests {
    @Test func test4K60FPSLimits() {
        // 4K 60fps should be limited to 2x on high-end devices
        let resolution = CGSize(width: 3840, height: 2160)
        let frameRate: Float = 60.0

        let maxRate = VideoPlaybackCapability.calculateMaxPlaybackRate(
            resolution: resolution,
            frameRate: frameRate
        )

        // Should be limited to 2.0 or lower
        #expect(maxRate <= 2.0)
    }

    @Test func test4K30FPSLimits() {
        // 4K 30fps should allow up to 3x on high-end devices
        let resolution = CGSize(width: 3840, height: 2160)
        let frameRate: Float = 30.0

        let maxRate = VideoPlaybackCapability.calculateMaxPlaybackRate(
            resolution: resolution,
            frameRate: frameRate
        )

        // Should allow at least 2x, but no more than 3x on high-end
        #expect(maxRate >= 1.5)
        #expect(maxRate <= 3.0)
    }

    @Test func test1080p60FPSLimits() {
        // 1080p 60fps should handle higher speeds
        let resolution = CGSize(width: 1920, height: 1080)
        let frameRate: Float = 60.0

        let maxRate = VideoPlaybackCapability.calculateMaxPlaybackRate(
            resolution: resolution,
            frameRate: frameRate
        )

        // Should allow at least 2x
        #expect(maxRate >= 2.0)
    }

    @Test func test1080p30FPSLimits() {
        // 1080p 30fps should handle maximum speeds
        let resolution = CGSize(width: 1920, height: 1080)
        let frameRate: Float = 30.0

        let maxRate = VideoPlaybackCapability.calculateMaxPlaybackRate(
            resolution: resolution,
            frameRate: frameRate
        )

        // Should allow 6x
        #expect(maxRate == 6.0)
    }

    @Test func testGeneratePlaybackRates() {
        // Test that rates are generated correctly
        let rates3x = VideoPlaybackCapability.generatePlaybackRates(maxRate: 3.0)
        #expect(rates3x == [1.0, 1.5, 2.0, 3.0])

        let rates2x = VideoPlaybackCapability.generatePlaybackRates(maxRate: 2.0)
        #expect(rates2x == [1.0, 1.5, 2.0])

        let rates6x = VideoPlaybackCapability.generatePlaybackRates(maxRate: 6.0)
        #expect(rates6x == [1.0, 1.5, 2.0, 3.0, 6.0])

        let rates1x = VideoPlaybackCapability.generatePlaybackRates(maxRate: 1.0)
        #expect(rates1x == [1.0])
    }

    @Test func lowResolutionVideos() {
        // 720p should handle all speeds
        let resolution = CGSize(width: 1280, height: 720)
        let frameRate: Float = 60.0

        let maxRate = VideoPlaybackCapability.calculateMaxPlaybackRate(
            resolution: resolution,
            frameRate: frameRate
        )

        // Should allow 6x
        #expect(maxRate == 6.0)
    }
}
