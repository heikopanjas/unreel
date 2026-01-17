import Foundation
import Testing
@testable import unreel_engine

// MARK: - Downloader Tests

@Test func downloaderInit() async throws {
    let _ = Downloader()
    // Just verify it can be created
    #expect(Downloader.maxConcurrentDownloads == 128)
}

@Test func invalidURLThrows() async throws {
    let downloader = Downloader()

    await #expect(throws: DownloaderError.self) {
        _ = try await downloader.downloadFeed(from: "not a valid url")
    }
}

@Test func emptyURLThrows() async throws {
    let downloader = Downloader()

    await #expect(throws: DownloaderError.self) {
        _ = try await downloader.downloadFeed(from: "")
    }
}

// MARK: - FeedDownloadResult Tests

@Test func feedDownloadResultSuccess() async throws {
    let feed = PodcastFeed(title: "Test")
    let result = FeedDownloadResult(url: "https://example.com", feed: feed, error: nil)

    #expect(result.isSuccess == true)
    #expect(result.feed != nil)
    #expect(result.error == nil)
}

@Test func feedDownloadResultFailure() async throws {
    let error = DownloaderError.invalidURL("test")
    let result = FeedDownloadResult(url: "https://example.com", feed: nil, error: error)

    #expect(result.isSuccess == false)
    #expect(result.feed == nil)
    #expect(result.error != nil)
}

// MARK: - Error Description Tests

@Test func downloaderErrorDescriptions() async throws {
    let invalidURL = DownloaderError.invalidURL("bad-url")
    #expect(invalidURL.errorDescription?.contains("Invalid URL") == true)

    let httpError = DownloaderError.httpError(404, "https://example.com")
    #expect(httpError.errorDescription?.contains("404") == true)

    let noData = DownloaderError.noData("https://example.com")
    #expect(noData.errorDescription?.contains("No data") == true)
}
