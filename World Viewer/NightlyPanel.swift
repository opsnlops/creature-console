import SwiftUI
import WorldCore

/// The nightly reports, by night: pick a night, read what each bird wrote to April and what it
/// chose to remember of the day, most important first. April: "Can you add something to World
/// Viewer to let me view the nightly reports by day?" (#218)
struct NightlyPanel: View {
    let store: WorldStore
    @Binding var scried: Scried?
    @State private var reflections: [Fact] = []
    @State private var filings: [NightlyReports.Filing] = []
    @State private var chosen: String?
    @State private var report: [NightlyReports.BirdNight] = []
    @State private var loading = false

    /// Every night some bird remembered, and every night the librarian filed.
    private var nights: [NightlyReports.Night] {
        let remembered = NightlyReports.nights(fromReflections: reflections)
        let days = Set(remembered.map(\.day))
        let filedOnly = filings.map(\.day).filter { !days.contains($0) }
        return (remembered + Set(filedOnly).map { NightlyReports.Night(day: $0, birds: []) })
            .sorted { $0.day > $1.day }
    }

    private var filing: NightlyReports.Filing? {
        filings.first { $0.day == chosen }
    }

    var body: some View {
        // Plain SwiftUI, never HSplitView (#209): a fixed list of nights, then the night.
        HStack(spacing: 0) {
            List(nights, selection: $chosen) { night in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.title(of: night.day))
                        .font(.headline)
                    Text(night.birds.map(\.capitalized).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .frame(width: 220)

            Divider()

            Group {
                if chosen == nil {
                    ContentUnavailableView(
                        "Pick a night", systemImage: "moon.stars",
                        description: Text(
                            "What each bird wrote to April, and what it remembered of the day."))
                } else if loading {
                    ProgressView()
                } else {
                    NightView(report: report, filing: filing, scried: $scried)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            if nights.isEmpty && !loading {
                ContentUnavailableView(
                    "No nights yet", systemImage: "moon.zzz",
                    description: Text("The birds remember each day at 3:30 in the morning."))
            }
        }
        .task { await loadNights() }
        .task(id: chosen) { await loadNight() }
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task {
                        await loadNights()
                        await loadNight()
                    }
                }
            }
        }
    }

    private func loadNights() async {
        reflections = await store.nightlyReflections()
        filings = await store.nightlyFilings().compactMap(NightlyReports.filing(from:))
        if chosen == nil { chosen = nights.first?.day }
    }

    private func loadNight() async {
        guard let day = chosen else { return }
        loading = true
        let birds = nights.first { $0.day == day }?.birds ?? []
        let episodes = await store.nightlyEpisodes(day: day, birds: birds)
        report = NightlyReports.report(day: day, reflections: reflections, episodes: episodes)
        loading = false
    }

    /// "Wednesday, September 30" from "2026-09-30"; the day itself when it does not parse.
    static func title(of day: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(identifier: "UTC")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: day) else { return day }
        return date.formatted(
            Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).weekday(.wide).month(.wide)
                .day())
    }
}

/// One night: each bird's letter, then what it remembered.
private struct NightView: View {
    let report: [NightlyReports.BirdNight]
    let filing: NightlyReports.Filing?
    @Binding var scried: Scried?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let filing {
                    FilingView(filing: filing)
                        .onTapGesture { scried = .event(filing.event) }
                }
                ForEach(report) { bird in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(bird.bird.capitalized)
                            .font(.title2.bold())
                        if let letter = bird.reflectionText {
                            Text(letter)
                                .font(.body.italic())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .glassEffect(
                                    .regular.tint(.purple.opacity(0.12)),
                                    in: .rect(cornerRadius: 14)
                                )
                                .onTapGesture {
                                    if let fact = bird.reflection { scried = .fact(fact) }
                                }
                        }
                        ForEach(bird.episodes) { episode in
                            EpisodeRow(episode: episode)
                                .contentShape(Rectangle())
                                .onTapGesture { scried = .fact(episode.fact) }
                        }
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct EpisodeRow: View {
    let episode: NightlyReports.Episode

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(episode.salience, format: .number.precision(.fractionLength(2)))
                .font(.caption.monospacedDigit())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .glassEffect(
                    .regular.tint(.purple.opacity(episode.salience * 0.35)), in: .capsule
                )
                .help("How much it mattered to the bird, 0 to 1")
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.when)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(episode.what)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                Text(episode.about.map(\.rawValue).joined(separator: "  ·  "))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The librarian's night: what she would file, and why. While she watches, a proposal only.
private struct FilingView: View {
    let filing: NightlyReports.Filing

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    "\(filing.bird.capitalized) filed the record", systemImage: "books.vertical"
                )
                .font(.title2.bold())
                Spacer()
                Text(filing.watching ? "watching: nothing applied" : "applied")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .glassEffect(
                        .regular.tint((filing.watching ? Color.orange : .green).opacity(0.25)),
                        in: .capsule)
            }
            Text(
                "Read \(filing.learned) kept fact\(filing.learned == 1 ? "" : "s")"
                    + " and \(filing.overwritten) written over"
                    + (filing.dropped > 0
                        ? " · \(filing.dropped) proposal\(filing.dropped == 1 ? "" : "s") left out"
                        : "")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if filing.isEmpty {
                Text("Nothing needed filing.")
                    .foregroundStyle(.secondary)
            }
            if !filing.rewrites.isEmpty {
                section("Rewrite", systemImage: "square.and.pencil")
                ForEach(filing.rewrites, id: \.self) { rewrite in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(rewrite.subject) · \(rewrite.predicate)")
                            .font(.caption.monospaced())
                        Text(rewrite.value)
                            .textSelection(.enabled)
                        Text(
                            "replaces \(rewrite.replaces) fact\(rewrite.replaces == 1 ? "" : "s")"
                                + (rewrite.reason.isEmpty ? "" : " · \(rewrite.reason)")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            lines("Retire", systemImage: "archivebox", filing.retires)
            lines("Same thing", systemImage: "equal.circle", filing.same)
            lines("What the families mean", systemImage: "character.book.closed", filing.kinds)
            if !filing.questions.isEmpty {
                section("Questions for April", systemImage: "questionmark.bubble")
                ForEach(filing.questions, id: \.self) { question in
                    Text(question).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(.teal.opacity(0.10)), in: .rect(cornerRadius: 14))
    }

    private func section(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.headline)
            .padding(.top, 6)
    }

    @ViewBuilder
    private func lines(_ title: String, systemImage: String, _ lines: [NightlyReports.Filing.Line])
        -> some View
    {
        if !lines.isEmpty {
            section(title, systemImage: systemImage)
            ForEach(lines, id: \.self) { line in
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.what)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    if !line.reason.isEmpty {
                        Text(line.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
