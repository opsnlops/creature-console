import Foundation

/// Response body for `GET /api/v1/stage`. Items are sorted newest-first by `updated_at`.
public struct StageListDTO: Codable {

    public var count: Int32
    public var items: [Stage]

}
