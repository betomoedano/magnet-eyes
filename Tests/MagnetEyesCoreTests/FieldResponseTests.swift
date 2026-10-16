import XCTest
@testable import MagnetEyesCore

final class FieldResponseTests: XCTestCase {
    private let background = FieldVector(x: 23, y: -11, z: 38)

    private func centeredResponse(at baseline: FieldVector = .zero) -> FieldResponse {
        var response = FieldResponse()
        response.setBaseline(baseline)
        XCTAssertTrue(response.ingest(baseline, timestamp: 0))
        return response
    }

    private func advance(_ response: inout FieldResponse, to field: FieldVector,
                         seconds: Double = 2, rate: Int = 60) {
        for index in 1...Int(seconds * Double(rate)) {
            XCTAssertTrue(response.ingest(field, timestamp: Double(index) / Double(rate)))
        }
    }

    func testNoBaselineKeepsPupilsCentered() {
        var response = FieldResponse()
        XCTAssertTrue(response.ingest(background, timestamp: 0))
        XCTAssertTrue(response.ingest(.init(x: 100, y: -200, z: 300), timestamp: 1))
        XCTAssertNil(response.baseline)
        XCTAssertEqual(response.gazeX, 0)
        XCTAssertEqual(response.gazeY, 0)
    }

    func testStationaryBaselineIsCenteredAndDoesNotAdaptToHeldMagnet() {
        var response = centeredResponse(at: background)
        advance(&response, to: background)
        XCTAssertEqual(response.delta, .zero)
        XCTAssertEqual(response.gazeX, 0)
        XCTAssertEqual(response.gazeY, 0)

        for index in 121...720 {
            XCTAssertTrue(response.ingest(background + .init(x: 30, y: 0, z: 0),
                                          timestamp: Double(index) / 60))
        }
        XCTAssertEqual(response.baseline, background)
        XCTAssertGreaterThan(response.gazeX, 0.65, "A held field must not drift into the baseline.")
    }

    func testSmallJitterStaysInsideDeadzone() {
        var response = centeredResponse(at: background)
        for index in 1...180 {
            let sign = index.isMultiple(of: 2) ? 1.0 : -1.0
            let jitter = FieldVector(x: sign * 0.8, y: sign * 0.8, z: sign * 4)
            XCTAssertTrue(response.ingest(background + jitter, timestamp: Double(index) / 60))
            XCTAssertEqual(response.gazeX, 0)
            XCTAssertEqual(response.gazeY, 0, "Unselected Z noise must not move X/Y pupils.")
        }
    }

    func testDeadzoneBoundaryHasNoJump() {
        var atBoundary = centeredResponse()
        var justOutside = centeredResponse()
        advance(&atBoundary, to: .init(x: 1.5, y: 0, z: 0))
        advance(&justOutside, to: .init(x: 1.501, y: 0, z: 0))
        XCTAssertEqual(atBoundary.gazeX, 0)
        XCTAssertGreaterThan(justOutside.gazeX, 0)
        XCTAssertLessThan(justOutside.gazeX, 0.0001)
    }

    func testHugeFiniteDiagonalMovementRemainsInsideUnitEllipse() {
        var response = centeredResponse()
        for index in 1...360 {
            let sign = index < 180 ? 1.0 : -1.0
            XCTAssertTrue(response.ingest(.init(x: sign * 1e300, y: 1e300, z: -1e300),
                                          timestamp: Double(index) / 60))
            XCTAssertTrue(response.gazeX.isFinite && response.gazeY.isFinite)
            XCTAssertLessThanOrEqual(hypot(response.gazeX, response.gazeY), 1 + 1e-12)
        }
        XCTAssertLessThan(response.gazeX, -0.7)
        XCTAssertLessThan(response.gazeY, -0.7)
    }

    func testOppositeExtremeFiniteFieldsCannotPoisonRendering() {
        let limit = Double.greatestFiniteMagnitude
        var response = centeredResponse(at: .init(x: -limit, y: -limit, z: 0))
        // The implementation may reject an unrepresentable delta, but must never emit NaN.
        response.ingest(.init(x: limit, y: limit, z: 0), timestamp: 1.0 / 60)
        XCTAssertTrue(response.filtered?.isFinite ?? true, "Finite input arithmetic overflow must be contained.")
        XCTAssertTrue(response.delta.isFinite)
        XCTAssertTrue(response.gazeX.isFinite && response.gazeY.isFinite)
        XCTAssertLessThanOrEqual(hypot(response.gazeX, response.gazeY), 1 + 1e-12)
    }

    func testStepResponseIsSmoothMonotonicAndDoesNotOvershoot() {
        var response = centeredResponse()
        let field = FieldVector(x: 30, y: 0, z: 0)
        XCTAssertTrue(response.ingest(field, timestamp: 1.0 / 60))
        XCTAssertGreaterThan(response.gazeX, 0)
        XCTAssertLessThan(response.gazeX, 0.1, "A field step must not snap the pupil to its target.")
        var previous = response.gazeX
        for index in 2...240 {
            XCTAssertTrue(response.ingest(field, timestamp: Double(index) / 60))
            XCTAssertGreaterThanOrEqual(response.gazeX, previous)
            XCTAssertLessThanOrEqual(response.gazeX, 0.7125 + 1e-12)
            XCTAssertEqual(response.gazeY, 0)
            previous = response.gazeX
        }
        XCTAssertEqual(response.gazeX, 0.7125, accuracy: 1e-8)
    }

    func testSmoothingHasSimilarTimingAtThirtySixtyAndOneTwentyHertz() {
        let field = FieldVector(x: 30, y: -15, z: 0)
        var outputs: [(Double, Double)] = []
        for rate in [30, 60, 120] {
            var response = centeredResponse()
            advance(&response, to: field, seconds: 0.5, rate: rate)
            outputs.append((response.gazeX, response.gazeY))
        }
        for output in outputs.dropFirst() {
            XCTAssertEqual(output.0, outputs[0].0, accuracy: 0.015)
            XCTAssertEqual(output.1, outputs[0].1, accuracy: 0.015)
        }
    }

    func testAxisPairsAndIndependentInversionsUseExpectedScreenDirections() {
        let field = FieldVector(x: 12, y: -20, z: 30)
        for pair in AxisPair.allCases {
            var normal = centeredResponse()
            normal.axisPair = pair
            advance(&normal, to: field)
            XCTAssertEqual(normal.gazeX > 0, pair != .yz)
            XCTAssertEqual(normal.gazeY > 0, pair == .xy)
            for invertX in [false, true] {
                for invertY in [false, true] {
                    var inverted = centeredResponse()
                    inverted.axisPair = pair
                    inverted.invertX = invertX
                    inverted.invertY = invertY
                    advance(&inverted, to: field)
                    XCTAssertEqual(inverted.gazeX, normal.gazeX * (invertX ? -1 : 1), accuracy: 1e-12)
                    XCTAssertEqual(inverted.gazeY, normal.gazeY * (invertY ? -1 : 1), accuracy: 1e-12)
                }
            }
        }
    }

    func testSensitivityIncreasesResponseWithoutChangingDirectionOrBounds() {
        let field = FieldVector(x: 8, y: -6, z: 0)
        var low = centeredResponse()
        var high = centeredResponse()
        low.sensitivity = 0.5
        high.sensitivity = 2
        advance(&low, to: field)
        advance(&high, to: field)
        XCTAssertGreaterThan(high.gazeX, low.gazeX)
        XCTAssertGreaterThan(high.gazeY, low.gazeY)
        XCTAssertEqual(low.gazeY / low.gazeX, high.gazeY / high.gazeX, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(hypot(high.gazeX, high.gazeY), 1)
    }

    func testNonfiniteDuplicateAndBackwardSamplesAreRejectedWithoutChangingState() {
        var response = centeredResponse(at: background)
        XCTAssertTrue(response.ingest(.init(x: 40, y: 10, z: 30), timestamp: 1))
        let original = response
        let badFields = [FieldVector(x: .nan, y: 0, z: 0),
                         FieldVector(x: 0, y: .infinity, z: 0),
                         FieldVector(x: 0, y: 0, z: -.infinity)]
        for field in badFields {
            XCTAssertFalse(response.ingest(field, timestamp: 2))
        }
        for time in [1, 0.5, Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(response.ingest(background, timestamp: time))
        }
        XCTAssertEqual(response.filtered, original.filtered)
        XCTAssertEqual(response.baseline, original.baseline)
        XCTAssertEqual(response.delta, original.delta)
        XCTAssertEqual(response.gazeX, original.gazeX)
        XCTAssertEqual(response.gazeY, original.gazeY)
        XCTAssertTrue(response.ingest(background, timestamp: 2), "Rejected samples must not advance the clock.")
    }

    func testRebaselineClearsGazeAndFilterHistory() {
        var response = centeredResponse()
        advance(&response, to: .init(x: 40, y: -20, z: 10))
        XCTAssertGreaterThan(abs(response.gazeX), 0.5)
        response.setBaseline(background)
        XCTAssertEqual(response.baseline, background)
        XCTAssertEqual(response.filtered, background)
        XCTAssertEqual(response.delta, .zero)
        XCTAssertEqual(response.gazeX, 0)
        XCTAssertEqual(response.gazeY, 0)
        XCTAssertTrue(response.ingest(background, timestamp: 2.1))
        XCTAssertEqual(response.gazeX, 0)
        XCTAssertEqual(response.gazeY, 0)
    }

    func testFieldChangeIsVectorDifferenceNotDifferenceOfMagnitudes() {
        var response = centeredResponse(at: .init(x: 30, y: 0, z: 0))
        advance(&response, to: .init(x: 0, y: 30, z: 0), seconds: 3)
        XCTAssertEqual(response.delta.magnitude, sqrt(1800), accuracy: 1e-8)
        XCTAssertGreaterThan(response.delta.magnitude, 40)
    }
}

final class BaselineCaptureTests: XCTestCase {
    func testStationaryOneSecondCaptureAcceptsMean() {
        var capture = BaselineCapture()
        let field = FieldVector(x: 23, y: -11, z: 38)
        for index in 0..<30 {
            XCTAssertEqual(capture.ingest(field, timestamp: Double(index) / 30), .collecting)
        }
        guard case let .accepted(mean) = capture.ingest(field, timestamp: 1) else {
            return XCTFail("A stationary capture should be accepted after one second.")
        }
        XCTAssertEqual(mean.x, field.x, accuracy: 1e-12)
        XCTAssertEqual(mean.y, field.y, accuracy: 1e-12)
        XCTAssertEqual(mean.z, field.z, accuracy: 1e-12)
        XCTAssertEqual(capture.progress, 1)
    }

    func testUnstableFieldIsRejected() {
        var capture = BaselineCapture()
        var result: BaselineCapture.Result = .collecting
        for index in 0...30 {
            let field = FieldVector(x: index.isMultiple(of: 2) ? 10 : -10, y: 0, z: 0)
            result = capture.ingest(field, timestamp: Double(index) / 30)
        }
        XCTAssertEqual(result, .unstable)
    }

    func testCaptureRequiresBothElapsedTimeAndEnoughSamples() {
        var capture = BaselineCapture()
        XCTAssertEqual(capture.ingest(.zero, timestamp: 0), .collecting)
        XCTAssertEqual(capture.ingest(.zero, timestamp: 1), .collecting)
        for index in 1...17 {
            XCTAssertEqual(capture.ingest(.zero, timestamp: 1 + Double(index) / 100), .collecting)
        }
        XCTAssertEqual(capture.ingest(.zero, timestamp: 1.18), .accepted(.zero))
    }

    func testCaptureIgnoresMalformedAndOutOfOrderSamples() {
        var capture = BaselineCapture()
        XCTAssertEqual(capture.ingest(.zero, timestamp: 0), .collecting)
        XCTAssertEqual(capture.ingest(.zero, timestamp: 0.1), .collecting)
        XCTAssertEqual(capture.ingest(.init(x: .nan, y: 0, z: 0), timestamp: 10), .collecting)
        XCTAssertEqual(capture.ingest(.zero, timestamp: .infinity), .collecting)
        XCTAssertEqual(capture.ingest(.init(x: 100, y: 100, z: 100), timestamp: 0.1), .collecting)
        XCTAssertEqual(capture.ingest(.init(x: 100, y: 100, z: 100), timestamp: 0.05), .collecting)
        XCTAssertEqual(capture.progress, 0.1, accuracy: 1e-12)
        for index in 2..<20 {
            XCTAssertEqual(capture.ingest(.zero, timestamp: Double(index) / 20), .collecting)
        }
        XCTAssertEqual(capture.ingest(.zero, timestamp: 1), .accepted(.zero))
    }
}
