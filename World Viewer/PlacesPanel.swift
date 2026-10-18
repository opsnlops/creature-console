import MapKit
import SwiftUI
import WorldCore

/// April's phone's fix, read from the world's facts (#248). Kept out of the view, so it is no
/// actor's and tests can call it from anywhere.
struct PlaceFix: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// How sure, in meters; nil when the phone did not say.
    var accuracy: Double?
    var since: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static let april = try! EntityID(validating: "person:april")

    /// The current `location.gps` on April, if the world holds one.
    static func april(in facts: [Fact]) -> PlaceFix? {
        guard
            let fact = facts.last(where: {
                $0.subjectID == april && $0.predicate == WorldFacts.locationGPS
            }),
            case .object(let fields) = fact.value,
            case .number(let latitude)? = fields["latitude"],
            case .number(let longitude)? = fields["longitude"]
        else { return nil }
        var accuracy: Double?
        if case .number(let meters)? = fields["accuracy_m"] { accuracy = meters }
        return PlaceFix(
            latitude: latitude, longitude: longitude, accuracy: accuracy, since: fact.validFrom)
    }
}

/// Where April is, as the world knows it (#248): her phone's fix on a map, how sure it is, and
/// how old. The places the birds learn from her join it next. The world's alone - shown to
/// April here, and never to a bird.
struct PlacesPanel: View {
    let store: WorldStore
    @State private var camera: MapCameraPosition = .automatic

    private var fix: PlaceFix? { PlaceFix.april(in: store.facts) }

    var body: some View {
        if let fix {
            Map(position: $camera) {
                if let accuracy = fix.accuracy {
                    MapCircle(center: fix.coordinate, radius: accuracy)
                        .foregroundStyle(.purple.opacity(0.15))
                        .stroke(.purple, lineWidth: 1)
                }
                Marker("April", systemImage: "hare.fill", coordinate: fix.coordinate)
                    .tint(.purple)
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill")
                    if let accuracy = fix.accuracy {
                        Text("within \(Int(accuracy.rounded())) m ·")
                    }
                    Text(fix.since, style: .relative) + Text(" ago")
                }
                .font(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(12)
            }
            .onChange(of: fix) { camera = .automatic }
        } else {
            ContentUnavailableView(
                "No Fix From April's Phone", systemImage: "location.slash",
                description: Text(
                    "The house tells the world where her phone is when it has a GPS fix, and the world holds one for half an hour."
                ))
        }
    }
}
