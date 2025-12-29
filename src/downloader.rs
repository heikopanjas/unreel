//! Feed downloading functionality

use anyhow::Context;

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
    let response = reqwest::get(url).await.context(format!("Failed to download feed from {}", url))?;

    let content = response.text().await.context("Failed to read response body")?;

    Ok(content)
}
