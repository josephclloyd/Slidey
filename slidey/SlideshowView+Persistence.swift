import SwiftUI

extension SlideshowView {

    // Per-image session edits (rotation, flip, vignette, adjustments, crop, photo effect,
    // and editStacks) are intentionally not restored across app restarts — only
    // favouriteImages and denoiseURLLevels (a HUD slider convenience, applies nothing on
    // its own) persist. Every session edit's rendered result lives only in in-memory
    // caches that are never written to disk, so restoring just the "recipe" either
    // silently re-triggers recomputation (editStacks' bug) or shows a stale value with no
    // way to tell it apart from a fresh session. Drop any values a previous app version
    // may have persisted so they don't linger unused.
    func loadFavourites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "favouriteImages") {
            favouriteURLStrings = Set(saved)
        }
        denoiseURLLevels = (UserDefaults.standard.dictionary(forKey: "denoiseURLLevels") as? [String: Double]) ?? [:]
        for key in ["editStacks", "rotationAngles", "flippedHorizontally", "flippedVertically",
                    "vignetteURLLevels", "adjustmentURLLevels", "photoEffects", "cropRegions"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func saveFavourites() {
        UserDefaults.standard.set(Array(favouriteURLStrings), forKey: "favouriteImages")
        UserDefaults.standard.set(denoiseURLLevels, forKey: "denoiseURLLevels")
    }
}
