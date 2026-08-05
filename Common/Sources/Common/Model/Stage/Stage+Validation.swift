import Foundation

extension Stage {

    /// What's wrong with this stage, or `nil` if the server will accept it.
    ///
    /// Mirrors the server's parser (`src/server/stage/helpers.cpp`) so the editor blocks a bad save
    /// locally with a useful message instead of round-tripping a 400.
    public var validationProblem: String? {
        if title.count > StageLimits.maxTitle {
            return "Title is longer than \(StageLimits.maxTitle) characters."
        }
        if notes.count > StageLimits.maxNotes {
            return "Notes are longer than \(StageLimits.maxNotes) characters."
        }
        if version < 1 || version > StageLimits.currentVersion {
            return
                "Stage version \(version) isn't supported by this client (current is \(StageLimits.currentVersion))."
        }
        if placements.count > StageLimits.maxPlacements {
            return
                "\(placements.count) creatures placed; the maximum is \(StageLimits.maxPlacements), one per audio lane."
        }

        var seen = Set<CreatureIdentifier>()
        for placement in placements {
            if placement.creatureID.isEmpty {
                return "A placement is missing its creature."
            }
            if !seen.insert(placement.creatureID).inserted {
                let name =
                    placement.creatureName.isEmpty ? placement.creatureID : placement.creatureName
                return "\(name) is placed on the stage more than once."
            }
            if let problem = placement.validationProblem {
                return problem
            }
        }
        return nil
    }

    public var isValid: Bool { validationProblem == nil }
}

extension StagePlacement {

    /// What's wrong with this placement's geometry, or `nil` if the server will accept it.
    public var validationProblem: String? {
        let label = creatureName.isEmpty ? creatureID : creatureName
        for (axis, value) in [("X", x), ("Y", y), ("Z", z)] {
            guard value.isFinite else {
                return "\(label)'s \(axis) position isn't a number."
            }
            guard abs(value) <= StageLimits.coordinateLimit else {
                return
                    "\(label)'s \(axis) position (\(value) m) is outside the ±\(Int(StageLimits.coordinateLimit)) m stage."
            }
        }
        guard yaw.isFinite else {
            return "\(label)'s facing isn't a number."
        }
        return nil
    }
}
