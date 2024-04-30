
import Foundation
import OSLog

struct ServerLogItem : Codable {

    var priority: Int32
    var level: String
    var message: String

}
