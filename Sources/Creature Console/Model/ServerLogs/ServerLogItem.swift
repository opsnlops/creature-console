
import Foundation

struct ServerLogItem : Decodable {

    var timestamp: Date
    var level: String
    var message: String
    var logger_name: String
    var thread_id: UInt32

}
