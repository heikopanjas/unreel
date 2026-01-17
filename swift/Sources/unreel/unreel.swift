import ArgumentParser
import Foundation
import unreel_engine

@main
struct Unreel: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "unreel",
        abstract: "Create local copies of your podcast feeds",
        version: unreelEngineVersion,
        subcommands: [
            Sync.self,
            Subscribe.self,
            List.self,
            Update.self,
            Unsubscribe.self,
            Import.self,
            Export.self
        ]
    )
}

// MARK: - Sync Command

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Download and parse a podcast feed (one-time operation)"
    )

    @Argument(help: "URL of the podcast feed to sync")
    var url: String

    @Option(name: .shortAndLong, help: "Episode selection: ranges (1,7,23-38), newest:N, oldest:N, all")
    var episodes: String

    func run() async throws {
        let downloader = Downloader()

        print("→ Downloading feed from \(url) ... ", terminator: "")
        fflush(stdout)

        let feed = try await downloader.fetchFeed(from: url)
        print("✓")

        // Display feed information
        print()
        print("Feed Information:")

        if let title = feed.title {
            print("  Title: \(title)")
        }

        if let description = feed.description {
            print("  Description: \(description)")
        }

        if let link = feed.link {
            print("  Link: \(link)")
        }

        print()
        print("→ \(feed.items.count) episodes in feed")

        // Parse episode selection
        print("→ Selecting episodes ... ", terminator: "")
        fflush(stdout)

        let selector = try parseEpisodes(episodes)
        let indices = try selectEpisodes(selector, total: feed.items.count)

        print("✓")
        print("✓ \(indices.count) episodes selected")

        // Display selected episodes
        print()
        print("Selected Episodes:")

        for index in indices {
            let item = feed.items[index]
            let episodeNumber = feed.items.count - index

            print()
            print("  \(episodeNumber). \(item.title ?? "(No title)")")

            if let pubDate = item.pubDate {
                let formatter = DateFormatter()
                formatter.dateStyle = .long
                formatter.timeStyle = .short
                print("     Published: \(formatter.string(from: pubDate))")
            }

            if let description = item.description {
                let truncated = description.prefix(200)
                let cleaned = truncated
                    .replacingOccurrences(of: "<br>", with: " ")
                    .replacingOccurrences(of: "<br/>", with: " ")
                    .replacingOccurrences(of: "\n", with: " ")
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                print("     Description: \(cleaned)\(description.count > 200 ? "..." : "")")
            }

            if let enclosure = item.enclosure {
                print("     Audio: \(enclosure.url)")

                if let lengthStr = enclosure.length, let length = Int64(lengthStr) {
                    let sizeMB = Double(length) / (1024.0 * 1024.0)
                    print("     Size: \(String(format: "%.1f", sizeMB)) MB")
                }
            }
        }
    }
}

// MARK: - Subscribe Command

struct Subscribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Subscribe to a podcast feed"
    )

    @Argument(help: "URL of the podcast feed to subscribe to")
    var url: String

    func run() async throws {
        print("→ Connecting to database ... ", terminator: "")
        fflush(stdout)

        let db = try await Database()
        print("✓")

        print("→ Downloading feed from \(url) ... ", terminator: "")
        fflush(stdout)

        let result = try await subscribeToPodcast(url: url, database: db)
        print("✓")

        print()
        print("✓ Subscribed to \(result.podcast.name)")
        print("  Feed URL: \(url)")
        print("  Episodes: \(result.episodeCount) total")
    }
}

// MARK: - List Command

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all podcast subscriptions"
    )

    @Flag(name: .long, help: "Show only ID and name (one line per podcast)")
    var short = false

    @Flag(name: .long, help: "Show all episodes with title and publication date")
    var long = false

    func run() async throws {
        let db = try await Database()
        let podcasts = try await db.getAllPodcasts()

        if podcasts.isEmpty {
            if !short && !long {
                print("! No podcast subscriptions found")
                print("  Use 'unreel subscribe <URL>' to subscribe to a podcast")
            }
            return
        }

        // Short format: ID and Name only
        if short {
            for podcast in podcasts {
                print("\(podcast.id ?? 0)\t\(podcast.name)")
            }
            return
        }

        // Long format: Include all episodes
        if long {
            print("Podcast Subscriptions (\(podcasts.count)):")

            for podcast in podcasts {
                let episodes = try await db.getEpisodes(podcastID: podcast.id!)

                print()
                print("  \(podcast.name) (\(episodes.count) episodes)")

                let formatter = DateFormatter()
                formatter.dateFormat = "MMM dd, yyyy"

                for episode in episodes {
                    if let pubDate = episode.pubDate {
                        print("    • \(episode.title) (\(formatter.string(from: pubDate)))")
                    } else {
                        print("    • \(episode.title)")
                    }
                }
            }
            return
        }

        // Default format with podcast details
        print("Podcast Subscriptions (\(podcasts.count)):")

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short

        let shortFormatter = DateFormatter()
        shortFormatter.dateStyle = .long

        for podcast in podcasts {
            print()
            print("  \(podcast.name)")
            print("    ID: \(podcast.id ?? 0)")
            print("    Feed URL: \(podcast.feedURL)")

            if let lastDownload = podcast.lastDownload {
                print("    Last Updated: \(dateFormatter.string(from: lastDownload))")
            } else {
                print("    Last Updated: Never")
            }

            let episodeCount = try await db.getEpisodeCount(podcastID: podcast.id!)
            print("    Episodes: \(episodeCount)")

            if let newestDate = try await db.getNewestEpisodeDate(podcastID: podcast.id!) {
                print("    Newest Episode: \(shortFormatter.string(from: newestDate))")
            }
        }
    }
}

// MARK: - Update Command

struct Update: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Update subscriptions (refresh episode lists)"
    )

    @Argument(help: "Optional: specific podcast name to update")
    var name: String?

    @Flag(name: .long, help: "Show debug warnings")
    var debug = false

    func run() async throws {
        print("→ Connecting to database ... ", terminator: "")
        fflush(stdout)

        let db = try await Database()
        print("✓")

        print("→ Loading subscriptions ... ", terminator: "")
        fflush(stdout)

        var podcasts = try await db.getAllPodcasts()
        print("✓")

        if podcasts.isEmpty {
            print()
            print("! No podcast subscriptions found")
            print("  Use 'unreel subscribe <URL>' to subscribe to a podcast")
            return
        }

        // Filter by name if specified
        if let filterName = name {
            podcasts = podcasts.filter { $0.name.localizedCaseInsensitiveContains(filterName) }

            if podcasts.isEmpty {
                print()
                print("! No podcasts match '\(filterName)'")
                return
            }
        }

        print("→ Updating \(podcasts.count) podcast(s) ... ", terminator: "")
        fflush(stdout)

        let results = await updateFeedsInParallel(podcasts: podcasts, database: db)
        print("✓")

        // Separate successful updates with new episodes from errors
        let podcastsWithNew = results.filter { $0.error == nil && !$0.newEpisodes.isEmpty }
        let errors = results.filter { $0.error != nil }

        // Count totals
        let totalNewEpisodes = podcastsWithNew.reduce(0) { $0 + $1.newEpisodes.count }
        let podcastsUpdated = results.filter { $0.error == nil }.count

        // Display podcasts with new episodes
        if !podcastsWithNew.isEmpty {
            print()
            print("New Episodes:")

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM dd, yyyy"

            for result in podcastsWithNew.sorted(by: { $0.podcast.name < $1.podcast.name }) {
                print()
                print("  \(result.podcast.name) (\(result.newEpisodes.count) new)")

                for episode in result.newEpisodes {
                    if let pubDate = episode.pubDate {
                        print("    • \(episode.title) (\(formatter.string(from: pubDate)))")
                    } else {
                        print("    • \(episode.title)")
                    }
                }
            }
        }

        // Display errors
        if !errors.isEmpty {
            print()
            print("Errors:")
            for result in errors {
                print("  ✗ \(result.podcast.name): \(result.error?.localizedDescription ?? "Unknown error")")
            }
        }

        // Summary
        print()
        if totalNewEpisodes > 0 {
            print("✓ Updated \(podcastsUpdated) podcast(s): \(totalNewEpisodes) new episode(s)")
        } else {
            print("✓ Updated \(podcastsUpdated) podcast(s): no new episodes")
        }

        if !errors.isEmpty {
            print("! \(errors.count) podcast(s) failed to update")
        }
    }
}

// MARK: - Unsubscribe Command

struct Unsubscribe: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Unsubscribe from a podcast"
    )

    @Argument(help: "Podcast ID or feed URL to unsubscribe from")
    var idOrURL: String?

    @Flag(name: .long, help: "Remove all podcast subscriptions")
    var all = false

    @Flag(name: .long, help: "Skip confirmation prompt (use with --all)")
    var force = false

    func run() async throws {
        print("→ Connecting to database ... ", terminator: "")
        fflush(stdout)

        let db = try await Database()
        print("✓")

        // Handle --all flag
        if all {
            let podcasts = try await db.getAllPodcasts()

            if podcasts.isEmpty {
                print()
                print("! No podcast subscriptions to remove")
                return
            }

            var totalEpisodes = 0
            for podcast in podcasts {
                totalEpisodes += try await db.getEpisodeCount(podcastID: podcast.id!)
            }

            // Confirm unless --force
            if !force {
                print()
                print("! This will remove \(podcasts.count) podcast(s) and \(totalEpisodes) episode(s) from the database.")
                print("? Are you sure? [y/N] ", terminator: "")
                fflush(stdout)

                guard let input = readLine()?.lowercased(), input == "y" || input == "yes" else {
                    print()
                    print("→ Operation cancelled")
                    return
                }
            }

            print("→ Removing all subscriptions ... ", terminator: "")
            fflush(stdout)

            let deleted = try await db.deleteAllPodcasts()
            print("✓")

            print()
            print("✓ Removed \(deleted) podcast(s) and \(totalEpisodes) episode(s)")
            return
        }

        // Handle single podcast unsubscribe
        guard let idOrURL = idOrURL else {
            print()
            print("✗ Please specify a podcast ID or URL, or use --all to remove all subscriptions")
            return
        }

        print("→ Looking up podcast ... ", terminator: "")
        fflush(stdout)

        // Try to parse as ID first, otherwise treat as URL
        let podcast: Podcast?
        if let id = Int64(idOrURL) {
            podcast = try await db.getPodcast(byID: id)
        } else {
            podcast = try await db.getPodcast(byURL: idOrURL)
        }

        guard let podcast = podcast else {
            print("✗")
            print()
            print("✗ Podcast not found: \(idOrURL)")
            return
        }

        print("✓")

        let episodeCount = try await db.getEpisodeCount(podcastID: podcast.id!)

        print("→ Unsubscribing from \(podcast.name) ... ", terminator: "")
        fflush(stdout)

        try await db.deletePodcast(id: podcast.id!)
        print("✓")

        print()
        print("✓ Unsubscribed from \(podcast.name)")
        print("  Removed episodes: \(episodeCount)")
    }
}

// MARK: - Import Command

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Import podcasts from an OPML file"
    )

    @Argument(help: "Path to the OPML file")
    var file: String

    @Flag(name: .long, help: "Show debug warnings")
    var debug = false

    func run() async throws {
        print("→ Parsing OPML file \(file) ... ", terminator: "")
        fflush(stdout)

        let url = URL(fileURLWithPath: file)
        let entries = try parseOPML(at: url)
        print("✓")

        if entries.isEmpty {
            print()
            print("! No podcast feeds found in OPML file")
            return
        }

        print("→ Found \(entries.count) podcast(s) in OPML file")

        print("→ Connecting to database ... ", terminator: "")
        fflush(stdout)

        let db = try await Database()
        print("✓")

        // Get existing podcasts to check for duplicates
        let existing = try await db.getAllPodcasts()
        let existingURLs = Set(existing.map { $0.feedURL })

        let totalInOPML = entries.count
        let newEntries = entries.filter { !existingURLs.contains($0.feedURL) }
        let skipped = totalInOPML - newEntries.count

        if newEntries.isEmpty {
            print()
            print("✓ All \(totalInOPML) podcast(s) are already subscribed")
            return
        }

        if skipped > 0 {
            print("→ Skipping \(skipped) already subscribed podcast(s)")
        }

        print()
        print("Importing \(newEntries.count) new podcast(s):")

        let results = await importFromOPML(entries: newEntries, database: db)

        // Count successes and failures
        let imported = results.filter { $0.error == nil }.count
        let failed = results.filter { $0.error != nil }.count

        // Display results
        for result in results {
            print()
            if result.error == nil {
                print("  ✓ \(result.podcast.name) (\(result.episodeCount) episodes)")
            } else {
                print("  ✗ \(result.podcast.name): \(result.error!.localizedDescription)")
            }
        }

        print()
        if failed > 0 {
            print("! Import complete: \(imported) imported, \(failed) failed, \(skipped) skipped")
        } else {
            print("✓ Import complete: \(imported) imported, \(skipped) skipped")
        }
    }
}

// MARK: - Export Command

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export subscriptions to an OPML file"
    )

    @Argument(help: "Path to the output OPML file")
    var file: String

    func run() async throws {
        print("→ Connecting to database ... ", terminator: "")
        fflush(stdout)

        let db = try await Database()
        print("✓")

        print("→ Loading subscriptions ... ", terminator: "")
        fflush(stdout)

        let podcasts = try await db.getAllPodcasts()
        print("✓")

        if podcasts.isEmpty {
            print()
            print("! No podcast subscriptions to export")
            return
        }

        print("→ Generating OPML ... ", terminator: "")
        fflush(stdout)

        let opml = generateOPML(from: podcasts)
        print("✓")

        print("→ Writing to \(file) ... ", terminator: "")
        fflush(stdout)

        try opml.write(toFile: file, atomically: true, encoding: .utf8)
        print("✓")

        print()
        print("✓ Exported \(podcasts.count) podcast(s) to \(file)")
    }
}
