//! Unreel - A command line tool for creating local copies of podcast feeds

mod database;
mod downloader;
mod parser;
mod selector;

pub use database::{AddEpisodeResult, Database, Episode, Podcast};
pub use downloader::download_feed;
pub use parser::{parse_feed, parse_opml};
pub use selector::{EpisodeSelector, parse_episodes, select_episodes};

/// Result type alias for unreel operations
pub type Result<T> = anyhow::Result<T>;
