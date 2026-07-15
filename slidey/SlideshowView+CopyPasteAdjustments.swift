import AppKit

extension SlideshowView {

    func copyCurrentAdjustments() {
        guard let sourceURL = imageLoader.currentImageURL else { return }

        let collected = collectCopyableEdits(from: sourceURL)

        guard collected.hasEdits else {
            savedToast = "No adjustments to copy"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No adjustments to copy" { self.savedToast = nil }
            }
            return
        }

        copiedAdjustments = collected

        let message = "Adjustments copied"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }

    func pasteAdjustments() {
        guard let copied = copiedAdjustments else {
            savedToast = "No adjustments copied"
            savedToastIsError = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if self.savedToast == "No adjustments copied" { self.savedToast = nil }
            }
            return
        }

        guard let url = imageLoader.currentImageURL else { return }

        applyCopiedEdits(copied, to: url)
        updateDisplayImage()

        let message = "Adjustments pasted"
        savedToast = message
        savedToastIsError = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if self.savedToast == message { self.savedToast = nil }
        }
    }
}
