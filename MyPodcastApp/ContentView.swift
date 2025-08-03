//
//  ContentView.swift
//  MyPodcastApp
//
//  Created by Byron on 2025-06-25.
//

import SwiftUI
import Foundation
import AVFoundation
import Combine


//MARK: - Models

struct Podcast: Identifiable, Codable {
    let id = UUID()
    let collectionName: String
    let artistName: String
    let artworkUrl600: String
    let feedUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case collectionName, artistName, artworkUrl600, feedUrl
    }
}

struct Episode: Identifiable {
    var id: String
    let title: String
    let pubDate: Date?
    let audioURL: String
    let duration: String?
    let imageURL: String?
    let podcastImageURL: String?
    let description: String?
    let podcastName: String?
    
    init(title: String, pubDate: Date?, audioURL: String, duration: String?, imageURL: String?, podcastImageURL: String?, description: String?, podcastName: String?) {
        self.id = audioURL
        self.title = title
        self.pubDate = pubDate
        self.audioURL = audioURL
        self.duration = duration
        self.imageURL = imageURL
        self.podcastImageURL = podcastImageURL
        self.description = description
        self.podcastName = podcastName
    }
    
    var durationInMinutes: String? {
        guard let duration = duration else { return nil }
        
        let parts = duration.split(separator: ":").map { Int($0) ?? 0 }
        
        let totalSeconds: Int
        switch parts.count {
        case 3:
            totalSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
        case 2:
            totalSeconds = parts[0] * 60 + parts[1]
        case 1:
            totalSeconds = parts[0]
        default:
            return nil
        }
        
        let roundedMinutes = Int(round(Double(totalSeconds) / 60.0))
        let hours = roundedMinutes / 60
        let minutes = roundedMinutes % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

struct SearchResults: Decodable {
    let results: [Podcast]
}


//MARK: - ViewModels

@MainActor
class PodcastSearchViewModel: ObservableObject {
    @Published var podcasts: [Podcast] = []
    
    func search(term: String){
        let searchTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?media=podcast&term=\(searchTerm)"
        
        guard let url = URL(string: urlString) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data else {
                print("No data or error: \(String(describing: error))")
                return
            }
            
            do {
                let decoded = try JSONDecoder().decode(SearchResults.self, from: data)
                DispatchQueue.main.async {
                    self.podcasts = decoded.results
                    print("Decoded \(decoded.results.count) podcasts")
                }
            } catch {
                print("Failed to decode: \(error)")
            }
        }.resume()
    }
    
}

//MARK: - RSSParser
class RSSParser: NSObject, XMLParserDelegate {
    var episodes: [Episode] = []
    var currentElement = ""
    var currentTitle = ""
    var currentAudioURL = ""
    var currentPubDate = ""
    var duration = ""
    var imageURL = ""
    var currentDescription = ""
    var insideItem = false
    var podcastImageURL = ""
    var podcastName = ""
    
    func parse(data: Data) -> [Episode] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return episodes
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            insideItem = true
            currentTitle = ""
            currentAudioURL = ""
            currentPubDate = ""
            duration = ""
            imageURL = ""
            currentDescription = ""
        }
        if insideItem && elementName == "enclosure", let url = attributeDict["url"] {
            currentAudioURL = url
        }
        if elementName == "itunes:image", let href = attributeDict["href"] {
            imageURL = href
        }
        if !insideItem && elementName == "itunes:image", let href = attributeDict["href"] {
            podcastImageURL = href
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideItem && currentElement == "title" {
            currentTitle += string
        }
        if currentElement == "pubDate" {
            currentPubDate += string
        }
        if currentElement == "itunes:duration" {
            duration += string
        }
        if currentElement == "description" {
            currentDescription += string
        }
        if !insideItem && currentElement == "title" {
            podcastName += string
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item" {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "E, d MMM yyyy HH:mm:ss Z"
            let trimmedDateString = currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)
            let date = formatter.date(from: trimmedDateString)
            episodes.append(Episode(
                title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                pubDate: date,
                audioURL: currentAudioURL,
                duration: duration.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURL: imageURL.isEmpty ? nil : imageURL,
                podcastImageURL: podcastImageURL,
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                podcastName: podcastName
            ))
            insideItem = false
        }
    }
}

//MARK: - AudioPlayerViewModel
@MainActor
class AudioPlayerViewModel: ObservableObject {
    static let shared = AudioPlayerViewModel()
    private let elapsedTimesKey = "episodeElapsedTimes"
    
    private var timeObserverToken: Any?
    private var player: AVPlayer?
    
    @Published var episode: Episode?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var durationTime: Double = 0
    @Published var currentEpisodeID: String? = nil
    @Published var isPlayerSheetVisible: Bool = false
    @Published var showMiniPlayer: Bool = false
    @Published var podcastImageURL: String?
    @Published var episodeQueue: [Episode] = []
    @Published private(set) var elapsedTimes: [String: Double] = [:]
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: elapsedTimesKey),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.elapsedTimes = saved
        }
    }
    
    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }
    
    func load(episode: Episode, podcastImageURL: String? = nil) {
        if self.episode?.audioURL == episode.audioURL { return }
        
        self.episode = episode
        self.currentEpisodeID = episode.id
        self.podcastImageURL = podcastImageURL
        
        guard let url = URL(string: episode.audioURL) else { return }
        
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.isPlaying = false
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
        
        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite {
                    self.durationTime = seconds
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }
        
        addPeriodicTimeObserver()
        
        if let savedTime = elapsedTimes[episode.audioURL], savedTime > 0 {
            let cmTime = CMTime(seconds: savedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime)
        }
    }
    
    @MainActor
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.currentTime = time.seconds
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            savePlaybackProgress()
        } else {
            player.play()
            isPlaying = true
            showMiniPlayer = true
        }
    }
    
    func skipForward(seconds: Double = 15) {
        guard let player = player else { return }
        let current = player.currentTime()
        let newTime = CMTime(seconds: current.seconds + seconds, preferredTimescale: current.timescale)
        player.seek(to: newTime)
    }
    
    func skipBackward(seconds: Double = 15) {
        guard let player = player else { return }
        let current = player.currentTime()
        let newTime = CMTime(seconds: max(current.seconds - seconds, 0), preferredTimescale: current.timescale)
        player.seek(to: newTime)
    }
    
    func seek(to time: CMTime) {
        player?.seek(to: time)
    }
    
    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", mins, secs)
    }
    
    @objc private func playerDidFinishPlaying(notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            self.isPlaying = false
            self.currentTime = 0
            self.showMiniPlayer = false
            self.isPlayerSheetVisible = false
            
            if !episodeQueue.isEmpty {
                let nextEpisode = episodeQueue.removeFirst()
                self.load(episode: nextEpisode, podcastImageURL: self.podcastImageURL)
                self.play()
            } else {
                self.player?.seek(to: .zero)
            }
        }
    }
    
    func addToQueue(_ episode: Episode) {
        guard episode.id != self.episode?.id,
              !episodeQueue.contains(where: { $0.id == episode.id }) else {
            return
        }
        episodeQueue.append(episode)
    }
    
    func play() {
        player?.play()
        isPlaying = true
        showMiniPlayer = true
    }
    
    private func saveElapsedTimes() {
        if let data = try? JSONEncoder().encode(elapsedTimes) {
            UserDefaults.standard.set(data, forKey: elapsedTimesKey)
        }
    }
    
    private func savePlaybackProgress() {
        if let current = self.episode {
            elapsedTimes[current.audioURL] = currentTime
            saveElapsedTimes()
        }
    }
}

//MARK: - LibraryViewModel
@MainActor
class LibraryViewModel: ObservableObject {
    @Published var subscriptions: [Podcast] = []
    
    private let subscriptionsKey = "subscribedPodcasts"
    
    init() {
        loadSubscriptions()
    }
    
    func subscribe(to podcast: Podcast) {
        if !subscriptions.contains(where: { $0.collectionName == podcast.collectionName }) {
            subscriptions.append(podcast)
            saveSubscriptions()
        }
    }
    
    func unsubscribe(from podcast: Podcast) {
        subscriptions.removeAll { $0.collectionName == podcast.collectionName }
        saveSubscriptions()
    }
    
    private func saveSubscriptions() {
        if let data = try? JSONEncoder().encode(subscriptions) {
            UserDefaults.standard.set(data, forKey: subscriptionsKey)
        }
    }
    
    private func loadSubscriptions() {
        if let data = UserDefaults.standard.data(forKey: subscriptionsKey),
           let decoded = try? JSONDecoder().decode([Podcast].self, from: data) {
            subscriptions = decoded
        }
    }
}


//MARK: - Views

enum Tab {
    case home, search, library, settings
}

//MARK: - ContentView
struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @StateObject private var libraryVM = LibraryViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                Text("Home").tabItem {
                    Label("Home", systemImage: "house")
                }
                SearchView().tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                LibraryView().tabItem {
                    Label("Library", systemImage: "book.fill")
                }
                Text("Settings").tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                QueueView().tabItem {
                    Label("Queue", systemImage: "text.badge.plus")
                }
            }
            if audioVM.showMiniPlayer {
                MiniPlayerView()
                    .transition(.move(edge: .bottom))
                    .padding(.bottom, 49)
            }
        }
        .environmentObject(libraryVM)
        //      .animation(.easeInOut, value: audioVM.showMiniPlayer)
    }
}

//MARK: - SearchView
struct SearchView: View {
    @StateObject var fetcher = PodcastSearchViewModel()
    @State private var searchText: String = ""
    
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search podcasts...", text: $searchText, onCommit: {
                    fetcher.search(term: searchText)
                })
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
                
                List(fetcher.podcasts) { podcast in
                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                        HStack {
                            AsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                                image.resizable()
                            } placeholder: {
                                Color.gray
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black, lineWidth: 0.5))
                            
                            VStack(alignment: .leading) {
                                Text(podcast.collectionName)
                                    .font(.headline)
                                Text(podcast.artistName)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
            
            .navigationTitle("Search")
        }
    }
}

//MARK: - PodcastDetailView
struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    @EnvironmentObject var libraryVM: LibraryViewModel
    
    var body: some View {
        List {
            Section {
                ZStack {
                    Color.white // Match app background
                    VStack(spacing: 12) {
                        if let imageUrl = URL(string: podcast.artworkUrl600) {
                            AsyncImage(url: imageUrl) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 200)
                                    .cornerRadius(16)
                                    .shadow(radius: 6)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                                    .frame(width: 200, height: 200)
                                    .cornerRadius(16)
                            }
                        }
                        Text(podcast.collectionName)
                            .font(.title)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Text("\(episodes.count) episodes")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Button(action: {
                            if libraryVM.subscriptions.contains(where: { $0.collectionName == podcast.collectionName }) {
                                libraryVM.unsubscribe(from: podcast)
                            } else {
                                libraryVM.subscribe(to: podcast)
                            }
                        }) {
                            Text(libraryVM.subscriptions.contains(where: { $0.collectionName == podcast.collectionName }) ? "Unsubscribe" : "Subscribe")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        Divider()
                            .padding(.top, 4)
                    }
      //              .frame(maxWidth: .infinity)
       //             .padding(.vertical)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            
            ForEach(episodes) { episode in
                NavigationLink(destination: EpisodeDetailView(episode: episode, podcastTitle: podcast.collectionName, podcastImageURL: podcast.artworkUrl600)) {
                    HStack(alignment: .top, spacing: 10) {
                        if let imageURL = episode.imageURL, let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.2), lineWidth: 0.5))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                                .font(.headline)
                            
                            HStack(spacing: 8) {
                                if let pubDate = episode.pubDate {
                                    Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                                } else {
                                    Text("Date not available")
                                }
                                
                                if let duration = episode.durationInMinutes {
                                    Text("• \(duration)")
                                }
                            }
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
 //       .navigationTitle(podcast.collectionName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let feedUrl = podcast.feedUrl {
                fetchEpisodes(from: feedUrl)
            }
        }
    }
    
    func fetchEpisodes(from feedUrl: String) {
        guard let url = URL(string: feedUrl) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data else {
                print("Error fetching data: \(error?.localizedDescription ?? "Unknown error")")
                return
            }
            
            let parser = RSSParser()
            let result = parser.parse(data: data)
            DispatchQueue.main.async {
                self.episodes = result
            }
        }.resume()
    }
}

//MARK: - EpisodeDetailView
struct EpisodeDetailView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    
    let episode: Episode
    let podcastTitle: String
    let podcastImageURL: String?
    
    var isCurrentlyPlaying: Bool {
        audioVM.episode?.id == episode.id && audioVM.isPlaying
    }
    
    var isInQueue: Bool {
        audioVM.episodeQueue.contains(where: { $0.id == episode.id })
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let imageURL = episode.imageURL ?? podcastImageURL,
                   let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 6)
  //                  .overlay(RoundedRectangle(cornerRadius: 16)
  //                      .stroke(Color.black, lineWidth: 0.5))
                    .padding(.top)
                }
                HStack(spacing: 8) {
                    if let pubDate = episode.pubDate {
                        Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("Date not available")
                    }
                    if let duration = episode.durationInMinutes {
                        Text("• \(duration)")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                
                Text(episode.title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(podcastTitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                ZStack {
                    Button(action: {
                        if audioVM.episode?.id == episode.id {
                            audioVM.togglePlayPause()
                        } else {
                            AudioPlayerViewModel.shared.addToQueue(episode)
                            audioVM.load(episode: episode, podcastImageURL: podcastImageURL)
                            audioVM.togglePlayPause()
                        }
                        audioVM.showMiniPlayer = true
                    }) {
                        Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                    }
                }
                
                Button(action: {
                    if isInQueue {
                        audioVM.episodeQueue.removeAll { $0.id == episode.id }
                    } else {
                        audioVM.addToQueue(episode)
                    }
                }) {
                    Label(
                        isInQueue ? "Remove from Queue" : "Add to Queue",
                        systemImage: isInQueue ? "text.badge.minus" : "text.badge.plus"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(isInQueue ? .red : .blue)
                
                Divider()
                
                var parsedDescription: AttributedString? {
                    guard let desc = episode.description,
                          let data = desc.data(using: .utf8) else { return nil }
                    
                    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                        .documentType: NSAttributedString.DocumentType.html,
                        .characterEncoding: String.Encoding.utf8.rawValue
                    ]
                    
                    if let nsAttrStr = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
                       var swiftUIAttrStr = try? AttributedString(nsAttrStr, including: \.uiKit) {
                        
                        for run in swiftUIAttrStr.runs {
                            swiftUIAttrStr[run.range].font = .system(size: 16)
                        }
                        
                        return swiftUIAttrStr
                    }
                    
                    return nil
                }
                
                if let description = parsedDescription {
                    Text(description)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $audioVM.isPlayerSheetVisible) {
            EpisodePlayerView(
                episode: episode,
                podcastTitle: podcastTitle,
                podcastImageURL: podcastImageURL
            )
        }
    }
}

//MARK: - EpisodePlayerView
struct EpisodePlayerView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    
    let episode: Episode
    let podcastTitle: String
    let podcastImageURL: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    audioVM.isPlayerSheetVisible = false
                }) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .padding()
                }
            }
        }
        ScrollView {
            VStack(spacing: 10) {
                if let imageURL = episode.imageURL ?? podcastImageURL,
                   let url = URL(string: imageURL) {
                    AsyncImage(url: url) { image in
                        image.resizable()
                    } placeholder: {
                        Color.gray
                    }
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black, lineWidth: 0.5))
                    .padding(.top)
                }
                HStack(spacing: 8) {
                    if let pubDate = episode.pubDate {
                        Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        Text("Date not available")
                    }
                    if let duration = episode.durationInMinutes {
                        Text("• \(duration)")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                
                Text(episode.title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Text(podcastTitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                
                HStack(spacing: 30) {
                    Button(action: { audioVM.skipBackward() }) {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                    }
                    Button(action: {
                        if audioVM.episode?.id != episode.id {
                            audioVM.load(episode: episode)
                        }
                        audioVM.togglePlayPause() }) {
                            Image(systemName: audioVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 100))
                        }
                    Button(action: { audioVM.skipForward() }) {
                        Image(systemName: "goforward.15")
                            .font(.title)
                    }
                }
                
                VStack(spacing: 12) {
                    HStack {
                        Text(audioVM.formattedTime(audioVM.currentTime))
                        Slider(value: $audioVM.currentTime, in: 0...audioVM.durationTime, onEditingChanged: { isEditing in
                            if !isEditing {
                                let newTime = CMTime(seconds: audioVM.currentTime, preferredTimescale: 1)
                                audioVM.seek(to: newTime)
                            }
                        })
                        Text(audioVM.formattedTime(audioVM.durationTime - audioVM.currentTime))
                    }
                    .font(.caption)
                    .padding(.horizontal)
                }
                
                Divider()
                
                if let desc = episode.description {
                    Text(desc)
                        .font(.body)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle("Now Playing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//MARK: - MiniPlayerView
struct MiniPlayerView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    
    var body: some View {
        if audioVM.episode != nil {
            ZStack {
                HStack {
                    if let url = URL(string: audioVM.podcastImageURL ?? "") {
                        AsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .frame(width: 40, height: 40)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black, lineWidth: 0.5)
                        )
                    }
                    
                    Spacer()
                    
                }
                
                HStack(spacing: 24) {
                    Button(action: {
                        audioVM.skipBackward()
                    }) {
                        Image(systemName: "gobackward")
                            .foregroundColor(.primary)
                    }
                    
                    Button(action: {
                        audioVM.togglePlayPause()
                    }) {
                        Image(systemName: audioVM.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundColor(.primary)
                            .font(.title)
                    }
                    
                    Button(action: {
                        audioVM.skipForward()
                    }) {
                        Image(systemName: "goforward")
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .onTapGesture {
                audioVM.isPlayerSheetVisible = true
            }
        }
    }
} 

//MARK: - LibraryView
struct LibraryView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    
    var body: some View {
        NavigationStack {
            List(libraryVM.subscriptions) { podcast in
                NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                    HStack {
                        AsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black, lineWidth: 0.5)
                        )
                        
                        VStack(alignment: .leading) {
                            Text(podcast.collectionName)
                                .font(.headline)
                            Text(podcast.artistName)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Library")
        }
    }
}

//MARK: - QueueView
/*
struct QueueView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @State private var isEditing = false
    
    private var reorderableQueue: [Episode] {
        audioVM.episodeQueue.filter { $0.id != audioVM.episode?.id }
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                if audioVM.episodeQueue.isEmpty && audioVM.episode == nil {
                    Spacer()
                    VStack {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                            .padding(.bottom, 10)
                        Text("Add podcasts to your queue")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // ✅ Now Playing Section
                /*            if let nowPlaying = audioVM.episode {
                                VStack(alignment: .leading) {
                                    Text("Now Playing")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                    
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: nowPlaying.podcastImageURL ?? "")) { phase in
                                            switch phase {
                                            case .empty:
                                                Color.gray
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            case .failure:
                                                Color.gray
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        
                                        Text(nowPlaying.title)
                                            .font(.headline)
                                            .lineLimit(2)
                                        
                                        Spacer()
                                    }
                                    .padding()
                                    .contentShape(Rectangle()) // ← ensures full row is tappable
                                    .onTapGesture {
                                        audioVM.isPlayerSheetVisible = true
                                    }
                                    
                                    if !reorderableQueue.isEmpty {
                                                Divider()
                                                    .padding(.top, 4)

                                                Text("Queue")
                                                    .font(.subheadline)
                                                    .foregroundColor(.gray)
                                                    .padding(.horizontal)
                                                    .padding(.bottom, 4)
                                            }
                                }
                            } */
                            if let nowPlaying = audioVM.episode {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Now Playing")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .padding(.horizontal)
                                        .padding(.top)

                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: nowPlaying.podcastImageURL ?? "")) { phase in
                                            switch phase {
                                            case .empty:
                                                Color.gray
                                                    .frame(width: 60, height: 60)
                                                    .cornerRadius(8)
                                            case .success(let image):
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .cornerRadius(8)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.black, lineWidth: 0.5)
                                                    )
                                            case .failure:
                                                Color.gray
                                                    .frame(width: 60, height: 60)
                                                    .cornerRadius(8)
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }

                                        Text(nowPlaying.title)
                                            .font(.headline)
                                            .lineLimit(2)

                                        Spacer()
                                    }
                                    .padding()
                                    .contentShape(Rectangle()) // ensure full row is tappable
                                    .onTapGesture {
                                        audioVM.isPlayerSheetVisible = true
                                    }

                                    // ✅ Only show this if the queue has items
                                    if !reorderableQueue.isEmpty {
                                        Divider()
                                            .padding(.horizontal)
                                            .padding(.top, 4)

                                        Text("Queue")
                                            .font(.subheadline)
                                            .foregroundColor(.gray)
                                            .padding(.horizontal)
                                            .padding(.vertical, 6)
                                    }
                                }
                            }
                            
                            // ✅ Queue List (excluding currently playing)
                            List {
                                ForEach(Array(reorderableQueue.enumerated()), id: \.element.id) { index, episode in
                                    HStack(spacing: 12) {
                                        AsyncImage(url: URL(string: episode.podcastImageURL ?? "")) { phase in
                                            switch phase {
                                            case .empty:
                                                Color.gray
                                            case .success(let image):
                                                image.resizable().scaledToFill()
                                            case .failure:
                                                Color.gray
                                            @unknown default:
                                                EmptyView()
                                            }
                                        }
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        
                                        Text(episode.title)
                                            .font(.headline)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 4)
                                    .contentShape(Rectangle())
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            audioVM.episodeQueue.removeAll { $0.id == episode.id }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                    .onDrag {
                                        NSItemProvider(object: String(index) as NSString)
                                    }
                                }
                                .onMove(perform: moveEpisode)
                                .moveDisabled(false)
                            }
                            .listStyle(.plain)
                            .frame(minHeight: 300) // avoids collapse when list is short
                            .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
                        }
                    }
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !audioVM.episodeQueue.isEmpty {
                        Button(isEditing ? "Done" : "Reorder") {
                            isEditing.toggle()
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !audioVM.episodeQueue.isEmpty {
                        Button("Clear") {
                            audioVM.episodeQueue.removeAll()
                        }
                        .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private func moveEpisode(from source: IndexSet, to destination: Int) {
        guard let nowPlayingID = audioVM.episode?.id else {
            audioVM.episodeQueue.move(fromOffsets: source, toOffset: destination)
            return
        }

        var filteredQueue = audioVM.episodeQueue.filter { $0.id != nowPlayingID }
        filteredQueue.move(fromOffsets: source, toOffset: destination)

        if let nowPlaying = audioVM.episode {
            audioVM.episodeQueue = [nowPlaying] + filteredQueue
        }
    }
} */

struct QueueView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            VStack {
                if audioVM.episodeQueue.isEmpty {
                    Spacer()
                    VStack {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                            .padding(.bottom, 10)
                        Text("Add podcasts to your queue")
                            .font(.title3)
                            .foregroundColor(.gray)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    Spacer()
                } else {
                    List {
                        ForEach(Array(audioVM.episodeQueue.enumerated()), id: \.element.id) { index, episode in
                            HStack(spacing: 12) {

                                AsyncImage(url: URL(string: episode.podcastImageURL ?? "")) { phase in
                                    switch phase {
                                    case .empty:
                                        Color.gray
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                    case .success(let image):
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.black, lineWidth: 0.5)
                                            )
                                    case .failure:
                                        Color.gray
                                            .frame(width: 60, height: 60)
                                            .cornerRadius(8)
                                    @unknown default:
                                        EmptyView()
                                    }
                                }

                                Text(episode.title)
                                    .font(.headline)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    audioVM.episodeQueue.removeAll { $0.id == episode.id }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .onDrag {
                                NSItemProvider(object: String(index) as NSString)
                            }
                        }
                        .onMove(perform: moveEpisode)
                        .moveDisabled(false)
                    }
                    .listStyle(.plain)
                    .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
                }
            }
            .navigationTitle("Queue")
            .toolbar {
                  ToolbarItem(placement: .navigationBarLeading) {
                      if !audioVM.episodeQueue.isEmpty {
                          Button(isEditing ? "Done" : "Reorder") {
                              isEditing.toggle()
                          }
                      }
                  }
                  ToolbarItem(placement: .navigationBarTrailing) {
                      if !audioVM.episodeQueue.isEmpty {
                          Button("Clear") {
                              audioVM.episodeQueue.removeAll()
                          }
                          .foregroundColor(.red)
                    }
                }
            }
        }
    }

    private func moveEpisode(from source: IndexSet, to destination: Int) {
        audioVM.episodeQueue.move(fromOffsets: source, toOffset: destination)
    }
}

#Preview {
    ContentView()
}
