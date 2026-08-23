import Common
import Foundation

func creatureDetails(_ creature: Creature) -> String {
    var lines: [String] = []
    lines.append("Creature: \(creature.name) (\(creature.id))")
    lines.append("  Channel Offset: \(creature.channelOffset)")
    lines.append("  Audio Channel:  \(creature.audioChannel)")
    lines.append("  Mouth Slot:     \(creature.mouthSlot)")
    if let mouthInput = creature.mouthInput {
        lines.append(
            "  Mouth Input:    \(mouthInput) (slot \(creature.resolvedMouthSlot))")
    }
    lines.append("  Inputs:         \(creature.inputs.count)")

    if !creature.speechLoopAnimationIds.isEmpty {
        let joined = creature.speechLoopAnimationIds.joined(separator: ", ")
        lines.append("  Speech Loops:   \(joined)")
    }
    if !creature.idleAnimationIds.isEmpty {
        let joined = creature.idleAnimationIds.joined(separator: ", ")
        lines.append("  Idle Loops:     \(joined)")
    }

    if let gaze = creature.gaze, !gaze.isEmpty {
        lines.append("Gaze:")
        for named in gaze.axes {
            let range = String(
                format: "%.1f° → %.1f°", named.axis.degreesAtMin, named.axis.degreesAtMax)
            var line = "  \(named.name): input=\(named.axis.input) range=\(range)"
            if let listening = named.axis.listeningAmount {
                line += String(format: " listening=%.2f", listening)
            }
            lines.append(line)
        }
    }

    if let runtime = creature.runtime {
        lines.append("Runtime:")
        let idleEnabled = runtime.idleEnabled ?? false
        lines.append("  Idle Enabled:   \(idleEnabled ? "yes" : "no")")

        if let activity = runtime.activity {
            let anim = activity.animationId ?? "none"
            let session = activity.sessionId ?? "n/a"
            let reason = activity.reason?.rawValue ?? "unknown"
            let state = activity.state.rawValue
            lines.append(
                "  Activity:       state=\(state) reason=\(reason) anim=\(anim) session=\(session)")
            if let started = activity.startedAt {
                lines.append("    started_at:   \(started)")
            }
            if let updated = activity.updatedAt {
                lines.append("    updated_at:   \(updated)")
            }
        }

        if let counters = runtime.counters {
            lines.append("  Counters:")
            lines.append("    sessions_started:   \(counters.sessionsStartedTotal ?? 0)")
            lines.append("    sessions_cancelled: \(counters.sessionsCancelledTotal ?? 0)")
            lines.append("    idle_started:       \(counters.idleStartedTotal ?? 0)")
            lines.append("    idle_stopped:       \(counters.idleStoppedTotal ?? 0)")
            lines.append("    idle_toggles:       \(counters.idleTogglesTotal ?? 0)")
            lines.append("    skips_missing:      \(counters.skipsMissingCreatureTotal ?? 0)")
            lines.append("    bgm_takeovers:      \(counters.bgmTakeoversTotal ?? 0)")
            lines.append("    audio_resets:       \(counters.audioResetsTotal ?? 0)")
        }

        let bgmOwner = runtime.bgmOwner ?? "none"
        lines.append("  BGM Owner:     \(bgmOwner)")

        if let err = runtime.lastError {
            lines.append("  Last Error:    \(err.message) @ \(err.timestamp)")
        }
    }

    return lines.joined(separator: "\n")
}
