//
//  Playlist.swift
//  Creature Console
//
//  Created by April White on 8/19/23.
//

import Foundation

class Playlist {
    
    var id: Data
    var name: String
    var items: [PlaylistItem]
    
    init(id: Data, name: String, items: [PlaylistItem]) {
        self.id = id
        self.name = name
        self.items = items
    }
    
    init(fromServerPlaylist: Server_Playlist) {
        self.id = fromServerPlaylist.id.id
        self.name = fromServerPlaylist.name
        self.items = []
        
        for item in fromServerPlaylist.items {
            let thisItem = PlaylistItem(animationId: item.animationID.id, weight: item.weight)
            items.append(thisItem)
        }
    }
}



extension Playlist {
    static func mock() -> Playlist {
        
        let id = Data(DataHelper.generateRandomData(byteCount: 12))
        let name = "Mock Playlist"
        
        let items: [PlaylistItem] = [PlaylistItem.mock(), PlaylistItem.mock()]

        return Playlist(id: id, name: name, items: items)
    }
}
