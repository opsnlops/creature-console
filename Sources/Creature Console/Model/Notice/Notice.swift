
import Foundation

/**
 A notice from the server that we should pay attention to
 */
struct Notice: Decodable {

    var timestamp: Date
    var message: String
}
