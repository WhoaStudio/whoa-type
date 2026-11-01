import Foundation
import AVFoundation

nonisolated enum SoundPackValidator {
    static func file(_ path: String, in root: URL) throws -> URL {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
            throw PackError.invalid("Sample path escapes pack")
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: url.path) else {
            throw PackError.invalid("Missing or escaping pack file: \(path)")
        }
        return url
    }
    /// `inspectAudio: false` skips opening each WAV (used for cheap discovery at launch;
    /// `SoundPackRepository.load` always validates fully before decoding).
    static func validate(_ m: SoundPackManifest, root: URL, rate: Double, inspectAudio: Bool = true) throws -> [String: URL] {
        guard m.schemaVersion == 1, !m.id.isEmpty, !m.displayName.isEmpty,
              m.gainDB.isFinite, (-24...0).contains(m.gainDB),
              m.pitchCents.min.isFinite, m.pitchCents.max.isFinite,
              m.pitchCents.min >= -100, m.pitchCents.max <= 100, m.pitchCents.min <= m.pitchCents.max,
              m.samples[m.fallbackGroup] != nil, m.samples.count <= 512,
              rate.isFinite, (8000...192000).contains(rate) else { throw PackError.invalid("Invalid pack metadata") }
        if let license = m.license { _ = try file(license, in: root) }
        for mapping in [m.keys, m.keyGroups] {
            for (code, group) in mapping {
                guard let value = UInt16(code), value < 128, String(value) == code, m.samples[group] != nil else {
                    throw PackError.invalid("Invalid physical-key mapping")
                }
            }
        }
        guard m.preview.count <= 16 else { throw PackError.invalid("Preview has too many events") }
        var previous = -1
        var held = Set<UInt16>()
        for event in m.preview {
            guard event.keyCode < 128, event.atMs >= previous, (0...2000).contains(event.atMs) else {
                throw PackError.invalid("Invalid preview sequence")
            }
            if event.phase == .down {
                guard held.insert(event.keyCode).inserted else { throw PackError.invalid("Repeated preview down") }
            } else {
                guard held.remove(event.keyCode) != nil else { throw PackError.invalid("Unmatched preview release") }
            }
            previous = event.atMs
        }
        guard held.isEmpty else { throw PackError.invalid("Preview leaves held keys") }
        var paths = Set<String>()
        for sample in m.samples.values {
            guard !sample.down.isEmpty, !sample.up.isEmpty, sample.down.count <= 512, sample.up.count <= 512 else {
                throw PackError.invalid("Missing down/up samples")
            }
            paths.formUnion(sample.down); paths.formUnion(sample.up)
        }
        guard paths.count <= 512 else { throw PackError.invalid("Too many sample files") }
        var files: [String: URL] = [:]
        var bytes = 0
        for path in paths {
            let url = try file(path, in: root)
            guard url.pathExtension.lowercased() == "wav" else { throw PackError.invalid("Only PCM WAV is accepted") }
            guard inspectAudio else { files[path] = url; continue }
            let audio = try AVAudioFile(forReading: url)
            let format = audio.fileFormat
            let bits = format.streamDescription.pointee.mBitsPerChannel
            let flags = format.streamDescription.pointee.mFormatFlags
            guard format.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM,
                  format.channelCount == 1, [44100.0, 48000.0, 96000.0].contains(format.sampleRate),
                  ((flags & kAudioFormatFlagIsFloat != 0 && bits == 32) || (flags & kAudioFormatFlagIsFloat == 0 && [16,24].contains(bits))),
                  audio.length > 0, Double(audio.length) / format.sampleRate <= 0.5 else {
                throw PackError.invalid("Unsupported sample format or duration")
            }
            bytes += (Int(ceil(Double(audio.length) * rate / format.sampleRate)) + 32) * 4
            guard bytes <= 64 * 1024 * 1024 else { throw PackError.invalid("Decoded pack exceeds 64 MiB") }
            files[path] = url
        }
        return files
    }
}
