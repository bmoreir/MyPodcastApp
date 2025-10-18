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
    
    enum CodingKeys: String, CodingKey {
            case id, duration, title, pubDate, audioURL, imageURL, podcastImageURL, description, podcastName, episodeNumber
        }
    
    init(title: String, pubDate: Date?, audioURL: String, duration: String?, imageURL: String?, podcastImageURL: String?, description: String?, podcastName: String?, episodeNumber: String? = nil) {
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
    var currentEpisodeNumber = ""
    
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
            currentEpisodeNumber = ""
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
        case "description", "itunes:summary":
            if insideItem {
                currentDescription += trimmedString
            }
        case "itunes:episode":
            currentEpisodeNumber += trimmedString
        default:
            break
        }
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
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
        
        return Episode(
            title: currentTitle.trimmingCharacters(in: .whitespacesAndNewlines),
            pubDate: pubDate,
            audioURL: currentAudioURL.trimmingCharacters(in: .whitespacesAndNewlines),
            duration: duration.isEmpty ? nil : duration.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURL: imageURL.isEmpty ? nil : imageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastImageURL: podcastImageURL.isEmpty ? nil : podcastImageURL.trimmingCharacters(in: .whitespacesAndNewlines),
            description: currentDescription.isEmpty ? nil : currentDescription.trimmingCharacters(in: .whitespacesAndNewlines),
            podcastName: podcastName.isEmpty ? nil : podcastName.trimmingCharacters(in: .whitespacesAndNewlines),
            episodeNumber: currentEpisodeNumber.isEmpty ? nil : currentEpisodeNumber.trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        // Download and cache in background
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        ImageCache.shared.setImage(image, for: url.absoluteString)
                    }
                }
            } catch {
                // Ignore caching errors
            }
        }
    }
}

// Add this struct anywhere in your file, outside of classes
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
    let completed: Bool // whether episode was finished
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
    let streakDays: Int // consecutive days with listening
    let favoriteListeningHour: Int // hour of day (0-23)
    
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
    
    private var listeningSessions: [ListeningSession] = []
    private var currentSessionStart: Date?
    private var currentEpisode: Episode?
    
    private let sessionsKey = "listeningSessions"
    private let minSessionDuration: TimeInterval = 30 // Minimum 30 seconds to count as a session
    
    private init() {
        loadData()
        calculateStats()
    }
    
    func startListeningSession(for episode: Episode) {
        // Don't start a new session if we already have one for the same episode
        if let currentEpisode = currentEpisode,
           currentEpisode.id == episode.id,
           currentSessionStart != nil {
  //          print("📊 Session already active for this episode, skipping")
            return
        }
        
        // End previous session if one exists for a different episode
        if currentSessionStart != nil {
    //        print("📊 Ending previous session before starting new one")
            endListeningSession(completed: false)
        }
        
        currentSessionStart = Date()
        currentEpisode = episode
  //      print("📊 ✅ Started session for: \(episode.title)")
    }
    
    func endListeningSession(completed: Bool = false) {
        guard let startTime = currentSessionStart,
              let episode = currentEpisode else {
    //        print("📊 ❌ No active session to end")
            return
        }
        
        let endTime = Date()
        let duration = endTime.timeIntervalSince(startTime)
        
  //      print("📊 ⏹️ Ending session: \(duration) seconds, completed: \(completed)")
        
        let minDuration: TimeInterval = 30 // Changed from 30 to 5 for testing
        
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
    //        print("📊 ✅ Added session: \(session.episodeTitle) - \(duration)s")
    //        print("📊 📈 Total sessions now: \(listeningSessions.count)")
            saveData()
            calculateStats()
        }
   //     else {
    //        print("📊 ❌ Session too short: \(duration)s < \(minDuration)s")
     //   }
        
        currentSessionStart = nil
        currentEpisode = nil
    }
    
    func pauseSession() {
   //     print("📊 Pausing session")

        // When pausing, we end current session and will start new one on resume
        endListeningSession()
    }
        
    private func calculateStats() {
  //      print("📊 Calculating stats with \(listeningSessions.count) sessions")

        guard !listeningSessions.isEmpty else {
            overallStats = nil
            podcastStats = []
            recentSessions = []
    //        print("📊 No sessions - clearing stats")

            return
        }
        
        calculateOverallStats()
        calculatePodcastStats()
        updateRecentSessions()
        
     /*   if let stats = overallStats {
                print("📊 ✅ Stats calculated - Total time: \(stats.totalListeningTime)s, Episodes: \(stats.totalEpisodes)")
            } */
    }
    
    private func calculateOverallStats() {
        let totalTime = listeningSessions.reduce(0) { $0 + $1.duration }
        let uniqueEpisodes = Set(listeningSessions.map { $0.episodeID }).count
        let uniquePodcasts = Set(listeningSessions.map { $0.podcastName }).count
        
        let averageSession = totalTime / Double(listeningSessions.count)
        let longestSession = listeningSessions.max { $0.duration < $1.duration }?.duration ?? 0
        
        let completedSessions = listeningSessions.filter { $0.completed }.count
        let completionRate = Double(completedSessions) / Double(listeningSessions.count) * 100
        
        let firstListen = listeningSessions.min { $0.startTime < $1.startTime }?.startTime
        
        let streak = calculateStreak()
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
            favoriteListeningHour: favoriteHour
        )
    }
    
    private func calculatePodcastStats() {
        let podcastGroups = Dictionary(grouping: listeningSessions, by: { $0.podcastName })
        
        podcastStats = podcastGroups.map { (podcastName, sessions) in
            let totalTime = sessions.reduce(0) { $0 + $1.duration }
            let episodeCount = Set(sessions.map { $0.episodeID }).count
            let averageTime = totalTime / Double(sessions.count)
            
            let completed = sessions.filter { $0.completed }.count
            let completionRate = Double(completed) / Double(sessions.count) * 100
            
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
  //      print("📊 📋 Updated recent sessions: \(recentSessions.count) sessions")
  //          for (index, session) in recentSessions.prefix(3).enumerated() {
  //              print("📊 📋 Session \(index): \(session.episodeTitle) - \(session.duration)s")
  //          }
    }
    
    private func calculateStreak() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        var streak = 0
        var currentDate = today
        
        while true {
            let hasListeningOnDate = listeningSessions.contains { session in
                calendar.isDate(session.startTime, inSameDayAs: currentDate)
            }
            
            if hasListeningOnDate {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate) ?? currentDate
            } else {
                break
            }
        }
        
        return streak
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
    
    func clearAllStats() {
        listeningSessions.removeAll()
        saveData()
        calculateStats()
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
        
        // Update episode duration
        if var episodeSession = currentEpisodeSession {
            let duration = Date().timeIntervalSince(startTime)
            episodeSession.duration = duration
            episodeSession.endTime = Date()
            currentEpisodeSession = episodeSession
        }
        
        // Start pause timer - if not resumed within threshold, end session
        pauseTimer?.invalidate()
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
}

//MARK: - DownloadManager
@MainActor
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    
    @Published var downloadedEpisodes: Set<String> = []
    @Published var downloadProgress: [String: Double] = [:]
    @Published var activeDownloads: Set<String> = []
    
    private let downloadedEpisodesKey = "downloadedEpisodes"
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private let taskMapper = TaskMapper()
    
    private lazy var downloadSession: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "com.mypodcastapp.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    
    private override init() {
        super.init()
        loadDownloadedEpisodes()
        createDownloadsDirectory()
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
        
        Task {
            await taskMapper.setEpisodeID(episode.id, for: task)
        }
        
        task.resume()

        print("Started downloading: \(episode.title)")
    }
    
    func deleteDownload(_ episodeID: String) {
        guard let downloadPath = getDownloadPath(for: episodeID) else { return }
        
        // If this episode is currently playing, stop playback
        Task { @MainActor in
            let audioVM = AudioPlayerViewModel.shared
            if audioVM.episode?.id == episodeID && audioVM.isPlaying {
                audioVM.togglePlayPause() // Stop playback
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
            Task {
                await taskMapper.removeEpisodeID(for: task)
            }
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
        // Create a hash of the episode ID for a clean filename
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
}

// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Create a semaphore to wait for the async task
        let semaphore = DispatchSemaphore(value: 0)
        var episodeID: String?
        
        Task {
            episodeID = await taskMapper.getEpisodeID(for: downloadTask)
            semaphore.signal()
        }
        
        // Wait for the async task to complete (with timeout)
        _ = semaphore.wait(timeout: .now() + 5)
        
        guard let unwrappedEpisodeID = episodeID,
              let destinationURL = getDownloadPath(for: unwrappedEpisodeID) else {
            print("Failed to get episodeID or destination path")
            return
        }
        
        print("Download finished for: \(unwrappedEpisodeID)")
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
                self.downloadedEpisodes.insert(unwrappedEpisodeID)
                self.activeDownloads.remove(unwrappedEpisodeID)
                self.downloadProgress.removeValue(forKey: unwrappedEpisodeID)
                self.downloadTasks.removeValue(forKey: unwrappedEpisodeID)
                self.saveDownloadedEpisodes()
                print("Download completed and saved")
            }
            
            Task {
                await taskMapper.removeEpisodeID(for: downloadTask)
            }
        } catch {
            print("Error moving downloaded file: \(error)")
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        Task {
            guard let episodeID = await taskMapper.getEpisodeID(for: downloadTask) else {
                return
            }
            
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            
            await MainActor.run {
                self.downloadProgress[episodeID] = progress
            }
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let downloadTask = task as? URLSessionDownloadTask else { return }
        
        Task {
            guard let episodeID = await taskMapper.getEpisodeID(for: downloadTask) else {
                return
            }
            
            if let error = error {
                print("Download failed for \(episodeID): \(error)")
                await MainActor.run {
                    self.activeDownloads.remove(episodeID)
                    self.downloadProgress.removeValue(forKey: episodeID)
                    self.downloadTasks.removeValue(forKey: episodeID)
                }
                await taskMapper.removeEpisodeID(for: downloadTask)
            }
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
    
    private init() {
        loadStatuses()
        loadPreferences()
    }
    
    // MARK: - Status Management
    
    func markAsPlayed(_ episodeID: String) {
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
        // Note: Keep archived status as-is
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
        if let data = try? JSONEncoder().encode(episodeStatuses) {
            UserDefaults.standard.set(data, forKey: statusesKey)
        }
    }
    
    private func loadStatuses() {
        if let data = UserDefaults.standard.data(forKey: statusesKey),
           let decoded = try? JSONDecoder().decode([String: EpisodeStatus].self, from: data) {
            episodeStatuses = decoded
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
    
    var showMiniPlayer: Bool {
        episode != nil && (isPlaying || currentTime > 0)
    }
    
    private init() {
        if let data = UserDefaults.standard.data(forKey: elapsedTimesKey),
           let saved = try? JSONDecoder().decode([String: Double].self, from: data) {
            self.elapsedTimes = saved
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
        
        let downloadManager = DownloadManager.shared
        let audioURL: URL
        
        print("🎵 Loading episode: \(episode.title)")
        print("📱 Episode ID: \(episode.id)")
        print("🔍 Is downloaded: \(downloadManager.isDownloaded(episode.id))")
        
        if downloadManager.isDownloaded(episode.id),
           let localURL = downloadManager.getLocalURL(for: episode.id) {
            print("📁 Local URL: \(localURL)")
            print("📁 File exists: \(FileManager.default.fileExists(atPath: localURL.path))")
            
            if let attributes = try? FileManager.default.attributesOfItem(atPath: localURL.path) {
                let fileSize = attributes[.size] as? Int64 ?? 0
                print("📁 File size: \(fileSize) bytes")
            }
            
            audioURL = localURL
            print("✅ Playing from local download: \(episode.title)")
        } else if let url = URL(string: episode.audioURL) {
            audioURL = url
            print("🌐 Streaming: \(episode.title)")
        } else {
            print("❌ No valid URL found")
            return
        }
        
        print("🎧 Creating player with URL: \(audioURL)")
        let asset = AVURLAsset(url: audioURL)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        updateDurationFromAsset(asset)
        self.isPlaying = false
        
        setupPlayerItemObserver(for: playerItem)
        
        // Check player item status after a brief delay
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            
            if let item = self.player?.currentItem {
                print("Player item status: \(item.status.rawValue)")
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
        
        if let savedTime = elapsedTimes[episode.audioURL], savedTime > 0 {
            let cmTime = CMTime(seconds: savedTime, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
            player?.seek(to: cmTime)
        }
        
        updateNowPlayingInfo()
        StatisticsManager.shared.startListeningSession(for: episode)
        SessionManager.shared.startEpisodeInSession(episode: episode)
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
        ) { [weak self] _ in
            Task { @MainActor in
                self?.playerDidFinishPlaying()
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
        
        // Clean up remote command handlers
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.skipForwardCommand.removeTarget(nil)
        commandCenter.skipBackwardCommand.removeTarget(nil)
        
        // Clear now playing info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    // Add a public method to clean up when needed (for testing or app shutdown)
    func cleanup() {
        StatisticsManager.shared.endListeningSession(completed: false)
        cleanupAllObservers()
        player?.pause()
        player = nil
        episode = nil
        isPlaying = false
    }
    
    @MainActor
    private func addPeriodicTimeObserver() {
        guard let player = player else { return }
        
        let interval = CMTime(seconds: 1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            DispatchQueue.main.async {
                self?.currentTime = time.seconds
                self?.savePlaybackProgress()
            }
        }
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        
        if isPlaying {
      //      print("📊 🔄 Pausing playback")

            player.pause()
            isPlaying = false
            savePlaybackProgress()
            StatisticsManager.shared.pauseSession()
            SessionManager.shared.pauseEpisodeInSession() // ADD
        } else {
    //        print("📊 ▶️ Starting playback")

   //         player.play()
            player.rate = playbackSpeed // Use the current speed setting
            isPlaying = true
            SessionManager.shared.resumeEpisodeInSession() // ADD

            if let episode = episode {
                        StatisticsManager.shared.startListeningSession(for: episode)
            }
        }
        
        updateNowPlayingInfo()
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
                    }
                }
            } catch {
                print("Failed to load real duration: \(error)")
            }
        }
    }
    
    private func playerDidFinishPlaying() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            
            if let episodeID = self.episode?.id {
                        EpisodeTrackingManager.shared.markAsPlayed(episodeID)
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
                SessionManager.shared.endSession()

                // Clean up when playback ends and no queue
                self.cleanupCurrentEpisodeObservers()
                self.episode = nil
                self.podcastImageURL = nil
                self.player?.seek(to: .zero)
                self.player = nil
            }
        }
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
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                Task {@MainActor in
                    self?.saveElapsedTimes()
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
        
        // Enable/disable commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.skipForwardCommand.isEnabled = true
        commandCenter.skipBackwardCommand.isEnabled = true
        
        // Configure skip intervals
        commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        
        // Add handlers
        commandCenter.playCommand.addTarget { [weak self] _ in
            if self?.player != nil {
                self?.togglePlayPause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true {
                self?.togglePlayPause()
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward()
            return .success
        }
        
        commandCenter.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward()
            return .success
        }
    }

    // Update the now playing info for lock screen/control center
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
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackSpeed) : 0.0
        ]
        
        // Add artwork if available
        if let imageURLString = episode.imageURL ?? podcastImageURL,
           let imageURL = URL(string: imageURLString) {
            
            // In a production app, you'd want to cache this image
            URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    DispatchQueue.main.async {
                        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                    }
                }
            }.resume()
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

    }

    // Keep deinit for completeness, though it won't be called for singleton
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
    
    init() {
        loadSubscriptions()
        loadPreferences()
        loadAllEpisodes()
            
            // Refresh in background if we have subscriptions
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
                let (data, _) = try await URLSession.shared.data(from: url)
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
                        episodeNumber: episode.episodeNumber
                    )
                }
                
                episodes.append(contentsOf: episodesWithPodcastInfo)
            } catch {
                print("Failed to fetch episodes for \(podcast.collectionName): \(error)")
            }
        }
        
        allEpisodes = episodes
        isLoadingEpisodes = false
        saveAllEpisodes()
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
        if let data = try? JSONEncoder().encode(allEpisodes) {
            UserDefaults.standard.set(data, forKey: allEpisodesKey)
        }
    }

    private func loadAllEpisodes() {
        if let data = UserDefaults.standard.data(forKey: allEpisodesKey),
           let decoded = try? JSONDecoder().decode([Episode].self, from: data) {
            allEpisodes = decoded
        }
    }
    
    var sortedSubscriptions: [Podcast] {
        switch sortOrder {
        case .dateAdded:
            return subscriptions // Keep original order (date added)
        case .alphabetical:
            return subscriptions.sorted { $0.collectionName.lowercased() < $1.collectionName.lowercased() }
        }
    }

    func getUnplayedCount(for podcast: Podcast) -> Int {
        let podcastEpisodes = allEpisodes.filter { $0.podcastName == podcast.collectionName }
        let trackingManager = EpisodeTrackingManager.shared
        return podcastEpisodes.filter { !trackingManager.isPlayed($0.id) }.count
    }

    func formatUnplayedCount(_ count: Int) -> String {
        if count == 0 {
            return ""
        } else if count < 100 {
            return "\(count)"
        } else if count < 1000 {
            return String(format: "%.1fk", Double(count) / 1000.0)
        } else {
            let thousands = count / 1000
            return "\(thousands)k"
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
            showUnplayedBadges = true // Default to true
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
        //      .animation(.easeInOut, value: audioVM.showMiniPlayer)
        .sheet(isPresented: $audioVM.isPlayerSheetVisible) {
            if let episode = audioVM.episode {
                EpisodePlayerView(
                    episode: episode,
                    podcastTitle: episode.podcastName ?? "Unknown Podcast",
                    podcastImageURL: audioVM.podcastImageURL
                )
            }
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
                                LazyHStack(spacing: 12) {
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
                                                    .frame(width: 120)
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
    
    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search podcasts...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding()
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
    @EnvironmentObject var libraryVM: LibraryViewModel
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    
    var filteredEpisodes: [Episode] {
        episodes.filter { episode in
            trackingManager.shouldShowEpisode(episode.id)
        }
    }
    
    var body: some View {
        List {
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
                    
                    Text("\(filteredEpisodes.count) of \(episodes.count) episodes")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
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
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            showFilterOptions.toggle()
                        }) {
                            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    Divider()
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
            }
            
            // Filter Options (when visible)
            if showFilterOptions {
                Section("Filter Options") {
                    Toggle("Hide Played Episodes", isOn: $trackingManager.hidePlayedEpisodes)
                    Toggle("Hide Archived Episodes", isOn: $trackingManager.hideArchivedEpisodes)
                    
                    if !episodes.isEmpty {
                        Button("Mark All as Played") {
                            trackingManager.markAllAsPlayed(for: episodes)
                        }
                        
                        Button("Mark All as Unplayed") {
                            trackingManager.markAllAsUnplayed(for: episodes)
                        }
                    }
                }
            }
            
            // Loading/Error/Empty states
            if isLoadingEpisodes {
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
            else if let error = loadingError {
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
            else if filteredEpisodes.isEmpty && hasLoadedEpisodes {
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
                            "All episodes are hidden by your current filter settings.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        if !episodes.isEmpty {
                            Button("Show All Episodes") {
                                trackingManager.hidePlayedEpisodes = false
                                trackingManager.hideArchivedEpisodes = false
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
            else {
                ForEach(filteredEpisodes) { episode in
                    EpisodeRowView(episode: episode, podcastImageURL: podcast.artworkUrl600)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedEpisode = episode
                        }
                        .episodeContextMenu(episode: episode)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(podcast.collectionName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedEpisode) { episode in
            EpisodeDetailView(episode: episode, podcastTitle: podcast.collectionName, podcastImageURL: podcast.artworkUrl600)
        }
        .onAppear {
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
    
    func fetchEpisodes(from feedUrl: String) async {
        guard let url = URL(string: feedUrl) else {
            loadingError = "Invalid RSS feed URL."
            hasLoadedEpisodes = true
            return
        }
        
        isLoadingEpisodes = true
        loadingError = nil
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 404 {
                    isLoadingEpisodes = false
                    hasLoadedEpisodes = true
                    loadingError = "Podcast feed not found (404). This feed may have been moved or deleted."
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
            
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                loadingError = "No internet connection. Please check your network and try again."
            } else if (error as NSError).code == NSURLErrorTimedOut {
                loadingError = "Request timed out. Please try again."
            } else {
                loadingError = "Network error: \(error.localizedDescription)"
            }
        }
    }
}

//MARK: - EpisodeRowView
struct EpisodeRowView: View {
    let episode: Episode
    let podcastImageURL: String?
    let onPlayTapped: (() -> Void)?
    
    @ObservedObject private var audioVM = AudioPlayerViewModel.shared
    @ObservedObject private var downloadManager = DownloadManager.shared
    @ObservedObject private var trackingManager = EpisodeTrackingManager.shared
    
    private var isCurrentlyPlaying: Bool {
        audioVM.episode?.id == episode.id && audioVM.isPlaying
    }
    
    private var isCurrentEpisode: Bool {
        audioVM.episode?.id == episode.id
    }
    
    init(episode: Episode, podcastImageURL: String?, onPlayTapped: (() -> Void)? = nil) {
        self.episode = episode
        self.podcastImageURL = podcastImageURL
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
            .frame(width: 65, height: 65)
            .cornerRadius(8)
            .shadow(radius: 6)
            .opacity(trackingManager.isPlayed(episode.id) ? 0.6 : 1.0)
            
            VStack(alignment: .leading, spacing: 1) {
                if let episodeNumber = episode.episodeNumber, !episodeNumber.isEmpty {
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
                    // Status indicators
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
                    
                    if downloadManager.isDownloaded(episode.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                }
                
                HStack(spacing: 4) {
                    if let pubDate = episode.pubDate {
                        Text(pubDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if episode.pubDate != nil && episode.durationInMinutes != nil {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    if let duration = episode.durationInMinutes {
                        Text(duration)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                onPlayTapped?()
            }) {
                Image(systemName: isCurrentlyPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(height: 70)
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
                
                // Status badges
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
                
                // First row of buttons
                HStack(spacing: 12) {
                    // Queue Button
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
                        if isDownloading {
                            HStack {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                                    .scaleEffect(0.8)
                                Text("\(Int(downloadProgress * 100))%")
                            }
                        } else {
                            Label(
                                isDownloaded ? "Delete Download" : "Download",
                                systemImage: isDownloaded ? "trash" : "arrow.down.circle"
                            )
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isDownloaded ? .red : .green)
                }
                
                // Second row of buttons
                HStack(spacing: 12) {
                    // Mark Played/Unplayed Button
                    Button(action: {
                        if trackingManager.isPlayed(episode.id) {
                            trackingManager.markAsUnplayed(episode.id)
                        } else {
                            trackingManager.markAsPlayed(episode.id)
                        }
                    }) {
                        Label(
                            trackingManager.isPlayed(episode.id) ? "Mark as Unplayed" : "Mark as Played",
                            systemImage: trackingManager.isPlayed(episode.id) ? "circle" : "checkmark.circle.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(trackingManager.isPlayed(episode.id) ? .gray : .green)
                    
                    // Archive/Unarchive Button
                    Button(action: {
                        trackingManager.toggleArchived(episode.id)
                    }) {
                        Label(
                            trackingManager.isArchived(episode.id) ? "Unarchive" : "Archive",
                            systemImage: trackingManager.isArchived(episode.id) ? "tray.and.arrow.up" : "archivebox"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(trackingManager.isArchived(episode.id) ? .blue : .orange)
                }
                
                Divider()
                
                if let desc = episode.description {
                    EpisodeDescriptionView(htmlString: desc)
                }
            }
        }
        .navigationTitle("Episode")
        .navigationBarTitleDisplayMode(.inline)
    }
}

//MARK: - EpisodeDescriptionView
struct EpisodeDescriptionView: View {
    let htmlString: String
    
    var body: some View {
        if let description = parsedDescription {
            Text(description)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    private var parsedDescription: AttributedString? {
        guard let data = htmlString.data(using: .utf8) else { return nil }
        
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
                        Image(systemName: "gobackward.15")
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
                    EpisodeDescriptionView(htmlString: desc)
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
            HStack {
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
                
                Text(podcast.collectionName)
                    .font(.caption)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
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
    
    enum LibraryTab: String, CaseIterable {
        case subscriptions = "Subscriptions"
        case newReleases = "New Releases"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Library Tab", selection: $selectedTab) {
                    ForEach(LibraryTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content
                if selectedTab == .subscriptions {
                    subscriptionsView
                } else {
                    newReleasesView
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
                            Image(systemName: "arrow.clockwise")
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
            }
        }
    }
    
    private var newReleasesView: some View {
        Group {
            if libraryVM.isLoadingEpisodes {
                VStack {
                    ProgressView()
                        .scaleEffect(1.2)
                        .padding()
                    Text("Loading new episodes...")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if libraryVM.subscriptions.isEmpty {
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
                    ForEach(libraryVM.recentEpisodes.filter { trackingManager.shouldShowEpisode($0.id) }) { episode in
                        EpisodeRowView(
                            episode: episode,
                            podcastImageURL: episode.podcastImageURL
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
        .onAppear {
            if libraryVM.allEpisodes.isEmpty && !libraryVM.subscriptions.isEmpty {
                Task {
                    await libraryVM.refreshAllEpisodes()
                }
            }
        }
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
    @State private var selectedPeriod: StatsPeriod = .allTime
    @State private var selectedTab: StatsTab = .overview
    
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
                    
                    SessionsStatsView()
                        .tag(StatsTab.sessions)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu("More") {
                        Button("Clear All Data", role: .destructive) {
                            statsManager.clearAllStats()
                        }
                    }
                }
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
                        subtitle: period == .allTime ? "Since \(stats.firstListenDate?.formatted(date: .abbreviated, time: .omitted) ?? "Unknown")" : period.rawValue,
                        icon: "clock.fill",
                        color: .blue
                    )
                    
                    HStack(spacing: 16) {
                        StatsCardView(
                            title: "Episodes",
                            value: "\(stats.totalEpisodes)",
                            subtitle: "Listened to",
                            icon: "play.circle.fill",
                            color: .green
                        )
                        
                        StatsCardView(
                            title: "Podcasts",
                            value: "\(stats.totalPodcasts)",
                            subtitle: "Different shows",
                            icon: "mic.fill",
                            color: .purple
                        )
                    }
                    
                    HStack(spacing: 16) {
                        StatsCardView(
                            title: "Avg Session",
                            value: stats.averageSessionLengthFormatted,
                            subtitle: "Per session",
                            icon: "timer",
                            color: .orange
                        )
                        
                        StatsCardView(
                            title: "Completion Rate",
                            value: "\(Int(stats.completionRate))%",
                            subtitle: "Episodes finished",
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
    @State private var selectedSession: UserSession?
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
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
                    ForEach(sessionManager.userSessions) { session in
                        Button(action: {
                            selectedSession = session
                        }) {
                            SessionCardView(session: session)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            .padding()
        }
        .navigationDestination(item: $selectedSession) { session in
            SessionDetailView(session: session)
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
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            List {
                Section("Playback") {
                    PlaybackSpeedSettingView()
                }
                
                Section("Episode Display") {
                    Toggle("Hide Played Episodes", isOn: $trackingManager.hidePlayedEpisodes)
                    Toggle("Hide Archived Episodes", isOn: $trackingManager.hideArchivedEpisodes)
                    
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
    let subtitle: String
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
            
            Text(subtitle)
                .font(.caption2)
                .foregroundColor(.gray)
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

#Preview {
    ContentView()
}
