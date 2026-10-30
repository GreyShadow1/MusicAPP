import XCTest
@testable import FLACPlayer

final class EqualizerTests: XCTestCase {
    func testEveryPresetHasOneGainPerBand() {
        for preset in EqualizerSettings.presets {
            XCTAssertEqual(preset.gains.count, EqualizerSettings.frequencies.count, preset.name)
        }
    }

    func testDisabledByDefaultWithoutGain() {
        let settings = EqualizerSettings()
        XCTAssertFalse(settings.isEnabled)
        XCTAssertEqual(settings.headroom, 0)
    }

    func testHeadroomCompensatesLargestBoost() {
        var settings = EqualizerSettings()
        settings.isEnabled = true
        settings.apply(EqualizerSettings.presets[1])
        XCTAssertEqual(settings.headroom, -6)
    }

    func testManualChangeClearsPresetAndIsClamped() {
        var settings = EqualizerSettings()
        settings.setGain(99, band: 2)
        XCTAssertNil(settings.presetName)
        XCTAssertEqual(settings.gains[2], EqualizerSettings.maxGain)
    }

    func testCodableRoundTrip() throws {
        var settings = EqualizerSettings()
        settings.isEnabled = true
        settings.apply(EqualizerSettings.presets[2])
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(EqualizerSettings.self, from: data), settings)
    }
}
