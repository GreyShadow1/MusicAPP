import AVFoundation
import XCTest
@testable import FLACPlayer

final class FLACDecoderTests: XCTestCase {
    private func decodeAll(_ decoder: FLACDecoder) throws -> [[Float]] {
        let info = decoder.info
        let format = try XCTUnwrap(AVAudioFormat(
            standardFormatWithSampleRate: Double(info.sampleRate),
            channels: AVAudioChannelCount(info.channels)
        ))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
        var channels = [[Float]](repeating: [], count: info.channels)
        while try decoder.read(into: buffer) > 0 {
            let data = try XCTUnwrap(buffer.floatChannelData)
            for channel in 0..<info.channels {
                channels[channel].append(contentsOf: UnsafeBufferPointer(start: data[channel], count: Int(buffer.frameLength)))
            }
        }
        return channels
    }

    func testReads16BitFormat() throws {
        let decoder = try FLACDecoder(url: Fixture.tagged16.url)
        XCTAssertEqual(decoder.info, FLACStreamInfo(sampleRate: 44100, channels: 2, bitDepth: 16, totalFrames: 22050))
        XCTAssertEqual(decoder.info.duration, 0.5, accuracy: 0.001)
    }

    func testReads24BitHighResolutionFormat() throws {
        let decoder = try FLACDecoder(url: Fixture.tagged24.url)
        XCTAssertEqual(decoder.info, FLACStreamInfo(sampleRate: 96000, channels: 2, bitDepth: 24, totalFrames: 24000))
    }

    func testDecodesEveryFrameWithoutErrors() throws {
        let decoder = try FLACDecoder(url: Fixture.tagged24.url)
        let channels = try decodeAll(decoder)
        XCTAssertEqual(channels.map(\.count), [24000, 24000])
        XCTAssertEqual(decoder.errorCount, 0)
        XCTAssertTrue(channels[0].contains { $0 != 0 }, "L'audio decodificato non deve essere silenzio")
    }

    func testSampleConversionIsLossless() throws {
        // Moltiplicando per 2^(bit-1) ogni campione deve tornare un intero esatto.
        let decoder = try FLACDecoder(url: Fixture.tagged24.url)
        for sample in try decodeAll(decoder)[0] {
            let integer = Double(sample) * 8_388_608
            XCTAssertEqual(integer, integer.rounded())
        }
    }

    func testIntegrityMatchesEmbeddedMD5() throws {
        XCTAssertEqual(try FLACDecoder.verify(url: Fixture.tagged16.url), 22050)
        XCTAssertEqual(try FLACDecoder.verify(url: Fixture.tagged24.url), 24000)
    }

    func testSeekReturnsSameSamplesAsLinearRead() throws {
        let reference = try decodeAll(FLACDecoder(url: Fixture.tagged16.url))

        let decoder = try FLACDecoder(url: Fixture.tagged16.url)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512))

        for target in [15000, 3, 11025, 21000] {
            try decoder.seek(toFrame: Int64(target))
            let count = try decoder.read(into: buffer)
            let data = try XCTUnwrap(buffer.floatChannelData)
            XCTAssertEqual(count, 512)
            XCTAssertEqual(
                Array(UnsafeBufferPointer(start: data[0], count: count)),
                Array(reference[0][target..<(target + count)]),
                "Seek alla posizione \(target)"
            )
        }
    }

    func testSeekPastEndFailsAndDecoderStaysUsable() throws {
        let decoder = try FLACDecoder(url: Fixture.tagged16.url)
        XCTAssertThrowsError(try decoder.seek(toFrame: 1_000_000))
        XCTAssertNoThrow(try decoder.seek(toFrame: 100))

        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64))
        XCTAssertEqual(try decoder.read(into: buffer), 64)
    }

    func testMissingFileReportsNotReadable() {
        let url = URL(fileURLWithPath: "/percorso/inesistente.flac")
        XCTAssertThrowsError(try FLACDecoder(url: url)) { error in
            XCTAssertEqual(error as? FLACError, .fileNotReadable)
        }
    }

    func testInvalidFileIsRejected() {
        XCTAssertThrowsError(try FLACDecoder(url: Fixture.notFLAC.url)) { error in
            XCTAssertEqual(error as? FLACError, .notFLAC)
        }
    }

    func testDamagedFileDoesNotStopDecodingButIsDetected() throws {
        let decoder = try FLACDecoder(url: Fixture.corrupt.url)
        _ = try decodeAll(decoder)
        XCTAssertGreaterThan(decoder.errorCount, 0)
        XCTAssertThrowsError(try FLACDecoder.verify(url: Fixture.corrupt.url))
    }
}
