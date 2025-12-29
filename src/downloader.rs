//! Feed downloading functionality

use crate::Result;

/// Downloads a podcast feed from the given URL
///
/// Makes an HTTP GET request to download the RSS/XML feed content.
///
/// # Arguments
///
/// * `url` - The URL of the podcast feed to download
///
/// # Returns
///
/// Returns the feed content as a String
///
/// # Errors
///
/// Returns an error if the request fails or the response cannot be read
pub async fn download_feed(url: &str) -> Result<String>
{
    // For now, use reqwest to download the feed
    // We'll need to add reqwest as a dependency
    let response = reqwest::get(url).await?;
    let content = response.text().await?;
    Ok(content)
}
