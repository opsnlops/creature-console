import Foundation

/// Response body for `GET /api/v1/animation/dialog/script`. Items are sorted
/// newest-first by `updated_at`.
public struct DialogScriptListDTO: Codable {

    public var count: Int32
    public var items: [DialogScript]

}
