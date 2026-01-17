import Foundation
import Testing
@testable import unreel_engine

@Test func libraryVersion() async throws {
    #expect(unreelEngineVersion == "0.1.0")
}

// MARK: - Model Tests

@Test func podcastFeedInit() async throws {
    let feed = PodcastFeed(title: "Test Podcast", description: "A test")
    #expect(feed.title == "Test Podcast")
    #expect(feed.description == "A test")
    #expect(feed.items.isEmpty)
}

@Test func podcastItemInit() async throws {
    let enclosure = Enclosure(url: "https://example.com/ep1.mp3", length: "12345", mimeType: "audio/mpeg")
    let item = PodcastItem(
        title: "Episode 1",
        description: "First episode",
        enclosure: enclosure,
        pubDate: Date(),
        guid: "ep-001"
    )
    #expect(item.title == "Episode 1")
    #expect(item.enclosure?.url == "https://example.com/ep1.mp3")
    #expect(item.guid == "ep-001")
}

@Test func generateGUIDDeterministic() async throws {
    let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
    let guid1 = generateGUID(title: "Test Episode", pubDate: date)
    let guid2 = generateGUID(title: "Test Episode", pubDate: date)
    #expect(guid1 == guid2)
    #expect(guid1.hasPrefix("generated:"))
}

@Test func generateGUIDDifferentInputs() async throws {
    let date = Date(timeIntervalSince1970: 1704067200)
    let guid1 = generateGUID(title: "Episode A", pubDate: date)
    let guid2 = generateGUID(title: "Episode B", pubDate: date)
    #expect(guid1 != guid2)
}

@Test func opmlEntryInit() async throws {
    let entry = OpmlEntry(name: "My Podcast", feedURL: "https://example.com/feed.xml")
    #expect(entry.name == "My Podcast")
    #expect(entry.feedURL == "https://example.com/feed.xml")
}
