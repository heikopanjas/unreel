// RSS and OPML parsing using Foundation XMLParser
//
// Streaming SAX-style parsing for memory efficiency.

import Foundation

// MARK: - Parser Errors

public enum ParserError: Error, LocalizedError {
    case invalidData
    case parsingFailed(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidData:
            return "Invalid XML data"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        }
    }
}

// MARK: - RSS Feed Parser

/// Parses an RSS/XML podcast feed
///
/// Extracts feed metadata and episode information from the XML content.
///
/// - Parameter data: The raw XML data of the podcast feed
/// - Returns: A parsed `PodcastFeed` structure
/// - Throws: `ParserError` if the XML is malformed or cannot be parsed
public func parseFeed(_ data: Data) throws -> PodcastFeed {
    let delegate = RSSParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate

    guard parser.parse() else {
        if let error = parser.parserError {
            throw ParserError.parsingFailed(error.localizedDescription)
        }
        throw ParserError.invalidData
    }

    return delegate.feed
}

/// Parses an RSS/XML podcast feed from a string
///
/// - Parameter xmlContent: The raw XML content as a string
/// - Returns: A parsed `PodcastFeed` structure
/// - Throws: `ParserError` if the XML is malformed or cannot be parsed
public func parseFeed(_ xmlContent: String) throws -> PodcastFeed {
    guard let data = xmlContent.data(using: .utf8) else {
        throw ParserError.invalidData
    }
    return try parseFeed(data)
}

// MARK: - RSS Parser Delegate

private final class RSSParserDelegate: NSObject, XMLParserDelegate {
    var feed = PodcastFeed()

    private var currentItem: PodcastItem?
    private var currentElement = ""
    private var currentText = ""
    private var isInItem = false

    // Pre-allocate capacity for items array (most feeds have 10-100 episodes)
    private var items: ContiguousArray<PodcastItem> = []

    func parserDidStartDocument(_ parser: XMLParser) {
        items.reserveCapacity(64)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentText = ""

        switch elementName {
        case "item":
            isInItem = true
            currentItem = PodcastItem()

        case "enclosure" where isInItem:
            if let url = attributeDict["url"] {
                currentItem?.enclosure = Enclosure(
                    url: url,
                    length: attributeDict["length"],
                    mimeType: attributeDict["type"]
                )
            }

        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let text = String(data: CDATABlock, encoding: .utf8) {
            currentText += text
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if isInItem {
            // Inside an <item> element
            switch elementName {
            case "item":
                if let item = currentItem {
                    items.append(item)
                }
                currentItem = nil
                isInItem = false

            case "title":
                currentItem?.title = text

            case "description":
                currentItem?.description = text

            case "pubDate":
                currentItem?.pubDate = parseRFC2822Date(text)

            case "guid":
                currentItem?.guid = text

            default:
                break
            }
        } else {
            // Feed-level elements (outside <item>)
            switch elementName {
            case "title":
                if feed.title == nil {
                    feed.title = text
                }

            case "description":
                if feed.description == nil {
                    feed.description = text
                }

            case "link":
                if feed.link == nil {
                    feed.link = text
                }

            default:
                break
            }
        }

        currentText = ""
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        feed.items = items
    }
}

// MARK: - OPML Parser

/// Parses an OPML file to extract podcast subscriptions
///
/// Extracts podcast names and feed URLs from outline elements with xmlUrl attributes.
/// Handles both flat and nested outline structures.
///
/// - Parameter url: URL to the OPML file
/// - Returns: An array of `OpmlEntry` structures containing podcast names and feed URLs
/// - Throws: `ParserError` if the file cannot be read or the XML is malformed
public func parseOPML(at url: URL) throws -> [OpmlEntry] {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw ParserError.fileNotFound(url.path)
    }

    let data = try Data(contentsOf: url)
    return try parseOPML(data)
}

/// Parses OPML data to extract podcast subscriptions
///
/// - Parameter data: The raw OPML data
/// - Returns: An array of `OpmlEntry` structures
/// - Throws: `ParserError` if the XML is malformed
public func parseOPML(_ data: Data) throws -> [OpmlEntry] {
    let delegate = OPMLParserDelegate()
    let parser = XMLParser(data: data)
    parser.delegate = delegate

    guard parser.parse() else {
        if let error = parser.parserError {
            throw ParserError.parsingFailed(error.localizedDescription)
        }
        throw ParserError.invalidData
    }

    return delegate.entries
}

/// Parses OPML content from a string
///
/// - Parameter content: The OPML content as a string
/// - Returns: An array of `OpmlEntry` structures
/// - Throws: `ParserError` if the XML is malformed
public func parseOPML(_ content: String) throws -> [OpmlEntry] {
    guard let data = content.data(using: .utf8) else {
        throw ParserError.invalidData
    }
    return try parseOPML(data)
}

// MARK: - OPML Parser Delegate

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    var entries: [OpmlEntry] = []

    func parserDidStartDocument(_ parser: XMLParser) {
        entries.reserveCapacity(32)
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName == "outline" else { return }

        // Check for feed URL
        guard let feedURL = attributeDict["xmlUrl"] else { return }

        // Get name from text or title attribute
        let name = attributeDict["text"] ?? attributeDict["title"] ?? "Untitled Podcast"

        entries.append(OpmlEntry(name: name, feedURL: feedURL))
    }
}

// MARK: - Date Parsing

/// RFC 2822 date formatter for RSS pubDate parsing
private let rfc2822Formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter
}()

/// Alternative RFC 2822 format without day name
private let rfc2822FormatterAlt: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "dd MMM yyyy HH:mm:ss Z"
    return formatter
}()

/// RFC 2822 format with timezone abbreviation (e.g., "GMT", "PST")
private let rfc2822FormatterTZ: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter
}()

/// Parse an RFC 2822 date string
///
/// Tries multiple formats to handle variations in RSS feeds.
///
/// - Parameter string: The date string to parse
/// - Returns: A Date if parsing succeeds, nil otherwise
private func parseRFC2822Date(_ string: String) -> Date? {
    // Try standard format first
    if let date = rfc2822Formatter.date(from: string) {
        return date
    }

    // Try without day name
    if let date = rfc2822FormatterAlt.date(from: string) {
        return date
    }

    // Try with timezone abbreviation
    if let date = rfc2822FormatterTZ.date(from: string) {
        return date
    }

    return nil
}

// MARK: - OPML Generation

/// Generates OPML content from a list of podcasts
///
/// Creates an OPML 2.0 document that can be imported by other podcast apps.
///
/// - Parameter podcasts: The podcasts to export
/// - Returns: OPML content as a string
public func generateOPML(from podcasts: [Podcast]) -> String {
    var output = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
        <head>
            <title>Podcast Subscriptions</title>
        </head>
        <body>

        """

    for podcast in podcasts {
        let escapedName = escapeXML(podcast.name)
        let escapedURL = escapeXML(podcast.feedURL)
        output += "    <outline text=\"\(escapedName)\" xmlUrl=\"\(escapedURL)\"/>\n"
    }

    output += """
        </body>
        </opml>
        """

    return output
}

/// Escape XML special characters
private func escapeXML(_ string: String) -> String {
    string
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&apos;")
}
