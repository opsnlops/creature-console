import Foundation

public struct ServerLogItem: Codable {

    public var timestamp: Date
    public var level: String
    public var message: String
    public var logger_name: String
    public var thread_id: UInt32

}
