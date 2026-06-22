import Foundation

extension NSNotification.Name {
    static let selectDirectory = NSNotification.Name("SelectDirectory")
    static let openDirectory = NSNotification.Name("OpenDirectory")

    static let enhanceImage = NSNotification.Name("EnhanceImage")
    static let removeEnhancement = NSNotification.Name("RemoveEnhancement")
    static let smoothImage = NSNotification.Name("SmoothImage")
    static let removeSmoothing = NSNotification.Name("RemoveSmoothing")
    static let upscaleImage = NSNotification.Name("UpscaleImage")
    static let removeUpscaling = NSNotification.Name("RemoveUpscaling")

    static let scaleToNative = NSNotification.Name("ScaleToNative")
    static let scaleToFill = NSNotification.Name("ScaleToFill")
    static let rotateClockwise = NSNotification.Name("RotateClockwise")
    static let rotateCounterClockwise = NSNotification.Name("RotateCounterClockwise")

    static let saveEditedImage = NSNotification.Name("SaveEditedImage")
    static let revealInFinder = NSNotification.Name("RevealInFinder")
    static let moveToTrash = NSNotification.Name("MoveToTrash")
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
}
