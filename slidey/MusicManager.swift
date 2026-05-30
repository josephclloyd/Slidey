import Foundation
import MusicKit
import SwiftUI
import Combine

enum MusicMode: String {
    case off
    case song
    case playlist
    case random
}

@MainActor
final class MusicManager: ObservableObject {
    @Published var musicMode: MusicMode = .off
    @Published var isAuthorized = false
    @Published var selectedSongTitle: String?
    @Published var selectedPlaylistName: String?
    @Published var currentTrackTitle: String?
    @Published var currentTrackArtist: String?
    @Published var showTrackOverlay = false
    @Published var authorizationDenied = false

    private var selectedSongID: String?
    private var selectedPlaylistID: String?
    private var lastConfiguredMode: MusicMode = .off
    private let player = ApplicationMusicPlayer.shared
    private var isActive = false
    private var overlayTask: Task<Void, Never>?
    private var queueObserver: AnyCancellable?

    init() {
        let modeStr = UserDefaults.standard.string(forKey: "musicMode") ?? "off"
        musicMode = MusicMode(rawValue: modeStr) ?? .off
        selectedSongID = UserDefaults.standard.string(forKey: "musicSongID")
        selectedPlaylistID = UserDefaults.standard.string(forKey: "musicPlaylistID")
        selectedSongTitle = UserDefaults.standard.string(forKey: "musicSongTitle")
        selectedPlaylistName = UserDefaults.standard.string(forKey: "musicPlaylistName")
        isAuthorized = MusicAuthorization.currentStatus == .authorized

        if let lastStr = UserDefaults.standard.string(forKey: "lastMusicMode"),
           let mode = MusicMode(rawValue: lastStr) {
            lastConfiguredMode = mode
        } else if musicMode != .off {
            lastConfiguredMode = musicMode
            UserDefaults.standard.set(musicMode.rawValue, forKey: "lastMusicMode")
        }

        queueObserver = player.queue.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in
                self?.handleTrackChange()
            }
        }
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        if isAuthorized { return true }
        let status = await MusicAuthorization.request()
        isAuthorized = status == .authorized
        if !isAuthorized { authorizationDenied = true }
        return isAuthorized
    }

    func setOff() {
        musicMode = .off
        UserDefaults.standard.set("off", forKey: "musicMode")
        player.stop()
    }

    func selectSong(_ song: Song) {
        selectedSongID = song.id.rawValue
        selectedSongTitle = song.title
        musicMode = .song
        lastConfiguredMode = .song
        UserDefaults.standard.set("song", forKey: "musicMode")
        UserDefaults.standard.set("song", forKey: "lastMusicMode")
        UserDefaults.standard.set(song.id.rawValue, forKey: "musicSongID")
        UserDefaults.standard.set(song.title, forKey: "musicSongTitle")
        if isActive { Task { await startPlayback() } }
    }

    func selectPlaylist(_ playlist: Playlist) {
        selectedPlaylistID = playlist.id.rawValue
        selectedPlaylistName = playlist.name
        musicMode = .playlist
        lastConfiguredMode = .playlist
        UserDefaults.standard.set("playlist", forKey: "musicMode")
        UserDefaults.standard.set("playlist", forKey: "lastMusicMode")
        UserDefaults.standard.set(playlist.id.rawValue, forKey: "musicPlaylistID")
        UserDefaults.standard.set(playlist.name, forKey: "musicPlaylistName")
        if isActive { Task { await startPlayback() } }
    }

    func setShuffle() {
        musicMode = .random
        lastConfiguredMode = .random
        UserDefaults.standard.set("random", forKey: "musicMode")
        UserDefaults.standard.set("random", forKey: "lastMusicMode")
        if isActive { Task { await startPlayback() } }
    }

    func resumeIfConfigured() {
        if musicMode != .off && isActive && player.state.playbackStatus == .playing {
            return
        }

        var modeToPlay = musicMode
        if modeToPlay == .off {
            guard lastConfiguredMode != .off else { return }
            modeToPlay = lastConfiguredMode
            musicMode = modeToPlay
            UserDefaults.standard.set(modeToPlay.rawValue, forKey: "musicMode")
        }

        if !isActive { isActive = true }
        Task { await startPlayback() }
    }

    func activate() {
        guard !isActive else { return }
        isActive = true
        guard musicMode != .off else { return }
        Task { await startPlayback() }
    }

    func deactivate() {
        isActive = false
        guard musicMode != .off else { return }
        player.pause()
    }

    func fetchSongs() async -> [Song] {
        do {
            let request = MusicLibraryRequest<Song>()
            let response = try await request.response()
            return Array(response.items).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
        } catch {
            return []
        }
    }

    func fetchPlaylists() async -> [Playlist] {
        do {
            let request = MusicLibraryRequest<Playlist>()
            let response = try await request.response()
            return Array(response.items).sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            return []
        }
    }

    private func startPlayback() async {
        guard isAuthorized else { return }
        do {
            switch musicMode {
            case .off:
                return

            case .song:
                guard let idStr = selectedSongID else { return }
                var request = MusicLibraryRequest<Song>()
                request.filter(matching: \.id, equalTo: MusicItemID(idStr))
                let response = try await request.response()
                guard let song = response.items.first else { return }
                player.queue = ApplicationMusicPlayer.Queue(for: [song])
                player.state.repeatMode = .one

            case .playlist:
                guard let idStr = selectedPlaylistID else { return }
                var request = MusicLibraryRequest<Playlist>()
                request.filter(matching: \.id, equalTo: MusicItemID(idStr))
                let response = try await request.response()
                guard let playlist = response.items.first else { return }
                let detailed = try await playlist.with(.tracks)
                if let tracks = detailed.tracks {
                    player.queue = ApplicationMusicPlayer.Queue(for: tracks)
                    player.state.repeatMode = .all
                }

            case .random:
                let request = MusicLibraryRequest<Song>()
                let response = try await request.response()
                guard !response.items.isEmpty else { return }
                player.queue = ApplicationMusicPlayer.Queue(for: response.items)
                player.state.shuffleMode = .songs
                player.state.repeatMode = .all
            }
            try await player.play()
        } catch {
            print("MusicManager: playback failed – \(error)")
        }
    }

    private func handleTrackChange() {
        let entry = player.queue.currentEntry
        let title = entry?.title
        let artist = entry?.subtitle

        guard title != currentTrackTitle || artist != currentTrackArtist else { return }
        currentTrackTitle = title
        currentTrackArtist = artist

        guard musicMode != .off, isActive, title != nil else { return }
        overlayTask?.cancel()
        withAnimation(.easeInOut(duration: 0.3)) { showTrackOverlay = true }
        overlayTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled {
                withAnimation(.easeInOut(duration: 0.3)) { showTrackOverlay = false }
            }
        }
    }
}

struct SongPickerView: View {
    let musicManager: MusicManager
    let onSelect: (Song) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var songs: [Song] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredSongs: [Song] {
        if searchText.isEmpty { return songs }
        return songs.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.artistName.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a Song")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            TextField("Search songs\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if isLoading {
                Spacer()
                ProgressView("Loading library\u{2026}")
                Spacer()
            } else if songs.isEmpty {
                Spacer()
                Text("No songs found in your Music library.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredSongs) { song in
                    Button {
                        onSelect(song)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(song.title)
                            Text(song.artistName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 450, height: 500)
        .task {
            songs = await musicManager.fetchSongs()
            isLoading = false
        }
    }
}

struct PlaylistPickerView: View {
    let musicManager: MusicManager
    let onSelect: (Playlist) -> Void
    @Environment(\.dismiss) var dismiss
    @State private var playlists: [Playlist] = []
    @State private var searchText = ""
    @State private var isLoading = true

    private var filteredPlaylists: [Playlist] {
        if searchText.isEmpty { return playlists }
        return playlists.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose a Playlist")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            TextField("Search playlists\u{2026}", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
                .padding(.bottom, 8)

            if isLoading {
                Spacer()
                ProgressView("Loading playlists\u{2026}")
                Spacer()
            } else if playlists.isEmpty {
                Spacer()
                Text("No playlists found in your Music library.")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filteredPlaylists) { playlist in
                    Button {
                        onSelect(playlist)
                        dismiss()
                    } label: {
                        Text(playlist.name)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 450, height: 500)
        .task {
            playlists = await musicManager.fetchPlaylists()
            isLoading = false
        }
    }
}
