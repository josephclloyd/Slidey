import SwiftUI

extension SlideshowView {

    func loadFavourites() {
        if let saved = UserDefaults.standard.stringArray(forKey: "favouriteImages") {
            favouriteURLStrings = Set(saved)
        }
        if let saved = UserDefaults.standard.dictionary(forKey: "rotationAngles") as? [String: Double] {
            for (key, val) in saved {
                if let url = URL(string: key) {
                    rotationAngles[url] = Angle(degrees: val)
                }
            }
        }
        if let data = UserDefaults.standard.data(forKey: "editStacks"),
           let decoded = try? JSONDecoder().decode([String: EditStack].self, from: data) {
            editStacks = Dictionary(uniqueKeysWithValues: decoded.compactMap { key, val -> (URL, EditStack)? in
                guard let url = URL(string: key) else { return nil }
                return (url, val)
            })
        }
        denoiseURLLevels = (UserDefaults.standard.dictionary(forKey: "denoiseURLLevels") as? [String: Double]) ?? [:]
        flippedHorizontally = Set(UserDefaults.standard.stringArray(forKey: "flippedHorizontally") ?? [])
        flippedVertically = Set(UserDefaults.standard.stringArray(forKey: "flippedVertically") ?? [])
        vignetteURLLevels = (UserDefaults.standard.dictionary(forKey: "vignetteURLLevels") as? [String: Double]) ?? [:]
        if let data = UserDefaults.standard.data(forKey: "adjustmentURLLevels"),
           let decoded = try? JSONDecoder().decode([String: ImageAdjustments].self, from: data) {
            adjustmentURLLevels = decoded
        }
        let rawEffects = (UserDefaults.standard.dictionary(forKey: "photoEffects") as? [String: String]) ?? [:]
        imageEffects = Dictionary(uniqueKeysWithValues: rawEffects.compactMap { key, val -> (URL, String)? in
            guard let url = URL(string: key) else { return nil }
            return (url, val)
        })
        if let data = UserDefaults.standard.data(forKey: "cropRegions"),
           let decoded = try? JSONDecoder().decode([String: CropRegion].self, from: data) {
            cropRegions = decoded
        }
    }

    func saveFavourites() {
        UserDefaults.standard.set(Array(favouriteURLStrings), forKey: "favouriteImages")
        let rotDict = Dictionary(uniqueKeysWithValues: rotationAngles.map { ($0.key.absoluteString, $0.value.degrees) })
        UserDefaults.standard.set(rotDict, forKey: "rotationAngles")
        let editStacksDict = Dictionary(uniqueKeysWithValues: editStacks.map { ($0.key.absoluteString, $0.value) })
        if let data = try? JSONEncoder().encode(editStacksDict) {
            UserDefaults.standard.set(data, forKey: "editStacks")
        }
        UserDefaults.standard.set(denoiseURLLevels, forKey: "denoiseURLLevels")
        UserDefaults.standard.set(Array(flippedHorizontally), forKey: "flippedHorizontally")
        UserDefaults.standard.set(Array(flippedVertically), forKey: "flippedVertically")
        UserDefaults.standard.set(vignetteURLLevels, forKey: "vignetteURLLevels")
        if let data = try? JSONEncoder().encode(adjustmentURLLevels) {
            UserDefaults.standard.set(data, forKey: "adjustmentURLLevels")
        }
        let effectsDict = Dictionary(uniqueKeysWithValues: imageEffects.map { ($0.key.absoluteString, $0.value) })
        UserDefaults.standard.set(effectsDict, forKey: "photoEffects")
        if let data = try? JSONEncoder().encode(cropRegions) {
            UserDefaults.standard.set(data, forKey: "cropRegions")
        }
    }
}
