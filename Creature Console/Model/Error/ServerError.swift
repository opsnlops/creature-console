//
//  ServerError.swift
//  Creature Console
//
//  Created by April White on 6/10/23.
//

import Foundation

enum ServerError : Error {
    case communicationError(String)
    case dataFormatError(String)
    case otherError(String)
    case databaseError(String)
    case notFound(String)
}
