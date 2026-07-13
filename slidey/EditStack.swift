import Foundation

enum EditStepTag: String, Codable, CaseIterable {
    case enhance, smooth, sharpen, upscale, faceRestore, redEyeRemoval, backgroundRemoval, artifactRemoval, jpegCleanup, colorize, grainReduction
}

enum EditStep: Codable, Equatable {
    case enhance
    case smooth(noiseLevel: Double)
    case sharpen
    case upscale(factor: Int)
    case faceRestore
    case redEyeRemoval
    case backgroundRemoval
    case artifactRemoval
    case jpegCleanup(strength: Double)
    case colorize
    case grainReduction(strength: Double)

    var caseTag: EditStepTag {
        switch self {
        case .enhance: return .enhance
        case .smooth: return .smooth
        case .sharpen: return .sharpen
        case .upscale: return .upscale
        case .faceRestore: return .faceRestore
        case .redEyeRemoval: return .redEyeRemoval
        case .backgroundRemoval: return .backgroundRemoval
        case .artifactRemoval: return .artifactRemoval
        case .jpegCleanup: return .jpegCleanup
        case .colorize: return .colorize
        case .grainReduction: return .grainReduction
        }
    }

    var titleTag: String {
        switch self {
        case .enhance: return "enhanced"
        case .smooth: return "smoothed"
        case .sharpen: return "sharpened"
        case .upscale(let factor): return "\(factor)\u{00d7} upscaled"
        case .faceRestore: return "faces restored"
        case .redEyeRemoval: return "red-eye removed"
        case .backgroundRemoval: return "background removed"
        case .artifactRemoval: return "artifacts removed"
        case .jpegCleanup(let strength): return "JPEG cleaned up (\(Int(strength))%)"
        case .colorize: return "colorized"
        case .grainReduction(let strength): return "grain reduced (\(Int(strength))%)"
        }
    }
}

struct EditStack: Codable, Equatable {
    var steps: [EditStep] = []

    mutating func append(_ step: EditStep) {
        steps.removeAll { $0.caseTag == step.caseTag }
        steps.append(step)
    }

    mutating func remove(caseTag: EditStepTag) {
        steps.removeAll { $0.caseTag == caseTag }
    }

    func contains(caseTag: EditStepTag) -> Bool {
        steps.contains { $0.caseTag == caseTag }
    }

    var isEmpty: Bool { steps.isEmpty }
}
