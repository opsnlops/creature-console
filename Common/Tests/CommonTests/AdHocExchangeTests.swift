import Foundation
import Testing

@testable import Common

@Suite("AdHocExchange tests")
struct AdHocExchangeTests {

    static let readyJSON = """
        {
            "session_id": "0b8f3f1e-8a70-4b8e-9d1a-2f5c6e7d8a9b",
            "creature_id": "beaky-1",
            "creature_name": "Beaky",
            "status": "ready",
            "title": "Beaky - 20260820143012 - somebody-is-at-the-door",
            "transcript": "Somebody is at the door!\\nI wonder who it is.",
            "duration_ms": 23417,
            "created_at": "2026-08-20T14:30:12Z",
            "finished_at": "2026-08-20T14:30:36Z",
            "parts": [
                {
                    "index": 1,
                    "animation_id": "anim-1",
                    "text": "Somebody is at the door!",
                    "duration_ms": 11200
                },
                {
                    "index": 2,
                    "animation_id": "anim-2",
                    "text": "I wonder who it is.",
                    "duration_ms": 12217
                }
            ]
        }
        """

    @Test("decodes a finished exchange from server JSON")
    func decodesFinishedExchange() throws {
        let exchange = try JSONDecoder().decode(
            AdHocExchange.self, from: Data(Self.readyJSON.utf8))

        #expect(exchange.sessionId == "0b8f3f1e-8a70-4b8e-9d1a-2f5c6e7d8a9b")
        #expect(exchange.id == exchange.sessionId)
        #expect(exchange.creatureId == "beaky-1")
        #expect(exchange.creatureName == "Beaky")
        #expect(exchange.status == .ready)
        #expect(exchange.title == "Beaky - 20260820143012 - somebody-is-at-the-door")
        #expect(exchange.durationMs == 23417)
        #expect(exchange.parts.count == 2)
        #expect(exchange.parts[0].index == 1)
        #expect(exchange.parts[0].id == 1)
        #expect(exchange.parts[1].text == "I wonder who it is.")

        let created = try #require(exchange.createdAt)
        let finished = try #require(exchange.finishedAt)
        #expect(finished.timeIntervalSince(created) == 24)
    }

    @Test("decodes a streaming exchange with the finished-only fields absent")
    func decodesStreamingExchange() throws {
        let json = """
            {
                "session_id": "abc",
                "creature_id": "beaky-1",
                "creature_name": "Beaky",
                "status": "streaming",
                "title": "",
                "transcript": "",
                "duration_ms": 0,
                "created_at": "2026-08-20T14:30:12Z",
                "parts": []
            }
            """
        let exchange = try JSONDecoder().decode(AdHocExchange.self, from: Data(json.utf8))

        #expect(exchange.status == .streaming)
        #expect(exchange.finishedAt == nil)
        #expect(exchange.title.isEmpty)
        #expect(exchange.transcript.isEmpty)
        #expect(exchange.durationMs == 0)
        #expect(exchange.parts.isEmpty)
    }

    @Test("accepts fractional-seconds timestamps too")
    func acceptsFractionalSecondTimestamps() throws {
        let json = """
            {
                "session_id": "abc",
                "creature_id": "beaky-1",
                "status": "ready",
                "created_at": "2026-08-20T14:30:12.345Z"
            }
            """
        let exchange = try JSONDecoder().decode(AdHocExchange.self, from: Data(json.utf8))
        let created = try #require(exchange.createdAt)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let expected = try #require(formatter.date(from: "2026-08-20T14:30:12.345Z"))
        #expect(abs(created.timeIntervalSince(expected)) < 0.001)
    }

    @Test("unknown status collapses to .unknown instead of failing")
    func unknownStatusIsLenient() throws {
        let json = """
            {
                "session_id": "abc",
                "creature_id": "beaky-1",
                "status": "archived"
            }
            """
        let exchange = try JSONDecoder().decode(AdHocExchange.self, from: Data(json.utf8))
        #expect(exchange.status == .unknown)
    }

    @Test("round-trips through encode and decode")
    func roundTrips() throws {
        let original = try JSONDecoder().decode(
            AdHocExchange.self, from: Data(Self.readyJSON.utf8))
        let reencoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AdHocExchange.self, from: reencoded)
        #expect(decoded == original)
    }

    @Test("list DTO decodes count and items")
    func listDTODecodes() throws {
        let json = """
            {
                "count": 1,
                "items": [\(Self.readyJSON)]
            }
            """
        let list = try JSONDecoder().decode(AdHocExchangeListDTO.self, from: Data(json.utf8))
        #expect(list.count == 1)
        #expect(list.items.first?.creatureName == "Beaky")
    }
}

@Suite("ExchangeAudioFormat tests")
struct ExchangeAudioFormatTests {

    @Test("route filenames match the server's audio routes")
    func routeFilenames() {
        #expect(ExchangeAudioFormat.mp3.routeFilename == "audio.mp3")
        #expect(ExchangeAudioFormat.ogg.routeFilename == "audio.ogg")
        #expect(ExchangeAudioFormat.wav.routeFilename == "audio.wav")
    }

    @Test("fallback filename combines session id and extension")
    func fallbackFilename() {
        #expect(
            ExchangeAudioFormat.mp3.filename(forSessionId: "abc-123") == "abc-123.mp3")
        #expect(
            ExchangeAudioFormat.wav.filename(forSessionId: "abc-123") == "abc-123.wav")
    }
}

@Suite("CacheType decoding tests")
struct CacheTypeDecodingTests {

    private struct Envelope: Codable {
        let cacheType: CacheType

        enum CodingKeys: String, CodingKey {
            case cacheType = "cache_type"
        }
    }

    @Test("decodes the ad-hoc exchange list invalidation")
    func decodesExchangeListInvalidation() throws {
        let invalidation = try JSONDecoder().decode(
            CacheInvalidation.self,
            from: Data(#"{"cache_type": "ad-hoc-exchange-list"}"#.utf8))
        #expect(invalidation.cacheType == .adHocExchangeList)
    }

    @Test("unrecognized cache types collapse to .unknown instead of throwing")
    func unknownCacheTypeIsLenient() throws {
        let invalidation = try JSONDecoder().decode(
            CacheInvalidation.self,
            from: Data(#"{"cache_type": "some-future-cache"}"#.utf8))
        #expect(invalidation.cacheType == .unknown)
    }

    @Test("known cache types still decode to their cases")
    func knownCacheTypesDecode() throws {
        let invalidation = try JSONDecoder().decode(
            CacheInvalidation.self,
            from: Data(#"{"cache_type": "sound-list"}"#.utf8))
        #expect(invalidation.cacheType == .soundList)
    }
}
