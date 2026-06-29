import Foundation

/**
 These are various types used in the system
 */

public typealias AnimationIdentifier = String
public typealias CreatureIdentifier = String
public typealias PlaylistIdentifier = String
public typealias SoundIdentifier = String
public typealias UniverseIdentifier = Int
public typealias DmxFixtureIdentifier = String

/// A Dynamixel servo's ID on its bus (the `dxl_id` reported by the server).
public typealias DynamixelIdentifier = Int
public typealias FixturePatternIdentifier = String

/// Dialog scripts use real `UUID`s (not the legacy `String` OID-era identifiers).
public typealias DialogScriptIdentifier = UUID
/// One specific cached ElevenLabs dialog generation (take).
public typealias DialogGenerationIdentifier = UUID
/// A storyboard (HyperCard-style card of programmable tiles for live performance).
public typealias StoryboardIdentifier = UUID

public typealias FrameDataIndentifier = String
public typealias TrackIdentifier = UUID

public typealias EncodedFrameData = String
