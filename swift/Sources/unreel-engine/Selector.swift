// Episode selection parsing and logic
//
// This module provides functionality to parse and resolve episode selection expressions
// that support multiple formats: numeric ranges, newest/oldest keywords, and mixed selections.

import Foundation

// MARK: - Selector Errors

public enum SelectorError: Error, LocalizedError {
    case emptySelection
    case invalidNumber(String)
    case invalidRange(String)
    case rangeStartGreaterThanEnd(Int, Int)
    case zeroNotAllowed
    case zeroCountNotAllowed(String)
    case episodeOutOfRange(Int, Int)
    case noEpisodes
    case noMatchingEpisodes

    public var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Episode selection cannot be empty"
        case .invalidNumber(let part):
            return "Invalid episode number: '\(part)'"
        case .invalidRange(let part):
            return "Invalid range format '\(part)'. Expected format: START-END"
        case .rangeStartGreaterThanEnd(let start, let end):
            return "Range start (\(start)) must be less than or equal to end (\(end))"
        case .zeroNotAllowed:
            return "Episode numbers must be greater than 0"
        case .zeroCountNotAllowed(let keyword):
            return "Count for '\(keyword):' must be greater than 0"
        case .episodeOutOfRange(let episode, let total):
            return "Episode \(episode) not found (feed has \(total) episodes)"
        case .noEpisodes:
            return "Feed has no episodes"
        case .noMatchingEpisodes:
            return "No episodes match selection"
        }
    }
}

// MARK: - Episode Selector

/// Represents different ways to select episodes from a podcast feed
public enum EpisodeSelector: Equatable, Sendable {
    /// Select specific episode numbers (chronological: 1 = oldest)
    case numeric([Int])
    /// Select N most recent episodes
    case newest(Int)
    /// Select N oldest episodes
    case oldest(Int)
    /// Select all episodes
    case all
    /// Mixed selection combining multiple selectors
    indirect case mixed([EpisodeSelector])
}

// MARK: - Parsing

/// Parse an episode selection string into an EpisodeSelector
///
/// Supports multiple formats:
/// - Numeric: "1,7,23" - specific episode numbers
/// - Ranges: "23-38" - inclusive range of episodes
/// - Keywords: "newest:3", "oldest:5", "newest", "oldest", "all"
/// - Mixed: "1-10,newest:3" - combination of formats
///
/// Episode numbering is chronological where 1 = oldest (first published) episode.
/// Keywords "newest" and "oldest" without numbers default to 1.
///
/// - Parameter input: The episode selection string to parse
/// - Returns: An EpisodeSelector representing the selection
/// - Throws: `SelectorError` if the input string has invalid syntax
public func parseEpisodes(_ input: String) throws -> EpisodeSelector {
    let input = input.trimmingCharacters(in: .whitespaces)

    guard !input.isEmpty else {
        throw SelectorError.emptySelection
    }

    // Check for "all" keyword
    if input == "all" {
        return .all
    }

    // Split by comma to handle multiple parts
    let parts = input
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

    guard !parts.isEmpty else {
        throw SelectorError.emptySelection
    }

    // Parse each part
    var selectors: [EpisodeSelector] = []
    selectors.reserveCapacity(parts.count)

    for part in parts {
        let selector = try parseSinglePart(part)
        selectors.append(selector)
    }

    // If only one selector, return it directly
    if selectors.count == 1 {
        return selectors[0]
    }

    // Check if all selectors are Numeric - if so, merge them
    let allNumeric = selectors.allSatisfy { selector in
        if case .numeric = selector { return true }
        return false
    }

    if allNumeric {
        var allNumbers: [Int] = []
        for selector in selectors {
            if case .numeric(let numbers) = selector {
                allNumbers.append(contentsOf: numbers)
            }
        }
        return .numeric(allNumbers)
    }

    return .mixed(selectors)
}

/// Parse a single part of an episode selection (no commas)
private func parseSinglePart(_ part: String) throws -> EpisodeSelector {
    // Check for newest (with or without :N)
    if part.hasPrefix("newest") {
        if part == "newest" {
            return .newest(1)
        } else if part.hasPrefix("newest:") {
            let countStr = String(part.dropFirst("newest:".count))
            guard let count = Int(countStr) else {
                throw SelectorError.invalidNumber(part)
            }
            guard count > 0 else {
                throw SelectorError.zeroCountNotAllowed("newest")
            }
            return .newest(count)
        }
    }

    // Check for oldest (with or without :N)
    if part.hasPrefix("oldest") {
        if part == "oldest" {
            return .oldest(1)
        } else if part.hasPrefix("oldest:") {
            let countStr = String(part.dropFirst("oldest:".count))
            guard let count = Int(countStr) else {
                throw SelectorError.invalidNumber(part)
            }
            guard count > 0 else {
                throw SelectorError.zeroCountNotAllowed("oldest")
            }
            return .oldest(count)
        }
    }

    // Check for range (contains hyphen)
    if part.contains("-") {
        let rangeParts = part.split(separator: "-")

        guard rangeParts.count == 2 else {
            throw SelectorError.invalidRange(part)
        }

        guard let start = Int(rangeParts[0].trimmingCharacters(in: .whitespaces)),
              let end = Int(rangeParts[1].trimmingCharacters(in: .whitespaces)) else {
            throw SelectorError.invalidRange(part)
        }

        guard start > 0, end > 0 else {
            throw SelectorError.zeroNotAllowed
        }

        guard start <= end else {
            throw SelectorError.rangeStartGreaterThanEnd(start, end)
        }

        // Expand range into individual numbers
        let numbers = Array(start...end)
        return .numeric(numbers)
    }

    // Must be a single number
    guard let number = Int(part) else {
        throw SelectorError.invalidNumber(part)
    }

    guard number > 0 else {
        throw SelectorError.zeroNotAllowed
    }

    return .numeric([number])
}

// MARK: - Selection

/// Select episodes from a feed based on a selector and total episode count
///
/// Converts an EpisodeSelector into actual 0-based indices into the feed.items array.
/// Episode numbering is chronological: 1 = oldest (last in RSS feed), N = newest (first in RSS feed).
///
/// - Parameters:
///   - selector: The episode selector to resolve
///   - total: The total number of episodes in the feed
/// - Returns: A sorted array of unique 0-based indices into the feed items array
/// - Throws: `SelectorError` if episode numbers are out of range or the selection is invalid
public func selectEpisodes(_ selector: EpisodeSelector, total: Int) throws -> [Int] {
    guard total > 0 else {
        throw SelectorError.noEpisodes
    }

    let indices: [Int]

    switch selector {
    case .numeric(let numbers):
        var result: [Int] = []
        result.reserveCapacity(numbers.count)

        for num in numbers {
            guard num <= total else {
                throw SelectorError.episodeOutOfRange(num, total)
            }

            // Convert chronological numbering to RSS feed index
            // Episode 1 (oldest) = last item in feed (index total-1)
            // Episode N (newest) = first item in feed (index 0)
            let index = total - num
            result.append(index)
        }
        indices = result

    case .newest(let count):
        let count = min(count, total)
        indices = Array(0..<count)

    case .oldest(let count):
        let count = min(count, total)
        let start = total - count
        indices = Array(start..<total)

    case .all:
        indices = Array(0..<total)

    case .mixed(let selectors):
        // Recursively resolve each selector and merge using Set for deduplication
        var allIndices = Set<Int>()

        for subSelector in selectors {
            let subIndices = try selectEpisodes(subSelector, total: total)
            allIndices.formUnion(subIndices)
        }

        indices = allIndices.sorted()
    }

    guard !indices.isEmpty else {
        throw SelectorError.noMatchingEpisodes
    }

    return indices
}
