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

    static let captureVideoFrame = NSNotification.Name("CaptureVideoFrame")

    static let saveEditedImage = NSNotification.Name("SaveEditedImage")
    static let exportWithEdits = NSNotification.Name("ExportWithEdits")
    static let revealInFinder = NSNotification.Name("RevealInFinder")
    static let openInPreview = NSNotification.Name("OpenInPreview")
    static let openWith = NSNotification.Name("OpenWith")
    static let moveToTrash = NSNotification.Name("MoveToTrash")
    static let copyToFolder = NSNotification.Name("CopyToFolder")
    static let moveToFolder = NSNotification.Name("MoveToFolder")
    static let exportVisibleImages = NSNotification.Name("ExportVisibleImages")
    static let exportSlideshowVideo = NSNotification.Name("ExportSlideshowVideo")
    static let renameImage = NSNotification.Name("RenameImage")
    static let copyImage = NSNotification.Name("CopyImage")
    static let copyFilePath = NSNotification.Name("CopyFilePath")

    static let toggleSlideshow = NSNotification.Name("ToggleSlideshow")
    static let toggleThumbnails = NSNotification.Name("ToggleThumbnails")
    static let toggleGridView = NSNotification.Name("ToggleGridView")
    static let toggleImageInfo = NSNotification.Name("ToggleImageInfo")
    static let toggleHistogram = NSNotification.Name("ToggleHistogram")

    static let musicOff = NSNotification.Name("MusicOff")
    static let musicChooseSong = NSNotification.Name("MusicChooseSong")
    static let musicChoosePlaylist = NSNotification.Name("MusicChoosePlaylist")
    static let musicShuffle = NSNotification.Name("MusicShuffle")

    static let toggleFavourite = NSNotification.Name("ToggleFavourite")
    static let toggleFavouritesOnly = NSNotification.Name("ToggleFavouritesOnly")
    static let toggleSearchBar = NSNotification.Name("ToggleSearchBar")
    static let showFilterPresets = NSNotification.Name("ShowFilterPresets")

    static let showKeyboardShortcuts = NSNotification.Name("ShowKeyboardShortcuts")
    static let showToolsGuide = NSNotification.Name("ShowToolsGuide")
    static let toggleShortcutsOverlay = NSNotification.Name("ToggleShortcutsOverlay")
    static let toggleSmartZoom = NSNotification.Name("ToggleSmartZoom")
    static let compareSideBySide = NSNotification.Name("CompareSideBySide")
    static let compareChooseRightPane = NSNotification.Name("CompareChooseRightPane")
    static let beforeAfterSlider = NSNotification.Name("BeforeAfterSlider")
    static let toggleFullScreen = NSNotification.Name("ToggleFullScreen")
    static let zoomIn = NSNotification.Name("ZoomIn")
    static let zoomOut = NSNotification.Name("ZoomOut")

    static let flipHorizontal = NSNotification.Name("FlipHorizontal")
    static let flipVertical = NSNotification.Name("FlipVertical")

    static let vignetteImage = NSNotification.Name("VignetteImage")

    static let selectiveColourImage = NSNotification.Name("SelectiveColourImage")
    static let removeSelectiveColour = NSNotification.Name("RemoveSelectiveColour")

    static let adjustmentsImage = NSNotification.Name("AdjustmentsImage")

    static let curvesImage = NSNotification.Name("CurvesImage")

    static let restoreFaces = NSNotification.Name("RestoreFaces")
    static let removeFaceRestoration = NSNotification.Name("RemoveFaceRestoration")

    static let redEyeRemoval = NSNotification.Name("RedEyeRemoval")
    static let removeRedEye = NSNotification.Name("RemoveRedEye")

    static let removeBackground = NSNotification.Name("RemoveBackground")
    static let restoreBackground = NSNotification.Name("RestoreBackground")

    static let removeArtifacts = NSNotification.Name("RemoveArtifacts")
    static let restoreArtifacts = NSNotification.Name("RestoreArtifacts")

    static let jpegCleanupImage = NSNotification.Name("JPEGCleanupImage")
    static let removeJPEGCleanup = NSNotification.Name("RemoveJPEGCleanup")

    static let grainReductionImage = NSNotification.Name("GrainReductionImage")
    static let removeGrainReduction = NSNotification.Name("RemoveGrainReduction")

    static let colorizeImage = NSNotification.Name("ColorizeImage")
    static let removeColorization = NSNotification.Name("RemoveColorization")

    static let cropImage = NSNotification.Name("CropImage")
    static let removeCrop = NSNotification.Name("RemoveCrop")

    static let straightenImage = NSNotification.Name("StraightenImage")
    static let removeStraighten = NSNotification.Name("RemoveStraighten")

    static let perspectiveCorrection = NSNotification.Name("PerspectiveCorrection")
    static let removePerspectiveCorrection = NSNotification.Name("RemovePerspectiveCorrection")

    static let localAdjustmentsImage = NSNotification.Name("LocalAdjustmentsImage")
    static let removeLocalAdjustments = NSNotification.Name("RemoveLocalAdjustments")

    static let objectRemovalImage = NSNotification.Name("ObjectRemovalImage")
    static let removeObjectRemoval = NSNotification.Name("RemoveObjectRemoval")

    static let shareImage = NSNotification.Name("ShareImage")
    static let setDesktopPicture = NSNotification.Name("SetDesktopPicture")
    static let printImage = NSNotification.Name("PrintImage")

    static let copyAdjustments = NSNotification.Name("CopyAdjustments")
    static let pasteAdjustments = NSNotification.Name("PasteAdjustments")

    static let batchApplyAll = NSNotification.Name("BatchApplyAll")
    static let batchApplyFavourites = NSNotification.Name("BatchApplyFavourites")

    static let editMetadata = NSNotification.Name("EditMetadata")
}
