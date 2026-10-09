import Foundation

/// Decides when a recording hands its audio to a new recognition request, and when to give up or
/// stop. Feed it the time and the microphone level about ten times a second.
///
/// Pure logic with no AppKit dependency so it can be unit tested.
struct SegmentScheduler {
    enum Action: Equatable {
        case none
        /// Hand the audio to a new request.
        case rotate
        /// The recording reached its time limit; stop and save it.
        case autoStop
        /// The recognizer keeps failing without hearing anything; stop and save what there is.
        case giveUp
    }

    /// A segment is rotated at the next pause once it is this old...
    var rotateAfter: TimeInterval = 45
    /// ...and in any case once it is this old.
    var forceRotateAt: TimeInterval = 55
    /// A level (0…1) below this counts as quiet.
    var quietLevel = 0.2
    /// How long it has to stay quiet to count as a pause.
    var quietDuration: TimeInterval = 0.3
    /// The safety limit for a whole recording, in case it is forgotten.
    var maxDuration: TimeInterval = 30 * 60
    /// How many segments in a row may fail without hearing anything before giving up.
    var maxFailures = 5
    /// A segment that ends without text counts as a failure if it ends sooner than this after it began,
    /// or if there was sound during it. Without either it is just a long silence the recognizer gave up
    /// on.
    var quickFailure: TimeInterval = 3

    private var recordingStart: TimeInterval = 0
    private var segmentStart: TimeInterval = 0
    private var quietSince: TimeInterval?
    private var failures = 0
    /// The level went above `quietLevel` at some point during this segment.
    private var heardSound = false
    private var autoStopFired = false

    /// Starts a recording, with its first segment.
    mutating func begin(at now: TimeInterval) {
        recordingStart = now
        segmentStart = now
        heardSound = false
        quietSince = nil
        failures = 0
        autoStopFired = false
    }

    /// For a rotation the scheduler didn't ask for (e.g. after the microphone changed).
    mutating func segmentStarted(at now: TimeInterval) {
        segmentStart = now
        heardSound = false
    }

    /// Call about ten times a second with the current level (0…1).
    mutating func tick(at now: TimeInterval, loudness: Double) -> Action {
        if now - recordingStart >= maxDuration, !autoStopFired {
            autoStopFired = true
            return .autoStop
        }
        if loudness < quietLevel {
            quietSince = quietSince ?? now
        } else {
            quietSince = nil
            heardSound = true
        }

        let age = now - segmentStart
        let quietFor = quietSince.map { now - $0 } ?? 0
        guard age >= forceRotateAt || (age >= rotateAfter && quietFor >= quietDuration) else { return .none }
        segmentStarted(at: now)
        return .rotate
    }

    /// Call when the segment that is receiving audio was ended by its recognizer (after a pause, or
    /// by failing). It is replaced at once, so no audio goes into a request that is already closed.
    mutating func segmentEnded(at now: TimeInterval, heardText: Bool) -> Action {
        let age = now - segmentStart
        let hadSound = heardSound
        segmentStarted(at: now)
        if heardText {
            failures = 0
        } else if age < quickFailure || hadSound {
            failures += 1
            if failures >= maxFailures { return .giveUp }
        }
        return .rotate
    }

    /// Maps an RMS amplitude to 0…1 on a decibel scale (-45 dB and below is 0, -15 dB and above is 1).
    static func loudness(rms: Float) -> Double {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(Double(rms))
        return min(max((decibels + 45) / 30, 0), 1)
    }
}
