
import Foundation

public class Playlist {

    var id: Data
    var name: String
    var items: [PlaylistItem]
    
    public init(id: Data, name: String, items: [PlaylistItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
}



extension Playlist {
    public static func mock() -> Playlist {
        
        let id = Data(DataHelper.generateRandomData(byteCount: 12))
        let name = "Mock Playlist"
        
        let items: [PlaylistItem] = [PlaylistItem.mock(), PlaylistItem.mock()]

        return Playlist(id: id, name: name, items: items)
    }
}
