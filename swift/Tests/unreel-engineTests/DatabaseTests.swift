import Foundation
import Testing
@testable import unreel_engine

// Helper to create a temporary database for testing
func withTestDatabase(_ body: (Database) async throws -> Void) async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let dbPath = tempDir.appendingPathComponent("test_\(UUID().uuidString).db").path

    let db = try await Database(path: dbPath)
    defer {
        try? FileManager.default.removeItem(atPath: dbPath)
        try? FileManager.default.removeItem(atPath: dbPath + "-wal")
        try? FileManager.default.removeItem(atPath: dbPath + "-shm")
    }

    try await body(db)
}

// MARK: - Podcast Tests

@Test func addPodcast() async throws {
    try await withTestDatabase { db in
        let id = try await db.addPodcast(name: "Test Podcast", feedURL: "https://example.com/feed.xml")
        #expect(id > 0)

        let podcast = try await db.getPodcast(byID: id)
        #expect(podcast != nil)
        #expect(podcast?.name == "Test Podcast")
        #expect(podcast?.feedURL == "https://example.com/feed.xml")
    }
}

@Test func addPodcastUpdateOnConflict() async throws {
    try await withTestDatabase { db in
        let id1 = try await db.addPodcast(name: "Original Name", feedURL: "https://example.com/feed.xml")
        let id2 = try await db.addPodcast(name: "Updated Name", feedURL: "https://example.com/feed.xml")

        // Should be same ID (upsert)
        #expect(id1 == id2)

        let podcast = try await db.getPodcast(byID: id1)
        #expect(podcast?.name == "Updated Name")
    }
}

@Test func getAllPodcasts() async throws {
    try await withTestDatabase { db in
        _ = try await db.addPodcast(name: "Podcast A", feedURL: "https://example.com/a.xml")
        _ = try await db.addPodcast(name: "Podcast B", feedURL: "https://example.com/b.xml")

        let podcasts = try await db.getAllPodcasts()
        #expect(podcasts.count == 2)
    }
}

@Test func getPodcastByURL() async throws {
    try await withTestDatabase { db in
        _ = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let found = try await db.getPodcast(byURL: "https://example.com/feed.xml")
        #expect(found != nil)
        #expect(found?.name == "Test")

        let notFound = try await db.getPodcast(byURL: "https://example.com/other.xml")
        #expect(notFound == nil)
    }
}

@Test func deletePodcast() async throws {
    try await withTestDatabase { db in
        let id = try await db.addPodcast(name: "To Delete", feedURL: "https://example.com/feed.xml")

        try await db.deletePodcast(id: id)

        let podcast = try await db.getPodcast(byID: id)
        #expect(podcast == nil)
    }
}

@Test func deleteAllPodcasts() async throws {
    try await withTestDatabase { db in
        _ = try await db.addPodcast(name: "A", feedURL: "https://example.com/a.xml")
        _ = try await db.addPodcast(name: "B", feedURL: "https://example.com/b.xml")

        let deleted = try await db.deleteAllPodcasts()
        #expect(deleted == 2)

        let podcasts = try await db.getAllPodcasts()
        #expect(podcasts.isEmpty)
    }
}

@Test func updateLastDownload() async throws {
    try await withTestDatabase { db in
        let id = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let now = Date()
        try await db.updateLastDownload(podcastID: id, timestamp: now)

        let podcast = try await db.getPodcast(byID: id)
        #expect(podcast?.lastDownload != nil)
        // Check within 1 second tolerance
        let diff = abs(podcast!.lastDownload!.timeIntervalSince(now))
        #expect(diff < 1)
    }
}

// MARK: - Episode Tests

@Test func addEpisode() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let result = try await db.addEpisode(
            podcastID: podcastID,
            title: "Episode 1",
            guid: "ep-001",
            pubDate: Date()
        )

        #expect(result.inserted == 1)

        let count = try await db.getEpisodeCount(podcastID: podcastID)
        #expect(count == 1)
    }
}

@Test func addEpisodeDuplicateGUID() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let result1 = try await db.addEpisode(
            podcastID: podcastID,
            title: "Episode 1",
            guid: "ep-001",
            pubDate: Date()
        )
        #expect(result1.inserted == 1)

        // Same GUID should update, not insert
        let result2 = try await db.addEpisode(
            podcastID: podcastID,
            title: "Episode 1 Updated",
            guid: "ep-001",
            pubDate: Date()
        )
        #expect(result2.inserted == 0)

        let count = try await db.getEpisodeCount(podcastID: podcastID)
        #expect(count == 1)
    }
}

@Test func addEpisodeGeneratesGUID() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        // Episode without GUID
        let result = try await db.addEpisode(
            podcastID: podcastID,
            title: "No GUID Episode",
            guid: nil,
            pubDate: Date(timeIntervalSince1970: 1704067200)
        )
        #expect(result.inserted == 1)

        // Same episode again should not duplicate
        let result2 = try await db.addEpisode(
            podcastID: podcastID,
            title: "No GUID Episode",
            guid: nil,
            pubDate: Date(timeIntervalSince1970: 1704067200)
        )
        #expect(result2.inserted == 0)

        let count = try await db.getEpisodeCount(podcastID: podcastID)
        #expect(count == 1)
    }
}

@Test func addEpisodesBatch() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let items = [
            PodcastItem(title: "Episode 1", pubDate: Date(), guid: "ep-001"),
            PodcastItem(title: "Episode 2", pubDate: Date(), guid: "ep-002"),
            PodcastItem(title: "Episode 3", pubDate: Date(), guid: "ep-003")
        ]

        let inserted = try await db.addEpisodes(podcastID: podcastID, items: items)
        #expect(inserted == 3)

        let count = try await db.getEpisodeCount(podcastID: podcastID)
        #expect(count == 3)
    }
}

@Test func getEpisodes() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        // Add episodes with different dates
        let date1 = Date(timeIntervalSince1970: 1704067200) // Jan 1, 2024
        let date2 = Date(timeIntervalSince1970: 1704153600) // Jan 2, 2024

        _ = try await db.addEpisode(podcastID: podcastID, title: "Older", guid: "old", pubDate: date1)
        _ = try await db.addEpisode(podcastID: podcastID, title: "Newer", guid: "new", pubDate: date2)

        let episodes = try await db.getEpisodes(podcastID: podcastID)
        #expect(episodes.count == 2)
        // Should be sorted newest first
        #expect(episodes[0].title == "Newer")
        #expect(episodes[1].title == "Older")
    }
}

@Test func getNewestEpisodeDate() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")

        let date1 = Date(timeIntervalSince1970: 1704067200)
        let date2 = Date(timeIntervalSince1970: 1704153600)

        _ = try await db.addEpisode(podcastID: podcastID, title: "Older", guid: "old", pubDate: date1)
        _ = try await db.addEpisode(podcastID: podcastID, title: "Newer", guid: "new", pubDate: date2)

        let newest = try await db.getNewestEpisodeDate(podcastID: podcastID)
        #expect(newest != nil)
        #expect(abs(newest!.timeIntervalSince(date2)) < 1)
    }
}

@Test func cascadeDeleteEpisodes() async throws {
    try await withTestDatabase { db in
        let podcastID = try await db.addPodcast(name: "Test", feedURL: "https://example.com/feed.xml")
        _ = try await db.addEpisode(podcastID: podcastID, title: "Episode", guid: "ep", pubDate: nil)

        // Deleting podcast should cascade to episodes
        try await db.deletePodcast(id: podcastID)

        // Check total episode count is 0
        let totalEpisodes = try await db.getTotalEpisodeCount()
        #expect(totalEpisodes == 0)
    }
}
