//
//  PlaylistErrors.swift
//  Creature Console
//
//  Created by April White on 8/19/23.
//

import Foundation


enum PlaylistErrors : Error {
    case communicationError(String)
    case dataFormatError(String)
    case otherError(String)
    case databaseError(String)
    case notFound(String)
}
