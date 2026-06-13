import Testing

@testable import creature_cli

@Suite("MongoServerAddress tests")
struct MongoServerAddressTests {

    // MARK: - Bare hostnames and IPs

    @Test("bare hostname gets default port and database")
    func bareHostname() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mainstage.local", database: "creature_server")
        #expect(uri == "mongodb://mainstage.local:27017/creature_server")
    }

    @Test("bare IPv4 address gets default port and database")
    func bareIPv4() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "10.3.2.11", database: "creature_server")
        #expect(uri == "mongodb://10.3.2.11:27017/creature_server")
    }

    @Test("host with explicit port is preserved")
    func hostWithPort() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "travel.local:27018", database: "creature_server")
        #expect(uri == "mongodb://travel.local:27018/creature_server")
    }

    @Test("surrounding whitespace is trimmed")
    func trimsWhitespace() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "  mainstage.local  ", database: "creature_server")
        #expect(uri == "mongodb://mainstage.local:27017/creature_server")
    }

    // MARK: - IPv6

    @Test("bare IPv6 literal is bracketed and gets default port")
    func bareIPv6() throws {
        let uri = try MongoServerAddress.connectionURI(for: "::1", database: "creature_server")
        #expect(uri == "mongodb://[::1]:27017/creature_server")
    }

    @Test("bracketed IPv6 without port gets default port")
    func bracketedIPv6NoPort() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "[fd00::5]", database: "creature_server")
        #expect(uri == "mongodb://[fd00::5]:27017/creature_server")
    }

    @Test("bracketed IPv6 with port is preserved")
    func bracketedIPv6WithPort() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "[fd00::5]:27018", database: "creature_server")
        #expect(uri == "mongodb://[fd00::5]:27018/creature_server")
    }

    // MARK: - Full URIs

    @Test("full URI without a database gets the database appended")
    func fullURIWithoutDatabase() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb://mainstage.local:27017", database: "creature_server")
        #expect(uri == "mongodb://mainstage.local:27017/creature_server")
    }

    @Test("full URI with trailing slash gets the database appended")
    func fullURITrailingSlash() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb://mainstage.local:27017/", database: "creature_server")
        #expect(uri == "mongodb://mainstage.local:27017/creature_server")
    }

    @Test("full URI with a database is passed through unchanged")
    func fullURIWithDatabase() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb://mainstage.local:27017/other_db", database: "creature_server")
        #expect(uri == "mongodb://mainstage.local:27017/other_db")
    }

    @Test("query string is preserved when appending the database")
    func fullURIWithQueryString() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb://user:pass@mainstage.local:27017?authSource=admin",
            database: "creature_server")
        #expect(uri == "mongodb://user:pass@mainstage.local:27017/creature_server?authSource=admin")
    }

    @Test("mongodb+srv URIs are accepted")
    func srvURI() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb+srv://cluster.example.com", database: "creature_server")
        #expect(uri == "mongodb+srv://cluster.example.com/creature_server")
    }

    @Test("multi-host URIs get the database appended")
    func multiHostURI() throws {
        let uri = try MongoServerAddress.connectionURI(
            for: "mongodb://host1:27017,host2:27017", database: "creature_server")
        #expect(uri == "mongodb://host1:27017,host2:27017/creature_server")
    }

    // MARK: - Errors

    @Test("empty address throws")
    func emptyAddress() {
        #expect(throws: MongoServerAddress.AddressError.emptyAddress) {
            try MongoServerAddress.connectionURI(for: "   ", database: "creature_server")
        }
    }

    @Test("non-mongodb scheme throws")
    func unsupportedScheme() {
        #expect(throws: MongoServerAddress.AddressError.unsupportedScheme("https")) {
            try MongoServerAddress.connectionURI(
                for: "https://mainstage.local", database: "creature_server")
        }
    }

    @Test("non-numeric port throws")
    func nonNumericPort() {
        #expect(throws: MongoServerAddress.AddressError.invalidPort("abc")) {
            try MongoServerAddress.connectionURI(
                for: "mainstage.local:abc", database: "creature_server")
        }
    }

    @Test("out-of-range port throws")
    func outOfRangePort() {
        #expect(throws: MongoServerAddress.AddressError.invalidPort("99999")) {
            try MongoServerAddress.connectionURI(
                for: "mainstage.local:99999", database: "creature_server")
        }
    }

    @Test("trailing colon with no port throws")
    func trailingColon() {
        #expect(throws: MongoServerAddress.AddressError.invalidAddress("mainstage.local:")) {
            try MongoServerAddress.connectionURI(
                for: "mainstage.local:", database: "creature_server")
        }
    }

    @Test("unclosed IPv6 bracket throws")
    func unclosedBracket() {
        #expect(throws: MongoServerAddress.AddressError.invalidAddress("[fd00::5")) {
            try MongoServerAddress.connectionURI(for: "[fd00::5", database: "creature_server")
        }
    }
}
