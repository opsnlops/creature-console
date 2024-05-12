import Foundation

public struct DataHelper {

    /**
     Generates random bytes

     Can be used to generate MongoDB style OIDs.
     */
    public static func generateRandomData(byteCount: Int) -> Data {
        return Data((0..<byteCount).map { _ in UInt8.random(in: 0...UInt8.max) })
    }

    public static func dataToHexString(data: Data) -> String {
        return data.map { String(format: "%02x", $0) }.joined()
    }

    /**
     Generate a 24 character String that looks lika a MongoDB OID. The server handles the conversion from this format to an actual OID, making things easier on us on the front end.
     */
    public static func generateRandomId() -> String {
        let randomData = DataHelper.generateRandomData(byteCount: 12)
        return DataHelper.dataToHexString(data: randomData)
    }

    public static func stringToOidData(oid: String) -> Data? {
        var data = Data(capacity: oid.count / 2)
        var index = oid.startIndex
        while index < oid.endIndex {
            let nextIndex = oid.index(index, offsetBy: 2)
            if let b = UInt8(oid[index..<nextIndex], radix: 16) {
                data.append(b)
            } else {
                return nil  // Return nil if the conversion fails
            }
            index = nextIndex
        }
        return data
    }
}
