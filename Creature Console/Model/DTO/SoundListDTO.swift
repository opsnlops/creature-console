
import Foundation


/**
 A Data Transfer Object for the Sound List
 */
struct SoundListDTO : Decodable {

    var count: Int32
    var items: [Sound]

}
