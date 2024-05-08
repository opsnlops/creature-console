
import Foundation


/**
 A simple request to play a sound file on the server
 */
struct PlaySoundRequestDTO : Decodable, Encodable {

    var file_name: String

}
