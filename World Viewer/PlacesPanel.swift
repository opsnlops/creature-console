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

/// A place April taught the birds, as the world pinned it from her phone (#248): read from its
/// `place.geo`.
struct TaughtPlace: Equatable, Identifiable, Sendable {
    var id: EntityID
    var latitude: Double
    var longitude: Double
    /// How far the place reaches, in meters.
    var radius: Double
    /// How many times her phone was there when she said so.
    var fixes: Int
    /// The bird that kept her word last: "Beaky".
    var teacher: String
    var since: Date

    var name: String { FactPageSections.name(of: id) }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Every taught place the world holds, by name. The point is GeoJSON: longitude first.
    static func all(in facts: [Fact]) -> [TaughtPlace] {
        facts.compactMap { fact -> TaughtPlace? in
            guard fact.predicate == WorldFacts.placeGeo, case .object(let fields) = fact.value,
                case .array(let point)? = fields["coordinates"], point.count == 2,
                case .number(let longitude) = point[0], case .number(let latitude) = point[1],
                case .number(let radius)? = fields["radius_m"]
            else { return nil }
            var fixes = 1
            if case .number(let count)? = fields["fixes"] { fixes = Int(count) }
            var teacher = ""
            if case .string(let source)? = fields["taught_by"] {
                teacher = source.split(separator: ":").last.map { $0.capitalized } ?? source
            }
            return TaughtPlace(
                id: fact.subjectID, latitude: latitude, longitude: longitude, radius: radius,
                fixes: fixes, teacher: teacher, since: fact.validFrom)
        }.sorted { $0.name < $1.name }
    }
}

/// Where April is, as the world knows it (#248): her phone's fix on a map, how sure it is, and
/// how old, and the places she taught the birds, each as far as it reaches. The world's alone -
/// shown to April here, and never to a bird.
struct PlacesPanel: View {
    let store: WorldStore
    @State private var camera: MapCameraPosition = .automatic

    private var fix: PlaceFix? { PlaceFix.april(in: store.facts) }
    private var places: [TaughtPlace] { TaughtPlace.all(in: store.facts) }

    var body: some View {
        if fix != nil || !places.isEmpty {
            Map(position: $camera) {
                ForEach(places) { place in
                    MapCircle(center: place.coordinate, radius: place.radius)
                        .foregroundStyle(.teal.opacity(0.15))
                        .stroke(.teal, lineWidth: 1)
                    Marker(place.name, systemImage: "mappin", coordinate: place.coordinate)
                        .tint(.teal)
                }
                if let fix {
                    if let accuracy = fix.accuracy {
                        MapCircle(center: fix.coordinate, radius: accuracy)
                            .foregroundStyle(.purple.opacity(0.15))
                            .stroke(.purple, lineWidth: 1)
                    }
                    Marker("April", systemImage: "hare.fill", coordinate: fix.coordinate)
                        .tint(.purple)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .overlay(alignment: .topLeading) {
                if let fix {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        if let accuracy = fix.accuracy {
                            Text("within \(Int(accuracy.rounded())) m ·")
                        }
                        Text("\(fix.since, style: .relative) ago")
                    }
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)
                    .padding(12)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if !places.isEmpty {
                    TaughtPlacesList(places: places).padding(12)
                }
            }
            .onChange(of: fix) { camera = .automatic }
            .onChange(of: places) { camera = .automatic }
        } else {
            ContentUnavailableView(
                "No Fix From April's Phone", systemImage: "location.slash",
                description: Text(
                    "The house tells the world where her phone is when it has a GPS fix, and the world holds one for half an hour. A place appears here once she tells a bird she is there."
                ))
        }
    }
}

/// The taught places, with who taught each last, when, and how often her phone was there.
private struct TaughtPlacesList: View {
    let places: [TaughtPlace]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(places) { place in
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill").foregroundStyle(.teal)
                    Text(place.name).bold()
                    Text(
                        "· \(Int(place.radius.rounded())) m · \(place.fixes) \(place.fixes == 1 ? "fix" : "fixes")"
                    )
                    if !place.teacher.isEmpty {
                        Text("· taught by \(place.teacher),")
                    }
                    Text("\(place.since, style: .relative) ago")
                }
                .font(.callout)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
    }
}
