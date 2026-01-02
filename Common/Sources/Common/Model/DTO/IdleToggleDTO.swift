import Foundation

public struct IdleToggleDTO: Codable {
  public let enabled: Bool

  public init(enabled: Bool) {
    self.enabled = enabled
  }
}
