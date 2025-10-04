import Foundation
import Testing

@testable import Common

@Suite("DataHelper utility functions")
struct DataHelperTests {

    @Test("generateRandomData creates data of correct length")
    func generateRandomDataCreatesCorrectLength() {
        let lengths = [0, 1, 12, 100, 1000]

        for length in lengths {
            let data = DataHelper.generateRandomData(byteCount: length)
            #expect(data.count == length)
        }
    }

    @Test("generateRandomData creates different data each time")
    func generateRandomDataCreatesDifferentData() {
        let data1 = DataHelper.generateRandomData(byteCount: 12)
        let data2 = DataHelper.generateRandomData(byteCount: 12)

        // Extremely unlikely to be equal (1 in 2^96 chance)
        #expect(data1 != data2)
    }

    @Test("dataToHexString converts data correctly")
    func dataToHexStringConvertsCorrectly() {
        let testCases: [(Data, String)] = [
            (Data([0x00]), "00"),
            (Data([0xFF]), "ff"),
            (Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF]), "0123456789abcdef"),
            (Data([0xDE, 0xAD, 0xBE, 0xEF]), "deadbeef"),
            (Data(), ""),
        ]

        for (data, expectedHex) in testCases {
            let hex = DataHelper.dataToHexString(data: data)
            #expect(hex == expectedHex)
        }
    }

    @Test("generateRandomId creates 24 character hex string")
    func generateRandomIdCreates24CharString() {
        for _ in 0..<10 {
            let id = DataHelper.generateRandomId()

            #expect(id.count == 24)

            // Verify it's all hex characters
            let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")
            let idCharacters = CharacterSet(charactersIn: id)
            #expect(hexCharacters.isSuperset(of: idCharacters))
        }
    }

    @Test("generateRandomId creates unique IDs")
    func generateRandomIdCreatesUniqueIDs() {
        var ids = Set<String>()

        for _ in 0..<100 {
            let id = DataHelper.generateRandomId()
            #expect(!ids.contains(id), "Generated duplicate ID: \(id)")
            ids.insert(id)
        }

        #expect(ids.count == 100)
    }

    @Test("stringToOidData converts valid hex correctly")
    func stringToOidDataConvertsValidHex() {
        let testCases: [(String, Data)] = [
            ("00", Data([0x00])),
            ("ff", Data([0xFF])),
            ("0123456789abcdef", Data([0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF])),
            ("deadbeef", Data([0xDE, 0xAD, 0xBE, 0xEF])),
            ("", Data()),
        ]

        for (hexString, expectedData) in testCases {
            let data = DataHelper.stringToOidData(oid: hexString)
            #expect(data == expectedData)
        }
    }

    @Test("stringToOidData handles uppercase hex")
    func stringToOidDataHandlesUppercase() {
        let uppercase = "DEADBEEF"
        let data = DataHelper.stringToOidData(oid: uppercase)

        #expect(data == Data([0xDE, 0xAD, 0xBE, 0xEF]))
    }

    @Test("stringToOidData returns nil for invalid hex")
    func stringToOidDataReturnsNilForInvalid() {
        let invalidInputs = [
            "zz",  // Invalid hex characters (even length)
            "xyzt",  // Invalid hex characters (even length)
            "12gg",  // Mix of valid and invalid (even length)
            "    ",  // Spaces (even length)
        ]

        for invalid in invalidInputs {
            let data = DataHelper.stringToOidData(oid: invalid)
            #expect(data == nil, "Expected nil for invalid input: \(invalid)")
        }
    }

    @Test("stringToOidData handles odd-length strings")
    func stringToOidDataHandlesOddLength() {
        // Odd-length strings should return nil since hex strings need 2 chars per byte
        let oddLengthInputs = ["1", "123", "12345", "a", "abc"]

        for input in oddLengthInputs {
            let data = DataHelper.stringToOidData(oid: input)
            #expect(data == nil, "Expected nil for odd-length input: \(input)")
        }
    }

    @Test("round-trip conversion preserves data")
    func roundTripConversionPreservesData() {
        let originalData = DataHelper.generateRandomData(byteCount: 12)

        let hexString = DataHelper.dataToHexString(data: originalData)
        let reconstructedData = DataHelper.stringToOidData(oid: hexString)

        #expect(reconstructedData == originalData)
    }

    @Test("MongoDB-style ID format is correct")
    func mongoDBStyleIDFormatIsCorrect() {
        let id = DataHelper.generateRandomId()

        // Should be 24 characters (12 bytes * 2 hex chars per byte)
        #expect(id.count == 24)

        // Should be all lowercase hex
        let lowercaseHex = CharacterSet(charactersIn: "0123456789abcdef")
        let idChars = CharacterSet(charactersIn: id)
        #expect(lowercaseHex.isSuperset(of: idChars))

        // Should be convertible back to 12 bytes
        let data = DataHelper.stringToOidData(oid: id)
        #expect(data?.count == 12)
    }
}
