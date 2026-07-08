import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

extension SlideshowView {

    func exportWithEdits() {
        guard let url = imageLoader.currentImageURL else { return }
        guard let original = imageLoader.currentImage else { return }

        var image = currentComposite(for: url) ?? original

        let isFlippedH = flippedHorizontally.contains(url.absoluteString)
        let isFlippedV = flippedVertically.contains(url.absoluteString)
        if isFlippedH || isFlippedV {
            image = applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: image) ?? image
        }

        if let effectName = imageEffects[url] {
            image = applyPhotoEffect(effectName, to: image) ?? image
        }

        if let adj = adjustmentURLLevels[url.absoluteString], !adj.isIdentity {
            image = applyAdjustments(adj, to: image) ?? image
        }

        if let curves = curvesURLLevels[url.absoluteString], !curves.isIdentity {
            image = applyCurves(curves, to: image) ?? image
        }

        if let vigLevel = vignetteURLLevels[url.absoluteString], vigLevel > 0 {
            image = applyVignette(intensity: vigLevel, to: image) ?? image
        }

        if let sAngle = straightenAngles[url.absoluteString], sAngle != 0 {
            image = applyStraightenTransform(angle: sAngle, to: image) ?? image
        }

        if let cropRegion = cropRegions[url.absoluteString] {
            image = applyCropToImage(image, region: cropRegion) ?? image
        }

        image = applyRotationIfNeeded(image)

        let ext = url.pathExtension.lowercased()
        let baseName = url.deletingPathExtension().lastPathComponent
        let suggestedName = "\(baseName)-edited.\(ext.isEmpty ? "png" : ext)"
        let sourceType = UTType(filenameExtension: ext) ?? .png

        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [sourceType]
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            let outType = UTType(filenameExtension: destURL.pathExtension) ?? sourceType
            guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                showErrorToast("Could not encode image for export")
                return
            }
            guard let dest = CGImageDestinationCreateWithURL(
                destURL as CFURL, outType.identifier as CFString, 1, nil
            ) else {
                showErrorToast("Could not create image destination")
                return
            }
            CGImageDestinationAddImage(dest, cgImage, nil)
            if CGImageDestinationFinalize(dest) {
                showSavedToast(filename: destURL.lastPathComponent)
            } else {
                showErrorToast("Export failed")
            }
        }
    }
}
