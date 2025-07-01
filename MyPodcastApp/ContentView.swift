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


//MARK - Models

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
    let id = UUID()
    let title: String
    let pubDate: Date?
    let audioURL: String
    let duration: String?
    let imageURL: String?
    let description: String?
    
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


//MARK - ViewModels

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
                description: currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)))
            insideItem = false
        }
    }
}


class AudioPlayerViewModel: ObservableObject {
    let episode: Episode
    
    private var timeObserverToken: Any?
    private var player: AVPlayer?
    
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var durationTime: Double = 0

    init(episode: Episode) {
        self.episode = episode

        guard let url = URL(string: episode.audioURL) else { return }

        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)

        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite {
                    await MainActor.run {
                        self.durationTime = seconds
                    }
                }
            } catch {
                print("Failed to load duration: \(error)")
            }
        }
        addPeriodicTimeObserver()
    }

    deinit {
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func addPeriodicTimeObserver() {
        guard let player = player else { return }

        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }

    func togglePlayPause() {
        guard let player = player else { return }

        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
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
}


//MARK - Views

enum Tab {
    case home, search, library, settings
}

struct ContentView: View {
    @State private var selectedTab: Tab = .home
    
    var body: some View {
        TabView {
            Text("Home").tabItem {
                Label("Home", systemImage: "house")
            }
            SearchView().tabItem {
                Label("Search", systemImage: "magnifyingglass")
            }
            Text("Library").tabItem {
                Label("Library", systemImage: "book.fill")
            }
            Text("Settings").tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

struct SearchView: View {
    @StateObject var fetcher = PodcastSearchViewModel()
    @State private var searchText: String = ""
    
    
    var body: some View {
        NavigationView {
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
            }
            
            .navigationTitle("Search")
        }
    }
}

struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    
    var body: some View {
        List(episodes) { episode in
            NavigationLink(destination: EpisodePlayerView(episode: episode, podcastTitle: podcast.collectionName, podcastImageURL: podcast.artworkUrl600)) {
                HStack(alignment: .top, spacing: 10) {
                    if let imageURL = episode.imageURL, let url = URL(string: imageURL) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.gray.opacity(0.3)
                        }
                        .frame(width: 60, height: 60)
                        .cornerRadius(8)
                    }
                    
                    VStack(alignment: .leading) {
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
        .navigationTitle(podcast.collectionName)
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

struct EpisodePlayerView: View {
    @StateObject private var audioVM: AudioPlayerViewModel

    let episode: Episode
    let podcastTitle: String
    let podcastImageURL: String?

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
                    .overlay(RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.black, lineWidth: 0.5))
                    .padding(.top)
                }

                Text(episode.title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text(podcastTitle)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                HStack(spacing: 30) {
                    Button(action: {audioVM.skipBackward()}) {
                        Image(systemName: "gobackward.15")
                            .font(.title)
                    }
                    Button(action: {audioVM.togglePlayPause()}) {
                        Image(systemName: audioVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 100))
                    }
                    Button(action: {audioVM.skipForward()}) {
                        Image(systemName: "goforward.15")
                            .font(.title)
                    }
                }
       //       .padding(.vertical)
                
                VStack(spacing: 12) {
                    HStack {
                        Text(audioVM.formattedTime(audioVM.currentTime))
                        Slider(value: $audioVM.currentTime, in: 0...audioVM.durationTime, onEditingChanged: { isEditing in
                            if !isEditing {
                                let newTime = CMTime(seconds: audioVM.currentTime, preferredTimescale: 1)
                                audioVM.seek(to: newTime)
                            }
                        })
                        Text(audioVM.formattedTime(audioVM.durationTime))
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
    
    init(episode: Episode, podcastTitle: String, podcastImageURL: String?) {
        self.episode = episode
        self.podcastTitle = podcastTitle
        self.podcastImageURL = podcastImageURL
        _audioVM = StateObject(wrappedValue: AudioPlayerViewModel(episode: episode))
    }
}

#Preview {
    ContentView()
}
