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

/// Where the world has April (#248, slice 3): the place in her `presence.place`, how it knows -
/// her word to a bird, or her phone at a place she taught - how sure, and since when.
struct PlacePresence: Equatable, Sendable {
    var place: EntityID
    /// The world worked it out from her phone, rather than being told.
    var inferred: Bool
    var confidence: Double
    var since: Date

    var name: String { FactPageSections.name(of: place) }

    /// Her current `presence.place`, if it names a place.
    static func april(in facts: [Fact]) -> PlacePresence? {
        guard
            let fact = facts.last(where: {
                $0.subjectID == PlaceFix.april && $0.predicate == WorldFacts.presencePlace
            }),
            let place = WorldFacts.link(in: fact.value), place.rawValue.hasPrefix("place:")
        else { return nil }
        return PlacePresence(
            place: place, inferred: fact.epistemic.type == .inferred,
            confidence: fact.epistemic.confidence, since: fact.validFrom)
    }

    /// "at the Gym · 85% · since 3:40 PM", or "· told" for her own word.
    var line: Text {
        let how = inferred ? "\(Int((confidence * 100).rounded()))%" : "told"
        return Text("at \(name) · \(how) · since \(since, style: .time)")
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

    /// Where its name hangs: due south of the point, on the circle's rim.
    var south: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude - radius / 111_195, longitude: longitude)
    }

    /// A point on its rim, due east: how big the circle is drawn, measured on the map.
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

/// Where on a place the pointer has it (#258): inside its circle moves it, on its rim sets how far
/// it reaches. Measured in points on the map, so it holds at any zoom.
enum PlaceGrip: Equatable, Sendable {
    case move
    case reach

    /// How far either side of the rim still holds the rim, in points.
    static let rimWidth: CGFloat = 8

    /// The grip at `point` on a circle drawn around `center` out to `rim` points; nil outside it.
    /// A circle too small to tell its rim from its middle only moves, and is caught a little
    /// beyond its edge.
    static func at(_ point: CGPoint, center: CGPoint, rim: CGFloat) -> PlaceGrip? {
        let distance = hypot(point.x - center.x, point.y - center.y)
        guard rim >= 3 * rimWidth else { return distance <= max(rim, rimWidth) ? .move : nil }
        if abs(distance - rim) <= rimWidth { return .reach }
        return distance < rim ? .move : nil
    }
}

/// Where April is, as the world knows it (#248): her phone's fix on a map, how sure it is, and
/// how old, and the places she taught the birds, each as far as it reaches. The world's alone -
/// shown to April here, and never to a bird.
///
/// She moves a place by dragging its circle, and sets how far it reaches by dragging its rim
/// (#258). MapKit draws everything; the panel only reads where the pointer is, in the map's own
/// points, through `MapProxy` - as a tap on a map is read. Over a circle the map stops panning, so
/// the drag is the place's. Three earlier tries drew handles of their own, and the map and the
/// handles never agreed: as MapKit annotations (0.22.0) a drag never reached them; over the map
/// (0.22.1, 0.22.2) they sat off their circles and moved at a different scale from the map.
struct PlacesPanel: View {
    let store: WorldStore
    @State private var camera: MapCameraPosition = .automatic
    /// Places April is moving, drawn where her drag has them until the world's fact arrives.
    @State private var drafts: [EntityID: TaughtPlace] = [:]
    /// The place and grip under the pointer, while it is over a circle.
    @State private var hovering: PlaceHold?
    /// The place and grip a drag has, and the place as the drag found it.
    @State private var dragging: PlaceDrag?
    /// Counts the camera's moves, so the map's proxy is read afresh after each one.
    @State private var cameraMoves = 0

    private var fix: PlaceFix? { PlaceFix.april(in: store.facts) }
    private var presence: PlacePresence? { PlacePresence.april(in: store.facts) }
    private var stored: [TaughtPlace] { TaughtPlace.all(in: store.facts) }
    private var places: [TaughtPlace] { stored.map { drafts[$0.id] ?? $0 } }
    private var held: PlaceHold? { dragging?.hold ?? hovering }

    var body: some View {
        if fix != nil || !stored.isEmpty {
            MapReader { proxy in
                let _ = cameraMoves
                // Panned and zoomed, never turned or tilted; and not panned while the pointer
                // holds a place, so a drag there moves the place.
                Map(position: $camera, interactionModes: held == nil ? [.pan, .zoom] : [.zoom]) {
                    ForEach(places) { place in
                        let isHeld = held?.id == place.id
                        // The place the world has her at, in her colour.
                        let isHers = presence?.place == place.id
                        MapCircle(center: place.coordinate, radius: place.radius)
                            .foregroundStyle(.teal.opacity(isHeld ? 0.3 : 0.15))
                            .stroke(
                                isHers ? .purple : .teal, lineWidth: isHeld ? 3 : isHers ? 2 : 1)
                        Annotation(place.name, coordinate: place.south, anchor: .top) {
                            Text(place.name)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .glassEffect(.regular, in: .capsule)
                                .allowsHitTesting(false)
                        }
                        .annotationTitles(.hidden)
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
                .mapStyle(.standard(elevation: .flat))
                .onMapCameraChange { cameraMoves += 1 }
                .onContinuousHover { phase in
                    guard dragging == nil else { return }
                    switch phase {
                    case .active(let location): hovering = hold(at: location, on: proxy)
                    case .ended: hovering = nil
                    }
                }
                .pointerStyle(pointer)
                .gesture(placeDrag(on: proxy), including: held == nil ? .subviews : .all)
            }
            .overlay(alignment: .topLeading) {
                if fix != nil || presence != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                        if let fix {
                            if let accuracy = fix.accuracy {
                                Text("within \(Int(accuracy.rounded())) m ·")
                            }
                            Text("\(fix.since, style: .relative) ago")
                        }
                        if let presence {
                            if fix != nil { Text("·") }
                            presence.line.bold()
                        }
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
                    TaughtPlacesList(places: places, focus: focus).padding(12)
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

    /// The place and grip under `location`, in the map's points: the circle whose middle is
    /// nearest, of those the pointer is on.
    private func hold(at location: CGPoint, on proxy: MapProxy) -> PlaceHold? {
        var best: (hold: PlaceHold, distance: CGFloat)?
        for place in places {
            guard let center = proxy.convert(place.coordinate, to: .local),
                let edge = proxy.convert(place.edge, to: .local),
                let grip = PlaceGrip.at(
                    location, center: center,
                    rim: hypot(edge.x - center.x, edge.y - center.y))
            else { continue }
            let distance = hypot(location.x - center.x, location.y - center.y)
            if best.map({ distance < $0.distance }) ?? true {
                best = (PlaceHold(id: place.id, grip: grip), distance)
            }
        }
        return best?.hold
    }

    private var pointer: PointerStyle? {
        guard let held else { return nil }
        switch held.grip {
        case .move: return dragging == nil ? .grabIdle : .grabActive
        case .reach: return .frameResize(position: .trailing)
        }
    }

    /// A drag on a place: inside it, the place moves as far as the pointer did; on its rim, it
    /// reaches to the pointer. Letting go asks the world to keep it there.
    private func placeDrag(on proxy: MapProxy) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragging == nil {
                    guard let hold = hovering,
                        let place = places.first(where: { $0.id == hold.id })
                    else { return }
                    dragging = PlaceDrag(hold: hold, origin: place)
                }
                guard let drag = dragging,
                    let start = proxy.convert(value.startLocation, from: .local),
                    let end = proxy.convert(value.location, from: .local)
                else { return }
                drafts[drag.hold.id] =
                    switch drag.hold.grip {
                    case .move: drag.origin.moved(from: start, to: end)
                    case .reach: drag.origin.reaching(end)
                    }
            }
            .onEnded { _ in
                guard let drag = dragging else { return }
                dragging = nil
                keep(drag.hold.id)
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

    /// Close enough to a place to take hold of it: its circle a good size on the map.
    private func focus(_ place: TaughtPlace) {
        withAnimation {
            camera = .region(
                MKCoordinateRegion(
                    center: place.coordinate, latitudinalMeters: place.radius * 8,
                    longitudinalMeters: place.radius * 8))
        }
    }
}

/// A place under the pointer, and how it is held.
private struct PlaceHold: Equatable {
    var id: EntityID
    var grip: PlaceGrip
}

/// A drag on a place: how it is held, and the place as the drag found it.
private struct PlaceDrag: Equatable {
    var hold: PlaceHold
    var origin: TaughtPlace
}

/// The taught places, with who taught each last, when, and how often her phone was there. A
/// place's name takes the map to it, close enough to move it.
private struct TaughtPlacesList: View {
    let places: [TaughtPlace]
    let focus: (TaughtPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(places) { place in
                HStack(spacing: 6) {
                    Button {
                        focus(place)
                    } label: {
                        Label {
                            Text(place.name).bold()
                        } icon: {
                            Image(systemName: "mappin.circle.fill").foregroundStyle(.teal)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Show \(place.name) close enough to move it")
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
