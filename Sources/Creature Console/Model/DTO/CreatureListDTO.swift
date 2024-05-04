
import Foundation


/**
 A Data Transfer Object for the Creature List
 */
struct CreatureListDTO : Decodable {

    var count: Int32
    var items: [Creature]

}
