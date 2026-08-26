#if os(macOS) || os(iOS) || os(tvOS)
    import Common
    import Foundation
    import Network

    /// Shared vocabulary for the two ways live audio packets reach the spatial pipeline:
    /// straight off the animatronic VLAN's multicast groups (macOS with a route to it), or
    /// through a `creature-cli network rtp-listen` relay over TCP (any network — and the only
    /// supported path on iOS and tvOS). Downstream of this
    /// type the pipeline neither knows nor cares which transport delivered a packet.
    enum SpatialPacketKind: Sendable {
        case rtp
        case rtcp
    }

    struct SpatialReceivedPacket: Sendable {
        let channel: Int
        let kind: SpatialPacketKind
        let data: Data
    }

    /// Where `SpatialLiveAudioSource` should get its packets.
    enum SpatialLiveTransport {
        #if os(macOS)
            /// Join the multicast groups directly on this interface. Requires a route to the
            /// animatronic VLAN.
            case multicast(NWInterface)
        #endif
        /// Connect to a `creature-cli network rtp-listen` relay.
        case relay(host: String, port: UInt16)
    }
#endif
