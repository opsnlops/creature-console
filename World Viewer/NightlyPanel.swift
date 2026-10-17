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
    @State private var review: FilingReview?
    @State private var checks: NightlyReports.FilingChecks?
    @State private var applying = false

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
                    NightView(
                        report: report, filing: filing, review: review, checks: $checks,
                        applying: applying, apply: { Task { await applyChecked() } },
                        scried: $scried)
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
        await loadReview()
        loading = false
    }

    /// The night's filing held against the record now: where the checkboxes start.
    private func loadReview() async {
        guard let filing else {
            review = nil
            checks = nil
            return
        }
        review = await store.filingReview(filing.event.eventID)
        checks = review.map(NightlyReports.FilingChecks.init(review:))
    }

    /// Applies what April checked, then reads the review again: each row then says what
    /// happened to it.
    private func applyChecked() async {
        guard let filing, let selection = checks?.selection else { return }
        applying = true
        defer { applying = false }
        guard let result = await store.applyFiling(filing.event.eventID, selection) else { return }
        await loadReview()
        checks?.record(result)
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
    let review: FilingReview?
    @Binding var checks: NightlyReports.FilingChecks?
    let applying: Bool
    let apply: () -> Void
    @Binding var scried: Scried?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let filing {
                    FilingView(
                        filing: filing, review: review, checks: $checks, applying: applying,
                        apply: apply, scry: { scried = .event(filing.event) })
                }
                ForEach(report) { bird in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(bird.bird.capitalized)
                            .font(.title2.bold())
                        if let letter = bird.reflectionText {
                            (bird.reflectionShared
                                ? Text(letter)
                                : Text("\(Image(systemName: "lock.fill")) ") + Text(letter))
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
                HStack(spacing: 6) {
                    Text(episode.when)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !episode.shared {
                        Label("kept private", systemImage: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(
                                "The bird kept this memory to itself; the other birds can't look it up"
                            )
                    }
                }
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

/// The librarian's night: what she would file, and why. Each item is checked against the record
/// now (#229, Ship 2); April checks what she agrees with, and applies.
private struct FilingView: View {
    let filing: NightlyReports.Filing
    let review: FilingReview?
    @Binding var checks: NightlyReports.FilingChecks?
    let applying: Bool
    let apply: () -> Void
    let scry: () -> Void
    @State private var confirming = false

    private var rows: [NightlyReports.FilingRow] {
        review.map(NightlyReports.rows(of:)) ?? []
    }

    private var checkedCount: Int { checks?.checked.count ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    "\(filing.bird.capitalized) filed the record", systemImage: "books.vertical"
                )
                .font(.title2.bold())
                Spacer()
                Button("Scry", systemImage: "eye", action: scry)
                    .buttonStyle(.glass)
                    .help("The night's memory.filed event")
                if review != nil {
                    Button(
                        "Apply \(checkedCount) checked", systemImage: "checkmark.seal",
                        action: { confirming = true }
                    )
                    .buttonStyle(.glassProminent)
                    .disabled(checkedCount == 0 || applying)
                }
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
            if review == nil, !filing.isEmpty {
                Text("The world could not review this filing; nothing can be applied from it.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            ForEach(FilingList.allCases, id: \.self) { list in
                let listRows = rows.filter { $0.key.list == list }
                if !listRows.isEmpty {
                    section(list)
                    ForEach(listRows) { row in
                        FilingRowView(row: row, checks: $checks)
                    }
                }
            }
            if !filing.questions.isEmpty {
                Label("Questions for April", systemImage: "questionmark.bubble")
                    .font(.headline)
                    .padding(.top, 6)
                ForEach(filing.questions, id: \.self) { question in
                    Text(question).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .glassEffect(.regular.tint(.teal.opacity(0.10)), in: .rect(cornerRadius: 14))
        .confirmationDialog(
            "Apply \(checkedCount) change\(checkedCount == 1 ? "" : "s") to the record?",
            isPresented: $confirming
        ) {
            Button("Apply", action: apply)
        } message: {
            Text(
                "The world checks each one again first, and skips anything that changed since the night."
            )
        }
    }

    private func section(_ list: FilingList) -> some View {
        let (title, image): (String, String) =
            switch list {
            case .rewrites: ("Rewrite", "square.and.pencil")
            case .retires: ("Retire", "archivebox")
            case .same: ("Same thing", "equal.circle")
            case .renames: ("Wrong kind", "arrow.triangle.swap")
            case .kinds: ("What the families mean", "character.book.closed")
            }
        return Label(title, systemImage: image)
            .font(.headline)
            .padding(.top, 6)
    }
}

/// One item: its checkbox, what it would do, and how it stands.
private struct FilingRowView: View {
    let row: NightlyReports.FilingRow
    @Binding var checks: NightlyReports.FilingChecks?

    private var outcome: FilingOutcome? { checks?.outcomes[row.key] }

    private var isOn: Binding<Bool> {
        Binding(
            get: { checks?.isChecked(row.key) ?? false },
            set: { checks?.set(row.key, checked: $0) })
    }

    private var tint: Color {
        if let outcome { return outcome.applied ? .green : .orange }
        switch row.item.status {
        case .ready: return row.item.checked ? .teal : .yellow
        case .stale: return .orange
        case .guarded: return .red
        case .applied: return .green
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("", isOn: isOn)
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!(checks?.canCheck(row.key) ?? false))
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Text(NightlyReports.badge(row.item, outcome: outcome))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .glassEffect(.regular.tint(tint.opacity(0.3)), in: .capsule)
                        .help(outcome?.reason ?? row.item.reason ?? "")
                }
                Text(row.body)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if !row.detail.isEmpty {
                    Text(row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let reason = outcome?.reason ?? row.item.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(tint)
                }
                if let end = row.item.validTo {
                    Text(
                        "ends \(end.formatted(date: .abbreviated, time: .shortened)), as what it replaces does"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                ForEach(row.replaced, id: \.self) { line in
                    Text("– \(line)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
