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
import MediaPlayer
import Charts


//MARK: - Models

//MARK: - Podcast
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

//MARK: - Episode
struct Episode: Identifiable, Hashable, Codable {
    var id: String
    var duration: String?
    let title: String
    let pubDate: Date?
    let audioURL: String
    let imageURL: String?
    let podcastImageURL: String?
    let description: String?
    let podcastName: String?
    let episodeNumber: String?
    let seasonNumber: String?
    
    enum CodingKeys: String, CodingKey {
        case id, duration, title, pubDate, audioURL, imageURL, podcastImageURL, description, podcastName, episodeNumber, seasonNumber
    }
    
    init(title: String, pubDate: Date?, audioURL: String, duration: String?, imageURL: String?, podcastImageURL: String?, description: String?, podcastName: String?, episodeNumber: String? = nil, seasonNumber: String? = nil) {
        self.id = audioURL
        self.title = title
        self.pubDate = pubDate
        self.audioURL = audioURL
        self.duration = duration
        self.imageURL = imageURL
        self.podcastImageURL = podcastImageURL
        self.description = description
        self.podcastName = podcastName
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
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
            if minutes == 0 {
                return "\(hours)h"
            } else {
                return "\(hours)h \(minutes)min"
            }
        } else {
            return "\(minutes)min"
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(audioURL)
    }
    
    static func == (lhs: Episode, rhs: Episode) -> Bool {
        return lhs.id == rhs.id && lhs.audioURL == rhs.audioURL
    }
}

struct SearchResults: Decodable {
    let results: [Podcast]
}

//MARK: - PodcastSettings
struct PodcastSettings: Codable {
    var skipIntroSeconds: Double = 0
    var skipOutroSeconds: Double = 0
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
    var currentContentEncoded = ""
    var insideItem = false
    var podcastImageURL = ""
    var podcastName = ""
    var currentEpisodeNumber = ""
    var currentSeasonNumber = ""
    var isReadingDescription = false
    var isReadingContentEncoded = false
    
    private var parseError: Error?
    private var foundValidItems = false
    private var podcastNameSet = false
    
    
    func parse(data: Data) -> [Episode] {
        episodes.removeAll()
        parseError = nil
        foundValidItems = false
        
        podcastImageURL = ""
        podcastName = ""
        podcastNameSet = false
        
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        let success = parser.parse()
        
        if !success {
            print("RSS Parser failed with error: \(parser.parserError?.localizedDescription ?? "Unknown error")")
            return []
        }
        
        if let error = parseError {
            print("RSS Parser encountered error: \(error.localizedDescription)")
            return []
        }
        
        // Filter out episodes without audio URLs (essential for podcast episodes)
        let validEpisodes = episodes.filter { !$0.audioURL.isEmpty }
        
        if validEpisodes.isEmpty && foundValidItems {
            print("RSS Parser: Found items but none had valid audio URLs")
        }
        
        return validEpisodes
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        
        if elementName == "item" {
            foundValidItems = true
            insideItem = true
            currentTitle = ""
            currentAudioURL = ""
            currentPubDate = ""
            duration = ""
            imageURL = ""
            currentDescription = ""
            currentContentEncoded = ""
            currentEpisodeNumber = ""
            currentSeasonNumber = ""
            isReadingDescription = false
            isReadingContentEncoded = false
        }
        
        // Handle audio enclosures
        if insideItem && elementName == "enclosure" {
            if let url = attributeDict["url"], let type = attributeDict["type"] {
                // Check if it's an audio file
                if type.hasPrefix("audio/") || url.contains(".mp3") || url.contains(".m4a") || url.contains(".wav") {
                    currentAudioURL = url
                }
            }
        }
        
        // Handle iTunes image tags
        if elementName == "itunes:image", let href = attributeDict["href"] {
            if insideItem {
                imageURL = href
            } else {
                podcastImageURL = href
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        let trimmedString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedString.isEmpty else { return }
        
        switch currentElement {
        case "title":
            if insideItem {
                currentTitle += trimmedString
            } else if !podcastNameSet {
                podcastName += trimmedString
                podcastNameSet = true
            }
        case "pubDate":
            currentPubDate += trimmedString
        case "itunes:duration":
            duration += trimmedString
        case "description":
            if insideItem && !isReadingDescription {
                currentDescription = trimmedString
                isReadingDescription = true
            } else if insideItem && isReadingDescription {
                currentDescription += trimmedString
            }
        case "content:encoded":
                    if insideItem && !isReadingContentEncoded {
                        currentContentEncoded = trimmedString
                        isReadingContentEncoded = true
                    } else if insideItem && isReadingContentEncoded {
                        currentContentEncoded += trimmedString
                    }
        case "itunes:summary":
            // Only use itunes:summary if description is still empty
            if insideItem && currentDescription.isEmpty && !isReadingDescription {
                currentDescription = trimmedString
                isReadingDescription = true
            } else if insideItem && isReadingDescription && currentDescription.isEmpty {
                currentDescription += trimmedString
            }
        case "itunes:episode":
            currentEpisodeNumber += trimmedString
        case "itunes:season":
            currentSeasonNumber += trimmedString
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "description" || elementName == "itunes:summary" {
            isReadingDescription = false
        }
        
        if elementName == "content:encoded" {
                    isReadingContentEncoded = false
                }
        
        if elementName == "item" {
            // Only add episode if it has essential data
            if !currentTitle.isEmpty && !currentAudioURL.isEmpty {
                let episode = createEpisode()
                episodes.append(episode)
            }
            insideItem = false
        }
    }
    
    private func createEpisode() -> Episode {
        // Parse the publication date with multiple format attempts
        let pubDate = RSSDateParser.parseDate(from: currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines))
        
        var finalDescription = currentDescription
                if !currentContentEncoded.isEmpty {
                    // Check if content:encoded has HTML tags
                    if currentContentEncoded.contains("<") && currentContentEncoded.contains(">") {
                        finalDescription = currentContentEncoded
                    } else if currentDescription.isEmpty {
                        // If description is empty, use content:encoded even without HTML
                        finalDescription = currentContentEncoded
                    }
                }
        
        return Episode(
            title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            pubDate: pubDate,
            audioURL: currentAudioURL.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration.isEmpty ? nil : duration.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: imageURL.isEmpty ? nil : imageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastImageURL: podcastImageURL.isEmpty ? nil : podcastImageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            description: finalDescription.isEmpty ? nil : finalDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastName: podcastName.isEmpty ? nil : podcastName.trimmingCharacters(in: .whitespacesAndNewlines),
            episodeNumber: currentEpisodeNumber.isEmpty ? nil : currentEpisodeNumber.trimmingCharacters(in: .whitespacesAndNewlines),
            seasonNumber: currentSeasonNumber.isEmpty ? nil : currentSeasonNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    
    // XMLParserDelegate error handling
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        self.parseError = parseError
        print("XML Parse Error: \(parseError.localizedDescription)")
    }
    
    func parser(_ parser: XMLParser, validationErrorOccurred validationError: Error) {
        print("XML Validation Error: \(validationError.localizedDescription)")
    }
}

//MARK: - RSSDateParser
struct RSSDateParser {
    // Cache formatters as static properties to avoid recreating them
    private static let cachedFormatters: [DateFormatter] = {
        let formats = [
            // RFC 2822 formats (most common in RSS)
            "E, d MMM yyyy HH:mm:ss Z",
            "E, dd MMM yyyy HH:mm:ss Z",
            "E, d MMM yyyy HH:mm:ss z",
            "E, dd MMM yyyy HH:mm:ss z",
            "E, d MMM yyyy HH:mm:ss 'GMT'",
            "E, dd MMM yyyy HH:mm:ss 'GMT'",
            
            // Without day of week
            "d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "d MMM yyyy HH:mm:ss z",
            "dd MMM yyyy HH:mm:ss z",
            
            // Without seconds
            "E, d MMM yyyy HH:mm Z",
            "E, dd MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm Z",
            "dd MMM yyyy HH:mm Z",
            
            // Without timezone
            "E, d MMM yyyy HH:mm:ss",
            "E, dd MMM yyyy HH:mm:ss",
            "d MMM yyyy HH:mm:ss",
            "dd MMM yyyy HH:mm:ss",
            "E, d MMM yyyy HH:mm",
            "E, dd MMM yyyy HH:mm",
            
            // ISO 8601 variants
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            
            // Alternative formats sometimes used
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            
            // US format variations
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy HH:mm",
            "MM/dd/yyyy",
            "MM-dd-yyyy",
            
            // Other variations
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy HH:mm",
            "dd/MM/yyyy",
            "dd-MM-yyyy",
            
            // Fallback formats
            "MMM d, yyyy HH:mm:ss",
            "MMM d, yyyy HH:mm",
            "MMM d, yyyy",
            "MMMM d, yyyy",
            "d MMMM yyyy"
        ]
        
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            formatter.timeZone = TimeZone(secondsFromGMT: 0) // Default to GMT if no timezone
            return formatter
        }
    }()
    
    // Add a cache for recently parsed dates to avoid re-parsing identical strings
    private static let dateCache: NSCache<NSString, NSDate> = {
        let cache = NSCache<NSString, NSDate>()
        cache.countLimit = 1000  // Limit cache size
        cache.totalCostLimit = 1024 * 1024  // 1MB limit
        return cache
    }()
    
    static func parseDate(from dateString: String) -> Date? {
        guard !dateString.isEmpty else { return nil }
        
        // Check cache first
        let cacheKey = dateString as NSString
        if let cachedDate = dateCache.object(forKey: cacheKey) {
            return cachedDate as Date
        }
        
        let cleanedDateString = cleanDateString(dateString)
        
        // Try the cached formatters in order of most common to least common
        for formatter in cachedFormatters {
            if let date = formatter.date(from: cleanedDateString) {
                // Cache the successful parse
                dateCache.setObject(date as NSDate, forKey: cacheKey)
                return date
            }
        }
        
        print("Failed to parse date: '\(dateString)' (cleaned: '\(cleanedDateString)')")
        return nil
    }
    
    private static func cleanDateString(_ dateString: String) -> String {
        var cleaned = dateString.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common problematic characters and patterns
        cleaned = cleaned.replacingOccurrences(of: " +0000", with: " GMT")
        cleaned = cleaned.replacingOccurrences(of: " -0000", with: " GMT")
        cleaned = cleaned.replacingOccurrences(of: "UT", with: "GMT")
        
        // Handle timezone abbreviations that DateFormatter doesn't recognize
        let timezoneReplacements = [
            " PDT": " -0700",
            " PST": " -0800",
            " EDT": " -0400",
            " EST": " -0500",
            " CDT": " -0500",
            " CST": " -0600",
            " MDT": " -0600",
            " MST": " -0700"
        ]
        
        for (abbrev, offset) in timezoneReplacements {
            cleaned = cleaned.replacingOccurrences(of: abbrev, with: offset)
        }
        
        // Remove duplicate spaces
        cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        
        return cleaned
    }
    
    // Optional: Method to clear the date cache if memory becomes an issue
    static func clearCache() {
        dateCache.removeAllObjects()
    }
}

// MARK: - Cached AsyncImage View
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var cachedImage: UIImage?
    @State private var shouldUseCached = false
    @State private var cachingTask: Task<Void, Never>?
    
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if shouldUseCached, let cachedImage = cachedImage {
                // Use cached image
                content(Image(uiImage: cachedImage))
            } else {
                // Use AsyncImage and cache the result
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder()
                    case .success(let image):
                        // Cache the successful image
                        content(image)
                            .onAppear {
                                cacheImageFromAsyncImage()
                            }
                    case .failure(_):
                        placeholder()
                    @unknown default:
                        placeholder()
                    }
                }
            }
        }
        .onAppear {
            checkCache()
        }
        .onChange(of: url) {
            // Reset state when URL changes
            shouldUseCached = false
            cachedImage = nil
            checkCache()
        }
    }
    
    private func checkCache() {
        guard let url = url else { return }
        
        let urlString = url.absoluteString
        if let cached = ImageCache.shared.getImage(for: urlString) {
            cachedImage = cached
            shouldUseCached = true
        }
    }
    
    private func cacheImageFromAsyncImage() {
        guard let url = url else { return }
        cachingTask?.cancel()

        cachingTask = Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    // Only cache if this view still exists and URL hasn't changed
                    guard self.url == url else { return }
                    ImageCache.shared.setImage(image, for: url.absoluteString)
                }
            } catch {
                // Ignore caching errors (e.g., cancelled, network issues)
            }
        }
    }
}

struct DurationFormatter {
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    static func formatLongDuration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = Int(seconds) / 3600 % 24
        let minutes = Int(seconds) / 60 % 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// MARK: - ImageCache
class ImageCache {
    static let shared = ImageCache()
    private var cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    
    private init() {
        // Set up memory cache
        cache.countLimit = 100 // Maximum 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB memory limit
        
        // Set up disk cache directory
        let urls = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = urls[0].appendingPathComponent("PodcastImageCache")
        
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    private func cacheFileName(for url: String) -> String {
        return url.data(using: .utf8)?.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-") ?? UUID().uuidString
    }
    
    func getImage(for url: String) -> UIImage? {
        // Check memory cache first
        if let cachedImage = cache.object(forKey: url as NSString) {
            return cachedImage
        }
        
        // Check disk cache
        let filename = cacheFileName(for: url)
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        if let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            cache.setObject(image, forKey: url as NSString)
            return image
        }
        return nil
    }
    
    func setImage(_ image: UIImage, for url: String) {
        // Store in memory cache
        cache.setObject(image, forKey: url as NSString)
        
        // Store in disk cache
        let filename = cacheFileName(for: url)
        let fileURL = cacheDirectory.appendingPathComponent(filename)
        
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: fileURL)
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}

//MARK: - ListeningSession
struct ListeningSession: Codable {
    var id = UUID()
    let episodeID: String
    let podcastName: String
    let episodeTitle: String
    let startTime: Date
    let endTime: Date
    let duration: TimeInterval // in seconds
    let completed: Bool
}

//MARK: - PodcastStats
struct PodcastStats: Identifiable, Codable {
    var id = UUID()
    let podcastName: String
    let totalListeningTime: TimeInterval
    let episodeCount: Int
    let averageListeningTime: TimeInterval
    let completionRate: Double // percentage of episodes completed
    let firstListenDate: Date
    let lastListenDate: Date
    
    var totalListeningTimeFormatted: String {
        return DurationFormatter.formatDuration(totalListeningTime)
    }
    
    var averageListeningTimeFormatted: String {
        return StatisticsManager.formatDuration(averageListeningTime)
    }
}

//MARK: - OverallStats
struct OverallStats: Codable {
    let totalListeningTime: TimeInterval
    let totalEpisodes: Int
    let totalPodcasts: Int
    let averageSessionLength: TimeInterval
    let longestSession: TimeInterval
    let completionRate: Double
    let firstListenDate: Date?
    let streakDays: Int
    let longestStreakDays: Int
    let favoriteListeningHour: Int
    
    var totalListeningTimeFormatted: String {
        return DurationFormatter.formatDuration(totalListeningTime)
    }
    
    var averageSessionLengthFormatted: String {
        return StatisticsManager.formatDuration(averageSessionLength)
    }
    
    var longestSessionFormatted: String {
        return StatisticsManager.formatDuration(longestSession)
    }
}

//MARK: - StatisticsManager
class StatisticsManager: ObservableObject {
    static let shared = StatisticsManager()
    
    @Published var overallStats: OverallStats?
    @Published var podcastStats: [PodcastStats] = []
    @Published var recentSessions: [ListeningSession] = []
    private var completedEpisodes: Set<String> = [] // Store episode IDs that were completed
    private let completedEpisodesKey = "completedEpisodes"
    private var listeningSessions: [ListeningSession] = []
    private var currentSessionStart: Date?
    private var currentEpisode: Episode?
    
    private let sessionsKey = "listeningSessions"
    private let minSessionDuration: TimeInterval = 30 // Minimum 30 seconds to count as a session
    
    private init() {
        loadData()
        loadCompletedEpisodes()
        calculateStats()
    }
    
    private func loadCompletedEpisodes() {
        if let data = UserDefaults.standard.data(forKey: completedEpisodesKey),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            completedEpisodes = decoded
        }
    }

    private func saveCompletedEpisodes() {
        if let data = try? JSONEncoder().encode(completedEpisodes) {
            UserDefaults.standard.set(data, forKey: completedEpisodesKey)
        }
    }

    // Add method to mark episode as completed
    func markEpisodeCompleted(_ episodeID: String) {
        completedEpisodes.insert(episodeID)
        saveCompletedEpisodes()
        calculateStats()
    }

    // Check if episode was ever completed
    func isEpisodeCompleted(_ episodeID: String) -> Bool {
        return completedEpisodes.contains(episodeID)
    }
    
    func startListeningSession(for episode: Episode) {
        // Don't start a new session if we already have one for the same episode
        if let currentEpisode = currentEpisode,
           currentEpisode.id == episode.id,
           currentSessionStart != nil {
            return
        }
        
        // End previous session if one exists for a different episode
        if currentSessionStart != nil {
            endListeningSession(completed: false)
        }
        
        currentSessionStart = Date()
        currentEpisode = episode
    }
    
    func endListeningSession(completed: Bool = false) {
        guard let startTime = currentSessionStart,
              let episode = currentEpisode else {
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
        
        let minDuration: TimeInterval = 30
        
        if duration >= minDuration {
            let session = ListeningSession(
                episodeID: episode.id,
                podcastName: episode.podcastName ?? "Unknown Podcast",
                episodeTitle: episode.title,
                startTime: startTime,
                endTime: endTime,
                duration: duration,
                completed: completed
            )
            
            listeningSessions.append(session)
            saveData()
            calculateStats()
        }
        
        currentSessionStart = nil
        currentEpisode = nil
    }
    
    func pauseSession() {
        
        // When pausing, we end current session and will start new one on resume
        endListeningSession()
    }
    
    func calculateStats() {
        guard !listeningSessions.isEmpty else {
            overallStats = nil
            podcastStats = []
            recentSessions = []
            return
        }
        
        calculateOverallStats()
        calculatePodcastStats()
        updateRecentSessions()
        
    }
    
    private func calculateOverallStats() {
        let totalTime = listeningSessions.reduce(0) { $0 + $1.duration }
        let uniqueEpisodes = Set(listeningSessions.map { $0.episodeID }).count
        let uniquePodcasts = Set(listeningSessions.map { $0.podcastName }).count
        
        let averageSession = totalTime / Double(listeningSessions.count)
        let longestSession = listeningSessions.max { $0.duration < $1.duration }?.duration ?? 0
        
        let uniqueEpisodeIDs = Set(listeningSessions.map { $0.episodeID })
        let completedCount = uniqueEpisodeIDs.filter { completedEpisodes.contains($0) }.count
        let completionRate = uniqueEpisodes > 0 ?
        Double(completedCount) / Double(uniqueEpisodes) * 100 : 0
        
        let firstListen = listeningSessions.min { $0.startTime < $1.startTime }?.startTime
        
        let streak = calculateStreak()
        let longestStreak = calculateLongestStreak()
        let favoriteHour = calculateFavoriteListeningHour()
        
        overallStats = OverallStats(
            totalListeningTime: totalTime,
            totalEpisodes: uniqueEpisodes,
            totalPodcasts: uniquePodcasts,
            averageSessionLength: averageSession,
            longestSession: longestSession,
            completionRate: completionRate,
            firstListenDate: firstListen,
            streakDays: streak,
            longestStreakDays: longestStreak,
            favoriteListeningHour: favoriteHour
        )
    }
    
    private func calculatePodcastStats() {
        let podcastGroups = Dictionary(grouping: listeningSessions, by: { $0.podcastName })
        
        podcastStats = podcastGroups.map { (podcastName, sessions) in
            let totalTime = sessions.reduce(0) { $0 + $1.duration }
            let uniqueEpisodeIDs = Set(sessions.map { $0.episodeID })
            let episodeCount = Set(sessions.map { $0.episodeID }).count
            let averageTime = totalTime / Double(sessions.count)
            
            let completedCount = uniqueEpisodeIDs.filter { completedEpisodes.contains($0) }.count
            let completionRate = episodeCount > 0 ?
            Double(completedCount) / Double(episodeCount) * 100 : 0
            
            let firstListen = sessions.min { $0.startTime < $1.startTime }?.startTime ?? Date()
            let lastListen = sessions.max { $0.startTime < $1.startTime }?.startTime ?? Date()
            
            return PodcastStats(
                podcastName: podcastName,
                totalListeningTime: totalTime,
                episodeCount: episodeCount,
                averageListeningTime: averageTime,
                completionRate: completionRate,
                firstListenDate: firstListen,
                lastListenDate: lastListen
            )
        }.sorted { $0.totalListeningTime > $1.totalListeningTime }
    }
    
    private func updateRecentSessions() {
        recentSessions = Array(listeningSessions.suffix(20).reversed())
    }
    
    private func calculateStreak() -> Int {
        guard !listeningSessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Check if there's listening activity today
        let hasListeningToday = listeningSessions.contains { session in
            calendar.isDate(session.startTime, inSameDayAs: today)
        }
        
        // Start from today if there's activity, otherwise start from yesterday
        var currentDate: Date
        if hasListeningToday {
            currentDate = today
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: today) {
            // Check if there's listening yesterday
            let hasListeningYesterday = listeningSessions.contains { session in
                calendar.isDate(session.startTime, inSameDayAs: yesterday)
            }
            
            // If no listening yesterday either, streak is broken
            if !hasListeningYesterday {
                return 0
            }
            
            currentDate = yesterday
        } else {
            return 0
        }
        
        // Count consecutive days backwards
        var streak = 0
        
        while true {
            let hasListeningOnDate = listeningSessions.contains { session in
                calendar.isDate(session.startTime, inSameDayAs: currentDate)
            }
            
            if hasListeningOnDate {
                streak += 1
                if let previousDay = calendar.date(byAdding: .day, value: -1, to: currentDate) {
                    currentDate = previousDay
                } else {
                    break
                }
            } else {
                break
            }
        }
        
        return streak
    }
    
    private func calculateLongestStreak() -> Int {
        guard !listeningSessions.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        
        // Get all unique days with listening activity
        let daysWithListening = Set(listeningSessions.map { session in
            calendar.startOfDay(for: session.startTime)
        }).sorted()
        
        guard !daysWithListening.isEmpty else { return 0 }
        
        var longestStreak = 1
        var currentStreak = 1
        
        for i in 1..<daysWithListening.count {
            let previousDay = daysWithListening[i - 1]
            let currentDay = daysWithListening[i]
            
            // Check if current day is exactly one day after previous day
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: previousDay),
               calendar.isDate(nextDay, inSameDayAs: currentDay) {
                currentStreak += 1
                longestStreak = max(longestStreak, currentStreak)
            } else {
                currentStreak = 1
            }
        }
        
        return longestStreak
    }
    
    private func calculateFavoriteListeningHour() -> Int {
        let hourGroups = Dictionary(grouping: listeningSessions) { session in
            Calendar.current.component(.hour, from: session.startTime)
        }
        
        return hourGroups.max { $0.value.count < $1.value.count }?.key ?? 12
    }
    
    private func saveData() {
        if let data = try? JSONEncoder().encode(listeningSessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([ListeningSession].self, from: data) {
            listeningSessions = decoded
        }
    }
    
    static func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) / 60 % 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    static func formatLongDuration(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86400
        let hours = Int(seconds) / 3600 % 24
        let minutes = Int(seconds) / 60 % 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    func getListeningTimeForPeriod(_ period: StatsPeriod) -> TimeInterval {
        let calendar = Calendar.current
        let now = Date()
        
        let startDate: Date
        switch period {
        case .today:
            startDate = calendar.startOfDay(for: now)
        case .thisWeek:
            startDate = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        case .thisMonth:
            startDate = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .thisYear:
            startDate = calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .allTime:
            return listeningSessions.reduce(0) { $0 + $1.duration }
        }
        
        return listeningSessions
            .filter { $0.startTime >= startDate }
            .reduce(0) { $0 + $1.duration }
    }
    
    @MainActor
    func clearAllStats() {
        listeningSessions.removeAll()
        completedEpisodes.removeAll()
        saveData()
        saveCompletedEpisodes()
        calculateStats()
        SessionManager.shared.clearAllSessions()
    }
}

// MARK: - SessionManager
@MainActor
class SessionManager: ObservableObject {
    static let shared = SessionManager()
    
    @Published var userSessions: [UserSession] = []
    @Published var currentSession: UserSession?
    
    private var currentEpisodeSession: EpisodeSession?
    private var episodeStartTime: Date?
    private var pauseTimer: Timer?
    private let pauseThreshold: TimeInterval = 30 // 30 seconds
    
    private let sessionsKey = "userSessions"
    private let sessionNumberKey = "sessionNumber"
    
    private init() {
        loadSessions()
    }
    
    // MARK: - Session Management
    
    func startSession() {
        guard currentSession == nil else {
            print("Session already active")
            return
        }
        
        let sessionNumber = getNextSessionNumber()
        currentSession = UserSession(
            sessionNumber: sessionNumber,
            startTime: Date(),
            endTime: Date(),
            totalDuration: 0,
            episodes: []
        )
        print("Started session #\(sessionNumber)")
    }
    
    func startEpisodeInSession(episode: Episode) {
        // Start session if not already active
        if currentSession == nil {
            startSession()
        }
        
        // Cancel any pending pause timer
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        // End previous episode session if exists
        if currentEpisodeSession != nil {
            endCurrentEpisodeSession(completed: false)
        }
        
        // Start new episode session
        episodeStartTime = Date()
        currentEpisodeSession = EpisodeSession(
            episodeID: episode.id,
            episodeTitle: episode.title,
            podcastName: episode.podcastName ?? "Unknown Podcast",
            imageURL: episode.imageURL ?? episode.podcastImageURL,
            duration: 0,
            startTime: Date(),
            endTime: Date(),
            completed: false
        )
        
        print("Started episode session: \(episode.title)")
    }
    
    func pauseEpisodeInSession() {
        guard let startTime = episodeStartTime else { return }
        pauseTimer?.invalidate()
        pauseTimer = nil

        // Update episode duration
        if var episodeSession = currentEpisodeSession {
            let duration = Date().timeIntervalSince(startTime)
            episodeSession.duration = duration
            episodeSession.endTime = Date()
            currentEpisodeSession = episodeSession
        }
        
        // Start pause timer - if not resumed within threshold, end session
        pauseTimer = Timer.scheduledTimer(withTimeInterval: pauseThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor in
                print("Pause threshold exceeded - ending session")
                self?.endSession()
            }
        }
        
        print("Episode paused - will end session if not resumed in \(pauseThreshold)s")
    }
    
    func resumeEpisodeInSession() {
        // Cancel pause timer
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        if currentSession == nil {
            startSession()
        }
        
        // Resume episode timing
        episodeStartTime = Date()
        print("Episode resumed - pause timer cancelled")
    }
    
    func endCurrentEpisodeSession(completed: Bool) {
        guard var episodeSession = currentEpisodeSession,
              let startTime = episodeStartTime else { return }
        
        // Calculate final duration
        let additionalDuration = Date().timeIntervalSince(startTime)
        episodeSession.duration += additionalDuration
        episodeSession.endTime = Date()
        episodeSession = EpisodeSession(
            id: episodeSession.id,
            episodeID: episodeSession.episodeID,
            episodeTitle: episodeSession.episodeTitle,
            podcastName: episodeSession.podcastName,
            imageURL: episodeSession.imageURL,
            duration: episodeSession.duration,
            startTime: episodeSession.startTime,
            endTime: Date(),
            completed: completed
        )
        
        // Add to current session
        if var session = currentSession {
            session.episodes.append(episodeSession)
            session.totalDuration += episodeSession.duration
            session.endTime = Date()
            currentSession = session
            print("Ended episode session: \(episodeSession.episodeTitle) - \(episodeSession.duration)s")
        }
        
        currentEpisodeSession = nil
        episodeStartTime = nil
    }
    
    func endSession() {
        // Cancel pause timer
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        // End current episode if active
        if currentEpisodeSession != nil {
            endCurrentEpisodeSession(completed: false)
        }
        
        // Save session
        if let session = currentSession, !session.episodes.isEmpty {
            userSessions.insert(session, at: 0) // Add to beginning for reverse chronological
            saveSessions()
            print("Ended session #\(session.sessionNumber) - Total: \(session.totalDuration)s, Episodes: \(session.episodes.count)")
        }
        
        currentSession = nil
    }
    
    func clearAllSessions() {
        // End current session if active
        if currentSession != nil {
            endSession()
        }
        
        // Clear all saved sessions
        userSessions.removeAll()
        saveSessions()
        
        // Reset session counter
        UserDefaults.standard.set(0, forKey: sessionNumberKey)
        
        print("✅ Cleared all session data")
    }
    
    // MARK: - Persistence
    
    private func saveSessions() {
        if let data = try? JSONEncoder().encode(userSessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
    
    private func loadSessions() {
        if let data = UserDefaults.standard.data(forKey: sessionsKey),
           let decoded = try? JSONDecoder().decode([UserSession].self, from: data) {
            userSessions = decoded
        }
    }
    
    private func getNextSessionNumber() -> Int {
        let current = UserDefaults.standard.integer(forKey: sessionNumberKey)
        let next = current + 1
        UserDefaults.standard.set(next, forKey: sessionNumberKey)
        return next
    }
}

enum StatsPeriod: String, CaseIterable {
    case today = "Today"
    case thisWeek = "This Week"
    case thisMonth = "This Month"
    case thisYear = "This Year"
    case allTime = "All Time"
}

struct UserSession: Identifiable, Codable, Hashable {
    var id = UUID()
    let sessionNumber: Int
    let startTime: Date
    var endTime: Date
    var totalDuration: TimeInterval
    var episodes: [EpisodeSession]
}

struct EpisodeSession: Identifiable, Codable, Hashable {
    var id = UUID()
    let episodeID: String
    let episodeTitle: String
    let podcastName: String
    let imageURL: String?
    var duration: TimeInterval
    let startTime: Date
    var endTime: Date
    let completed: Bool
}
/*
//MARK: - TaskMapper (Thread-safe mapping)
actor TaskMapper {
    private var mapping: [ObjectIdentifier: String] = [:]
    
    func setEpisodeID(_ episodeID: String, for task: URLSessionDownloadTask) {
        mapping[ObjectIdentifier(task)] = episodeID
    }
    
    func getEpisodeID(for task: URLSessionDownloadTask) -> String? {
        return mapping[ObjectIdentifier(task)]
    }
    
    func removeEpisodeID(for task: URLSessionDownloadTask) {
        mapping.removeValue(forKey: ObjectIdentifier(task))
    }
} */

//MARK: - DownloadManager
@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloadedEpisodes: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var activeDownloads: Set<String> = []
    @Published var autoDeleteOnCompletion: Bool = false
    
    private let downloadedEpisodesKey = "downloadedEpisodes"
    private let autoDeleteKey = "autoDeleteOnCompletion"
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    
    // CHANGE: Make these nonisolated with their own synchronization
    nonisolated(unsafe) private var taskToEpisodeMapping: [ObjectIdentifier: String] = [:]
    private let mappingQueue = DispatchQueue(label: "com.mypodcastapp.downloadmapping")
    
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.mypodcastapp.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        config.timeoutIntervalForRequest = 60 // 60 seconds for initial connection
        config.timeoutIntervalForResource = 3600 // 1 hour for entire download
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
        loadDownloadedEpisodes()
        loadAutoDeleteSetting()
        createDownloadsDirectory()
    }
    
    private func loadAutoDeleteSetting() {
        autoDeleteOnCompletion = UserDefaults.standard.bool(forKey: autoDeleteKey)
    }
    
    func setAutoDelete(_ enabled: Bool) {
        autoDeleteOnCompletion = enabled
        UserDefaults.standard.set(enabled, forKey: autoDeleteKey)
    }
    
    private func createDownloadsDirectory() {
        let fileManager = FileManager.default
        if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let downloadsPath = documentsPath.appendingPathComponent("Downloads")
            try? fileManager.createDirectory(at: downloadsPath, withIntermediateDirectories: true)
        }
    }
    
    func isDownloaded(_ episodeID: String) -> Bool {
        return downloadedEpisodes.contains(episodeID)
    }
    
    func isDownloading(_ episodeID: String) -> Bool {
        return activeDownloads.contains(episodeID)
    }
    
    func downloadEpisode(_ episode: Episode) {
        guard let url = URL(string: episode.audioURL) else { return }
        guard !isDownloaded(episode.id) && !isDownloading(episode.id) else { return }
        
        activeDownloads.insert(episode.id)
        downloadProgress[episode.id] = 0.0
        
        let task = downloadSession.downloadTask(with: url)
        downloadTasks[episode.id] = task
        
        // Store mapping - use helper method
        setEpisodeID(episode.id, for: task)
        
        task.resume()
        
        print("Started downloading: \(episode.title)")
    }
    
    func deleteDownload(_ episodeID: String) {
        guard let downloadPath = getDownloadPath(for: episodeID) else { return }
        
        // If this episode is currently playing, stop playback
        Task { @MainActor in
            let audioVM = AudioPlayerViewModel.shared
            if audioVM.episode?.id == episodeID && audioVM.isPlaying {
                audioVM.togglePlayPause()
                print("⏹️ Stopped playback of deleted episode")
            }
            
            // Remove from downloaded list and delete file
            self.downloadedEpisodes.remove(episodeID)
            self.saveDownloadedEpisodes()
            try? FileManager.default.removeItem(at: downloadPath)
            print("🗑️ Deleted download for episode: \(episodeID)")
        }
    }
    
    func cancelDownload(_ episodeID: String) {
        if let task = downloadTasks[episodeID] {
            task.cancel()
            // Remove mapping
            removeEpisodeID(for: task)
        }
        downloadTasks.removeValue(forKey: episodeID)
        activeDownloads.remove(episodeID)
        downloadProgress.removeValue(forKey: episodeID)
    }
    
    func getLocalURL(for episodeID: String) -> URL? {
        guard isDownloaded(episodeID) else { return nil }
        return getDownloadPath(for: episodeID)
    }
    
    private func saveDownloadedEpisodes() {
        let array = Array(downloadedEpisodes)
        UserDefaults.standard.set(array, forKey: downloadedEpisodesKey)
    }
    
    private func loadDownloadedEpisodes() {
        if let array = UserDefaults.standard.array(forKey: downloadedEpisodesKey) as? [String] {
            downloadedEpisodes = Set(array)
        }
    }
    
    nonisolated private func sanitizeFilename(for episodeID: String) -> String {
        let hash = episodeID.hash
        return "\(abs(hash)).mp3"
    }
    
    nonisolated private func getDownloadPath(for episodeID: String) -> URL? {
        guard let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let filename = sanitizeFilename(for: episodeID)
        return documentsPath.appendingPathComponent("Downloads").appendingPathComponent(filename)
    }
    
    // MARK: - Thread-safe mapping helpers
    
    nonisolated private func setEpisodeID(_ episodeID: String, for task: URLSessionDownloadTask) {
        mappingQueue.sync {
            taskToEpisodeMapping[ObjectIdentifier(task)] = episodeID
        }
    }
    
    nonisolated private func getEpisodeID(for task: URLSessionDownloadTask) -> String? {
        return mappingQueue.sync {
            taskToEpisodeMapping[ObjectIdentifier(task)]
        }
    }
    
    nonisolated private func removeEpisodeID(for task: URLSessionDownloadTask) {
        mappingQueue.sync {
            _ = taskToEpisodeMapping.removeValue(forKey: ObjectIdentifier(task))
        }
    }
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Get episode ID synchronously
        guard let episodeID = getEpisodeID(for: downloadTask),
              let destinationURL = getDownloadPath(for: episodeID) else {
            print("Failed to get episodeID or destination path")
            return
        }
        
        print("Download finished for: \(episodeID)")
        print("Moving from: \(location)")
        print("Moving to: \(destinationURL)")
        
        do {
            let downloadsDir = destinationURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
            
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("File moved successfully")
            
            Task { @MainActor in
                self.downloadedEpisodes.insert(episodeID)
                self.activeDownloads.remove(episodeID)
                self.downloadProgress.removeValue(forKey: episodeID)
                self.downloadTasks.removeValue(forKey: episodeID)
                self.saveDownloadedEpisodes()
                print("Download completed and saved")
            }
            
            // Clean up mapping
            removeEpisodeID(for: downloadTask)
        } catch {
            print("Error moving downloaded file: \(error)")
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let episodeID = getEpisodeID(for: downloadTask) else {
            return
        }
        
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        
        Task { @MainActor in
            self.downloadProgress[episodeID] = progress
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        guard let episodeID = getEpisodeID(for: downloadTask) else {
            return
        }
        
        if let error = error {
            print("Download failed for \(episodeID): \(error)")
            Task { @MainActor in
                self.activeDownloads.remove(episodeID)
                self.downloadProgress.removeValue(forKey: episodeID)
                self.downloadTasks.removeValue(forKey: episodeID)
            }
            
            // Clean up mapping
            removeEpisodeID(for: downloadTask)
        }
    }
}

//MARK: - EpisodeStatus
struct EpisodeStatus: Codable {
    var isPlayed: Bool = false
    var isArchived: Bool = false
    var lastPlayedDate: Date?
    var playCount: Int = 0
}

//MARK: - EpisodeTrackingManager
@MainActor
class EpisodeTrackingManager: ObservableObject {
    static let shared = EpisodeTrackingManager()
    
    @Published var episodeStatuses: [String: EpisodeStatus] = [:]
    @Published var hidePlayedEpisodes: Bool = false
    @Published var hideArchivedEpisodes: Bool = false
    
    private let statusesKey = "episodeStatuses"
    private let hidePlayedKey = "hidePlayedEpisodes"
    private let hideArchivedKey = "hideArchivedEpisodes"
    
    private var statusesFileURL: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("episodeStatuses.json")
    }
    
    private init() {
        loadStatuses()
        loadPreferences()
    }
    
    // MARK: - Status Management
    func markAsPlayed(_ episodeID: String) {
        // If this episode is currently playing, stop playback
        let audioVM = AudioPlayerViewModel.shared
        if audioVM.episode?.id == episodeID {
            audioVM.cleanup() // This stops playback and clears the player
        }
        
        var status = episodeStatuses[episodeID] ?? EpisodeStatus()
        status.isPlayed = true
        status.isArchived = true // Marking played also archives
        status.lastPlayedDate = Date()
        status.playCount += 1
        episodeStatuses[episodeID] = status
        saveStatuses()
    }
    
    func markAsUnplayed(_ episodeID: String) {
        var status = episodeStatuses[episodeID] ?? EpisodeStatus()
        status.isPlayed = false
        status.isArchived = false // Marking unplayed also unarchives
        episodeStatuses[episodeID] = status
        saveStatuses()
    }
    
    func toggleArchived(_ episodeID: String) {
        var status = episodeStatuses[episodeID] ?? EpisodeStatus()
        status.isArchived.toggle()
        episodeStatuses[episodeID] = status
        saveStatuses()
    }
    
    func archive(_ episodeID: String) {
        var status = episodeStatuses[episodeID] ?? EpisodeStatus()
        status.isArchived = true
        episodeStatuses[episodeID] = status
        saveStatuses()
    }
    
    func unarchive(_ episodeID: String) {
        var status = episodeStatuses[episodeID] ?? EpisodeStatus()
        status.isArchived = false
        episodeStatuses[episodeID] = status
        saveStatuses()
    }
    
    // MARK: - Status Queries
    
    func isPlayed(_ episodeID: String) -> Bool {
        return episodeStatuses[episodeID]?.isPlayed ?? false
    }
    
    func isArchived(_ episodeID: String) -> Bool {
        return episodeStatuses[episodeID]?.isArchived ?? false
    }
    
    func shouldShowEpisode(_ episodeID: String) -> Bool {
        let status = episodeStatuses[episodeID] ?? EpisodeStatus()
        
        if hideArchivedEpisodes && status.isArchived {
            return false
        }
        
        if hidePlayedEpisodes && status.isPlayed {
            return false
        }
        
        return true
    }
    
    func getPlayCount(_ episodeID: String) -> Int {
        return episodeStatuses[episodeID]?.playCount ?? 0
    }
    
    func getLastPlayedDate(_ episodeID: String) -> Date? {
        return episodeStatuses[episodeID]?.lastPlayedDate
    }
    
    // MARK: - Preference Management
    
    func toggleHidePlayedEpisodes() {
        hidePlayedEpisodes.toggle()
        savePreferences()
    }
    
    func toggleHideArchivedEpisodes() {
        hideArchivedEpisodes.toggle()
        savePreferences()
    }
    
    // MARK: - Batch Operations
    
    func markAllAsPlayed(for episodes: [Episode]) {
        for episode in episodes {
            markAsPlayed(episode.id)
        }
    }
    
    func markAllAsUnplayed(for episodes: [Episode]) {
        for episode in episodes {
            markAsUnplayed(episode.id)
        }
    }
    
    func archiveAll(for episodes: [Episode]) {
        for episode in episodes {
            archive(episode.id)
        }
    }
    
    // MARK: - Persistence
    private func saveStatuses() {
        do {
            let data = try JSONEncoder().encode(episodeStatuses)
            try data.write(to: statusesFileURL, options: .atomic)
        } catch {
            print("❌ Failed to save episode statuses: \(error)")
        }
    }
    
    private func loadStatuses() {
        do {
            let data = try Data(contentsOf: statusesFileURL)
            episodeStatuses = try JSONDecoder().decode([String: EpisodeStatus].self, from: data)
        } catch {
            print("⚠️ No episode statuses found or failed to load: \(error)")
            episodeStatuses = [:]
        }
    }
    
    private func savePreferences() {
        UserDefaults.standard.set(hidePlayedEpisodes, forKey: hidePlayedKey)
        UserDefaults.standard.set(hideArchivedEpisodes, forKey: hideArchivedKey)
    }
    
    private func loadPreferences() {
        hidePlayedEpisodes = UserDefaults.standard.bool(forKey: hidePlayedKey)
        hideArchivedEpisodes = UserDefaults.standard.bool(forKey: hideArchivedKey)
    }
    
    // MARK: - Statistics
    
    func getTotalPlayedCount() -> Int {
        return episodeStatuses.values.filter { $0.isPlayed }.count
    }
    
    func getTotalArchivedCount() -> Int {
        return episodeStatuses.values.filter { $0.isArchived }.count
    }
}


//MARK: - ViewModels

//MARK: - PodcastSearchViewModel
@MainActor
class PodcastSearchViewModel: ObservableObject {
    @Published var podcasts: [Podcast] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    func search(term: String) async {
        guard !term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            podcasts = []
            return
        }
        
        let searchTerm = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://itunes.apple.com/search?media=podcast&term=\(searchTerm)"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid search URL"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(SearchResults.self, from: data)
            
            podcasts = decoded.results
            print("Decoded \(decoded.results.count) podcasts")
        } catch {
            print("Search failed: \(error)")
            errorMessage = "Search failed. Please try again."
            podcasts = []
        }
        
        isLoading = false
    }
}

//MARK: - AudioPlayerViewModel
@MainActor
class AudioPlayerViewModel: ObservableObject {
    static let shared = AudioPlayerViewModel()
    private let elapsedTimesKey = "episodeElapsedTimes"
    private let playbackSpeedKey = "playbackSpeed"
    private let completedKey = "episodeCompleted"
    
    private var timeObserverToken: Any?
    private var player: AVPlayer?
    private var playerItemObserver: NSObjectProtocol?
    private var currentPlayerItem: AVPlayerItem?
    private var saveTimer: Timer?
    private var audioSessionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    
    @Published var episode: Episode?
    @Published var isPlaying = false
    @Published var currentTime: Double = 0
    @Published var durationTime: Double = 0
    @Published var isPlayerSheetVisible: Bool = false
    @Published var podcastImageURL: String?
    @Published var episodeQueue: [Episode] = []
    @Published var playbackSpeed: Float = 1.0
    
    @Published private(set) var elapsedTimes: [String: Double] = [:]
    @Published private(set) var episodeCompleted: [String: Bool] = [:]
    
    var showMiniPlayer: Bool {
        episode != nil && (isPlaying || currentTime > 0)
    }
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: elapsedTimesKey),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.elapsedTimes = saved
        }
        
        if let data = UserDefaults.standard.data(forKey: completedKey),
           let saved = try? JSONDecoder().decode([String: Bool].self, from: data) {
            self.episodeCompleted = saved
        }
        
        self.playbackSpeed = UserDefaults.standard.object(forKey: playbackSpeedKey) as? Float ?? 1.0
        
        configureAudioSession()
        setupAudioSessionObservers()
        setupRemoteTransportControls()
        
    }
    
    func load(episode: Episode, podcastImageURL: String? = nil) {
        cleanupCurrentEpisodeObservers()
        
        if self.episode?.audioURL == episode.audioURL { return }
        
        self.episode = episode
        self.podcastImageURL = podcastImageURL
        
        episodeQueue.removeAll { $0.id == episode.id }
        
        setupRemoteTransportControls()
        
        let downloadManager = DownloadManager.shared
        let audioURL: URL
                
        if downloadManager.isDownloaded(episode.id),
           let localURL = downloadManager.getLocalURL(for: episode.id) {
            
            if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path) {
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("📁 File size: \(fileSize) bytes")
            }
            audioURL = localURL
        } else if let url = URL(string: episode.audioURL) {
            audioURL = url
        } else {
            return
        }
        
        print("🎧 Creating player with URL: \(audioURL)")
        let asset = AVURLAsset(url: audioURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        updateDurationFromAsset(asset)
        self.isPlaying = false
        
        print("👀 Setting up observer for player item: \(playerItem)")

        setupPlayerItemObserver(for: playerItem)
        
        // Check player item status after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if let item = self.player?.currentItem {
                if let error = item.error {
                    print("❌ Player error: \(error.localizedDescription)")
                }
            }
        }
        
        // Check player item status after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if let item = self.player?.currentItem {
                switch item.status {
                case .readyToPlay:
                    print("Player item status: ready to play")
                case .failed:
                    print("Player item status: failed")
                    if let error = item.error {
                        print("Player error: \(error.localizedDescription)")
                    }
                case .unknown:
                    print("Player item status: unknown")
                @unknown default:
                    print("Player item status: other")
                }
            }
        }
        
        addPeriodicTimeObserver()
        
        // REPLACE the savedTime restoration with this:
        let settings = PodcastSortPreferences.shared.getSettings(for: episode.podcastName ?? "")
        
        // Check if episode was completed
        if episodeCompleted[episode.audioURL] == true {
            // Episode was completed, start from beginning
            if settings.skipIntroSeconds > 0 {
                let cmTime = CMTime(seconds: settings.skipIntroSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                player?.seek(to: cmTime)
            }
            // Reset the completed flag
            episodeCompleted[episode.audioURL] = false
            saveCompletedStatus()
        } else if let savedTime = elapsedTimes[episode.audioURL], savedTime > 0 {
            // Episode in progress, resume from saved position
            let cmTime = CMTime(seconds: savedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime)
        } else if settings.skipIntroSeconds > 0 {
            // First time playing, skip intro
            let cmTime = CMTime(seconds: settings.skipIntroSeconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime)
        }
        
        updateNowPlayingInfo()
        StatisticsManager.shared.startListeningSession(for: episode)
        SessionManager.shared.startEpisodeInSession(episode: episode)
    }
    
    private func saveCompletedStatus() {
        if let data = try? JSONEncoder().encode(episodeCompleted) {
            UserDefaults.standard.set(data, forKey: completedKey)
        }
    }
    
    @MainActor
    private func cleanupCurrentEpisodeObservers() {
        // Remove player item observer
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
            playerItemObserver = nil
        }
        currentPlayerItem = nil
        
        // Remove time observer
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
    }
    
    @MainActor
    private func setupPlayerItemObserver(for playerItem: AVPlayerItem) {
        currentPlayerItem = playerItem
        playerItemObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self = self,
                      let notificationItem = notification.object as? AVPlayerItem,
                      notificationItem == self.currentPlayerItem else {
                    return
                }
                self.playerDidFinishPlaying()
            }
        }
    }
    
    @MainActor
    private func cleanupAllObservers() {
        // Clean up current episode observers
        cleanupCurrentEpisodeObservers()
        
        // Clean up audio session observers
        if let observer = audioSessionObserver {
            NotificationCenter.default.removeObserver(observer)
            audioSessionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
   
        // Clear now playing info
        clearNowPlayingInfo()
        
    }
    
    func cleanup() {
        StatisticsManager.shared.endListeningSession(completed: false)
        cleanupAllObservers()
        clearNowPlayingInfo()
        player?.pause()
        player = nil
        episode = nil
        isPlaying = false
    }
    
    @MainActor
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        
        if let token = timeObserverToken {
                player.removeTimeObserver(token)
                timeObserverToken = nil
            }
        
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.currentTime = time.seconds
                self.savePlaybackProgress()
                
                self.updateNowPlayingInfo()
                
                if let episode = self.episode,
                   let podcastName = episode.podcastName {
                    let settings = PodcastSortPreferences.shared.getSettings(for: podcastName)
                    let timeRemaining = self.durationTime - self.currentTime
                    
                    if settings.skipOutroSeconds > 0 &&
                        timeRemaining <= settings.skipOutroSeconds &&
                        timeRemaining > 0.5 {
                        // Mark as played and handle cleanup before moving to next
                        if let episodeID = self.episode?.id {
                            EpisodeTrackingManager.shared.markAsPlayed(episodeID)
                            StatisticsManager.shared.markEpisodeCompleted(episodeID)
                            
                            if let episode = self.episode {
                                self.episodeCompleted[episode.audioURL] = true
                                self.saveCompletedStatus()
                            }
                            
                            if DownloadManager.shared.autoDeleteOnCompletion &&
                                DownloadManager.shared.isDownloaded(episodeID) {
                                DownloadManager.shared.deleteDownload(episodeID)
                            }
                        }
                        
                        StatisticsManager.shared.endListeningSession(completed: true)
                        SessionManager.shared.endCurrentEpisodeSession(completed: true)
                        // Skip to end to trigger next episode
                        self.playerDidFinishPlaying()
                    }
                }
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
            player.pause()
            isPlaying = false
            savePlaybackProgress()
            StatisticsManager.shared.pauseSession()
            SessionManager.shared.pauseEpisodeInSession()
        } else {
            player.rate = playbackSpeed // Use the current speed setting
            isPlaying = true
            SessionManager.shared.resumeEpisodeInSession()
            
            if let episode = episode {
                StatisticsManager.shared.startListeningSession(for: episode)
            }
        }
        
        updateNowPlayingInfo()
    }
    
    func skipForward(seconds: Double = 30) {
        guard let player = player else { return }
        let current = player.currentTime()
        let newTime = CMTime(seconds: current.seconds + seconds, preferredTimescale: current.timescale)
        player.seek(to: newTime) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func skipBackward(seconds: Double = 10) {
        guard let player = player else { return }
        let current = player.currentTime()
        let newTime = CMTime(seconds: max(current.seconds - seconds, 0), preferredTimescale: current.timescale)
        player.seek(to: newTime) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func seek(to time: CMTime) {
        player?.seek(to: time) { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateNowPlayingInfo()
            }
        }
    }
    
    func formattedTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "0:00" }
        
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func updateDurationFromAsset(_ asset: AVURLAsset) {
        Task {
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                if seconds.isFinite && seconds > 0 {
                    await MainActor.run {
                        self.durationTime = seconds
                        self.episode?.duration = self.formattedTime(seconds)
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("Failed to load real duration: \(error)")
            }
        }
    }
    
    private func playerDidFinishPlaying() {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            
            if let episodeID = self.episode?.id {
                EpisodeTrackingManager.shared.markAsPlayed(episodeID)
                StatisticsManager.shared.markEpisodeCompleted(episodeID)
                
                if let episode = self.episode {
                    self.episodeCompleted[episode.audioURL] = true
                    self.saveCompletedStatus()
                }
                
                if DownloadManager.shared.autoDeleteOnCompletion &&
                    DownloadManager.shared.isDownloaded(episodeID) {
                    DownloadManager.shared.deleteDownload(episodeID)
                }
            }
            
            
            StatisticsManager.shared.endListeningSession(completed: true)
            SessionManager.shared.endCurrentEpisodeSession(completed: true)
            
            self.isPlaying = false
            self.currentTime = 0
            self.isPlayerSheetVisible = false
            
            if !episodeQueue.isEmpty {
                let nextEpisode = episodeQueue.removeFirst()
                self.load(episode: nextEpisode, podcastImageURL: nextEpisode.podcastImageURL)
                self.play()
            } else {
                self.clearNowPlayingInfo()
                
                SessionManager.shared.endSession()
                
                self.cleanupCurrentEpisodeObservers()
                self.episode = nil
                self.podcastImageURL = nil
                self.player?.seek(to: .zero)
                self.player = nil
            }
        }
    }
    
    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("🎵 Cleared Now Playing info from lock screen")
    }
    
    func addToQueue(_ episode: Episode) {
        episodeQueue.append(episode)
    }
    
    func play() {
        player?.rate = playbackSpeed // Use the current speed setting
        isPlaying = true
    }
    
    private func saveElapsedTimes() {
        if let data = try? JSONEncoder().encode(elapsedTimes) {
            UserDefaults.standard.set(data, forKey: elapsedTimesKey)
        }
    }

    private func savePlaybackProgress() {
        if let current = self.episode {
            elapsedTimes[current.audioURL] = currentTime
            
            if saveTimer == nil {
                saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                    Task { @MainActor in
                        self?.saveElapsedTimes()
                        self?.saveTimer = nil
                    }
                }
            }
        }
    }
    
    func playNow(_ episode: Episode, podcastImageURL: String? = nil) {
        load(episode: episode, podcastImageURL: podcastImageURL)
        togglePlayPause()
    }
    
    func playFromQueue(_ episode: Episode) {
        episodeQueue.removeAll { $0.id == episode.id }
        
        load(episode: episode, podcastImageURL: episode.podcastImageURL)
        togglePlayPause()
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = isPlaying ? speed : 0
        
        // Save the speed setting
        UserDefaults.standard.set(speed, forKey: playbackSpeedKey)
        
        // Update now playing info
        updateNowPlayingInfo()
    }
    
    private func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Set category for playback with ability to mix with other audio when needed
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [])
            
            // Activate the session
            try audioSession.setActive(true)
            
            print("Audio session configured successfully")
        } catch {
            print("Failed to configure audio session: \(error)")
        }
    }
    
    private func setupAudioSessionObservers() {
        let notificationCenter = NotificationCenter.default
        
        // Handle audio interruptions (calls, other audio apps)
        audioSessionObserver = notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioSessionInterruption(notification)
            }
        }
        
        // Handle route changes (headphones plugged/unplugged, AirPods connection)
        routeChangeObserver = notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleAudioRouteChange(notification)
            }
        }
    }
    
    @MainActor
    private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began (phone call, other audio app started)
            if isPlaying {
                player?.pause()
                isPlaying = false
                savePlaybackProgress()
            }
            
        case .ended:
            // Interruption ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Resume playback if the system suggests we should
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.player?.play()
                    self?.isPlaying = true
                }
            }
            
        @unknown default:
            break
        }
    }
    
    @MainActor
    private func handleAudioRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones were unplugged or AirPods disconnected
            if isPlaying {
                player?.pause()
                isPlaying = false
                savePlaybackProgress()
            }
            
        case .newDeviceAvailable, .routeConfigurationChange:
            // New audio device connected or route changed
            break
            
        case .unknown, .categoryChange, .override, .wakeFromSleep, .noSuitableRouteForCategory:
            // Handle other route change reasons - typically no action needed
            break
            
        @unknown default:
            break
        }
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        // Disable all commands first to reset
        commandCenter.skipForwardCommand.isEnabled = false
        commandCenter.skipBackwardCommand.isEnabled = false
        commandCenter.nextTrackCommand.isEnabled = false
        commandCenter.previousTrackCommand.isEnabled = false
        
        // Remove all existing targets
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        // Configure skip intervals BEFORE enabling
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 30)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 10)]
        
        // Now enable commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        
        // Add handlers
        commandCenter.playCommand.addTarget { [weak self] _ in
            print("🎧 Play command received")
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.player != nil && !self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            print("🎧 Pause command received")
            DispatchQueue.main.async {
                guard let self = self else { return }
                if self.isPlaying {
                    self.togglePlayPause()
                }
            }
            return .success
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] event in
            print("🎧 Skip Forward command received")
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let skipEvent = event as? MPSkipIntervalCommandEvent {
                    self.skipForward(seconds: skipEvent.interval)
                } else {
                    self.skipForward(seconds: 30)
                }
            }
            return .success
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] event in
            print("🎧 Skip Backward command received")
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let skipEvent = event as? MPSkipIntervalCommandEvent {
                    self.skipBackward(seconds: skipEvent.interval)
                } else {
                    self.skipBackward(seconds: 10)
                }
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            print("🎧 Next Track command received (mapped to skip forward)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.skipForward(seconds: 30)
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            print("🎧 Previous Track command received (mapped to skip backward)")
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.skipBackward(seconds: 10)
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            print("🎧 Change Playback Position command received")
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            
            DispatchQueue.main.async {
                guard let self = self else { return }
                let newTime = CMTime(seconds: event.positionTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                self.player?.seek(to: newTime)
            }
            return .success
        }
        
        verifyRemoteCommands()
    }
    
    private func verifyRemoteCommands() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        print("🎧 Remote Command Status:")
        print("  Play: \(commandCenter.playCommand.isEnabled)")
        print("  Pause: \(commandCenter.pauseCommand.isEnabled)")
        print("  Skip Forward: \(commandCenter.skipForwardCommand.isEnabled)")
        print("  Skip Backward: \(commandCenter.skipBackwardCommand.isEnabled)")
        print("  Next Track: \(commandCenter.nextTrackCommand.isEnabled)")
        print("  Previous Track: \(commandCenter.previousTrackCommand.isEnabled)")
    }
    
    private func updateNowPlayingInfo() {
        guard let episode = episode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        
        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: episode.podcastName ?? "Unknown Podcast",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: durationTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        
        // Add artwork if available
        if let imageURLString = episode.imageURL ?? podcastImageURL,
           let imageURL = URL(string: imageURLString) {
            
            // Check cache first
            if let cachedImage = ImageCache.shared.getImage(for: imageURLString) {
                let artwork = MPMediaItemArtwork(boundsSize: cachedImage.size) { _ in cachedImage }
                nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            } else {
                // Set info without artwork first
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                
                // Then fetch artwork in background
                URLSession.shared.dataTask(with: imageURL) { [weak self] data, _, _ in
                    if let data = data, let image = UIImage(data: data) {
                        // Cache the image
                        ImageCache.shared.setImage(image, for: imageURLString)
                        
                        DispatchQueue.main.async {
                            guard let self = self, self.episode?.id == episode.id else { return }
                            
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        }
                    }
                }.resume()
            }
        } else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        }
    }
    
    deinit {
        if let observer = audioSessionObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = playerItemObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Remove time observer
        if let token = timeObserverToken, let player = player {
            player.removeTimeObserver(token)
        }
        
        // Clean up remote command handlers
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
    }
}

//MARK: - LibraryViewModel
@MainActor
class LibraryViewModel: ObservableObject {
    @Published var subscriptions: [Podcast] = []
    @Published var allEpisodes: [Episode] = []
    @Published var isLoadingEpisodes = false
    @Published var layoutStyle: LibraryLayoutStyle = .list
    @Published var sortOrder: LibrarySortOrder = .dateAdded
    @Published var showUnplayedBadges: Bool = true
    
    private let subscriptionsKey = "subscribedPodcasts"
    private let layoutStyleKey = "libraryLayoutStyle"
    private let sortOrderKey = "librarySortOrder"
    private let showBadgesKey = "showUnplayedBadges"
    private let allEpisodesKey = "allEpisodesCache"
    
    private var allEpisodesFileURL: URL {
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return documentsPath.appendingPathComponent("allEpisodesCache.json")
        }
    
    init() {
        loadSubscriptions()
        loadPreferences()
        loadAllEpisodes()
        
        if !subscriptions.isEmpty {
            Task {
                await refreshAllEpisodes()
            }
        }
    }
    
    func subscribe(to podcast: Podcast) {
        if !subscriptions.contains(where: { $0.collectionName == podcast.collectionName }) {
            subscriptions.append(podcast)
            saveSubscriptions()
            Task {
                await refreshAllEpisodes()
            }
        }
    }
    
    func unsubscribe(from podcast: Podcast) {
        subscriptions.removeAll { $0.collectionName == podcast.collectionName }
        saveSubscriptions()
        Task {
            await refreshAllEpisodes()
        }
    }
    
    func refreshAllEpisodes() async {
        guard !subscriptions.isEmpty else {
            allEpisodes = []
            saveAllEpisodes()
            return
        }
        
        isLoadingEpisodes = true
        var episodes: [Episode] = []
        
        for podcast in subscriptions {
            guard let feedUrl = podcast.feedUrl,
                  let url = URL(string: feedUrl) else {
                continue
            }
            
            do {
                // Add timeout configuration
                var request = URLRequest(url: url)
                request.timeoutInterval = 30 // 30 seconds timeout
                request.cachePolicy = .reloadIgnoringLocalCacheData
                
                let (data, _) = try await URLSession.shared.data(for: request)
                let parser = RSSParser()
                let podcastEpisodes = parser.parse(data: data)
                
                // Add podcast info to episodes for display
                let episodesWithPodcastInfo = podcastEpisodes.map { episode in
                    Episode(
                        title: episode.title,
                        pubDate: episode.pubDate,
                        audioURL: episode.audioURL,
                        duration: episode.duration,
                        imageURL: episode.imageURL,
                        podcastImageURL: podcast.artworkUrl600,
                        description: episode.description,
                        podcastName: podcast.collectionName,
                        episodeNumber: episode.episodeNumber,
                        seasonNumber: episode.seasonNumber
                    )
                }
                
                episodes.append(contentsOf: episodesWithPodcastInfo)
            } catch {
                // Log error but continue with other podcasts
                let nsError = error as NSError
                if nsError.code == NSURLErrorTimedOut {
                    print("⏱️ Timeout fetching episodes for \(podcast.collectionName)")
                } else {
                    print("❌ Failed to fetch episodes for \(podcast.collectionName): \(error.localizedDescription)")
                }
            }
        }
        
        if !episodes.isEmpty {
            allEpisodes = episodes
            saveAllEpisodes()
        }
        isLoadingEpisodes = false
    }
    
    var recentEpisodes: [Episode] {
        let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        
        return allEpisodes
            .filter { episode in
                guard let pubDate = episode.pubDate else { return false }
                return pubDate >= twoWeeksAgo
            }
            .sorted { ($0.pubDate ?? Date.distantPast) > ($1.pubDate ?? Date.distantPast) }
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

    private func saveAllEpisodes() {
        do {
            let data = try JSONEncoder().encode(allEpisodes)
            try data.write(to: allEpisodesFileURL, options: .atomic)
            print("✅ Saved \(allEpisodes.count) episodes to file (\(data.count) bytes)")
        } catch {
            print("❌ Failed to save episodes: \(error)")
        }
    }
    
    // REPLACE loadAllEpisodes():
    private func loadAllEpisodes() {
        do {
            let data = try Data(contentsOf: allEpisodesFileURL)
            allEpisodes = try JSONDecoder().decode([Episode].self, from: data)
            print("✅ Loaded \(allEpisodes.count) episodes from file")
        } catch {
            print("⚠️ No cached episodes found or failed to load: \(error)")
            allEpisodes = []
        }
    }
    
    var sortedSubscriptions: [Podcast] {
        switch sortOrder {
        case .dateAdded:
            return subscriptions // Keep original order (date added)
        case .alphabetical:
            return subscriptions.sorted {
                stripLeadingArticles($0.collectionName).lowercased() < stripLeadingArticles($1.collectionName).lowercased()
            }
        }
    }

    // Add this helper function to LibraryViewModel
    private func stripLeadingArticles(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let lowercased = trimmed.lowercased()
        
        // Check for common articles at the beginning
        let articles = ["the ", "a ", "an "]
        
        for article in articles {
            if lowercased.hasPrefix(article) {
                // Return the string without the article
                let index = trimmed.index(trimmed.startIndex, offsetBy: article.count)
                return String(trimmed[index...])
            }
        }
        
        return trimmed
    }
    
    func getUnplayedCount(for podcast: Podcast) -> Int {
        let podcastEpisodes = allEpisodes.filter { $0.podcastName == podcast.collectionName }
        let trackingManager = EpisodeTrackingManager.shared
        let playedCount = podcastEpisodes.filter { trackingManager.isPlayed($0.id) }.count
        return podcastEpisodes.count - playedCount
    }
    
    func formatUnplayedCount(_ count: Int) -> String {
        if count == 0 {
            return ""
        } else if count < 100 {
            return "\(count)"
        } else if count < 1000 {
            // For 100-999, truncate to one decimal place (e.g., 0.1k, 0.5k, 0.9k)
            let truncated = floor(Double(count) / 100.0) / 10.0
            return String(format: "%.1fk", truncated)
        } else if count < 10000 {
            // For 1000-9999, truncate to one decimal place
            let truncated = floor(Double(count) / 100.0) / 10.0
            return String(format: "%.1fk", truncated)
        } else {
            return "+"
        }
    }
    
    private func savePreferences() {
        if let layoutData = try? JSONEncoder().encode(layoutStyle) {
            UserDefaults.standard.set(layoutData, forKey: layoutStyleKey)
        }
        if let sortData = try? JSONEncoder().encode(sortOrder) {
            UserDefaults.standard.set(sortData, forKey: sortOrderKey)
        }
        UserDefaults.standard.set(showUnplayedBadges, forKey: showBadgesKey)
    }
    
    private func loadPreferences() {
        if let data = UserDefaults.standard.data(forKey: layoutStyleKey),
           let decoded = try? JSONDecoder().decode(LibraryLayoutStyle.self, from: data) {
            layoutStyle = decoded
        }
        if let data = UserDefaults.standard.data(forKey: sortOrderKey),
           let decoded = try? JSONDecoder().decode(LibrarySortOrder.self, from: data) {
            sortOrder = decoded
        }
        showUnplayedBadges = UserDefaults.standard.bool(forKey: showBadgesKey)
        if UserDefaults.standard.object(forKey: showBadgesKey) == nil {
            showUnplayedBadges = true
        }
    }
    
    func updateLayoutStyle(_ style: LibraryLayoutStyle) {
        layoutStyle = style
        savePreferences()
    }
    
    func updateSortOrder(_ order: LibrarySortOrder) {
        sortOrder = order
        savePreferences()
    }
    
    func toggleUnplayedBadges() {
        showUnplayedBadges.toggle()
        savePreferences()
    }
}


//MARK: - Views

enum Tab {
    case home, search, library, statistics, queue
}

enum LibraryLayoutStyle: String, Codable, CaseIterable {
    case list = "List"
    case grid = "Grid"
    
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.3x3"
        }
    }
}

enum LibrarySortOrder: String, Codable, CaseIterable {
    case dateAdded = "Date Added"
    case alphabetical = "Alphabetical"
    
    var icon: String {
        switch self {
        case .dateAdded: return "clock"
        case .alphabetical: return "textformat"
        }
    }
}

//MARK: - ContentView
struct ContentView: View {
    @State private var selectedTab: Tab = .home
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @StateObject private var libraryVM = LibraryViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house")
                    }
                    .tag(Tab.home)
                
                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(Tab.search)
                
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "book.fill")
                    }
                    .tag(Tab.library)
                
                StatisticsView()
                    .tabItem {
                        Label("Statistics", systemImage: "chart.bar.fill")
                    }
                    .tag(Tab.statistics)
                
                QueueView()
                    .tabItem {
                        Label("Queue", systemImage: "text.badge.plus")
                    }
                    .tag(Tab.queue)
            }
            if audioVM.showMiniPlayer {
                MiniPlayerView()
                    .transition(.move(edge: .bottom))
                    .padding(.bottom, 49)
            }
        }
        .environmentObject(libraryVM)
        .sheet(isPresented: $audioVM.isPlayerSheetVisible) {
            if let episode = audioVM.episode {
                EpisodePlayerView(
                    episode: episode,
                    podcastTitle: episode.podcastName ?? "Unknown Podcast",
                    podcastImageURL: audioVM.podcastImageURL
                )
            }
        }
        .onAppear {
            cleanupOldUserDefaults()
        }
    }
    
    private func cleanupOldUserDefaults() {
            let defaults = UserDefaults.standard
            
            if defaults.object(forKey: "allEpisodesCache") != nil {
                defaults.removeObject(forKey: "allEpisodesCache")
                print("🧹 Cleaned up old allEpisodesCache from UserDefaults")
            }
            
            if defaults.object(forKey: "episodeStatuses") != nil {
                defaults.removeObject(forKey: "episodeStatuses")
                print("🧹 Cleaned up old episodeStatuses from UserDefaults")
            }
        }
}

//MARK: - HomeView
struct HomeView: View {
    @State private var showingSettings = false
    @ObservedObject private var statsManager = StatisticsManager.shared
    @EnvironmentObject var libraryVM: LibraryViewModel
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Welcome section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to MyPodcastApp")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let stats = statsManager.overallStats {
                            Text("You've listened to \(stats.totalListeningTimeFormatted) across \(stats.totalPodcasts) podcasts")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        } else {
                            Text("Start exploring podcasts to see your statistics")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    
                    // Recent subscriptions
                    if !libraryVM.subscriptions.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Your Subscriptions")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(libraryVM.subscriptions.prefix(5)) { podcast in
                                        NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                                            VStack {
                                                CachedAsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                                                    image.resizable()
                                                } placeholder: {
                                                    Color.gray
                                                }
                                                .frame(width: 120, height: 120)
                                                .cornerRadius(12)
                                                .shadow(radius: 4)
                                                
                                                Text(podcast.collectionName)
                                                    .font(.caption)
                                                    .lineLimit(2)
                                                    .multilineTextAlignment(.center)
                                                    .frame(width: 120, height: 40, alignment: .top)
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
            .navigationTitle("Home")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(isPresented: $showingSettings)
            }
        }
    }
}

//MARK: - SearchView
struct SearchView: View {
    @StateObject var fetcher = PodcastSearchViewModel()
    @State private var searchText: String = ""
    @FocusState private var isSearchFieldFocused: Bool
    
    var body: some View {
        NavigationStack {
            VStack {
                ZStack(alignment: .trailing) {
                    TextField("Search podcasts...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .focused($isSearchFieldFocused)
                        .onSubmit {
                            Task {
                                await fetcher.search(term: searchText)
                            }
                        }
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .padding(.trailing, 8)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding()
                .animation(.easeInOut(duration: 0.2), value: searchText.isEmpty)
                .onSubmit {
                    Task {
                        await fetcher.search(term: searchText)
                    }
                }
                
                if fetcher.isLoading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Searching...")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    Spacer()
                } else if let errorMessage = fetcher.errorMessage {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                            .padding(.bottom, 8)
                        
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Try Again") {
                            Task {
                                await fetcher.search(term: searchText)
                            }
                        }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                    }
                    .padding()
                    Spacer()
                } else if fetcher.podcasts.isEmpty && !searchText.isEmpty {
                    VStack {
                        Image(systemName: "magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                            .padding(.bottom, 8)
                        
                        Text("No podcasts found")
                            .font(.headline)
                            .foregroundColor(.gray)
                        
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    Spacer()
                } else {
                    List(fetcher.podcasts) { podcast in
                        NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                            HStack {
                                CachedAsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                .shadow(radius: 6)
                                
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
            }
            .navigationTitle("Search")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isSearchFieldFocused = false
                    }
                }
            }
        }
    }
}

//MARK: - PodcastSortPreferences
@MainActor
class PodcastSortPreferences: ObservableObject {
    static let shared = PodcastSortPreferences()
    
    @Published var sortOrders: [String: EpisodeSortOrder] = [:]
    @Published var podcastSettings: [String: PodcastSettings] = [:]
    @Published var hideArchivedSettings: [String: Bool] = [:]
    
    private let sortOrdersKey = "podcastSortOrders"
    private let settingsKey = "podcastSettings"
    private let hideArchivedKey = "podcastHideArchivedSettings"
    
    enum EpisodeSortOrder: String, Codable {
        case newestFirst = "Newest First"
        case oldestFirst = "Oldest First"
    }
    
    private init() {
        loadSortOrders()
    }
    
    func getSortOrder(for podcastName: String) -> EpisodeSortOrder {
        return sortOrders[podcastName] ?? .newestFirst
    }
    
    func setSortOrder(_ order: EpisodeSortOrder, for podcastName: String) {
        sortOrders[podcastName] = order
        saveSortOrders()
    }
    
    private func saveSortOrders() {
        if let data = try? JSONEncoder().encode(sortOrders) {
            UserDefaults.standard.set(data, forKey: sortOrdersKey)
        }
    }
    
    private func loadSortOrders() {
        if let data = UserDefaults.standard.data(forKey: sortOrdersKey),
           let decoded = try? JSONDecoder().decode([String: EpisodeSortOrder].self, from: data) {
            sortOrders = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode([String: PodcastSettings].self, from: data) {
            podcastSettings = decoded
        }
        
        if let data = UserDefaults.standard.data(forKey: hideArchivedKey),
           let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            hideArchivedSettings = decoded
        }
    }
    
    func getSettings(for podcastName: String) -> PodcastSettings {
        return podcastSettings[podcastName] ?? PodcastSettings()
    }
    
    func setSettings(_ settings: PodcastSettings, for podcastName: String) {
        podcastSettings[podcastName] = settings
        saveSettings()
    }
    
    private func saveSettings() {
        if let data = try? JSONEncoder().encode(podcastSettings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }
    
    func getHideArchived(for podcastName: String) -> Bool {
        return hideArchivedSettings[podcastName] ?? false
    }
    
    func setHideArchived(_ hide: Bool, for podcastName: String) {
        hideArchivedSettings[podcastName] = hide
        saveHideArchivedSettings()
    }
    
    private func saveHideArchivedSettings() {
        if let data = try? JSONEncoder().encode(hideArchivedSettings) {
            UserDefaults.standard.set(data, forKey: hideArchivedKey)
        }
    }
}

//MARK: - PodcastDetailView
struct PodcastDetailView: View {
    let podcast: Podcast
    @State private var episodes: [Episode] = []
    @State private var hasLoadedEpisodes = false
    @State private var isLoadingEpisodes = false
    @State private var loadingError: String?
    @State private var selectedEpisode: Episode?
    @State private var showFilterOptions = false
    @State private var isSelectionMode = false
    @State private var selectedEpisodes: Set<String> = []
    @State private var hideArchived = false
    @State private var searchText = ""
    @EnvironmentObject var libraryVM: LibraryViewModel
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    @ObservedObject private var sortPreferences = PodcastSortPreferences.shared
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    
    var filteredEpisodes: [Episode] {
        episodes.filter { episode in
            if hideArchived && trackingManager.isArchived(episode.id) {
                return false
            }
            if trackingManager.hidePlayedEpisodes && trackingManager.isPlayed(episode.id) {
                return false
            }
            return true
        }
    }
    
    var sortedAndFilteredEpisodes: [Episode] {
        let filtered = filteredEpisodes
        // Apply search filter
        let searchFiltered = searchText.isEmpty ? filtered : filtered.filter { episode in
            episode.title.localizedCaseInsensitiveContains(searchText)
        }
        
        let sortOrder = sortPreferences.getSortOrder(for: podcast.collectionName)
        
        switch sortOrder {
        case .newestFirst:
            return searchFiltered.sorted { ($0.pubDate ?? Date.distantPast) > ($1.pubDate ?? Date.distantPast) }
        case .oldestFirst:
            return searchFiltered.sorted { ($0.pubDate ?? Date.distantPast) < ($1.pubDate ?? Date.distantPast) }
        }
    }
    
    var body: some View {
        List {
            podcastHeaderSection
            
            if showFilterOptions {
                filterOptionsSection
                skipSettingsSection
            }
            
            contentSection
        }
        .listStyle(.plain)
        .refreshable {
            if let feedUrl = podcast.feedUrl {
                await fetchEpisodes(from: feedUrl)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if audioVM.showMiniPlayer {
                Color.clear.frame(height: 70)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                trailingToolbarButton
            }
            
            if isSelectionMode && !selectedEpisodes.isEmpty {
                ToolbarItem(placement: .navigationBarLeading) {
                    actionsMenu
                }
            }
        }
        .navigationDestination(item: $selectedEpisode) { episode in
            EpisodeDetailView(episode: episode, podcastTitle: podcast.collectionName, podcastImageURL: podcast.artworkUrl600)
        }
        .onAppear {
            hideArchived = sortPreferences.getHideArchived(for: podcast.collectionName)
            
            if !hasLoadedEpisodes {
                if let feedUrl = podcast.feedUrl {
                    Task {
                        await fetchEpisodes(from: feedUrl)
                    }
                } else {
                    loadingError = "This podcast doesn't have a valid RSS feed URL."
                    hasLoadedEpisodes = true
                }
            }
        }
    }
    
    // MARK: - Header Section
    private var podcastHeaderSection: some View {
        Section {
            VStack(spacing: 12) {
                if let imageUrl = URL(string: podcast.artworkUrl600) {
                    CachedAsyncImage(url: imageUrl) { image in
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
                
                HStack(spacing: 4) {
                    Text("\(episodes.count) episodes")
                    
                    let archivedCount = episodes.filter { trackingManager.isArchived($0.id) }.count
                    if archivedCount > 0 {
                        Text("•")
                        Text("\(archivedCount) archived")
                    }
                }
                .font(.subheadline)
                .foregroundColor(.gray)
                
                HStack(spacing: 12) {
                    subscribeButton
                    filterButton
                }
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search episodes...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 4)
                
                Divider()
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
    }
    
    private var subscribeButton: some View {
        let isSubscribed = libraryVM.subscriptions.contains(where: { $0.collectionName == podcast.collectionName })
          
          return Button(action: {
              if isSubscribed {
                  libraryVM.unsubscribe(from: podcast)
              } else {
                  libraryVM.subscribe(to: podcast)
              }
          }) {
              VStack(spacing: 4) {
                  Image(systemName: isSubscribed ? "minus.circle" : "plus.circle")
                      .font(.title2)
                      .foregroundColor(isSubscribed ? .red : .green)
                      .frame(height: 28)
                  Text(isSubscribed ? "Unsubscribe" : "Subscribe")
                      .font(.caption)
                      .foregroundColor(.primary)
                      .multilineTextAlignment(.center)
                      .frame(height: 32)
              }
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(PlainButtonStyle())
    }
    
    private var filterButton: some View {
        Button(action: {
               showFilterOptions.toggle()
           }) {
               VStack(spacing: 4) {
                   Image(systemName: "line.3.horizontal.decrease.circle")
                       .font(.title2)
                       .foregroundColor(.blue)
                       .frame(height: 28)
                   Text("Filter")
                       .font(.caption)
                       .foregroundColor(.primary)
                       .multilineTextAlignment(.center)
                       .frame(height: 32)
               }
               .frame(maxWidth: .infinity)
           }
           .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Filter Sections
    private var filterOptionsSection: some View {
        Section("Filter Options") {
            Toggle("Hide Played Episodes", isOn: $trackingManager.hidePlayedEpisodes)
            
            Toggle("Hide Archived Episodes", isOn: $hideArchived)
                .onChange(of: hideArchived) { _, newValue in
                    sortPreferences.setHideArchived(newValue, for: podcast.collectionName)
                }
            
            if !episodes.isEmpty {
                Button("Mark All as Played") {
                    trackingManager.markAllAsPlayed(for: episodes)
                }
                
                Button("Mark All as Unplayed") {
                    trackingManager.markAllAsUnplayed(for: episodes)
                }
            }
            
            Toggle("Show Oldest First", isOn: Binding(
                get: { sortPreferences.getSortOrder(for: podcast.collectionName) == .oldestFirst },
                set: { isOn in
                    sortPreferences.setSortOrder(
                        isOn ? .oldestFirst : .newestFirst,
                        for: podcast.collectionName
                    )
                }
            ))
        }
    }
    
    private var skipSettingsSection: some View {
        Section("Skip Settings") {
            SkipIntroOutroSettings(podcastName: podcast.collectionName)
        }
    }
    
    // MARK: - Content Section
    @ViewBuilder
    private var contentSection: some View {
        if isLoadingEpisodes {
            loadingStateView
        } else if let error = loadingError {
            errorStateView(error: error)
        } else if sortedAndFilteredEpisodes.isEmpty && hasLoadedEpisodes {
            emptyStateView
        } else {
            episodesListView
        }
    }
    
    private var loadingStateView: some View {
        Section {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Loading episodes...")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    private func errorStateView(error: String) -> some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                Text("Failed to Load Episodes")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                Button("Try Again") {
                    if let feedUrl = podcast.feedUrl {
                        Task {
                            await fetchEpisodes(from: feedUrl)
                        }
                    }
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    private var emptyStateView: some View {
        Section {
            VStack(spacing: 12) {
                Image(systemName: episodes.isEmpty ? "podcast" : "eye.slash")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                
                Text(episodes.isEmpty ? "No Episodes Available" : "No Episodes to Show")
                    .font(.headline)
                    .foregroundColor(.gray)
                
                Text(episodes.isEmpty ?
                     "This podcast feed doesn't contain any episodes or they couldn't be parsed." :
                        "All episodes are hidden by your current filter settings for this podcast.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                
                if !episodes.isEmpty {
                    Button("Show All Episodes") {
                        trackingManager.hidePlayedEpisodes = false
                        hideArchived = false
                        sortPreferences.setHideArchived(false, for: podcast.collectionName)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
    }
    
    // MARK: - Episodes List
    private var episodesListView: some View {
        ForEach(Array(sortedAndFilteredEpisodes.enumerated()), id: \.element.id) { index, episode in
            episodeRow(index: index, episode: episode)
        }
    }
    
    private func episodeRow(index: Int, episode: Episode) -> some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                selectionButton(for: episode)
            }
            
            EpisodeRowView(episode: episode, podcastImageURL: podcast.artworkUrl600)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    handleEpisodeTap(episode: episode)
                }
                .onLongPressGesture {
                    handleEpisodeLongPress(episode: episode)
                }
                .contextMenu {
                    episodeContextMenu(index: index, episode: episode)
                }
        }
    }
    
    private func selectionButton(for episode: Episode) -> some View {
        Button(action: {
            toggleEpisodeSelection(episode: episode)
        }) {
            Image(systemName: selectedEpisodes.contains(episode.id) ? "checkmark.circle.fill" : "circle")
                .foregroundColor(selectedEpisodes.contains(episode.id) ? .blue : .gray)
                .font(.title3)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    @ViewBuilder
    private func episodeContextMenu(index: Int, episode: Episode) -> some View {
        if isSelectionMode {
            Button(action: {
                selectAllAbove(index: index)
            }) {
                Label("Select All Above", systemImage: "arrow.up.to.line")
            }
            
            Button(action: {
                selectAllBelow(index: index)
            }) {
                Label("Select All Below", systemImage: "arrow.down.to.line")
            }
            
            Button(action: {
                selectAll()
            }) {
                Label("Select All", systemImage: "checkmark.circle")
            }
            
            Button(action: {
                deselectAll()
            }) {
                Label("Deselect All", systemImage: "circle")
            }
        } else {
            EpisodeContextMenuContent(episode: episode)
        }
    }
    
    // MARK: - Toolbar
    private var trailingToolbarButton: some View {
        Group {
            if isSelectionMode {
                HStack(spacing: 8) {
                    Button("Done") {
                        isSelectionMode = false
                        selectedEpisodes.removeAll()
                    }
                    
                    Menu {
                        Button(action: {
                            selectAll()
                        }) {
                            Label("Select All", systemImage: "checkmark.circle")
                        }
                        
                        Button(action: {
                            deselectAll()
                        }) {
                            Label("Deselect All", systemImage: "circle")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            } else {
                Button("Select") {
                    isSelectionMode = true
                }
            }
        }
    }
    
    private var actionsMenu: some View {
        Menu {
            Button("Mark as Played") {
                for episodeID in selectedEpisodes {
                    trackingManager.markAsPlayed(episodeID)
                }
                selectedEpisodes.removeAll()
                isSelectionMode = false
            }
            
            Button("Mark as Unplayed") {
                for episodeID in selectedEpisodes {
                    trackingManager.markAsUnplayed(episodeID)
                }
                selectedEpisodes.removeAll()
                isSelectionMode = false
            }
            
            Button("Archive") {
                for episodeID in selectedEpisodes {
                    trackingManager.archive(episodeID)
                }
                selectedEpisodes.removeAll()
                isSelectionMode = false
            }
            
            Button("Unarchive") {
                for episodeID in selectedEpisodes {
                    trackingManager.unarchive(episodeID)
                }
                selectedEpisodes.removeAll()
                isSelectionMode = false
            }
            
            Divider()
            
            Button("Select All") {
                selectAll()
            }
            
            Button("Deselect All") {
                deselectAll()
            }
        } label: {
            Text("Actions (\(selectedEpisodes.count))")
        }
    }
    
    // MARK: - Helper Methods
    private func toggleEpisodeSelection(episode: Episode) {
        if selectedEpisodes.contains(episode.id) {
            selectedEpisodes.remove(episode.id)
        } else {
            selectedEpisodes.insert(episode.id)
        }
    }
    
    private func handleEpisodeTap(episode: Episode) {
        if isSelectionMode {
            toggleEpisodeSelection(episode: episode)
        } else {
            selectedEpisode = episode
        }
    }
    
    private func handleEpisodeLongPress(episode: Episode) {
        if !isSelectionMode {
            isSelectionMode = true
            selectedEpisodes.insert(episode.id)
        }
    }
    
    func selectAllAbove(index: Int) {
        guard index < sortedAndFilteredEpisodes.count else { return }

        for i in 0...index {
            if i < sortedAndFilteredEpisodes.count {
                selectedEpisodes.insert(sortedAndFilteredEpisodes[i].id)
            }
        }
    }
    
    func selectAllBelow(index: Int) {
        guard index < sortedAndFilteredEpisodes.count else { return }

        for i in index..<sortedAndFilteredEpisodes.count {
            selectedEpisodes.insert(sortedAndFilteredEpisodes[i].id)
        }
    }
    
    func selectAll() {
        selectedEpisodes = Set(sortedAndFilteredEpisodes.map { $0.id })
    }
    
    func deselectAll() {
        selectedEpisodes.removeAll()
    }
    
    func fetchEpisodes(from feedUrl: String) async {
        guard let url = URL(string: feedUrl) else {
            loadingError = "Invalid RSS feed URL."
            hasLoadedEpisodes = true
            return
        }
        
        isLoadingEpisodes = true
        loadingError = nil
        
        do {
            // Add timeout configuration
            var request = URLRequest(url: url)
            request.timeoutInterval = 30 // 30 seconds timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData // Ensure fresh data
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 404 {
                    isLoadingEpisodes = false
                    hasLoadedEpisodes = true
                    loadingError = "Podcast feed not found (404). This feed may have been moved or deleted."
                    return
                } else if httpResponse.statusCode >= 500 {
                    isLoadingEpisodes = false
                    hasLoadedEpisodes = true
                    loadingError = "Server error (\(httpResponse.statusCode)). The podcast server is experiencing issues. Please try again later."
                    return
                } else if httpResponse.statusCode >= 400 {
                    isLoadingEpisodes = false
                    hasLoadedEpisodes = true
                    loadingError = "Server error (\(httpResponse.statusCode)). Please try again later."
                    return
                }
            }
            
            if data.isEmpty {
                isLoadingEpisodes = false
                hasLoadedEpisodes = true
                loadingError = "The podcast feed is empty."
                return
            }
            
            let parser = RSSParser()
            let parsedEpisodes = parser.parse(data: data)
            
            isLoadingEpisodes = false
            hasLoadedEpisodes = true
            
            if parsedEpisodes.isEmpty {
                loadingError = "Unable to parse episodes from this podcast feed. The feed may be malformed or in an unsupported format."
            } else {
                episodes = parsedEpisodes
                print("Successfully loaded \(parsedEpisodes.count) episodes")
            }
            
        } catch {
            isLoadingEpisodes = false
            hasLoadedEpisodes = true
            
            let nsError = error as NSError
            
            // Handle specific error types
            switch nsError.code {
            case NSURLErrorTimedOut:
                loadingError = "Request timed out. The podcast feed is taking too long to respond. Please check your connection and try again."
                
            case NSURLErrorNotConnectedToInternet:
                loadingError = "No internet connection. Please check your network and try again."
                
            case NSURLErrorNetworkConnectionLost:
                loadingError = "Network connection lost. Please check your connection and try again."
                
            case NSURLErrorCannotConnectToHost:
                loadingError = "Cannot connect to the podcast server. The server may be down or unreachable."
                
            case NSURLErrorDNSLookupFailed:
                loadingError = "Cannot find the podcast server. Please check the feed URL."
                
            case NSURLErrorBadServerResponse:
                loadingError = "The server sent an invalid response. Please try again later."
                
            default:
                loadingError = "Network error: \(error.localizedDescription)"
            }
            
            print("❌ Failed to fetch episodes: \(error.localizedDescription) (code: \(nsError.code))")
        }
    }
}

//MARK: - EpisodeRowView
struct EpisodeRowView: View {
    let episode: Episode
    let podcastImageURL: String?
    let onPlayTapped: (() -> Void)?
    let showPodcastName: Bool
    
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    
    private var isCurrentlyPlaying: Bool {
        audioVM.episode?.id == episode.id && audioVM.isPlaying
    }
    
    private var isCurrentEpisode: Bool {
        audioVM.episode?.id == episode.id
    }
    
    private var displayDuration: String {
        // Check if episode has any saved progress
        if let savedTime = audioVM.elapsedTimes[episode.audioURL],
           savedTime > 0 {
            
            // Get the actual duration in seconds from the player if this is the current episode
            let actualDurationSeconds: Double
            if audioVM.episode?.id == episode.id && audioVM.durationTime > 0 {
                // Use the precise duration from the audio player
                actualDurationSeconds = audioVM.durationTime
            } else if let durationStr = episode.duration {
                // Parse duration string to get total seconds
                let parts = durationStr.split(separator: ":").map { Int($0) ?? 0 }
                let totalSeconds: Int
                switch parts.count {
                case 3:
                    totalSeconds = parts[0] * 3600 + parts[1] * 60 + parts[2]
                case 2:
                    totalSeconds = parts[0] * 60 + parts[1]
                case 1:
                    totalSeconds = parts[0]
                default:
                    // Can't parse duration, show original
                    return episode.durationInMinutes ?? ""
                }
                actualDurationSeconds = Double(totalSeconds)
            } else {
                // No duration available, show original
                return episode.durationInMinutes ?? ""
            }
            
            // Calculate remaining time
            let remainingSeconds = actualDurationSeconds - savedTime
            
            // Convert to minutes, rounding UP (ceiling) to match user expectations
            let remainingMinutes = Int(ceil(remainingSeconds / 60.0))
            let hours = remainingMinutes / 60
            let minutes = remainingMinutes % 60
            
            if hours > 0 {
                if minutes == 0 {
                    return "\(hours)h remaining"
                } else {
                    return "\(hours)h \(minutes)min remaining"
                }
            } else {
                return "\(minutes)min remaining"
            }
        }
        
        // Default: show total duration
        return episode.durationInMinutes ?? ""
    }
    
    init(episode: Episode, podcastImageURL: String?, showPodcastName: Bool = false, onPlayTapped: (() -> Void)? = nil) {
        self.episode = episode
        self.podcastImageURL = podcastImageURL
        self.showPodcastName = showPodcastName
        self.onPlayTapped = onPlayTapped ?? {
            if AudioPlayerViewModel.shared.episode?.id == episode.id {
                AudioPlayerViewModel.shared.togglePlayPause()
            } else {
                AudioPlayerViewModel.shared.playNow(episode, podcastImageURL: podcastImageURL)
            }
        }
    }
    
    var body: some View {
            HStack(spacing: 8) {
                CachedAsyncImage(url: URL(string: episode.imageURL ?? podcastImageURL ?? "")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 70, height: 70)
                .cornerRadius(8)
                .shadow(radius: 6)
                .opacity(trackingManager.isPlayed(episode.id) ? 0.6 : 1.0)
                
                VStack(alignment: .leading, spacing: 2) {
                    if showPodcastName, let podcastName = episode.podcastName {
                        Text(podcastName)
                            .font(.caption2)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                    
                    if let seasonNumber = episode.seasonNumber, !seasonNumber.isEmpty,
                       let episodeNumber = episode.episodeNumber, !episodeNumber.isEmpty {
                        Text("S\(seasonNumber) E\(episodeNumber)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    } else if let episodeNumber = episode.episodeNumber, !episodeNumber.isEmpty {
                        Text("Episode \(episodeNumber)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    
                    Text(episode.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundColor(isCurrentEpisode ? .blue : (trackingManager.isPlayed(episode.id) ? .gray : .primary))
                        .strikethrough(trackingManager.isPlayed(episode.id), color: .gray)
                    
                    HStack(spacing: 4) {
                        if trackingManager.isPlayed(episode.id) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        
                        if trackingManager.isArchived(episode.id) && !trackingManager.isPlayed(episode.id) {
                            Image(systemName: "archivebox.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                        
                        if downloadManager.isDownloading(episode.id) {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 12, height: 12)
                        } else if downloadManager.isDownloaded(episode.id) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue)
                        }
                        
                        if audioVM.episodeQueue.contains(where: { $0.id == episode.id }) {
                            Image(systemName: "text.badge.plus")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                    }
                    
                    HStack(spacing: 4) {
                        if let pubDate = episode.pubDate {
                                Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if episode.pubDate != nil && !displayDuration.isEmpty {
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            
                            if !displayDuration.isEmpty {
                                Text(displayDuration)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .id(isCurrentEpisode ? audioVM.currentTime : 0)
                            }
                    }
                    .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button(action: {
                    onPlayTapped?()
                }) {
                    Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.vertical, 8)
            .swipeActions(edge: .leading) {
                Button(action: {
                    AudioPlayerViewModel.shared.addToQueue(episode)
                }) {
                    Label("Queue", systemImage: "text.badge.plus")
                }
            .tint(.blue)
        }
    }
}

//MARK: - EpisodeDetailView
struct EpisodeDetailView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    
    let episode: Episode
    let podcastTitle: String
    let podcastImageURL: String?
    
    var isCurrentlyPlaying: Bool {
        audioVM.episode?.id == episode.id && audioVM.isPlaying
    }
    
    var isInQueue: Bool {
        audioVM.episodeQueue.contains(where: { $0.id == episode.id })
    }
    
    var isDownloaded: Bool {
        downloadManager.isDownloaded(episode.id)
    }
    
    var isDownloading: Bool {
        downloadManager.isDownloading(episode.id)
    }
    
    var downloadProgress: Double {
        downloadManager.downloadProgress[episode.id] ?? 0.0
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                CachedAsyncImage(url: URL(string: episode.imageURL ?? podcastImageURL ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 300, height: 300)
                .cornerRadius(16)
                .shadow(radius: 6)
                .padding(.top)
                
                HStack(spacing: 8) {
                    if trackingManager.isPlayed(episode.id) {
                        Label("Played", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .foregroundColor(.green)
                            .cornerRadius(8)
                    }
                    
                    if trackingManager.isArchived(episode.id) {
                        Label("Archived", systemImage: "archivebox.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(8)
                    }
                    
                    if isDownloaded {
                        Label("Downloaded", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.2))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                    }
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
                            audioVM.episodeQueue.removeAll { $0.id == episode.id }
                            audioVM.playNow(episode, podcastImageURL: podcastImageURL)
                        }
                    }) {
                        Image(systemName: isCurrentlyPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .resizable()
                            .frame(width: 100, height: 100)
                            .foregroundColor(.blue)
                    }
                }
                
                // All buttons in one row
                HStack(spacing: 32) {
                    // Queue Button
                    Button(action: {
                        if isInQueue {
                            audioVM.episodeQueue.removeAll { $0.id == episode.id }
                        } else {
                            audioVM.addToQueue(episode)
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: isInQueue ? "text.badge.minus" : "text.badge.plus")
                                .font(.title2)
                                .foregroundColor(isInQueue ? .red : .blue)
                                .frame(height: 28)
                            Text(isInQueue ? "Unqueue" : "Queue")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Download Button
                    Button(action: {
                        if isDownloaded {
                            downloadManager.deleteDownload(episode.id)
                        } else if isDownloading {
                            downloadManager.cancelDownload(episode.id)
                        } else {
                            downloadManager.downloadEpisode(episode)
                        }
                    }) {
                        VStack(spacing: 4) {
                            if isDownloading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(1.2)
                                    .frame(height: 28)
                            } else {
                                Image(systemName: isDownloaded ? "trash" : "arrow.down.circle")
                                    .font(.title2)
                                    .foregroundColor(isDownloaded ? .red : .green)
                                    .frame(height: 28)
                            }
                            Text(isDownloading ? "\(Int(downloadProgress * 100))%" : (isDownloaded ? "Delete" : "Download"))
                                .font(.caption)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Mark Played/Unplayed Button
                    Button(action: {
                        if trackingManager.isPlayed(episode.id) {
                            trackingManager.markAsUnplayed(episode.id)
                        } else {
                            trackingManager.markAsPlayed(episode.id)
                        }
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: trackingManager.isPlayed(episode.id) ? "circle" : "checkmark.circle.fill")
                                .font(.title2)
                                .foregroundColor(trackingManager.isPlayed(episode.id) ? .gray : .green)
                                .frame(height: 28)
                            Text(trackingManager.isPlayed(episode.id) ? "Unplayed" : "Played")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Archive/Unarchive Button
                    Button(action: {
                        trackingManager.toggleArchived(episode.id)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: trackingManager.isArchived(episode.id) ? "tray.and.arrow.up" : "archivebox")
                                .font(.title2)
                                .foregroundColor(trackingManager.isArchived(episode.id) ? .blue : .orange)
                                .frame(height: 28)
                            Text(trackingManager.isArchived(episode.id) ? "Unarchive" : "Archive")
                                .font(.caption)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .frame(height: 32)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Divider()
                
                if let desc = episode.description {
                    EpisodeDescriptionView(htmlString: desc)
                }
            }
            .padding(.bottom, audioVM.showMiniPlayer ? 80 : 0)
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//MARK: - EpisodeDescriptionView
struct EpisodeDescriptionView: View {
    let htmlString: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        if let description = parsedDescription {
            Text(description)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var parsedDescription: AttributedString? {
        // Pre-process HTML to add line breaks between paragraphs
        let processedHTML = htmlString
            .replacingOccurrences(of: "</p>", with: "</p><br>")
        
        guard let data = processedHTML.data(using: .utf8) else { return nil }
        
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        
        if let nsAttrStr = try? NSAttributedString(data: data, options: options, documentAttributes: nil),
           var swiftUIAttrStr = try? AttributedString(nsAttrStr, including: \.uiKit) {
            
            // Apply color and base font while preserving existing traits (bold, italic, links)
            for run in swiftUIAttrStr.runs {
                let existingTraits = swiftUIAttrStr[run.range].uiKit.font?.fontDescriptor.symbolicTraits ?? []
                
                // Check if this run has a link
                let hasLink = swiftUIAttrStr[run.range].link != nil
                
                var font: UIFont
                if existingTraits.contains(.traitBold) && existingTraits.contains(.traitItalic) {
                    font = .systemFont(ofSize: 16, weight: .bold).italics()
                } else if existingTraits.contains(.traitBold) {
                    font = .systemFont(ofSize: 16, weight: .bold)
                } else if existingTraits.contains(.traitItalic) {
                    font = .italicSystemFont(ofSize: 16)
                } else {
                    font = .systemFont(ofSize: 16)
                }
                
                swiftUIAttrStr[run.range].font = Font(font)
                
                // Apply appropriate color based on whether it's a link
                if hasLink {
                    swiftUIAttrStr[run.range].foregroundColor = .blue
                    // Optional: add underline to links
                    swiftUIAttrStr[run.range].underlineStyle = .single
                } else {
                    swiftUIAttrStr[run.range].foregroundColor = colorScheme == .dark ? .white : .black
                }
            }
            
            return swiftUIAttrStr
        }
        
        return nil
    }
}

// Helper extension for italic font
extension UIFont {
    func italics() -> UIFont {
        guard let descriptor = fontDescriptor.withSymbolicTraits([.traitItalic, .traitBold]) else {
            return self
        }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}

//MARK: - EpisodePlayerView
struct EpisodePlayerView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @Environment(\.dismiss) var dismiss
    
    let episode: Episode
    let podcastTitle: String
    let podcastImageURL: String?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: {
                    audioVM.isPlayerSheetVisible = false
                    dismiss()
                }) {
                    Image(systemName: "chevron.down")
                        .font(.title2)
                        .padding()
                }
            }
        }
        ScrollView {
            VStack(spacing: 10) {
                CachedAsyncImage(url: URL(string: episode.imageURL ?? podcastImageURL ?? "")) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Color.gray.opacity(0.3)
                }
                .frame(width: 300, height: 300)
                .cornerRadius(16)
                .shadow(radius: 6)
                .padding(.top)
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
                        Image(systemName: "gobackward.10")
                            .font(.title)
                    }
                    Button(action: {
                        if audioVM.episode?.id != episode.id {
                            audioVM.playNow(episode)
                        }
                        audioVM.togglePlayPause() }) {
                            Image(systemName: audioVM.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 100))
                        }
                    Button(action: { audioVM.skipForward() }) {
                        Image(systemName: "goforward.30")
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
                    EpisodeDescriptionView(htmlString: desc)
                }
            }
            .padding(.bottom, audioVM.showMiniPlayer ? 80 : 0)
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
            HStack {
                ZStack(alignment: .bottomLeading) {
                    if let imageURL = audioVM.episode?.imageURL ?? audioVM.podcastImageURL,
                       let url = URL(string: imageURL) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable()
                        } placeholder: {
                            Color.gray
                        }
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .cornerRadius(8)
                        .shadow(radius: 6)
                    }
                    
                    // Progress bar overlay
                    if audioVM.durationTime > 0 {
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(Color.blue)
                                .frame(
                                    width: geometry.size.width * CGFloat(audioVM.currentTime / audioVM.durationTime),
                                    height: 3
                                )
                        }
                        .frame(height: 3)
                        .cornerRadius(1.5)
                        .offset(y: -3)
                    }
                }
                .frame(width: 50, height: 50)
                
                VStack(alignment: .leading, spacing: 2) {
                    if let episodeTitle = audioVM.episode?.title {
                        Text(episodeTitle)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                Spacer()
                
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
            .onTapGesture {
                audioVM.isPlayerSheetVisible = true
            }
        }
    }
}

//MARK: - PodcastGridItem
struct PodcastGridItem: View {
    let podcast: Podcast
    let unplayedCount: Int
    let showBadge: Bool
    @EnvironmentObject var libraryVM: LibraryViewModel
    
    var body: some View {
        NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    CachedAsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                        image
                            .resizable()
                            .scaledToFit()
                    } placeholder: {
                        Color.gray.opacity(0.3)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    
                    if showBadge && unplayedCount > 0 {
                        Text(libraryVM.formatUnplayedCount(unplayedCount))
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.red)
                            .cornerRadius(10)
                            .offset(x: 4, y: -4)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

//MARK: - LibrarySettingsSheet
struct LibrarySettingsSheet: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Layout") {
                    Picker("Style", selection: $libraryVM.layoutStyle) {
                        ForEach(LibraryLayoutStyle.allCases, id: \.self) { style in
                            Label(style.rawValue, systemImage: style.icon)
                                .tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: libraryVM.layoutStyle) { _, newValue in
                        libraryVM.updateLayoutStyle(newValue)
                    }
                }
                
                Section("Sort Order") {
                    Picker("Order", selection: $libraryVM.sortOrder) {
                        ForEach(LibrarySortOrder.allCases, id: \.self) { order in
                            Label(order.rawValue, systemImage: order.icon)
                                .tag(order)
                        }
                    }
                    .pickerStyle(.inline)
                    .onChange(of: libraryVM.sortOrder) { _, newValue in
                        libraryVM.updateSortOrder(newValue)
                    }
                }
                
                Section("Display Options") {
                    Toggle("Show Unplayed Count", isOn: $libraryVM.showUnplayedBadges)
                        .onChange(of: libraryVM.showUnplayedBadges) { _, _ in
                            libraryVM.toggleUnplayedBadges()
                        }
                }
            }
            .navigationTitle("Library Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

//MARK: - LibraryView
struct LibraryView: View {
    @EnvironmentObject var libraryVM: LibraryViewModel
    @State private var selectedTab: LibraryTab = .subscriptions
    @State private var selectedEpisode: Episode?
    @State private var showSettings = false
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    
    enum LibraryTab: String, CaseIterable, Identifiable {
        case subscriptions = "Subscriptions"
        case newReleases = "New Releases"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Library Tab", selection: $selectedTab) {
                    ForEach(LibraryTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                TabView(selection: $selectedTab) {
                    subscriptionsView
                        .tag(LibraryTab.subscriptions)
                    
                    newReleasesView
                        .tag(LibraryTab.newReleases)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .safeAreaInset(edge: .bottom) {
                if AudioPlayerViewModel.shared.showMiniPlayer {
                    Color.clear.frame(height: 70)
                }
            }
            .navigationTitle("Library")
            .navigationDestination(item: $selectedEpisode) { episode in
                EpisodeDetailView(
                    episode: episode,
                    podcastTitle: episode.podcastName ?? "Unknown Podcast",
                    podcastImageURL: episode.podcastImageURL
                )
            }
            .toolbar {
                if selectedTab == .subscriptions {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            showSettings = true
                        }) {
                            Image(systemName: "gear")
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            Task {
                                await libraryVM.refreshAllEpisodes()
                            }
                        }) {
                            if libraryVM.isLoadingEpisodes {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(libraryVM.isLoadingEpisodes)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                LibrarySettingsSheet()
                    .environmentObject(libraryVM)
            }
        }
    }
    
    private var subscriptionsView: some View {
        Group {
            if libraryVM.subscriptions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "books.vertical")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No Subscriptions")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text("Search for podcasts to subscribe")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryVM.layoutStyle == .list {
                // List Layout
                List(libraryVM.sortedSubscriptions) { podcast in
                    NavigationLink(destination: PodcastDetailView(podcast: podcast)) {
                        HStack {
                            ZStack(alignment: .topTrailing) {
                                CachedAsyncImage(url: URL(string: podcast.artworkUrl600)) { image in
                                    image.resizable()
                                } placeholder: {
                                    Color.gray
                                }
                                .frame(width: 60, height: 60)
                                .cornerRadius(8)
                                .shadow(radius: 6)
                                
                                if libraryVM.showUnplayedBadges {
                                    let unplayedCount = libraryVM.getUnplayedCount(for: podcast)
                                    if unplayedCount > 0 {
                                        Text(libraryVM.formatUnplayedCount(unplayedCount))
                                            .font(.caption2)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(Color.red)
                                            .cornerRadius(8)
                                            .offset(x: 5, y: -5)
                                            .id(trackingManager.episodeStatuses.count)
                                    }
                                }
                            }
                            
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
                .refreshable {
                    await libraryVM.refreshAllEpisodes()
                }
            } else {
                // Grid Layout
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ], spacing: 16) {
                        ForEach(libraryVM.sortedSubscriptions) { podcast in
                            PodcastGridItem(
                                podcast: podcast,
                                unplayedCount: libraryVM.getUnplayedCount(for: podcast),
                                showBadge: libraryVM.showUnplayedBadges
                            )
                        }
                    }
                    .padding()
                }
                .refreshable {
                    await libraryVM.refreshAllEpisodes()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: libraryVM.isLoadingEpisodes)
    }
    
    private var newReleasesView: some View {
        Group {
            if libraryVM.subscriptions.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "star")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No Subscriptions")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text("Subscribe to podcasts to see new releases")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryVM.recentEpisodes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)
                    
                    Text("No New Episodes")
                        .font(.title2)
                        .foregroundColor(.gray)
                    
                    Text("No episodes from the last 2 weeks")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Button("Refresh") {
                        Task {
                            await libraryVM.refreshAllEpisodes()
                        }
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(libraryVM.recentEpisodes.filter { !trackingManager.isPlayed($0.id) && trackingManager.shouldShowEpisode($0.id) }) { episode in
                        EpisodeRowView(
                            episode: episode,
                            podcastImageURL: episode.podcastImageURL,
                            showPodcastName: true
                        )
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEpisode = episode
                        }
                        .episodeContextMenu(episode: episode)
                    }
                    
                    // Show count of hidden episodes if any
                    if trackingManager.hidePlayedEpisodes || trackingManager.hideArchivedEpisodes {
                        let hiddenCount = libraryVM.recentEpisodes.count - libraryVM.recentEpisodes.filter { trackingManager.shouldShowEpisode($0.id) }.count
                        
                        if hiddenCount > 0 {
                            Section {
                                HStack {
                                    Spacer()
                                    Text("\(hiddenCount) episode\(hiddenCount == 1 ? "" : "s") hidden by filters")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .refreshable {
                    await libraryVM.refreshAllEpisodes()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: libraryVM.isLoadingEpisodes)
    }
}

//MARK: - QueueEpisodeRowView
struct QueueEpisodeRowView: View {
    let episode: Episode
    let index: Int
    let onPlayTapped: () -> Void
    let onDeleteTapped: () -> Void
    let onEpisodeTapped: () -> Void
    
    var body: some View {
        EpisodeRowView(
            episode: episode,
            podcastImageURL: episode.podcastImageURL,
            onPlayTapped: onPlayTapped
        )
        .padding(.vertical, 4)
        .listRowSeparator(.visible)
        .contentShape(Rectangle())
        .onTapGesture {
            onEpisodeTapped()
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDeleteTapped()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .onDrag {
            NSItemProvider(object: String(index) as NSString)
        }
    }
}

//MARK: - QueueView
struct QueueView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @State private var isEditing = false
    @State private var selectedEpisode: Episode?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Currently Playing Section
                if let currentEpisode = audioVM.episode {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Now Playing")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                        
                        EpisodeRowView(
                            episode: currentEpisode,
                            podcastImageURL: audioVM.podcastImageURL,
                            onPlayTapped: {
                                audioVM.togglePlayPause()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEpisode = currentEpisode
                        }
                        
                        Divider()
                    }
                    .background(Color(.systemGray6))
                }
                
                // Queue Section
                if audioVM.episodeQueue.isEmpty && audioVM.episode == nil {
                    // Empty state
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
                } else if audioVM.episodeQueue.isEmpty {
                    Spacer()
                    VStack {
                        Image(systemName: "text.badge.plus")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                            .padding(.bottom, 10)
                        Text("Your queue is empty")
                            .font(.title3)
                            .foregroundColor(.gray)
                        Text("Add more episodes to continue listening")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .multilineTextAlignment(.center)
                    .padding()
                    Spacer()
                } else {
                    // Queue list
                    VStack(alignment: .leading, spacing: 0) {
                        queueHeaderView
                        queueListView
                    }
                    .navigationDestination(item: $selectedEpisode) { episode in
                        EpisodeDetailView(
                            episode: episode,
                            podcastTitle: episode.podcastName ?? "Unknown Podcast",
                            podcastImageURL: episode.podcastImageURL
                        )
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
                        Button("Clear Queue") {
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
    
    private var queueHeaderView: some View {
        HStack {
            Text("Up Next (\(audioVM.episodeQueue.count))")
                .font(.headline)
                .foregroundColor(.primary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var queueListView: some View {
        List {
            ForEach(Array(audioVM.episodeQueue.enumerated()), id: \.element.id) { index, episode in
                QueueEpisodeRowView(
                    episode: episode,
                    index: index,
                    onPlayTapped: {
                        audioVM.playFromQueue(episode)
                    },
                    onDeleteTapped: {
                        audioVM.episodeQueue.removeAll { $0.id == episode.id }
                    },
                    onEpisodeTapped: {
                        selectedEpisode = episode
                    }
                )
            }
            .onMove(perform: moveEpisode)
            .moveDisabled(false)
        }
        .listStyle(.plain)
        .environment(\.editMode, isEditing ? .constant(.active) : .constant(.inactive))
    }
}

// MARK: - StatisticsView
struct StatisticsView: View {
    @ObservedObject private var statsManager = StatisticsManager.shared
    @ObservedObject private var sessionManager = SessionManager.shared
    @State private var selectedPeriod: StatsPeriod = .allTime
    @State private var selectedTab: StatsTab = .overview
    @State private var selectedSession: UserSession?
    @State private var showClearConfirmation = false
    
    enum StatsTab: String, CaseIterable {
        case overview = "Overview"
        case podcasts = "Podcasts"
        case sessions = "Sessions"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Period Picker
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(StatsPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Tab Picker
                Picker("Tab", selection: $selectedTab) {
                    ForEach(StatsTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Content
                TabView(selection: $selectedTab) {
                    OverviewStatsView(period: selectedPeriod)
                        .tag(StatsTab.overview)
                    
                    PodcastStatsView()
                        .tag(StatsTab.podcasts)
                    
                    SessionsStatsView(selectedSession: $selectedSession)
                        .tag(StatsTab.sessions)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .safeAreaInset(edge: .bottom) {
                if AudioPlayerViewModel.shared.showMiniPlayer {
                    Color.clear.frame(height: 70)
                }
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("More") {
                        Button("Clear All Data", role: .destructive) {
                   //         statsManager.clearAllStats()
                            showClearConfirmation = true
                        }
                    }
                }
            }
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
            }
            .alert("Clear All Statistics?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    statsManager.clearAllStats()
                }
            } message: {
                Text("This will permanently delete all your listening statistics, session history, and completion data. This action cannot be undone.")
            }
        }
    }
}

// MARK: - OverviewStatsView
struct OverviewStatsView: View {
    let period: StatsPeriod
    @ObservedObject private var statsManager = StatisticsManager.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let stats = statsManager.overallStats {
                    // Main Stats Cards
                    StatsCardView(
                        title: "Total Listening Time",
                        value: period == .allTime ? stats.totalListeningTimeFormatted :
                            StatisticsManager.formatLongDuration(statsManager.getListeningTimeForPeriod(period)),
                        icon: "clock.fill",
                        color: .blue
                    )
                    
                    HStack(spacing: 16) {
                        StatsCardView(
                            title: "Episodes",
                            value: "\(stats.totalEpisodes)",
                            icon: "play.circle.fill",
                            color: .green
                        )
                        
                        StatsCardView(
                            title: "Podcasts",
                            value: "\(stats.totalPodcasts)",
                            icon: "mic.fill",
                            color: .purple
                        )
                    }
                    
                    HStack(spacing: 16) {
                        StatsCardView(
                            title: "Avg Session",
                            value: stats.averageSessionLengthFormatted,
                            icon: "timer",
                            color: .orange
                        )
                        
                        StatsCardView(
                            title: "Completion Rate",
                            value: "\(Int(stats.completionRate))%",
                            icon: "checkmark.circle.fill",
                            color: .green
                        )
                    }
                    
                    // Additional Stats
                    VStack(spacing: 12) {
                        StatsRowView(
                            title: "Longest Session",
                            value: stats.longestSessionFormatted,
                            icon: "stopwatch"
                        )
                        
                        StatsRowView(
                            title: "Current Streak",
                            value: "\(stats.streakDays) days",
                            icon: "flame.fill"
                        )
                        
                        StatsRowView(
                            title: "Longest Streak",
                            value: "\(stats.longestStreakDays) days",
                            icon: "trophy.fill"
                        )
                        
                        StatsRowView(
                            title: "Favorite Time",
                            value: formatHour(stats.favoriteListeningHour),
                            icon: "sun.max.fill"
                        )
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Statistics Yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Start listening to podcasts to see your statistics")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                }
            }
            .padding()
        }
        .onAppear {
            statsManager.calculateStats()
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        
        let calendar = Calendar.current
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        
        return "\(hour):00"
    }
}

// MARK: - PodcastStatsView
struct PodcastStatsView: View {
    @ObservedObject private var statsManager = StatisticsManager.shared
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if statsManager.podcastStats.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "mic")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Podcast Statistics")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Listen to podcasts to see detailed statistics for each show")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ForEach(Array(statsManager.podcastStats.enumerated()), id: \.element.id) { index, podcastStat in
                        PodcastStatsCardView(podcastStat: podcastStat, rank: index + 1)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - SessionsStatsView
struct SessionsStatsView: View {
    @ObservedObject private var sessionManager = SessionManager.shared
    @Binding var selectedSession: UserSession?
    
    var longestSessions: [UserSession] {
        Array(sessionManager.userSessions
            .sorted { $0.totalDuration > $1.totalDuration }
            .prefix(3))
    }
    
    var mostRecentSessions: [UserSession] {
        Array(sessionManager.userSessions
            .sorted { $0.endTime > $1.endTime }
            .prefix(3))
    }
    
    var mostEpisodesSession: [UserSession] {
        Array(sessionManager.userSessions
            .sorted { $0.episodes.count > $1.episodes.count }
            .prefix(3))
    }
    
    var todaysSessions: [UserSession] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        return sessionManager.userSessions.filter { session in
            calendar.isDate(session.startTime, inSameDayAs: today)
        }.sorted { $0.endTime > $1.endTime }
    }
    
    var thisWeeksSessions: [UserSession] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        
        return sessionManager.userSessions.filter { session in
            session.startTime >= weekAgo
        }.sorted { $0.endTime > $1.endTime }
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if sessionManager.userSessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("No Sessions Yet")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("Start listening to create your first session")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    // Today's Sessions
                    if !todaysSessions.isEmpty {
                        SessionCategoryView(
                            title: "Today",
                            sessions: todaysSessions,
                            icon: "calendar.badge.clock",
                            selectedSession: $selectedSession
                        )
                    }
                    
                    // This Week's Sessions
                    if !thisWeeksSessions.isEmpty {
                        SessionCategoryView(
                            title: "This Week",
                            sessions: thisWeeksSessions,
                            icon: "calendar",
                            selectedSession: $selectedSession
                        )
                    }
                    
                    // Longest Sessions
                    if !longestSessions.isEmpty {
                        SessionCategoryView(
                            title: "Longest Sessions",
                            sessions: longestSessions,
                            icon: "crown.fill",
                            selectedSession: $selectedSession
                        )
                    }
                    
                    // Most Episodes
                    if !mostEpisodesSession.isEmpty {
                        SessionCategoryView(
                            title: "Most Episodes",
                            sessions: mostEpisodesSession,
                            icon: "list.number",
                            selectedSession: $selectedSession
                        )
                    }
                    
                    // Most Recent Sessions
                    if !mostRecentSessions.isEmpty {
                        SessionCategoryView(
                            title: "Recent Sessions",
                            sessions: mostRecentSessions,
                            icon: "clock.fill",
                            selectedSession: $selectedSession
                        )
                    }
                    
                    // Total Stats Summary
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Summary")
                            .font(.title3)
                            .fontWeight(.bold)
                            .padding(.horizontal)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("Total Sessions")
                                Spacer()
                                Text("\(sessionManager.userSessions.count)")
                                    .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Text("Total Listening Time")
                                Spacer()
                                Text(DurationFormatter.formatLongDuration(
                                    sessionManager.userSessions.reduce(0) { $0 + $1.totalDuration }
                                ))
                                .fontWeight(.semibold)
                            }
                            
                            HStack {
                                Text("Average Session")
                                Spacer()
                                let avgDuration = sessionManager.userSessions.isEmpty ? 0 :
                                    sessionManager.userSessions.reduce(0) { $0 + $1.totalDuration } / Double(sessionManager.userSessions.count)
                                Text(DurationFormatter.formatDuration(avgDuration))
                                    .fontWeight(.semibold)
                            }
                        }
                        .font(.subheadline)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - SessionCategoryView
struct SessionCategoryView: View {
    let title: String
    let sessions: [UserSession]
    let icon: String
    @Binding var selectedSession: UserSession?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                
                Text(title)
                    .font(.title3)
                    .fontWeight(.bold)
                
                Spacer()
                
                Text("\(sessions.count)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .padding(.horizontal)
            
            ForEach(sessions) { session in
                Button(action: {
                    selectedSession = session
                }) {
                    SessionCardView(session: session)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct SessionCardView: View {
    let session: UserSession
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Session #\(session.sessionNumber)")
                    .font(.headline)
                
                Spacer()
                
                Text(DurationFormatter.formatLongDuration(session.totalDuration))
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            HStack {
                Text(session.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text("•")
                    .foregroundColor(.gray)
                
                Text("\(session.startTime.formatted(date: .omitted, time: .shortened)) - \(session.endTime.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Text("\(session.episodes.count) episode\(session.episodes.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

//MARK: - SettingsView
struct SettingsView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @ObservedObject private var statsManager = StatisticsManager.shared
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    PlaybackSpeedSettingView()
                }
                
                Section("Downloads") {
                    Toggle("Auto-Delete on Completion", isOn: Binding(
                        get: { downloadManager.autoDeleteOnCompletion },
                        set: { downloadManager.setAutoDelete($0) }
                    ))
                    
                    Text("Automatically delete downloaded episodes when they finish playing")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Episode Information") {
                    HStack {
                        Text("Played Episodes")
                        Spacer()
                        Text("\(trackingManager.getTotalPlayedCount())")
                            .foregroundColor(.gray)
                    }
                    
                    HStack {
                        Text("Archived Episodes")
                        Spacer()
                        Text("\(trackingManager.getTotalArchivedCount())")
                            .foregroundColor(.gray)
                    }
                }
                .headerProminence(.increased)
                
                Section {
                    Text("Episode visibility filters are now set per-podcast in each podcast's detail view")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section("Statistics") {
                    Button("Clear All Statistics", role: .destructive) {
                        statsManager.clearAllStats()
                    }
                }
                
                Section("Cache") {
                    Button("Clear Image Cache") {
                        ImageCache.shared.clearCache()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
    }
}

struct PlaybackSpeedSettingView: View {
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    
    private let speedOptions: [Float] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playback Speed")
                .font(.headline)
            
            HStack(spacing: 12) {
                ForEach(speedOptions, id: \.self) { speed in
                    Button(action: {
                        audioVM.setPlaybackSpeed(speed)
                    }) {
                        Text("\(speed, specifier: "%.2f")x")
                            .font(.subheadline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                audioVM.playbackSpeed == speed ? Color.blue : Color.gray.opacity(0.2)
                            )
                            .foregroundColor(
                                audioVM.playbackSpeed == speed ? .white : .primary
                            )
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            Text("Current: \(audioVM.playbackSpeed, specifier: "%.2f")x speed")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 4)
    }
}

struct SessionDetailView: View {
    let session: UserSession
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Session Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Session #\(session.sessionNumber)")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Total Duration: \(DurationFormatter.formatLongDuration(session.totalDuration))")
                        .font(.headline)
                        .foregroundColor(.blue)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Started")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Ended")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(session.endTime.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Pie Chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Time Distribution")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    Chart(session.episodes) { episode in
                        SectorMark(
                            angle: .value("Duration", episode.duration),
                            innerRadius: .ratio(0.5),
                            angularInset: 1.5
                        )
                        .foregroundStyle(by: .value("Episode", episode.episodeTitle))
                        .annotation(position: .overlay) {
                            Text("\(Int((episode.duration / session.totalDuration) * 100))%")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(height: 300)
                    .padding()
                }
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Episode List
                VStack(alignment: .leading, spacing: 8) {
                    Text("Episodes (\(session.episodes.count))")
                        .font(.headline)
                        .padding(.horizontal)
                    
                    ForEach(session.episodes) { episode in
                        SessionEpisodeRowView(episode: episode, totalDuration: session.totalDuration)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SessionEpisodeRowView: View {
    let episode: EpisodeSession
    let totalDuration: TimeInterval
    
    var percentage: Int {
        Int((episode.duration / totalDuration) * 100)
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if let imageURL = episode.imageURL {
                CachedAsyncImage(url: URL(string: imageURL)) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.episodeTitle)
                    .font(.subheadline)
                    .lineLimit(2)
                
                Text(episode.podcastName)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                HStack {
                    Text(DurationFormatter.formatDuration(episode.duration))
                        .font(.caption)
                        .foregroundColor(.blue)
                    
                    Text("• \(percentage)% of session")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            Spacer()
            
            if episode.completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}


// MARK: - Supporting Views

struct StatsCardView: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct StatsRowView: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.gray)
                .fontWeight(.medium)
        }
    }
}

struct PodcastStatsCardView: View {
    let podcastStat: PodcastStats
    let rank: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("#\(rank)")
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue)
                    .cornerRadius(8)
                
                VStack(alignment: .leading) {
                    Text(podcastStat.podcastName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text("\(podcastStat.episodeCount) episodes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text(podcastStat.totalListeningTimeFormatted)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
            }
            
            HStack {
                Label(podcastStat.averageListeningTimeFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Spacer()
                
                Label("\(Int(podcastStat.completionRate))%", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct SessionRowView: View {
    let session: ListeningSession
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.episodeTitle)
                    .font(.subheadline)
                    .lineLimit(2)
                
                Text(session.podcastName)
                    .font(.caption)
                    .foregroundColor(.gray)
                
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            VStack(alignment: .trailing) {
                Text(StatisticsManager.formatDuration(session.duration))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if session.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

//MARK: - Episode Context Menu
extension View {
    func episodeContextMenu(episode: Episode) -> some View {
        self.contextMenu {
            EpisodeContextMenuContent(episode: episode)
        }
    }
}

struct EpisodeContextMenuContent: View {
    let episode: Episode
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        // Play/Pause
        Button(action: {
            if audioVM.episode?.id == episode.id {
                audioVM.togglePlayPause()
            } else {
                audioVM.playNow(episode, podcastImageURL: episode.podcastImageURL)
            }
        }) {
            Label(
                audioVM.episode?.id == episode.id && audioVM.isPlaying ? "Pause" : "Play",
                systemImage: audioVM.episode?.id == episode.id && audioVM.isPlaying ? "pause" : "play"
            )
        }
        
        // Add to Queue
        Button(action: {
            audioVM.addToQueue(episode)
        }) {
            Label("Add to Queue", systemImage: "text.badge.plus")
        }
        
        Divider()
        
        // Mark Played/Unplayed
        Button(action: {
            if trackingManager.isPlayed(episode.id) {
                trackingManager.markAsUnplayed(episode.id)
            } else {
                trackingManager.markAsPlayed(episode.id)
            }
        }) {
            Label(
                trackingManager.isPlayed(episode.id) ? "Mark as Unplayed" : "Mark as Played",
                systemImage: trackingManager.isPlayed(episode.id) ? "circle" : "checkmark.circle"
            )
        }
        
        // Archive/Unarchive
        Button(action: {
            trackingManager.toggleArchived(episode.id)
        }) {
            Label(
                trackingManager.isArchived(episode.id) ? "Unarchive" : "Archive",
                systemImage: trackingManager.isArchived(episode.id) ? "tray.and.arrow.up" : "archivebox"
            )
        }
        
        Divider()
        
        // Download
        if downloadManager.isDownloaded(episode.id) {
            Button(role: .destructive, action: {
                downloadManager.deleteDownload(episode.id)
            }) {
                Label("Delete Download", systemImage: "trash")
            }
        } else if downloadManager.isDownloading(episode.id) {
            Button(action: {
                downloadManager.cancelDownload(episode.id)
            }) {
                Label("Cancel Download", systemImage: "xmark")
            }
        } else {
            Button(action: {
                downloadManager.downloadEpisode(episode)
            }) {
                Label("Download", systemImage: "arrow.down.circle")
            }
        }
    }
}

//MARK: - SkipIntroOutroSettings
struct SkipIntroOutroSettings: View {
    let podcastName: String
    @ObservedObject private var sortPreferences = PodcastSortPreferences.shared
    
    @State private var skipIntroSeconds: Double = 0
    @State private var skipOutroSeconds: Double = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Skip Intro
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Skip Intro")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(skipIntroSeconds))s")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Slider(value: $skipIntroSeconds, in: 0...180, step: 5)
                    .onChange(of: skipIntroSeconds) { _, newValue in
                        var settings = sortPreferences.getSettings(for: podcastName)
                        settings.skipIntroSeconds = newValue
                        sortPreferences.setSettings(settings, for: podcastName)
                    }
                
                Text("Skip the first \(Int(skipIntroSeconds)) seconds of each episode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Skip Outro
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Skip Outro")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(skipOutroSeconds))s")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Slider(value: $skipOutroSeconds, in: 0...180, step: 5)
                    .onChange(of: skipOutroSeconds) { _, newValue in
                        var settings = sortPreferences.getSettings(for: podcastName)
                        settings.skipOutroSeconds = newValue
                        sortPreferences.setSettings(settings, for: podcastName)
                    }
                
                Text("Skip the last \(Int(skipOutroSeconds)) seconds of each episode")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
        .onAppear {
            let settings = sortPreferences.getSettings(for: podcastName)
            skipIntroSeconds = settings.skipIntroSeconds
            skipOutroSeconds = settings.skipOutroSeconds
        }
    }
}

#Preview {
    ContentView()
}
