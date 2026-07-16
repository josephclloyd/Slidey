import SwiftUI
import AppKit

extension SlideshowView {

    @ViewBuilder
    func attachFileNotifications<Content: View>(_ content: Content) -> some View {
        content
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.saveEditedImage)) { _ in
            ifKeyWindow { saveEditedImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.exportWithEdits)) { _ in
            ifKeyWindow { exportWithEdits() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleSlideshow)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                toggleSlideshow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleThumbnails)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                showThumbnails.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleImageInfo)) { _ in
            ifKeyWindow { toggleInfoOverlay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.renameImage)) { _ in
            ifKeyWindow { renameCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.moveToTrash)) { _ in
            ifKeyWindow { moveCurrentImageToTrash() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyToFolder)) { _ in
            ifKeyWindow { copyCurrentImageToFolder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.moveToFolder)) { _ in
            ifKeyWindow { moveCurrentImageToFolder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.exportVisibleImages)) { _ in
            ifKeyWindow { exportVisibleImages() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyImage)) { _ in
            ifKeyWindow { copyImageToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyFilePath)) { _ in
            ifKeyWindow { copyFilePathToClipboard() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.revealInFinder)) { _ in
            ifKeyWindow { revealCurrentImageInFinder() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.openInPreview)) { _ in
            ifKeyWindow { openCurrentImageInDefaultApp() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.openWith)) { _ in
            ifKeyWindow { showOpenWithMenu() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.setDesktopPicture)) { _ in
            ifKeyWindow { setAsDesktopPicture() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.shareImage)) { _ in
            ifKeyWindow { showShareSheet() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.printImage)) { _ in
            ifKeyWindow { printCurrentImage() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleFavourite)) { _ in
            ifKeyWindow { toggleFavourite() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleFavouritesOnly)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                toggleShowFavouritesOnly()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.toggleShortcutsOverlay)) { _ in
            ifKeyWindow { showShortcutsOverlay.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.showKeyboardShortcuts)) { _ in
            showKeyboardShortcuts = true
        }
        .sheet(isPresented: $showKeyboardShortcuts) {
            KeyboardShortcutsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.showToolsGuide)) { _ in
            showToolsGuide = true
        }
        .sheet(isPresented: $showToolsGuide) {
            ToolsGuideView()
        }
    }

    @ViewBuilder
    func attachMusicAndMiscNotifications<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: slideshowInterval) { _, _ in
            if slideshow.isPlaying { slideshow.reschedule(interval: slideshowInterval, advance: makeAdvanceClosure()) }
        }
        .onChange(of: shuffleOnAdvance) { _, newValue in
            if newValue && slideshow.isPlaying {
                slideshow.seedShuffleQueue(from: imageLoader.imageURLs, excluding: imageLoader.currentImageURL)
            } else if !newValue {
                slideshow.resetShuffleQueue()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                isFullScreen = false
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = true
                updateCursorVisibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window == myWindow {
                windowHasFocus = false
                showingOriginal = false
                updateCursorVisibility()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicOff)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                musicManager.setOff()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicChooseSong)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    showSongPicker = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicChoosePlaylist)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    showPlaylistPicker = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.musicShuffle)) { _ in
            if myWindow == nil || myWindow?.isKeyWindow == true {
                Task {
                    guard await musicManager.requestAuthorizationIfNeeded() else { return }
                    musicManager.setShuffle()
                }
            }
        }
        .sheet(isPresented: $showSongPicker) {
            SongPickerView(musicManager: musicManager) { song in
                musicManager.selectSong(song)
            }
        }
        .sheet(isPresented: $showPlaylistPicker) {
            PlaylistPickerView(musicManager: musicManager) { playlist in
                musicManager.selectPlaylist(playlist)
            }
        }
        .alert("Music Access Required", isPresented: $musicManager.authorizationDenied) {
            Button("OK") {}
        } message: {
            Text("""
            Slidey needs access to your Music library to play background music. \
            You can grant access in System Settings > Privacy & Security > Media & Apple Music.
            """)
        }
        .alert("No Faces Detected", isPresented: $showNoFaceAlert) {
            Button("OK") {}
        } message: {
            Text("No faces were found in this image.")
        }
        .alert("No Red-Eye Detected", isPresented: $showNoRedEyeDetectedAlert) {
            Button("OK") {}
        } message: {
            Text("Faces were found but no red-eye was detected in this image.")
        }
        .alert("Image Appears to Be in Color", isPresented: $showColorConfirmAlert) {
            Button("Colorize Anyway") { colorizeCurrentImage(force: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This image appears to already be in color. Colorization is designed for grayscale/B&W photos and may produce unexpected results on color images.")
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.batchApplyAll)) { _ in
            ifKeyWindow { batchApplyEdits(favouritesOnly: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.batchApplyFavourites)) { _ in
            ifKeyWindow { batchApplyEdits(favouritesOnly: true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.copyAdjustments)) { _ in
            ifKeyWindow { copyCurrentAdjustments() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.pasteAdjustments)) { _ in
            ifKeyWindow { pasteAdjustments() }
        }
        .focusedSceneValue(\.hasCurrentImage, imageLoader.currentImageURL != nil)
    }
}
