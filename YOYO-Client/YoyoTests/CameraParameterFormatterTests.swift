import Testing
@testable import Yoyo

struct CameraParameterFormatterTests {
    // MARK: - Exposure Compensation Formatting Tests

    @Test func exposureCompensationZero() {
        // Verify that 0 is displayed as +0.0
        let result = CameraParameterFormatter.formatExposureCompensation(0.0)
        #expect(result == "+0.0")
    }

    @Test func exposureCompensationNegativeZero() {
        // Verify that -0.0 is displayed as +0.0 to avoid showing -0.0
        let result = CameraParameterFormatter.formatExposureCompensation(-0.0)
        #expect(result == "+0.0")
    }

    @Test func exposureCompensationSmallNegativeValue() {
        // Verify that small negative values near zero (< 0.05) are displayed as +0.0
        let result = CameraParameterFormatter.formatExposureCompensation(-0.03)
        #expect(result == "+0.0")
    }

    @Test func exposureCompensationSmallPositiveValue() {
        // Verify that small positive values near zero (< 0.05) are displayed as +0.0
        let result = CameraParameterFormatter.formatExposureCompensation(0.04)
        #expect(result == "+0.0")
    }

    @Test func exposureCompensationPositiveValue() {
        // Verify that positive values include a plus sign
        let result = CameraParameterFormatter.formatExposureCompensation(1.5)
        #expect(result == "+1.5")
    }

    @Test func exposureCompensationNegativeValue() {
        // Verify that negative values include a minus sign
        let result = CameraParameterFormatter.formatExposureCompensation(-2.3)
        #expect(result == "-2.3")
    }

    @Test func exposureCompensationEdgeCasePositive() {
        // Verify that the boundary value 0.05 rounds to +0.1
        let result = CameraParameterFormatter.formatExposureCompensation(0.05)
        #expect(result == "+0.1")
    }

    @Test func exposureCompensationEdgeCaseNegative() {
        // Verify that the boundary value -0.05 rounds to -0.1
        let result = CameraParameterFormatter.formatExposureCompensation(-0.05)
        #expect(result == "-0.1")
    }

    @Test func exposureCompensationMaxPositive() {
        // Verify the maximum positive value
        let result = CameraParameterFormatter.formatExposureCompensation(2.0)
        #expect(result == "+2.0")
    }

    @Test func exposureCompensationMaxNegative() {
        // Verify the maximum negative value
        let result = CameraParameterFormatter.formatExposureCompensation(-2.0)
        #expect(result == "-2.0")
    }

    @Test func exposureCompensationRounding() {
        // Verify rounding to one decimal place
        let result = CameraParameterFormatter.formatExposureCompensation(1.27)
        #expect(result == "+1.3")
    }
}
