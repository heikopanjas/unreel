// Feed downloading functionality
//
// Provides async HTTP downloads using URLSession with support for parallel fetching.

import Foundation

// MARK: - Downloader Errors

public enum DownloaderError: Error, LocalizedError {
    case invalidURL(String)
    case downloadFailed(String, Error)
    case httpError(Int, String)
    case noData(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .downloadFailed(let url, let error):
            return "Failed to download \(url): \(error.localizedDescription)"
        case .httpError(let statusCode, let url):
            return "HTTP error \(statusCode) for \(url)"
        case .noData(let url):
            return "No data received from \(url)"
        }
    }
}

// MARK: - Downloader

/// HTTP downloader for podcast feeds
///
/// Uses URLSession for async downloads with configurable concurrency.
public struct Downloader: Sendable {
    private let session: URLSession

    /// Maximum concurrent downloads (default: 128 for high parallelism)
    public static let maxConcurrentDownloads = 128

    /// Create a new downloader with default configuration
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        self.session = URLSession(configuration: config)
    }

    /// Create a downloader with a custom URLSession
    public init(session: URLSession) {
        self.session = session
    }

    /// Download a podcast feed from the given URL
    ///
    /// - Parameter url: The URL of the podcast feed to download
    /// - Returns: The feed content as Data
    /// - Throws: `DownloaderError` if the request fails
    public func downloadFeed(from url: String) async throws -> Data {
        guard let feedURL = URL(string: url) else {
            throw DownloaderError.invalidURL(url)
        }

        return try await downloadFeed(from: feedURL)
    }

    /// Download a podcast feed from the given URL
    ///
    /// - Parameter url: The URL of the podcast feed to download
    /// - Returns: The feed content as Data
    /// - Throws: `DownloaderError` if the request fails
    public func downloadFeed(from url: URL) async throws -> Data {
        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw DownloaderError.downloadFailed(url.absoluteString, error)
        }

        // Check HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            guard (200...299).contains(httpResponse.statusCode) else {
                throw DownloaderError.httpError(httpResponse.statusCode, url.absoluteString)
            }
        }

        guard !data.isEmpty else {
            throw DownloaderError.noData(url.absoluteString)
        }

        return data
    }

    /// Download and parse a podcast feed
    ///
    /// - Parameter url: The URL of the podcast feed
    /// - Returns: The parsed PodcastFeed
    /// - Throws: Error if download or parsing fails
    public func fetchFeed(from url: String) async throws -> PodcastFeed {
        let data = try await downloadFeed(from: url)
        return try parseFeed(data)
    }

    /// Download and parse a podcast feed
    ///
    /// - Parameter url: The URL of the podcast feed
    /// - Returns: The parsed PodcastFeed
    /// - Throws: Error if download or parsing fails
    public func fetchFeed(from url: URL) async throws -> PodcastFeed {
        let data = try await downloadFeed(from: url)
        return try parseFeed(data)
    }
}

// MARK: - Parallel Downloads

/// Result of a parallel feed download
public struct FeedDownloadResult: Sendable {
    public let url: String
    public let feed: PodcastFeed?
    public let error: Error?

    public var isSuccess: Bool { feed != nil }
}

/// Download multiple feeds in parallel using TaskGroup
///
/// Uses high concurrency (128 concurrent downloads) for maximum speed.
///
/// - Parameters:
///   - urls: Array of feed URLs to download
///   - downloader: The downloader to use (default: new instance)
/// - Returns: Array of FeedDownloadResult in the same order as input URLs
public func downloadFeedsInParallel(
    urls: [String],
    downloader: Downloader = Downloader()
) async -> [FeedDownloadResult] {
    // Pre-allocate results array
    var results = [FeedDownloadResult?](repeating: nil, count: urls.count)

    await withTaskGroup(of: (Int, FeedDownloadResult).self) { group in
        for (index, url) in urls.enumerated() {
            group.addTask {
                do {
                    let feed = try await downloader.fetchFeed(from: url)
                    return (index, FeedDownloadResult(url: url, feed: feed, error: nil))
                } catch {
                    return (index, FeedDownloadResult(url: url, feed: nil, error: error))
                }
            }
        }

        // Collect results
        for await (index, result) in group {
            results[index] = result
        }
    }

    return results.compactMap { $0 }
}

/// Download and update multiple podcast feeds in parallel
///
/// For each podcast, downloads the feed, parses it, and adds new episodes to the database.
///
/// - Parameters:
///   - podcasts: Array of podcasts to update
///   - database: The database to update
///   - downloader: The downloader to use
/// - Returns: Array of UpdateResult for each podcast
public func updateFeedsInParallel(
    podcasts: [Podcast],
    database: Database,
    downloader: Downloader = Downloader()
) async -> [UpdateResult] {
    await withTaskGroup(of: UpdateResult.self) { group in
        for podcast in podcasts {
            group.addTask {
                do {
                    let feed = try await downloader.fetchFeed(from: podcast.feedURL)

                    // Add episodes to database
                    let items = Array(feed.items)
                    var newEpisodes: [NewEpisode] = []

                    for item in items {
                        let title = item.title ?? "Untitled"
                        let result = try await database.addEpisode(
                            podcastID: podcast.id!,
                            title: title,
                            guid: item.guid,
                            pubDate: item.pubDate
                        )

                        if result.inserted > 0 {
                            newEpisodes.append(NewEpisode(title: title, pubDate: item.pubDate))
                        }
                    }

                    // Update last download timestamp
                    try await database.updateLastDownload(podcastID: podcast.id!, timestamp: Date())

                    return UpdateResult(podcast: podcast, newEpisodes: newEpisodes, error: nil)
                } catch {
                    return UpdateResult(podcast: podcast, newEpisodes: [], error: error)
                }
            }
        }

        // Collect results
        var results: [UpdateResult] = []
        results.reserveCapacity(podcasts.count)

        for await result in group {
            results.append(result)
        }

        return results
    }
}

/// Subscribe to a new podcast feed
///
/// Downloads the feed, parses it, adds the podcast to the database, and stores all episodes.
///
/// - Parameters:
///   - url: The feed URL
///   - database: The database to use
///   - downloader: The downloader to use
/// - Returns: ImportResult with the new podcast and episode count
public func subscribeToPodcast(
    url: String,
    database: Database,
    downloader: Downloader = Downloader()
) async throws -> ImportResult {
    // Download and parse feed
    let feed = try await downloader.fetchFeed(from: url)

    let name = feed.title ?? "Untitled Podcast"

    // Add podcast to database
    let podcastID = try await database.addPodcast(name: name, feedURL: url)

    // Add all episodes in batch
    let items = Array(feed.items)
    let insertedCount = try await database.addEpisodes(podcastID: podcastID, items: items)

    // Update last download
    try await database.updateLastDownload(podcastID: podcastID, timestamp: Date())

    let podcast = Podcast(id: podcastID, name: name, feedURL: url, lastDownload: Date())
    return ImportResult(podcast: podcast, episodeCount: Int(insertedCount), error: nil)
}

/// Import podcasts from OPML in parallel
///
/// - Parameters:
///   - entries: OPML entries to import
///   - database: The database to use
///   - downloader: The downloader to use
/// - Returns: Array of ImportResult for each entry
public func importFromOPML(
    entries: [OpmlEntry],
    database: Database,
    downloader: Downloader = Downloader()
) async -> [ImportResult] {
    await withTaskGroup(of: ImportResult.self) { group in
        for entry in entries {
            group.addTask {
                do {
                    // Check if already subscribed
                    if let existing = try await database.getPodcast(byURL: entry.feedURL) {
                        return ImportResult(podcast: existing, episodeCount: 0, error: nil)
                    }

                    return try await subscribeToPodcast(
                        url: entry.feedURL,
                        database: database,
                        downloader: downloader
                    )
                } catch {
                    let placeholder = Podcast(name: entry.name, feedURL: entry.feedURL)
                    return ImportResult(podcast: placeholder, episodeCount: 0, error: error)
                }
            }
        }

        var results: [ImportResult] = []
        results.reserveCapacity(entries.count)

        for await result in group {
            results.append(result)
        }

        return results
    }
}
