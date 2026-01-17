//! Episode selection parsing and logic
//!
//! This module provides functionality to parse and resolve episode selection expressions
//! that support multiple formats: numeric ranges, newest/oldest keywords, and mixed selections.

use std::collections::BTreeSet;

use anyhow::{Context, bail};

use crate::Result;

/// Represents different ways to select episodes from a podcast feed
#[derive(Debug, Clone, PartialEq)]
pub enum EpisodeSelector
{
    /// Select specific episode numbers (chronological: 1 = oldest)
    Numeric(Vec<usize>),
    /// Select N most recent episodes
    Newest(usize),
    /// Select N oldest episodes
    Oldest(usize),
    /// Select all episodes
    All,
    /// Mixed selection combining multiple selectors
    Mixed(Vec<EpisodeSelector>)
}

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
/// # Arguments
///
/// * `input` - The episode selection string to parse
///
/// # Errors
///
/// Returns an error if the input string has invalid syntax or cannot be parsed
///
/// # Examples
///
/// ```
/// use unreel::parse_episodes;
///
/// let selector = parse_episodes("1,7,23-38").unwrap();
/// let selector = parse_episodes("newest:3").unwrap();
/// let selector = parse_episodes("newest").unwrap(); // defaults to newest:1
/// let selector = parse_episodes("1-10,oldest").unwrap();
/// ```
pub fn parse_episodes(input: &str) -> Result<EpisodeSelector>
{
    let input = input.trim();

    if input.is_empty() == true
    {
        bail!("Episode selection cannot be empty");
    }

    // Check for "all" keyword
    if input == "all"
    {
        return Ok(EpisodeSelector::All);
    }

    // Split by comma to handle multiple parts
    let parts: Vec<&str> = input.split(',').map(|s| s.trim()).filter(|s| s.is_empty() == false).collect();

    if parts.is_empty() == true
    {
        bail!("Episode selection cannot be empty");
    }

    // Parse each part
    let mut selectors = Vec::new();

    for part in parts
    {
        let selector = parse_single_part(part).context(format!("Failed to parse '{}'", part))?;
        selectors.push(selector);
    }

    // If only one selector, return it directly
    if selectors.len() == 1
    {
        Ok(selectors.into_iter().next().unwrap())
    }
    else
    {
        // Check if all selectors are Numeric - if so, merge them
        let all_numeric = selectors.iter().all(|s| matches!(s, EpisodeSelector::Numeric(_)));

        if all_numeric == true
        {
            let mut all_numbers = Vec::new();

            for selector in selectors
            {
                if let EpisodeSelector::Numeric(numbers) = selector
                {
                    all_numbers.extend(numbers);
                }
            }

            Ok(EpisodeSelector::Numeric(all_numbers))
        }
        else
        {
            Ok(EpisodeSelector::Mixed(selectors))
        }
    }
}

/// Parse a single part of an episode selection (no commas)
fn parse_single_part(part: &str) -> Result<EpisodeSelector>
{
    // Check for newest (with or without :N)
    if part.starts_with("newest") == true
    {
        if part == "newest"
        {
            // Default to newest:1
            return Ok(EpisodeSelector::Newest(1));
        }
        else if part.starts_with("newest:") == true
        {
            let count_str = part.strip_prefix("newest:").unwrap();
            let count = count_str.parse::<usize>().context("Invalid number after 'newest:'")?;

            if count == 0
            {
                bail!("Count for 'newest:' must be greater than 0");
            }

            return Ok(EpisodeSelector::Newest(count));
        }
    }

    // Check for oldest (with or without :N)
    if part.starts_with("oldest") == true
    {
        if part == "oldest"
        {
            // Default to oldest:1
            return Ok(EpisodeSelector::Oldest(1));
        }
        else if part.starts_with("oldest:") == true
        {
            let count_str = part.strip_prefix("oldest:").unwrap();
            let count = count_str.parse::<usize>().context("Invalid number after 'oldest:'")?;

            if count == 0
            {
                bail!("Count for 'oldest:' must be greater than 0");
            }

            return Ok(EpisodeSelector::Oldest(count));
        }
    }

    // Check for range (contains hyphen)
    if part.contains('-') == true
    {
        let range_parts: Vec<&str> = part.split('-').collect();

        if range_parts.len() != 2
        {
            bail!("Invalid range format '{}'. Expected format: START-END", part);
        }

        let start = range_parts[0].trim().parse::<usize>().context("Invalid start number in range")?;
        let end = range_parts[1].trim().parse::<usize>().context("Invalid end number in range")?;

        if start == 0 || end == 0
        {
            bail!("Episode numbers must be greater than 0");
        }

        if start > end
        {
            bail!("Range start ({}) must be less than or equal to end ({})", start, end);
        }

        // Expand range into individual numbers
        let numbers: Vec<usize> = (start..=end).collect();
        return Ok(EpisodeSelector::Numeric(numbers));
    }

    // Must be a single number
    let number = part.parse::<usize>().context("Invalid episode number")?;

    if number == 0
    {
        bail!("Episode numbers must be greater than 0");
    }

    Ok(EpisodeSelector::Numeric(vec![number]))
}

/// Select episodes from a feed based on a selector and total episode count
///
/// Converts an EpisodeSelector into actual 0-based indices into the feed.items array.
/// Episode numbering is chronological: 1 = oldest (last in RSS feed), N = newest (first in RSS feed).
///
/// # Arguments
///
/// * `selector` - The episode selector to resolve
/// * `total` - The total number of episodes in the feed
///
/// # Returns
///
/// A sorted vector of unique 0-based indices into the feed items array
///
/// # Errors
///
/// Returns an error if episode numbers are out of range or the selection is invalid
pub fn select_episodes(selector: &EpisodeSelector, total: usize) -> Result<Vec<usize>>
{
    if total == 0
    {
        bail!("Feed has no episodes");
    }

    let indices = match selector
    {
        | EpisodeSelector::Numeric(numbers) =>
        {
            let mut result = Vec::new();

            for &num in numbers
            {
                if num > total
                {
                    bail!("Episode {} not found (feed has {} episodes)", num, total);
                }

                // Convert chronological numbering to RSS feed index
                // Episode 1 (oldest) = last item in feed (index total-1)
                // Episode N (newest) = first item in feed (index 0)
                let index = total - num;
                result.push(index);
            }

            result
        }
        | EpisodeSelector::Newest(count) =>
        {
            let count = (*count).min(total);
            (0..count).collect()
        }
        | EpisodeSelector::Oldest(count) =>
        {
            let count = (*count).min(total);
            let start = total.saturating_sub(count);
            (start..total).collect()
        }
        | EpisodeSelector::All => (0..total).collect(),
        | EpisodeSelector::Mixed(selectors) =>
        {
            // Recursively resolve each selector and merge
            let mut all_indices = BTreeSet::new();

            for sub_selector in selectors
            {
                let sub_indices = select_episodes(sub_selector, total)?;

                for idx in sub_indices
                {
                    all_indices.insert(idx);
                }
            }

            all_indices.into_iter().collect()
        }
    };

    if indices.is_empty() == true
    {
        bail!("No episodes match selection");
    }

    Ok(indices)
}

#[cfg(test)]
mod tests
{
    use super::*;

    #[test]
    fn test_parse_single_number()
    {
        let selector = parse_episodes("5").unwrap();
        assert_eq!(selector, EpisodeSelector::Numeric(vec![5]));
    }

    #[test]
    fn test_parse_multiple_numbers()
    {
        let selector = parse_episodes("1,5,10").unwrap();
        assert_eq!(selector, EpisodeSelector::Numeric(vec![1, 5, 10]));
    }

    #[test]
    fn test_parse_range()
    {
        let selector = parse_episodes("1-5").unwrap();
        assert_eq!(selector, EpisodeSelector::Numeric(vec![1, 2, 3, 4, 5]));
    }

    #[test]
    fn test_parse_newest()
    {
        let selector = parse_episodes("newest:3").unwrap();
        assert_eq!(selector, EpisodeSelector::Newest(3));
    }

    #[test]
    fn test_parse_oldest()
    {
        let selector = parse_episodes("oldest:5").unwrap();
        assert_eq!(selector, EpisodeSelector::Oldest(5));
    }

    #[test]
    fn test_parse_newest_without_number()
    {
        let selector = parse_episodes("newest").unwrap();
        assert_eq!(selector, EpisodeSelector::Newest(1));
    }

    #[test]
    fn test_parse_oldest_without_number()
    {
        let selector = parse_episodes("oldest").unwrap();
        assert_eq!(selector, EpisodeSelector::Oldest(1));
    }

    #[test]
    fn test_parse_all()
    {
        let selector = parse_episodes("all").unwrap();
        assert_eq!(selector, EpisodeSelector::All);
    }

    #[test]
    fn test_parse_mixed_numbers_and_range()
    {
        let selector = parse_episodes("1,5,10-15").unwrap();

        // All numeric parts are merged into a single Numeric variant
        assert_eq!(selector, EpisodeSelector::Numeric(vec![1, 5, 10, 11, 12, 13, 14, 15]));
    }

    #[test]
    fn test_parse_mixed_with_newest()
    {
        let selector = parse_episodes("1-5,newest:2").unwrap();

        match selector
        {
            | EpisodeSelector::Mixed(selectors) =>
            {
                assert_eq!(selectors.len(), 2);
                assert_eq!(selectors[0], EpisodeSelector::Numeric(vec![1, 2, 3, 4, 5]));
                assert_eq!(selectors[1], EpisodeSelector::Newest(2));
            }
            | _ => panic!("Expected Mixed selector")
        }
    }

    #[test]
    fn test_parse_empty_fails()
    {
        assert!(parse_episodes("").is_err());
        assert!(parse_episodes("  ").is_err());
    }

    #[test]
    fn test_parse_zero_fails()
    {
        assert!(parse_episodes("0").is_err());
        assert!(parse_episodes("0-5").is_err());
        assert!(parse_episodes("1-0").is_err());
    }

    #[test]
    fn test_parse_invalid_range_fails()
    {
        assert!(parse_episodes("10-5").is_err()); // start > end
        assert!(parse_episodes("1-5-10").is_err()); // too many hyphens
    }

    #[test]
    fn test_parse_newest_zero_fails()
    {
        assert!(parse_episodes("newest:0").is_err());
    }

    #[test]
    fn test_select_single_episode()
    {
        let selector = EpisodeSelector::Numeric(vec![1]);
        let indices = select_episodes(&selector, 10).unwrap();
        assert_eq!(indices, vec![9]); // Episode 1 = last in feed (index 9)
    }

    #[test]
    fn test_select_multiple_episodes()
    {
        let selector = EpisodeSelector::Numeric(vec![1, 5, 10]);
        let indices = select_episodes(&selector, 10).unwrap();
        // Episode 1 = index 9, Episode 5 = index 5, Episode 10 = index 0
        assert_eq!(indices, vec![9, 5, 0]);
    }

    #[test]
    fn test_select_newest()
    {
        let selector = EpisodeSelector::Newest(3);
        let indices = select_episodes(&selector, 10).unwrap();
        assert_eq!(indices, vec![0, 1, 2]); // First 3 items in RSS feed
    }

    #[test]
    fn test_select_oldest()
    {
        let selector = EpisodeSelector::Oldest(3);
        let indices = select_episodes(&selector, 10).unwrap();
        assert_eq!(indices, vec![7, 8, 9]); // Last 3 items in RSS feed
    }

    #[test]
    fn test_select_all()
    {
        let selector = EpisodeSelector::All;
        let indices = select_episodes(&selector, 5).unwrap();
        assert_eq!(indices, vec![0, 1, 2, 3, 4]);
    }

    #[test]
    fn test_select_newest_more_than_total()
    {
        let selector = EpisodeSelector::Newest(10);
        let indices = select_episodes(&selector, 5).unwrap();
        assert_eq!(indices, vec![0, 1, 2, 3, 4]); // Capped to total
    }

    #[test]
    fn test_select_out_of_range_fails()
    {
        let selector = EpisodeSelector::Numeric(vec![100]);
        assert!(select_episodes(&selector, 10).is_err());
    }

    #[test]
    fn test_select_mixed_deduplicates()
    {
        // Select episodes 1-3 and 2-4, should deduplicate to 1,2,3,4
        let selector = EpisodeSelector::Mixed(vec![EpisodeSelector::Numeric(vec![1, 2, 3]), EpisodeSelector::Numeric(vec![2, 3, 4])]);
        let indices = select_episodes(&selector, 10).unwrap();
        // Episodes 1,2,3,4 = indices 9,8,7,6, sorted by BTreeSet
        assert_eq!(indices, vec![6, 7, 8, 9]);
    }

    #[test]
    fn test_select_mixed_with_newest()
    {
        let selector = EpisodeSelector::Mixed(vec![
            EpisodeSelector::Numeric(vec![1]), // index 9
            EpisodeSelector::Newest(2),        // indices 0, 1
        ]);
        let indices = select_episodes(&selector, 10).unwrap();
        assert_eq!(indices, vec![0, 1, 9]);
    }

    #[test]
    fn test_select_zero_total_fails()
    {
        let selector = EpisodeSelector::All;
        assert!(select_episodes(&selector, 0).is_err());
    }
}
