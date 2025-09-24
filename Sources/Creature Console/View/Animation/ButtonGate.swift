// ButtonGate.swift
// Debounces and serializes button press handling to avoid double-triggers

import Foundation

actor ButtonGate {
    private var lastPress: Date = .distantPast
    private let cooldown: TimeInterval

    init(cooldown: TimeInterval = 0.35) {
        self.cooldown = cooldown
    }

    func tryHandlePress(_ handler: @Sendable () async -> Void) async {
        let now = Date()
        guard now.timeIntervalSince(lastPress) > cooldown else {
            return
        }
        lastPress = now
        await handler()
    }
}
