import Foundation

/// Represents the type of background job reported by the server.
public enum JobType: String, Codable, Sendable {
    case lipSync = "lip-sync"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = JobType(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unknown:
            try container.encode("unknown")
        default:
            try container.encode(rawValue)
        }
    }
}

/// Represents the lifecycle status of a background job.
public enum JobStatus: String, Codable, Sendable {
    case queued
    case running
    case completed
    case failed
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = JobStatus(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unknown:
            try container.encode("unknown")
        default:
            try container.encode(rawValue)
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
        }
    }
}

/// Additional metadata for lip sync jobs provided in the job details JSON.
public struct LipSyncJobDetails: Codable, Equatable, Sendable {
    public let soundFile: String
    public let allowOverwrite: Bool

    enum CodingKeys: String, CodingKey {
        case soundFile = "sound_file"
        case allowOverwrite = "allow_overwrite"
    }

    public init(soundFile: String, allowOverwrite: Bool) {
        self.soundFile = soundFile
        self.allowOverwrite = allowOverwrite
    }
}

/// Response returned by the server when a job is queued successfully.
public struct JobCreatedResponse: Codable, Equatable, Sendable {
    public let jobId: String
    public let jobType: JobType
    public let message: String

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobType = "job_type"
        case message
    }

    public init(jobId: String, jobType: JobType, message: String) {
        self.jobId = jobId
        self.jobType = jobType
        self.message = message
    }
}

/// Progress update emitted while a background job is running.
public struct JobProgress: Codable, Equatable, Sendable {
    public let jobId: String
    public let jobType: JobType
    public let status: JobStatus
    public let progress: Double?
    public let details: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobType = "job_type"
        case status
        case progress
        case details
    }

    public init(
        jobId: String,
        jobType: JobType,
        status: JobStatus,
        progress: Double?,
        details: String?
    ) {
        self.jobId = jobId
        self.jobType = jobType
        self.status = status
        self.progress = progress
        self.details = details
    }

    /// Parses the `details` JSON into strongly typed metadata.
    public func decodeDetails<T: Decodable>(as type: T.Type) -> T? {
        guard let details, let data = details.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

/// Final completion payload describing the outcome of a job.
public struct JobCompletion: Codable, Equatable, Sendable {
    public let jobId: String
    public let jobType: JobType
    public let status: JobStatus
    public let result: String?
    public let details: String?

    enum CodingKeys: String, CodingKey {
        case jobId = "job_id"
        case jobType = "job_type"
        case status
        case result
        case details
    }

    public init(
        jobId: String,
        jobType: JobType,
        status: JobStatus,
        result: String?,
        details: String?
    ) {
        self.jobId = jobId
        self.jobType = jobType
        self.status = status
        self.result = result
        self.details = details
    }

    /// Parses the `details` JSON into strongly typed metadata.
    public func decodeDetails<T: Decodable>(as type: T.Type) -> T? {
        guard let details, let data = details.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
