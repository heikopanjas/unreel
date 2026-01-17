// Database management for podcast subscriptions
//
// Manages SQLite database for storing podcast subscriptions and episode metadata.
// Uses GRDB with DatabasePool for concurrent reads and WAL mode for performance.

import Foundation
import GRDB

// MARK: - Database Errors

public enum DatabaseError: Error, LocalizedError {
    case directoryNotFound
    case initializationFailed(String)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .directoryNotFound:
            return "Could not determine user data directory"
        case .initializationFailed(let message):
            return "Database initialization failed: \(message)"
        case .operationFailed(let message):
            return "Database operation failed: \(message)"
        }
    }
}

// MARK: - Database

/// Database manager for podcast subscriptions
///
/// Uses GRDB's DatabasePool for concurrent read access and WAL mode for performance.
/// The database is stored in the user's application support directory.
public actor Database {
    private let dbPool: DatabasePool

    /// Create a new database instance
    ///
    /// Opens or creates the SQLite database in the user's data directory
    /// and initializes the schema if needed.
    ///
    /// - Throws: `DatabaseError` if the database cannot be opened or schema creation fails
    public init() async throws {
        let dbPath = try Self.getDatabasePath()

        // Ensure parent directory exists
        let directory = dbPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Configure for performance
        var config = Configuration()
        config.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            // Use WAL mode for better concurrent performance
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            // Faster writes at slight risk of corruption on power loss
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        do {
            dbPool = try DatabasePool(path: dbPath.path, configuration: config)
        } catch {
            throw DatabaseError.initializationFailed(error.localizedDescription)
        }

        // Initialize schema
        try await initSchema()
    }

    /// Initialize with a custom database path (for testing)
    public init(path: String) async throws {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        do {
            dbPool = try DatabasePool(path: path, configuration: config)
        } catch {
            throw DatabaseError.initializationFailed(error.localizedDescription)
        }

        try await initSchema()
    }

    /// Get the database file path
    private static func getDatabasePath() throws -> URL {
        guard let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DatabaseError.directoryNotFound
        }

        let unreelDir = supportDir.appendingPathComponent("unreel", isDirectory: true)
        return unreelDir.appendingPathComponent("subscriptions.db")
    }

    /// Initialize database schema
    private func initSchema() async throws {
        do {
            try await dbPool.write { db in
                // Create podcasts table
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS podcasts (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        name TEXT NOT NULL,
                        feed_url TEXT NOT NULL UNIQUE,
                        last_download INTEGER
                    )
                    """)

                // Create episodes table
                try db.execute(sql: """
                    CREATE TABLE IF NOT EXISTS episodes (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        podcast_id INTEGER NOT NULL,
                        title TEXT NOT NULL,
                        guid TEXT,
                        pub_date INTEGER,
                        downloaded INTEGER NOT NULL DEFAULT 0,
                        FOREIGN KEY (podcast_id) REFERENCES podcasts(id) ON DELETE CASCADE
                    )
                    """)

                // Create unique index on guid (only when not NULL)
                try db.execute(sql: """
                    CREATE UNIQUE INDEX IF NOT EXISTS idx_episodes_podcast_guid
                    ON episodes(podcast_id, guid) WHERE guid IS NOT NULL
                    """)

                // Create index on podcast_id for faster lookups
                try db.execute(sql: """
                    CREATE INDEX IF NOT EXISTS idx_episodes_podcast_id
                    ON episodes(podcast_id)
                    """)
            }
        } catch {
            throw DatabaseError.initializationFailed(error.localizedDescription)
        }
    }

    // MARK: - Podcast Operations

    /// Add or update a podcast subscription
    ///
    /// If the podcast already exists (by feed_url), it updates the name.
    ///
    /// - Parameters:
    ///   - name: The podcast name
    ///   - feedURL: The RSS feed URL
    /// - Returns: The podcast ID
    public func addPodcast(name: String, feedURL: String) async throws -> Int64 {
        try await dbPool.write { db in
            // Use INSERT OR REPLACE pattern
            try db.execute(
                sql: """
                    INSERT INTO podcasts (name, feed_url, last_download)
                    VALUES (?, ?, NULL)
                    ON CONFLICT(feed_url) DO UPDATE SET name = excluded.name
                    """,
                arguments: [name, feedURL]
            )

            // Get the ID
            let id = try Int64.fetchOne(
                db,
                sql: "SELECT id FROM podcasts WHERE feed_url = ?",
                arguments: [feedURL]
            )!

            return id
        }
    }

    /// Update the last download timestamp for a podcast
    public func updateLastDownload(podcastID: Int64, timestamp: Date) async throws {
        try await dbPool.write { db in
            try db.execute(
                sql: "UPDATE podcasts SET last_download = ? WHERE id = ?",
                arguments: [timestamp.timeIntervalSince1970, podcastID]
            )
        }
    }

    /// Get all podcasts sorted by newest episode date
    public func getAllPodcasts() async throws -> [Podcast] {
        try await dbPool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT p.id, p.name, p.feed_url, p.last_download
                FROM podcasts p
                LEFT JOIN (
                    SELECT podcast_id, MAX(pub_date) as newest_date
                    FROM episodes
                    WHERE pub_date IS NOT NULL
                    GROUP BY podcast_id
                ) e ON p.id = e.podcast_id
                ORDER BY e.newest_date DESC NULLS LAST, p.name ASC
                """)

            return rows.map { row in
                Podcast(
                    id: row["id"],
                    name: row["name"],
                    feedURL: row["feed_url"],
                    lastDownload: (row["last_download"] as Int64?).map { Date(timeIntervalSince1970: Double($0)) }
                )
            }
        }
    }

    /// Get a podcast by feed URL
    public func getPodcast(byURL feedURL: String) async throws -> Podcast? {
        try await dbPool.read { db in
            try Podcast.fetchOne(db, sql: """
                SELECT id, name, feed_url, last_download
                FROM podcasts WHERE feed_url = ?
                """, arguments: [feedURL])
        }
    }

    /// Get a podcast by ID
    public func getPodcast(byID id: Int64) async throws -> Podcast? {
        try await dbPool.read { db in
            try Podcast.fetchOne(db, key: id)
        }
    }

    /// Delete a podcast and all its episodes
    public func deletePodcast(id: Int64) async throws {
        try await dbPool.write { db in
            try db.execute(sql: "DELETE FROM podcasts WHERE id = ?", arguments: [id])
        }
    }

    /// Delete all podcasts and episodes
    ///
    /// - Returns: The number of podcasts deleted
    public func deleteAllPodcasts() async throws -> Int {
        try await dbPool.write { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM podcasts")!
            try db.execute(sql: "DELETE FROM podcasts")
            return count
        }
    }

    // MARK: - Episode Operations

    /// Add or update an episode
    ///
    /// Episodes without GUIDs get a generated GUID based on title and publication date.
    /// If an episode with the same GUID exists, its metadata is updated.
    ///
    /// - Parameters:
    ///   - podcastID: The podcast ID
    ///   - title: The episode title
    ///   - guid: The episode GUID from RSS feed (may be nil/empty)
    ///   - pubDate: The publication date
    /// - Returns: AddEpisodeResult with inserted count
    public func addEpisode(
        podcastID: Int64,
        title: String,
        guid: String?,
        pubDate: Date?
    ) async throws -> AddEpisodeResult {
        let pubDateUnix = pubDate.map { Int64($0.timeIntervalSince1970) }
        let hasRealGUID = guid != nil && !guid!.isEmpty

        if hasRealGUID {
            let g = guid!

            return try await dbPool.write { db in
                // Check if episode exists
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)",
                    arguments: [podcastID, g]
                )!

                if exists {
                    // Update existing
                    try db.execute(
                        sql: "UPDATE episodes SET title = ?, pub_date = ? WHERE podcast_id = ? AND guid = ?",
                        arguments: [title, pubDateUnix, podcastID, g]
                    )
                    return AddEpisodeResult(inserted: 0)
                }

                // Check for generated GUID that matches
                let generated = generateGUID(title: title, pubDate: pubDate)
                let hasGenerated = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)",
                    arguments: [podcastID, generated]
                )!

                if hasGenerated {
                    // Update generated GUID to real one
                    try db.execute(
                        sql: "UPDATE episodes SET guid = ?, title = ?, pub_date = ? WHERE podcast_id = ? AND guid = ?",
                        arguments: [g, title, pubDateUnix, podcastID, generated]
                    )
                    return AddEpisodeResult(inserted: 0)
                }

                // Insert new episode
                try db.execute(
                    sql: "INSERT INTO episodes (podcast_id, title, guid, pub_date, downloaded) VALUES (?, ?, ?, ?, 0)",
                    arguments: [podcastID, title, g, pubDateUnix]
                )
                return AddEpisodeResult(inserted: 1)
            }
        }

        // No real GUID - generate one
        let generated = generateGUID(title: title, pubDate: pubDate)

        return try await dbPool.write { db in
            let exists = try Bool.fetchOne(
                db,
                sql: "SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)",
                arguments: [podcastID, generated]
            )!

            if exists {
                try db.execute(
                    sql: "UPDATE episodes SET title = ?, pub_date = ? WHERE podcast_id = ? AND guid = ?",
                    arguments: [title, pubDateUnix, podcastID, generated]
                )
                return AddEpisodeResult(inserted: 0)
            }

            try db.execute(
                sql: "INSERT INTO episodes (podcast_id, title, guid, pub_date, downloaded) VALUES (?, ?, ?, ?, 0)",
                arguments: [podcastID, title, generated, pubDateUnix]
            )
            return AddEpisodeResult(inserted: 1)
        }
    }

    /// Add multiple episodes in a single transaction (batch insert for performance)
    ///
    /// - Parameters:
    ///   - podcastID: The podcast ID
    ///   - items: The podcast items to add
    /// - Returns: Total number of new episodes inserted
    public func addEpisodes(podcastID: Int64, items: [PodcastItem]) async throws -> Int64 {
        try await dbPool.write { db in
            var totalInserted: Int64 = 0

            for item in items {
                let title = item.title ?? "Untitled"
                let pubDateUnix = item.pubDate.map { Int64($0.timeIntervalSince1970) }
                let hasRealGUID = item.guid != nil && !item.guid!.isEmpty

                let guidToUse: String
                if hasRealGUID {
                    guidToUse = item.guid!
                } else {
                    guidToUse = generateGUID(title: title, pubDate: item.pubDate)
                }

                // Check if exists
                let exists = try Bool.fetchOne(
                    db,
                    sql: "SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)",
                    arguments: [podcastID, guidToUse]
                )!

                if exists {
                    // Update existing
                    try db.execute(
                        sql: "UPDATE episodes SET title = ?, pub_date = ? WHERE podcast_id = ? AND guid = ?",
                        arguments: [title, pubDateUnix, podcastID, guidToUse]
                    )
                } else {
                    // Insert new
                    try db.execute(
                        sql: "INSERT INTO episodes (podcast_id, title, guid, pub_date, downloaded) VALUES (?, ?, ?, ?, 0)",
                        arguments: [podcastID, title, guidToUse, pubDateUnix]
                    )
                    totalInserted += 1
                }
            }

            return totalInserted
        }
    }

    /// Get episode count for a podcast
    public func getEpisodeCount(podcastID: Int64) async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM episodes WHERE podcast_id = ?",
                arguments: [podcastID]
            )!
        }
    }

    /// Get all episodes for a podcast sorted by publication date (newest first)
    public func getEpisodes(podcastID: Int64) async throws -> [Episode] {
        try await dbPool.read { db in
            try Episode.fetchAll(db, sql: """
                SELECT id, podcast_id, title, guid, pub_date, downloaded
                FROM episodes
                WHERE podcast_id = ?
                ORDER BY pub_date DESC NULLS LAST
                """, arguments: [podcastID])
        }
    }

    /// Get the newest episode publication date for a podcast
    public func getNewestEpisodeDate(podcastID: Int64) async throws -> Date? {
        try await dbPool.read { db in
            let timestamp = try Int64?.fetchOne(
                db,
                sql: "SELECT MAX(pub_date) FROM episodes WHERE podcast_id = ? AND pub_date IS NOT NULL",
                arguments: [podcastID]
            ) ?? nil

            return timestamp.map { Date(timeIntervalSince1970: Double($0)) }
        }
    }

    /// Get total podcast count
    public func getPodcastCount() async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM podcasts")!
        }
    }

    /// Get total episode count across all podcasts
    public func getTotalEpisodeCount() async throws -> Int {
        try await dbPool.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodes")!
        }
    }
}
