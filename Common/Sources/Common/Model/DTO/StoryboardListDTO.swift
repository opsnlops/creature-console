import Foundation

/// Response body for `GET /api/v1/storyboard`. Items are sorted newest-first by `updated_at`.
public struct StoryboardListDTO: Codable {

    public var count: Int32
    public var items: [Storyboard]

}
