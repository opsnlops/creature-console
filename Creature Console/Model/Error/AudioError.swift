//
//  AudioError.swift
//  Creature Console
//
//  Created by April White on 6/10/23.
//

import Foundation

enum AudioError : Error {
    case fileNotFound(String)
    case noAccess(String)
    case systemError(String)
}
