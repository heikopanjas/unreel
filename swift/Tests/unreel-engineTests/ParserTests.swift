import Foundation
import Testing
@testable import unreel_engine

// MARK: - RSS Parser Tests

@Test func parseSimpleRSSFeed() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Test Podcast</title>
            <description>A test podcast feed</description>
            <link>https://example.com</link>
            <item>
                <title>Episode 1</title>
                <description>First episode description</description>
                <guid>ep-001</guid>
                <pubDate>Mon, 01 Jan 2024 12:00:00 +0000</pubDate>
                <enclosure url="https://example.com/ep1.mp3" length="12345" type="audio/mpeg"/>
            </item>
            <item>
                <title>Episode 2</title>
                <description>Second episode</description>
                <guid>ep-002</guid>
                <pubDate>Tue, 02 Jan 2024 12:00:00 +0000</pubDate>
            </item>
        </channel>
        </rss>
        """

    let feed = try parseFeed(xml)

    #expect(feed.title == "Test Podcast")
    #expect(feed.description == "A test podcast feed")
    #expect(feed.link == "https://example.com")
    #expect(feed.items.count == 2)

    let ep1 = feed.items[0]
    #expect(ep1.title == "Episode 1")
    #expect(ep1.description == "First episode description")
    #expect(ep1.guid == "ep-001")
    #expect(ep1.enclosure?.url == "https://example.com/ep1.mp3")
    #expect(ep1.enclosure?.length == "12345")
    #expect(ep1.enclosure?.mimeType == "audio/mpeg")
    #expect(ep1.pubDate != nil)

    let ep2 = feed.items[1]
    #expect(ep2.title == "Episode 2")
    #expect(ep2.enclosure == nil)
}

@Test func parseFeedWithCDATA() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title><![CDATA[Podcast with <special> chars & stuff]]></title>
            <description><![CDATA[Description with "quotes"]]></description>
            <item>
                <title><![CDATA[Episode with <tags>]]></title>
                <guid><![CDATA[guid-with-cdata]]></guid>
            </item>
        </channel>
        </rss>
        """

    let feed = try parseFeed(xml)

    #expect(feed.title == "Podcast with <special> chars & stuff")
    #expect(feed.description == "Description with \"quotes\"")
    #expect(feed.items.count == 1)
    #expect(feed.items[0].title == "Episode with <tags>")
    #expect(feed.items[0].guid == "guid-with-cdata")
}

@Test func parseRFC2822Dates() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Date Test</title>
            <item>
                <title>Standard Format</title>
                <pubDate>Mon, 01 Jan 2024 12:00:00 +0000</pubDate>
            </item>
            <item>
                <title>With Timezone</title>
                <pubDate>Tue, 02 Jan 2024 12:00:00 GMT</pubDate>
            </item>
        </channel>
        </rss>
        """

    let feed = try parseFeed(xml)

    #expect(feed.items.count == 2)
    #expect(feed.items[0].pubDate != nil)
    #expect(feed.items[1].pubDate != nil)
}

@Test func parseEmptyFeed() async throws {
    let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
        <channel>
            <title>Empty Podcast</title>
        </channel>
        </rss>
        """

    let feed = try parseFeed(xml)

    #expect(feed.title == "Empty Podcast")
    #expect(feed.items.isEmpty)
}

@Test func parseInvalidXMLThrows() async throws {
    let xml = "not valid xml at all <unclosed"

    #expect(throws: ParserError.self) {
        try parseFeed(xml)
    }
}

// MARK: - OPML Parser Tests

@Test func parseSimpleOPML() async throws {
    let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head><title>Subscriptions</title></head>
        <body>
            <outline text="Podcast One" xmlUrl="https://example.com/feed1.xml"/>
            <outline text="Podcast Two" xmlUrl="https://example.com/feed2.xml"/>
        </body>
        </opml>
        """

    let entries = try parseOPML(opml)

    #expect(entries.count == 2)
    #expect(entries[0].name == "Podcast One")
    #expect(entries[0].feedURL == "https://example.com/feed1.xml")
    #expect(entries[1].name == "Podcast Two")
    #expect(entries[1].feedURL == "https://example.com/feed2.xml")
}

@Test func parseNestedOPML() async throws {
    let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <body>
            <outline text="Tech">
                <outline text="Tech Podcast" xmlUrl="https://example.com/tech.xml"/>
            </outline>
            <outline text="News">
                <outline text="News Podcast" xmlUrl="https://example.com/news.xml"/>
            </outline>
        </body>
        </opml>
        """

    let entries = try parseOPML(opml)

    #expect(entries.count == 2)
    #expect(entries[0].name == "Tech Podcast")
    #expect(entries[1].name == "News Podcast")
}

@Test func parseOPMLWithTitleAttribute() async throws {
    let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <body>
            <outline title="Using Title" xmlUrl="https://example.com/feed.xml"/>
        </body>
        </opml>
        """

    let entries = try parseOPML(opml)

    #expect(entries.count == 1)
    #expect(entries[0].name == "Using Title")
}

@Test func parseOPMLSkipsEntriesWithoutURL() async throws {
    let opml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <body>
            <outline text="Category Only"/>
            <outline text="Has URL" xmlUrl="https://example.com/feed.xml"/>
        </body>
        </opml>
        """

    let entries = try parseOPML(opml)

    #expect(entries.count == 1)
    #expect(entries[0].name == "Has URL")
}

// MARK: - OPML Generation Tests

@Test func generateOPMLFromPodcasts() async throws {
    let podcasts = [
        Podcast(id: 1, name: "Podcast One", feedURL: "https://example.com/feed1.xml"),
        Podcast(id: 2, name: "Podcast Two", feedURL: "https://example.com/feed2.xml")
    ]

    let opml = generateOPML(from: podcasts)

    #expect(opml.contains("Podcast One"))
    #expect(opml.contains("https://example.com/feed1.xml"))
    #expect(opml.contains("Podcast Two"))
    #expect(opml.contains("https://example.com/feed2.xml"))
    #expect(opml.contains("<opml version=\"2.0\">"))
}

@Test func generateOPMLEscapesSpecialCharacters() async throws {
    let podcasts = [
        Podcast(id: 1, name: "Podcast & Friends <test>", feedURL: "https://example.com/feed?a=1&b=2")
    ]

    let opml = generateOPML(from: podcasts)

    #expect(opml.contains("&amp;"))
    #expect(opml.contains("&lt;"))
    #expect(opml.contains("&gt;"))
    #expect(!opml.contains("<test>"))
}
