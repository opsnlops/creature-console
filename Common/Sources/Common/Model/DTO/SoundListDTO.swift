
import Foundation


/**
 A Data Transfer Object for the Sound List
 */
public struct SoundListDTO : Decodable {

    public var count: Int32
    public var items: [Sound]

}
