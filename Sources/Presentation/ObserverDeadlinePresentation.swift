import Foundation

public enum ObserverDeadlineServerPhase: String, Sendable, Equatable {
    case active = "ACTIVE"
    case closeRequired = "CLOSE_REQUIRED"
    case hardExpired = "HARD_EXPIRED"
    case terminal = "TERMINAL"
    case unknown = "UNKNOWN"

    public init(serverValue: String) {
        self = Self(rawValue: serverValue) ?? .unknown
    }
}

public struct ObserverDeadlineUXPresentation: Sendable, Equatable {
    public let serverPhase: String
    public let phase: ObserverDeadlineServerPhase
    public let remainingSeconds: Int
    public let elapsedSeconds: Int
    public let hardTTLSeconds: Int
    public let closeReminderSeconds: Int
    public let serverCloseRequired: Bool
    public let transportLive: Bool

    public init(
        serverPhase: String,
        remainingSeconds: Int,
        elapsedSeconds: Int,
        hardTTLSeconds: Int,
        closeReminderSeconds: Int,
        serverCloseRequired: Bool,
        transportLive: Bool
    ) {
        self.serverPhase = serverPhase
        self.phase = ObserverDeadlineServerPhase(serverValue: serverPhase)
        self.remainingSeconds = max(0, remainingSeconds)
        self.elapsedSeconds = max(0, elapsedSeconds)
        self.hardTTLSeconds = max(0, hardTTLSeconds)
        self.closeReminderSeconds = max(0, closeReminderSeconds)
        self.serverCloseRequired = serverCloseRequired
        self.transportLive = transportLive
    }

    public var contractConsistent: Bool {
        serverCloseRequired == (phase == .closeRequired)
    }

    public var headline: String {
        guard transportLive else { return "LAST OBSERVED · \(serverPhase)" }
        guard contractConsistent else { return "DEADLINE INCONSISTENT" }
        switch phase {
        case .active: return "SESSION ACTIVE"
        case .closeRequired: return "SAVE & EXIT"
        case .hardExpired: return "SESSION EXPIRED"
        case .terminal: return "SESSION ENDED"
        case .unknown: return "DEADLINE UNKNOWN"
        }
    }

    public var detail: String? {
        guard transportLive else {
            return "Cached timing is historical. No local timer promotes it to live truth."
        }
        guard contractConsistent else {
            return "SERVER PHASE / CLOSE_REQUIRED MISMATCH · OWNER CLOSE WITHHELD"
        }
        switch phase {
        case .active:
            return nil
        case .closeRequired:
            return "FINAL \(Self.duration(closeReminderSeconds)) WINDOW · SESSION STILL ACTIVE"
        case .hardExpired:
            return "HARD TTL REACHED"
        case .terminal:
            return "AUTHORITATIVE TERMINAL SESSION"
        case .unknown:
            return "SERVER DEADLINE PHASE NOT RECOGNIZED"
        }
    }

    public var tone: SemanticTone {
        guard transportLive else { return .warning }
        guard contractConsistent else { return .negative }
        switch phase {
        case .active: return .neutral
        case .closeRequired: return .warning
        case .hardExpired: return .negative
        case .terminal: return .neutral
        case .unknown: return .warning
        }
    }

    public var allowsNewSessionClose: Bool {
        guard transportLive && contractConsistent else { return false }
        return phase == .active || phase == .closeRequired
    }

    public var isFinalWarningWindow: Bool {
        transportLive && contractConsistent && phase == .closeRequired
    }

    public var shouldPresentAsExpired: Bool {
        transportLive && contractConsistent && phase == .hardExpired
    }

    public static func duration(_ seconds: Int) -> String {
        let value = max(0, seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}
