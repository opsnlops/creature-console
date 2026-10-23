import CoreLocation
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

/// A place April taught the birds, as the world pinned it from her phone (#248), or where she
/// moved it on the map (#258): read from its `place.geo`.
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
    /// Who moved it by hand on this map, "April"; empty while it is where her phone was.
    var placer: String = ""
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
            if case .string(let source)? = fields["taught_by"] { teacher = who(source) }
            var placer = ""
            if case .string(let source)? = fields["placed_by"] { placer = who(source) }
            return TaughtPlace(
                id: fact.subjectID, latitude: latitude, longitude: longitude, radius: radius,
                fixes: fixes, teacher: teacher, placer: placer, since: fact.validFrom)
        }.sorted { $0.name < $1.name }
    }

    /// A source by its name: `mind:beaky` is "Beaky", `wizard:april` is "April".
    private static func who(_ source: String) -> String {
        source.split(separator: ":").last.map { $0.capitalized } ?? source
    }

    // MARK: - Moving it on the map (#258)

    /// Dragged from `start` to `end`: the whole place moves as far as the pointer did, so it
    /// does not jump to where the pin was grabbed.
    func moved(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> TaughtPlace {
        var place = self
        place.latitude += end.latitude - start.latitude
        place.longitude += end.longitude - start.longitude
        return place
    }

    /// Its edge dragged to `point`: it reaches that far, within the bounds the world holds it to.
    func reaching(_ point: CLLocationCoordinate2D) -> TaughtPlace {
        let meters = CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: point.latitude, longitude: point.longitude))
        var place = self
        place.radius = min(
            max(meters, PlacePlacement.reach.lowerBound), PlacePlacement.reach.upperBound)
        return place
    }

    /// Where the edge's handle sits: due east of the point, as far as the place reaches.
    var edge: CLLocationCoordinate2D {
        let metersPerDegree = 111_320 * cos(latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: latitude, longitude: longitude + radius / max(metersPerDegree, 1))
    }

    /// Where it is drawn now, as a Wizard's word to the world.
    func placement(by wizard: String) -> PlacePlacement {
        PlacePlacement(latitude: latitude, longitude: longitude, radius: radius, placedBy: wizard)
    }
}

/// Where April is, as the world knows it (#248): her phone's fix on a map, how sure it is, and
/// how old, and the places she taught the birds, each as far as it reaches. She moves a place
/// by dragging its pin, and sets how far it reaches by dragging the dot on its edge (#258). The
/// world's alone - shown to April here, and never to a bird.
struct PlacesPanel: View {
    let store: WorldStore
    @State private var camera: MapCameraPosition = .automatic
    /// Where the map is looking, for the handles drawn over it.
    @State private var looking = MapLooking()
    /// Places April is moving, drawn where her drag has them until the world's fact arrives.
    @State private var drafts: [EntityID: TaughtPlace] = [:]

    private var fix: PlaceFix? { PlaceFix.april(in: store.facts) }
    private var stored: [TaughtPlace] { TaughtPlace.all(in: store.facts) }
    private var places: [TaughtPlace] { stored.map { drafts[$0.id] ?? $0 } }

    var body: some View {
        if fix != nil || !stored.isEmpty {
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(places) { place in
                        MapCircle(center: place.coordinate, radius: place.radius)
                            .foregroundStyle(.teal.opacity(0.15))
                            .stroke(.teal, lineWidth: 1)
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
                .onMapCameraChange(frequency: .continuous) { looking.camera = $0.camera }
                .overlay {
                    PlaceHandles(
                        places: places, proxy: proxy, looking: looking,
                        dragged: { drafts[$0.id] = $0 }, dropped: keep)
                }
            }
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
            // Only a place added or taken away refits the map: one April just moved stays
            // where she is looking.
            .onChange(of: stored.map(\.id)) { camera = .automatic }
            // The world's fact for a moved place arrived: what it holds is what is drawn.
            .onChange(of: stored) { old, new in
                for place in new where !old.contains(place) {
                    drafts[place.id] = nil
                }
            }
        } else {
            ContentUnavailableView(
                "No Fix From April's Phone", systemImage: "location.slash",
                description: Text(
                    "The house tells the world where her phone is when it has a GPS fix, and the world holds one for half an hour. A place appears here once she tells a bird she is there."
                ))
        }
    }

    /// April let go of a place: ask the world to keep it there; a refusal puts it back.
    private func keep(_ id: EntityID) {
        guard let moved = drafts[id] else { return }
        Task {
            let kept = await store.move(moved)
            if !kept { drafts[id] = nil }
        }
    }
}

/// Where the map is looking. Only the handles read it, so a pan redraws them and not the map.
@MainActor @Observable
private final class MapLooking {
    var camera: MapCamera?
}

/// Each place's handles and name, drawn over the map rather than inside it (#258). Viewer 0.22.0
/// drew them as MapKit annotations: the dentist vanished beside the gym, and a drag on the gym's
/// pin moved nothing. MapKit hides annotations that crowd each other, and handles the events of
/// the views it hosts itself. Over the map, each is placed where its coordinate falls and follows
/// the camera.
private struct PlaceHandles: View {
    let places: [TaughtPlace]
    let proxy: MapProxy
    let looking: MapLooking
    /// The place as a drag has it now.
    let dragged: (TaughtPlace) -> Void
    /// A drag let go of the place.
    let dropped: (EntityID) -> Void
    /// Each place being dragged, as it was when the drag began.
    @State private var origins: [EntityID: TaughtPlace] = [:]

    var body: some View {
        // Read, so the handles follow as the map pans and zooms.
        let _ = looking.camera
        ZStack(alignment: .topLeading) {
            ForEach(places) { place in
                if let point = proxy.convert(place.coordinate, to: .local) {
                    PlaceHandle(systemImage: "mappin", size: 28)
                        .help("Drag to move \(place.name)")
                        .gesture(
                            drag(place, by: \.coordinate) { origin, start, end in
                                origin.moved(from: start, to: end)
                            }
                        )
                        .position(point)
                    Text(place.name)
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .glassEffect(.regular, in: .capsule)
                        .allowsHitTesting(false)
                        .position(x: point.x, y: point.y + 30)
                }
                if let edge = proxy.convert(place.edge, to: .local) {
                    PlaceHandle(systemImage: nil, size: 12)
                        .help("Drag to set how far \(place.name) reaches")
                        .gesture(
                            drag(place, by: \.edge) { origin, _, end in
                                origin.reaching(end)
                            }
                        )
                        .position(edge)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A drag on one of a place's handles: the handle's own point moves by the drag's
    /// translation and is read back as a coordinate - the same conversion as a tap on the map.
    /// `change` turns the place as the drag found it, where its handle was, and where the
    /// handle is now into the place drawn.
    private func drag(
        _ place: TaughtPlace, by handle: KeyPath<TaughtPlace, CLLocationCoordinate2D>,
        _ change:
            @escaping (TaughtPlace, CLLocationCoordinate2D, CLLocationCoordinate2D) ->
            TaughtPlace
    ) -> some Gesture {
        // In the window's space: the handle moves under the pointer, so its own space would too.
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                let origin = origins[place.id] ?? place
                origins[place.id] = origin
                let start = origin[keyPath: handle]
                guard let point = proxy.convert(start, to: .local),
                    let end = proxy.convert(
                        CGPoint(
                            x: point.x + value.translation.width,
                            y: point.y + value.translation.height),
                        from: .local)
                else { return }
                dragged(change(origin, start, end))
            }
            .onEnded { _ in
                origins[place.id] = nil
                dropped(place.id)
            }
    }
}

/// A handle April drags on the map: a place's pin, or the dot on its edge.
private struct PlaceHandle: View {
    let systemImage: String?
    let size: CGFloat

    var body: some View {
        ZStack {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.tint(.teal).interactive(), in: .circle)
        // A little room around the small one, so it is easy to catch.
        .padding(6)
        .contentShape(.circle)
        .pointerStyle(.grabIdle)
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
                    if !place.placer.isEmpty {
                        Text("placed by \(place.placer),")
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
