// Models for unreel-engine
//
// Data structures for podcast feed parsing and database persistence.

import Foundation
import GRDB

// MARK: - Parsed Feed Models (from RSS/XML)

/// Represents a parsed podcast feed
public struct PodcastFeed: Sendable {
    public var title: String?
    public var description: String?
    public var link: String?
    public var items: ContiguousArray<PodcastItem>
    
    public init(
        title: String? = nil,
        description: String? = nil,
        link: String? = nil,
        items: ContiguousArray<PodcastItem> = []
    ) {
        self.title = title
        self.description = description
        self.link = link
        self.items = items
    }
}

/// Represents a single podcast episode from a parsed feed
public struct PodcastItem: Sendable {
    public var title: String?
    public var description: String?
    public var enclosure: Enclosure?
    public var pubDate: Date?
    public var guid: String?
    
    public init(
        title: String? = nil,
        description: String? = nil,
        enclosure: Enclosure? = nil,
        pubDate: Date? = nil,
        guid: String? = nil
    ) {
        self.title = title
        self.description = description
        self.enclosure = enclosure
        self.pubDate = pubDate
        self.guid = guid
    }
}

/// Represents a podcast episode's audio file
public struct Enclosure: Sendable {
    public let url: String
    public let length: String?
    public let mimeType: String?
    
    public init(url: String, length: String? = nil, mimeType: String? = nil) {
        self.url = url
        self.length = length
        self.mimeType = mimeType
    }
}

/// Represents a podcast entry from an OPML file
public struct OpmlEntry: Sendable {
    public let name: String
    public let feedURL: String
    
    public init(name: String, feedURL: String) {
        self.name = name
        self.feedURL = feedURL
    }
}

// MARK: - Database Models (GRDB)

/// Represents a podcast subscription in the database
public struct Podcast: Sendable, Codable, Identifiable {
    public var id: Int64?
    public var name: String
    public var feedURL: String
    public var lastDownload: Date?
    
    public init(id: Int64? = nil, name: String, feedURL: String, lastDownload: Date? = nil) {
        self.id = id
        self.name = name
        self.feedURL = feedURL
        self.lastDownload = lastDownload
    }
    
    // Map Swift property names to database column names
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case feedURL = "feed_url"
        case lastDownload = "last_download"
    }
}

extension Podcast: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "podcasts" }
}

/// Represents a podcast episode in the database
public struct Episode: Sendable, Codable, Identifiable {
    public var id: Int64?
    public var podcastID: Int64
    public var title: String
    public var guid: String
    public var pubDate: Date?
    public var downloaded: Bool
    
    public init(
        id: Int64? = nil,
        podcastID: Int64,
        title: String,
        guid: String,
        pubDate: Date? = nil,
        downloaded: Bool = false
    ) {
        self.id = id
        self.podcastID = podcastID
        self.title = title
        self.guid = guid
        self.pubDate = pubDate
        self.downloaded = downloaded
    }
    
    // Map Swift property names to database column names
    enum CodingKeys: String, CodingKey {
        case id
        case podcastID = "podcast_id"
        case title
        case guid
        case pubDate = "pub_date"
        case downloaded
    }
}

extension Episode: FetchableRecord, PersistableRecord {
    public static var databaseTableName: String { "episodes" }
}

// MARK: - Result Types

/// Result of adding an episode to the database
public struct AddEpisodeResult: Sendable {
    /// Number of episodes inserted (1 if new, 0 if existing)
    public let inserted: Int64
    /// Warning message if any
    public let warning: String?
    
    public init(inserted: Int64, warning: String? = nil) {
        self.inserted = inserted
        self.warning = warning
    }
}

/// Result of updating a podcast feed
public struct UpdateResult: Sendable {
    public let podcast: Podcast
    public let newEpisodes: [NewEpisode]
    public let error: Error?
    
    public init(podcast: Podcast, newEpisodes: [NewEpisode] = [], error: Error? = nil) {
        self.podcast = podcast
        self.newEpisodes = newEpisodes
        self.error = error
    }
}

/// Represents a newly added episode
public struct NewEpisode: Sendable {
    public let title: String
    public let pubDate: Date?
    
    public init(title: String, pubDate: Date? = nil) {
        self.title = title
        self.pubDate = pubDate
    }
}

/// Result of importing from OPML
public struct ImportResult: Sendable {
    public let podcast: Podcast
    public let episodeCount: Int
    public let error: Error?
    
    public init(podcast: Podcast, episodeCount: Int = 0, error: Error? = nil) {
        self.podcast = podcast
        self.episodeCount = episodeCount
        self.error = error
    }
}

// MARK: - GUID Generation

/// Generate a GUID from episode title and publication date
///
/// Used when an episode has no GUID in the feed. Creates a deterministic
/// identifier based on the episode's title and publication date.
public func generateGUID(title: String, pubDate: Date?) -> String {
    var hasher = Hasher()
    hasher.combine(title)
    if let date = pubDate {
        hasher.combine(date.timeIntervalSince1970)
    }
    let hash = hasher.finalize()
    return String(format: "generated:%016llx", UInt64(bitPattern: Int64(hash)))
}
