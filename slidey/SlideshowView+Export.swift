import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO

extension SlideshowView {

    /// Applies every re-appliable per-URL edit (flip, photo effect, local
    /// adjustments, adjustments, curves, vignette, straighten, perspective,
    /// crop, rotation) on top of a base image, in the same order the single-image
    /// export uses. Pixel-cached ML edits (enhance/upscale/etc.) are not included
    /// here — pass a base that already has them baked in when needed.
    func applyExportEdits(to base: NSImage, for url: URL) -> NSImage {
        var image = base

        let isFlippedH = flippedHorizontally.contains(url.absoluteString)
        let isFlippedV = flippedVertically.contains(url.absoluteString)
        if isFlippedH || isFlippedV {
            image = applyFlipTransform(horizontal: isFlippedH, vertical: isFlippedV, to: image) ?? image
        }

        if let effectName = imageEffects[url] {
            image = applyPhotoEffect(effectName, to: image) ?? image
        }

        if let layers = localAdjustmentURLLayers[url.absoluteString], !layers.isEmpty {
            image = applyLocalAdjustmentLayers(layers, to: image) ?? image
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

        if let selective = selectiveColourURLLevels[url.absoluteString] {
            image = applySelectiveColour(selective, to: image) ?? image
        }

        if let sAngle = straightenAngles[url.absoluteString], sAngle != 0 {
            image = applyStraightenTransform(angle: sAngle, to: image) ?? image
        }

        if let corners = perspectiveCorners[url.absoluteString] {
            image = applyPerspectiveTransform(corners: corners, to: image) ?? image
        }

        if let cropRegion = cropRegions[url.absoluteString] {
            image = applyCropToImage(image, region: cropRegion) ?? image
        }

        return image
    }

    func exportWithEdits() {
        guard let url = imageLoader.currentImageURL else { return }
        guard let original = imageLoader.currentImage else { return }

        var image = currentComposite(for: url) ?? original
        image = applyExportEdits(to: image, for: url)
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
