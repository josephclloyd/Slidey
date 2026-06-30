import Foundation

extension NSNotification.Name {
    static let selectDirectory = NSNotification.Name("SelectDirectory")
    static let openDirectory = NSNotification.Name("OpenDirectory")

    static let enhanceImage = NSNotification.Name("EnhanceImage")
    static let removeEnhancement = NSNotification.Name("RemoveEnhancement")
    static let smoothImage = NSNotification.Name("SmoothImage")
    static let removeSmoothing = NSNotification.Name("RemoveSmoothing")
    static let sharpenImage = NSNotification.Name("SharpenImage")
    static let removeSharpening = NSNotification.Name("RemoveSharpening")
    static let denoiseImage = NSNotification.Name("DenoiseImage")
    static let applyPhotoEffect = NSNotification.Name("ApplyPhotoEffect")
    static let upscaleImage2x = NSNotification.Name("UpscaleImage2x")
    static let upscaleImage4x = NSNotification.Name("UpscaleImage4x")
    static let removeUpscaling = NSNotification.Name("RemoveUpscaling")

    static let scaleToNative = NSNotification.Name("ScaleToNative")
    static let scaleToFill = NSNotification.Name("ScaleToFill")
    static let rotateClockwise = NSNotification.Name("RotateClockwise")
    static let rotateCounterClockwise = NSNotification.Name("RotateCounterClockwise")

    static let saveEditedImage = NSNotification.Name("SaveEditedImage")
    static let revealInFinder = NSNotification.Name("RevealInFinder")
    static let openInPreview = NSNotification.Name("OpenInPreview")
    static let openWith = NSNotification.Name("OpenWith")
    static let moveToTrash = NSNotification.Name("MoveToTrash")
    static let copyToFolder = NSNotification.Name("CopyToFolder")
    static let moveToFolder = NSNotification.Name("MoveToFolder")
    static let renameImage = NSNotification.Name("RenameImage")
    static let copyImage = NSNotification.Name("CopyImage")
    static let copyFilePath = NSNotification.Name("CopyFilePath")

    static let toggleSlideshow = NSNotification.Name("ToggleSlideshow")
    static let toggleThumbnails = NSNotification.Name("ToggleThumbnails")
    static let toggleImageInfo = NSNotification.Name("ToggleImageInfo")

    static let musicOff = NSNotification.Name("MusicOff")
    static let musicChooseSong = NSNotification.Name("MusicChooseSong")
    static let musicChoosePlaylist = NSNotification.Name("MusicChoosePlaylist")
    static let musicShuffle = NSNotification.Name("MusicShuffle")

    static let toggleFavourite = NSNotification.Name("ToggleFavourite")
    static let toggleFavouritesOnly = NSNotification.Name("ToggleFavouritesOnly")

    static let showKeyboardShortcuts = NSNotification.Name("ShowKeyboardShortcuts")
    static let toggleSmartZoom = NSNotification.Name("ToggleSmartZoom")

    static let flipHorizontal = NSNotification.Name("FlipHorizontal")
    static let flipVertical = NSNotification.Name("FlipVertical")

    static let vignetteImage = NSNotification.Name("VignetteImage")

    static let adjustmentsImage = NSNotification.Name("AdjustmentsImage")

    static let restoreFaces = NSNotification.Name("RestoreFaces")
    static let removeFaceRestoration = NSNotification.Name("RemoveFaceRestoration")

    static let redEyeRemoval = NSNotification.Name("RedEyeRemoval")
    static let removeRedEye = NSNotification.Name("RemoveRedEye")

    static let removeBackground = NSNotification.Name("RemoveBackground")
    static let restoreBackground = NSNotification.Name("RestoreBackground")
}
