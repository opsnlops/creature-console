import Foundation

/// A simple request to play a sound file on the server
public struct PlaySoundRequestDTO: Decodable, Encodable {

    public var file_name: String

}
