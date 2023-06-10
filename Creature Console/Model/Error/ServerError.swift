//
//  ServerError.swift
//  Creature Console
//
//  Created by April White on 6/10/23.
//

import Foundation

struct ServerError: LocalizedError, Identifiable {
    let id = UUID()
    let errorDescription: String?

    init(_ description: String) {
        self.errorDescription = description
    }
}
