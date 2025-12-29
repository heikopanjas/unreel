//! Unreel - A command line tool for creating local copies of podcast feeds

mod downloader;
mod parser;

pub use downloader::download_feed;
pub use parser::parse_feed;

/// Result type alias for unreel operations
pub type Result<T> = anyhow::Result<T>;
