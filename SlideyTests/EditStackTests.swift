import XCTest
@testable import Slidey

final class EditStackTests: XCTestCase {

    func testAppendAddsStep() {
        var stack = EditStack()
        stack.append(.enhance)
        XCTAssertEqual(stack.steps, [.enhance])
    }

    func testAppendMultipleSteps() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.sharpen)
        stack.append(.smooth(noiseLevel: 0.02))
        XCTAssertEqual(stack.steps.count, 3)
        XCTAssertEqual(stack.steps[0], .enhance)
        XCTAssertEqual(stack.steps[1], .sharpen)
        XCTAssertEqual(stack.steps[2], .smooth(noiseLevel: 0.02))
    }

    func testAppendMovesExistingStepToEnd() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.sharpen)
        stack.append(.enhance)
        XCTAssertEqual(stack.steps, [.sharpen, .enhance])
    }

    func testAppendSmoothUpdatesNoiseLevel() {
        var stack = EditStack()
        stack.append(.smooth(noiseLevel: 0.02))
        stack.append(.sharpen)
        stack.append(.smooth(noiseLevel: 0.05))
        XCTAssertEqual(stack.steps.count, 2)
        XCTAssertEqual(stack.steps[0], .sharpen)
        XCTAssertEqual(stack.steps[1], .smooth(noiseLevel: 0.05))
    }

    func testAppendUpscaleUpdatesFactor() {
        var stack = EditStack()
        stack.append(.upscale(factor: 2))
        stack.append(.upscale(factor: 4))
        XCTAssertEqual(stack.steps.count, 1)
        XCTAssertEqual(stack.steps[0], .upscale(factor: 4))
    }

    func testAppendJPEGCleanupUpdatesStrength() {
        var stack = EditStack()
        stack.append(.jpegCleanup(strength: 50))
        stack.append(.jpegCleanup(strength: 80))
        XCTAssertEqual(stack.steps.count, 1)
        XCTAssertEqual(stack.steps[0], .jpegCleanup(strength: 80))
    }

    func testRemoveDropsOnlyMatchingCase() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.sharpen)
        stack.append(.smooth(noiseLevel: 0.02))
        stack.remove(caseTag: .sharpen)
        XCTAssertEqual(stack.steps.count, 2)
        XCTAssertEqual(stack.steps[0], .enhance)
        XCTAssertEqual(stack.steps[1], .smooth(noiseLevel: 0.02))
    }

    func testRemoveNonExistentIsNoOp() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.remove(caseTag: .sharpen)
        XCTAssertEqual(stack.steps, [.enhance])
    }

    func testContains() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.upscale(factor: 4))
        XCTAssertTrue(stack.contains(caseTag: .enhance))
        XCTAssertTrue(stack.contains(caseTag: .upscale))
        XCTAssertFalse(stack.contains(caseTag: .sharpen))
    }

    func testIsEmpty() {
        var stack = EditStack()
        XCTAssertTrue(stack.isEmpty)
        stack.append(.enhance)
        XCTAssertFalse(stack.isEmpty)
        stack.remove(caseTag: .enhance)
        XCTAssertTrue(stack.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.smooth(noiseLevel: 0.02))
        stack.append(.upscale(factor: 4))
        stack.append(.faceRestore)
        stack.append(.colorize)

        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(EditStack.self, from: data)
        XCTAssertEqual(stack, decoded)
    }

    func testCodableRoundTripAllCases() throws {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.smooth(noiseLevel: 0.03))
        stack.append(.sharpen)
        stack.append(.upscale(factor: 2))
        stack.append(.faceRestore)
        stack.append(.redEyeRemoval)
        stack.append(.backgroundRemoval)
        stack.append(.artifactRemoval)
        stack.append(.jpegCleanup(strength: 75))
        stack.append(.colorize)

        let data = try JSONEncoder().encode(stack)
        let decoded = try JSONDecoder().decode(EditStack.self, from: data)
        XCTAssertEqual(stack, decoded)
        XCTAssertEqual(decoded.steps.count, 10)
    }

    func testEditStepTitleTag() {
        XCTAssertEqual(EditStep.enhance.titleTag, "enhanced")
        XCTAssertEqual(EditStep.smooth(noiseLevel: 0.02).titleTag, "smoothed")
        XCTAssertEqual(EditStep.sharpen.titleTag, "sharpened")
        XCTAssertEqual(EditStep.upscale(factor: 4).titleTag, "4\u{00d7} upscaled")
        XCTAssertEqual(EditStep.faceRestore.titleTag, "faces restored")
        XCTAssertEqual(EditStep.redEyeRemoval.titleTag, "red-eye removed")
        XCTAssertEqual(EditStep.backgroundRemoval.titleTag, "background removed")
        XCTAssertEqual(EditStep.artifactRemoval.titleTag, "artifacts removed")
        XCTAssertEqual(EditStep.jpegCleanup(strength: 50).titleTag, "JPEG cleaned up (50%)")
        XCTAssertEqual(EditStep.colorize.titleTag, "colorized")
    }

    func testEditStepCaseTag() {
        XCTAssertEqual(EditStep.enhance.caseTag, .enhance)
        XCTAssertEqual(EditStep.smooth(noiseLevel: 0.05).caseTag, .smooth)
        XCTAssertEqual(EditStep.upscale(factor: 2).caseTag, .upscale)
        XCTAssertEqual(EditStep.jpegCleanup(strength: 75).caseTag, .jpegCleanup)
    }

    func testBatchableStepsExcludeSlowOperations() {
        var stack = EditStack()
        stack.append(.enhance)
        stack.append(.smooth(noiseLevel: 0.02))
        stack.append(.sharpen)
        stack.append(.upscale(factor: 4))
        stack.append(.faceRestore)
        stack.append(.redEyeRemoval)
        stack.append(.backgroundRemoval)
        stack.append(.artifactRemoval)
        stack.append(.jpegCleanup(strength: 50))
        stack.append(.colorize)

        let slowTags: Set<EditStepTag> = [.upscale, .faceRestore, .redEyeRemoval, .backgroundRemoval, .artifactRemoval, .jpegCleanup, .colorize]
        var filtered = EditStack()
        for step in stack.steps where !slowTags.contains(step.caseTag) {
            filtered.append(step)
        }

        XCTAssertEqual(filtered.steps.count, 3)
        XCTAssertEqual(filtered.steps.map(\.caseTag), [.enhance, .smooth, .sharpen])
    }

    func testOrderPreservedAcrossOperations() {
        var stack = EditStack()
        stack.append(.sharpen)
        stack.append(.enhance)
        stack.append(.smooth(noiseLevel: 0.02))
        stack.append(.upscale(factor: 2))
        stack.remove(caseTag: .enhance)
        XCTAssertEqual(stack.steps.map(\.caseTag), [.sharpen, .smooth, .upscale])
        stack.append(.enhance)
        XCTAssertEqual(stack.steps.map(\.caseTag), [.sharpen, .smooth, .upscale, .enhance])
    }
}
