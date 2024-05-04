
import Foundation


/**
 The generic Status DTO that we use on the server
 */
struct StatusDTO : Decodable {

    // Status like OK, ERROR
    var status: String

    // HTTP Status Code
    var code: UInt16

    // Message
    var message: String

}
