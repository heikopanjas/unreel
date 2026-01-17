import Foundation
import Testing
@testable import unreel_engine

// MARK: - Parsing Tests

@Test func parseSingleNumber() async throws {
    let selector = try parseEpisodes("5")
    #expect(selector == .numeric([5]))
}

@Test func parseMultipleNumbers() async throws {
    let selector = try parseEpisodes("1,5,10")
    #expect(selector == .numeric([1, 5, 10]))
}

@Test func parseRange() async throws {
    let selector = try parseEpisodes("1-5")
    #expect(selector == .numeric([1, 2, 3, 4, 5]))
}

@Test func parseNewest() async throws {
    let selector = try parseEpisodes("newest:3")
    #expect(selector == .newest(3))
}

@Test func parseOldest() async throws {
    let selector = try parseEpisodes("oldest:5")
    #expect(selector == .oldest(5))
}

@Test func parseNewestWithoutNumber() async throws {
    let selector = try parseEpisodes("newest")
    #expect(selector == .newest(1))
}

@Test func parseOldestWithoutNumber() async throws {
    let selector = try parseEpisodes("oldest")
    #expect(selector == .oldest(1))
}

@Test func parseAll() async throws {
    let selector = try parseEpisodes("all")
    #expect(selector == .all)
}

@Test func parseMixedNumbersAndRange() async throws {
    let selector = try parseEpisodes("1,5,10-15")
    // All numeric parts are merged into a single Numeric variant
    #expect(selector == .numeric([1, 5, 10, 11, 12, 13, 14, 15]))
}

@Test func parseMixedWithNewest() async throws {
    let selector = try parseEpisodes("1-5,newest:2")

    if case .mixed(let selectors) = selector {
        #expect(selectors.count == 2)
        #expect(selectors[0] == .numeric([1, 2, 3, 4, 5]))
        #expect(selectors[1] == .newest(2))
    } else {
        Issue.record("Expected Mixed selector")
    }
}

@Test func parseEmptyFails() async throws {
    #expect(throws: SelectorError.self) { try parseEpisodes("") }
    #expect(throws: SelectorError.self) { try parseEpisodes("  ") }
}

@Test func parseZeroFails() async throws {
    #expect(throws: SelectorError.self) { try parseEpisodes("0") }
    #expect(throws: SelectorError.self) { try parseEpisodes("0-5") }
    #expect(throws: SelectorError.self) { try parseEpisodes("1-0") }
}

@Test func parseInvalidRangeFails() async throws {
    #expect(throws: SelectorError.self) { try parseEpisodes("10-5") } // start > end
    #expect(throws: SelectorError.self) { try parseEpisodes("1-5-10") } // too many hyphens
}

@Test func parseNewestZeroFails() async throws {
    #expect(throws: SelectorError.self) { try parseEpisodes("newest:0") }
}

// MARK: - Selection Tests

@Test func selectSingleEpisode() async throws {
    let selector = EpisodeSelector.numeric([1])
    let indices = try selectEpisodes(selector, total: 10)
    #expect(indices == [9]) // Episode 1 = last in feed (index 9)
}

@Test func selectMultipleEpisodes() async throws {
    let selector = EpisodeSelector.numeric([1, 5, 10])
    let indices = try selectEpisodes(selector, total: 10)
    // Episode 1 = index 9, Episode 5 = index 5, Episode 10 = index 0
    #expect(indices == [9, 5, 0])
}

@Test func selectNewest() async throws {
    let selector = EpisodeSelector.newest(3)
    let indices = try selectEpisodes(selector, total: 10)
    #expect(indices == [0, 1, 2]) // First 3 items in RSS feed
}

@Test func selectOldest() async throws {
    let selector = EpisodeSelector.oldest(3)
    let indices = try selectEpisodes(selector, total: 10)
    #expect(indices == [7, 8, 9]) // Last 3 items in RSS feed
}

@Test func selectAll() async throws {
    let selector = EpisodeSelector.all
    let indices = try selectEpisodes(selector, total: 5)
    #expect(indices == [0, 1, 2, 3, 4])
}

@Test func selectNewestMoreThanTotal() async throws {
    let selector = EpisodeSelector.newest(10)
    let indices = try selectEpisodes(selector, total: 5)
    #expect(indices == [0, 1, 2, 3, 4]) // Capped to total
}

@Test func selectOutOfRangeFails() async throws {
    let selector = EpisodeSelector.numeric([100])
    #expect(throws: SelectorError.self) {
        try selectEpisodes(selector, total: 10)
    }
}

@Test func selectMixedDeduplicates() async throws {
    // Select episodes 1-3 and 2-4, should deduplicate to 1,2,3,4
    let selector = EpisodeSelector.mixed([
        .numeric([1, 2, 3]),
        .numeric([2, 3, 4])
    ])
    let indices = try selectEpisodes(selector, total: 10)
    // Episodes 1,2,3,4 = indices 9,8,7,6, sorted
    #expect(indices == [6, 7, 8, 9])
}

@Test func selectMixedWithNewest() async throws {
    let selector = EpisodeSelector.mixed([
        .numeric([1]),   // index 9
        .newest(2)       // indices 0, 1
    ])
    let indices = try selectEpisodes(selector, total: 10)
    #expect(indices == [0, 1, 9])
}

@Test func selectZeroTotalFails() async throws {
    let selector = EpisodeSelector.all
    #expect(throws: SelectorError.self) {
        try selectEpisodes(selector, total: 0)
    }
}
