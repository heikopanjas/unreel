use std::{
    io::{self, Write},
    path::{Path, PathBuf}
};

use clap::{Parser, Subcommand};
use futures::stream::{self, StreamExt};
use owo_colors::OwoColorize;
use unreel::{Database, Podcast, Result, download_feed, parse_episodes, parse_feed, parse_opml, select_episodes};

/// Unreel - A command line tool for creating local copies of podcast feeds
#[derive(Parser)]
#[command(name = "unreel")]
#[command(about = "Create local copies of your podcast feeds", long_about = None)]
#[command(version)]
struct Cli
{
    #[command(subcommand)]
    command: Commands
}

#[derive(Subcommand)]
enum Commands
{
    /// Download and parse a podcast feed (one-time operation)
    Sync
    {
        /// URL of the podcast feed to sync
        url: String,

        /// Episode selection: ranges (1,7,23-38), newest:N, oldest:N, all, or mixed
        #[arg(short, long, required = true)]
        episodes: String
    },

    /// Subscribe to a podcast feed
    Subscribe
    {
        /// URL of the podcast feed to subscribe to
        url: String
    },

    /// List all podcast subscriptions
    List
    {
        /// Show only ID and name (one line per podcast)
        #[arg(long)]
        short: bool,

        /// Show all episodes with title and publication date
        #[arg(long)]
        long: bool
    },

    /// Update subscriptions (refresh episode lists)
    Update
    {
        /// Optional: specific podcast name to update (updates all if not specified)
        name: Option<String>,

        /// Show debug warnings (e.g., episodes without GUIDs)
        #[arg(long)]
        debug: bool
    },

    /// Unsubscribe from a podcast
    Unsubscribe
    {
        /// Podcast ID or feed URL to unsubscribe from
        id_or_url: Option<String>,

        /// Remove all podcast subscriptions
        #[arg(long)]
        all: bool,

        /// Skip confirmation prompt (use with --all)
        #[arg(long)]
        force: bool
    },

    /// Import podcasts from an OPML file
    Import
    {
        /// Path to the OPML file
        file: PathBuf,

        /// Show debug warnings (e.g., episodes without GUIDs)
        #[arg(long)]
        debug: bool
    },

    /// Export subscriptions to an OPML file
    Export
    {
        /// Path to the output OPML file
        file: PathBuf
    }
}

#[tokio::main]
async fn main()
{
    if let Err(e) = run().await
    {
        eprintln!("{} {}", "✗".red(), e.to_string().red());
        std::process::exit(1);
    }
}

async fn run() -> Result<()>
{
    let cli = Cli::parse();

    match cli.command
    {
        | Commands::Sync { url, episodes } => handle_sync(&url, &episodes).await?,
        | Commands::Subscribe { url } => handle_subscribe(&url).await?,
        | Commands::List { short, long } => handle_list(short, long).await?,
        | Commands::Update { name, debug } => handle_update(name.as_deref(), debug).await?,
        | Commands::Unsubscribe { id_or_url, all, force } => handle_unsubscribe(id_or_url.as_deref(), all, force).await?,
        | Commands::Import { file, debug } => handle_import(&file, debug).await?,
        | Commands::Export { file } => handle_export(&file).await?
    }

    Ok(())
}

async fn handle_sync(url: &str, episodes_str: &str) -> Result<()>
{
    print!("{} Downloading feed from {} ... ", "→".blue(), url.yellow());
    io::stdout().flush()?;

    let content = download_feed(url).await?;
    println!("{}", "✓".green());

    print!("{} Parsing feed ... ", "→".blue());
    io::stdout().flush()?;

    let feed = parse_feed(&content)?;
    println!("{}", "✓".green());

    // Display feed information
    println!();
    println!("{}", "Feed Information:".bold().cyan());

    if let Some(title) = &feed.title
    {
        println!("  {}: {}", "Title".bold(), title);
    }

    if let Some(description) = &feed.description
    {
        println!("  {}: {}", "Description".bold(), description);
    }

    if let Some(link) = &feed.link
    {
        println!("  {}: {}", "Link".bold(), link);
    }

    println!();
    println!("{} {} episodes in feed", "→".blue(), feed.items.len().to_string().yellow());

    // Parse episode selection
    print!("{} Selecting episodes ... ", "→".blue());
    io::stdout().flush()?;

    let selector = parse_episodes(episodes_str)?;
    let indices = select_episodes(&selector, feed.items.len())?;

    println!("{}", "✓".green());
    println!("{} {} episodes selected", "✓".green(), indices.len().to_string().yellow());

    // Display selected episodes with enhanced details
    println!();
    println!("{}", "Selected Episodes:".bold().cyan());

    for &index in &indices
    {
        let item = &feed.items[index];

        // Calculate chronological episode number (1 = oldest)
        let episode_number = feed.items.len() - index;

        println!();
        println!("  {}. {}", episode_number.to_string().yellow(), item.title.as_deref().unwrap_or("(No title)").bold());

        if let Some(pub_date) = &item.pub_date
        {
            // Convert to local timezone and format nicely
            let local_time = pub_date.with_time_zone(jiff::tz::TimeZone::system());
            let formatted = local_time.strftime("%B %d, %Y at %I:%M %p");
            println!("     {}: {}", "Published".dimmed(), formatted.dimmed());
        }

        // Display description if available (truncated)
        if let Some(description) = &item.description
        {
            let truncated = if description.len() > 200
            {
                format!("{}...", &description[..200])
            }
            else
            {
                description.clone()
            };

            // Clean up HTML and extra whitespace
            let cleaned = truncated.replace("<br>", " ").replace("<br/>", " ").replace('\n', " ").split_whitespace().collect::<Vec<_>>().join(" ");

            println!("     {}: {}", "Description".dimmed(), cleaned.dimmed());
        }

        if let Some(enclosure) = &item.enclosure
        {
            println!("     {}: {}", "Audio".dimmed(), enclosure.url.dimmed());

            // Display file size if available
            if let Some(ref length_str) = enclosure.length &&
                let Ok(length) = length_str.parse::<u64>()
            {
                let size_mb = length as f64 / (1024.0 * 1024.0);
                println!("     {}: {:.1} MB", "Size".dimmed(), size_mb.to_string().dimmed());
            }
        }
    }

    Ok(())
}

async fn handle_subscribe(url: &str) -> Result<()>
{
    print!("{} Connecting to database ... ", "→".blue());
    io::stdout().flush()?;

    let db = Database::new().await?;
    println!("{}", "✓".green());

    print!("{} Downloading feed from {} ... ", "→".blue(), url.yellow());
    io::stdout().flush()?;

    let content = download_feed(url).await?;
    println!("{}", "✓".green());

    print!("{} Parsing feed ... ", "→".blue());
    io::stdout().flush()?;

    let feed = parse_feed(&content)?;
    println!("{}", "✓".green());

    // Get podcast title
    let podcast_name = feed.title.as_deref().unwrap_or("Untitled Podcast");

    print!("{} Adding podcast to database ... ", "→".blue());
    io::stdout().flush()?;

    let podcast_id = db.add_podcast(podcast_name, url).await?;
    println!("{}", "✓".green());

    print!("{} Storing {} episodes ... ", "→".blue(), feed.items.len().to_string().yellow());
    io::stdout().flush()?;

    // Store all episodes
    let mut new_count = 0;
    for item in &feed.items
    {
        let title = item.title.as_deref().unwrap_or("Untitled Episode");
        let guid = item.guid.as_deref();

        // Convert jiff::Zoned to jiff::Timestamp
        let pub_date = item.pub_date.as_ref().map(|zoned| zoned.timestamp());

        let result = db.add_episode(podcast_id, title, guid, pub_date).await?;
        new_count += result.inserted;
    }

    // Update last download timestamp
    let now = jiff::Timestamp::now();
    db.update_last_download(podcast_id, now).await?;

    println!("{}", "✓".green());

    println!();
    println!("{} Subscribed to {}", "✓".green(), podcast_name.bold().cyan());
    println!("  {}: {}", "Feed URL".dimmed(), url.dimmed());
    println!("  {}: {} total ({} new)", "Episodes".dimmed(), feed.items.len().to_string().dimmed(), new_count.to_string().dimmed());

    Ok(())
}

async fn handle_list(short: bool, long: bool) -> Result<()>
{
    let db = Database::new().await?;
    let podcasts = db.get_all_podcasts().await?;

    if podcasts.is_empty() == true
    {
        if short == false && long == false
        {
            println!("{} No podcast subscriptions found", "!".yellow());
            println!("  Use {} to subscribe to a podcast", "unreel subscribe <URL>".cyan());
        }
        return Ok(());
    }

    // Short format: ID and Name only
    if short == true
    {
        for podcast in podcasts
        {
            println!("{}\t{}", podcast.id, podcast.name);
        }
        return Ok(());
    }

    // Long format: Include all episodes
    if long == true
    {
        println!("{}", format!("Podcast Subscriptions ({}):", podcasts.len()).bold().cyan());

        for podcast in podcasts
        {
            let episodes = db.get_episodes(podcast.id).await?;

            println!();
            println!("  {} ({} episodes)", podcast.name.bold(), episodes.len().to_string().yellow());

            for episode in episodes
            {
                if let Some(pub_date) = episode.pub_date
                {
                    let local_time = pub_date.to_zoned(jiff::tz::TimeZone::system());
                    let formatted = local_time.strftime("%b %d, %Y");
                    println!("    {} {} {}", "•".dimmed(), episode.title, format!("({})", formatted).dimmed());
                }
                else
                {
                    println!("    {} {}", "•".dimmed(), episode.title);
                }
            }
        }
        return Ok(());
    }

    // Default format with podcast details
    println!("{}", format!("Podcast Subscriptions ({}):", podcasts.len()).bold().cyan());

    for podcast in podcasts
    {
        println!();
        println!("  {}", podcast.name.bold());
        println!("    {}: {}", "ID".dimmed(), podcast.id.to_string().dimmed());
        println!("    {}: {}", "Feed URL".dimmed(), podcast.feed_url.dimmed());

        if let Some(last_download) = podcast.last_download
        {
            let local_time = last_download.to_zoned(jiff::tz::TimeZone::system());
            let formatted = local_time.strftime("%B %d, %Y at %I:%M %p");
            println!("    {}: {}", "Last Updated".dimmed(), formatted.dimmed());
        }
        else
        {
            println!("    {}: {}", "Last Updated".dimmed(), "Never".dimmed());
        }

        let episode_count = db.get_episode_count(podcast.id).await?;
        println!("    {}: {}", "Episodes".dimmed(), episode_count.to_string().dimmed());

        if let Some(newest_date) = db.get_newest_episode_date(podcast.id).await?
        {
            let local_time = newest_date.to_zoned(jiff::tz::TimeZone::system());
            let formatted = local_time.strftime("%B %d, %Y");
            println!("    {}: {}", "Newest Episode".dimmed(), formatted.dimmed());
        }
    }

    Ok(())
}

/// Maximum number of concurrent feed downloads
const MAX_CONCURRENT_UPDATES: usize = 128;

/// Information about a new episode
struct NewEpisode
{
    title:    String,
    pub_date: Option<jiff::Timestamp>
}

/// Result of updating a single podcast
struct UpdateResult
{
    name:         String,
    success:      bool,
    new_episodes: Vec<NewEpisode>,
    warnings:     Vec<String>,
    error:        Option<String>
}

/// Update a single podcast feed
///
/// Downloads the feed, parses it, stores new episodes, and updates the timestamp.
async fn update_single_podcast(db: Database, podcast: Podcast) -> UpdateResult
{
    let name = podcast.name.clone();

    // Download feed
    let content = match download_feed(&podcast.feed_url).await
    {
        | Ok(c) => c,
        | Err(e) => return UpdateResult { name, success: false, new_episodes: Vec::new(), warnings: Vec::new(), error: Some(format!("Failed to download: {}", e)) }
    };

    // Parse feed
    let feed = match parse_feed(&content)
    {
        | Ok(f) => f,
        | Err(e) => return UpdateResult { name, success: false, new_episodes: Vec::new(), warnings: Vec::new(), error: Some(format!("Failed to parse: {}", e)) }
    };

    // Store all episodes and track new ones
    let mut new_episodes = Vec::new();
    let mut warnings = Vec::new();

    for item in &feed.items
    {
        let title = item.title.as_deref().unwrap_or("Untitled Episode");
        let guid = item.guid.as_deref();
        let pub_date = item.pub_date.as_ref().map(|zoned| zoned.timestamp());

        match db.add_episode(podcast.id, title, guid, pub_date).await
        {
            | Ok(result) =>
            {
                if result.inserted > 0
                {
                    new_episodes.push(NewEpisode { title: title.to_string(), pub_date });
                }
                if let Some(warning) = result.warning
                {
                    warnings.push(warning);
                }
            }
            | Err(e) => return UpdateResult { name, success: false, new_episodes, warnings, error: Some(format!("Database error: {}", e)) }
        }
    }

    // Update last download timestamp
    let now = jiff::Timestamp::now();
    if let Err(e) = db.update_last_download(podcast.id, now).await
    {
        return UpdateResult { name, success: false, new_episodes, warnings, error: Some(format!("Failed to update timestamp: {}", e)) };
    }

    UpdateResult { name, success: true, new_episodes, warnings, error: None }
}

async fn handle_update(name: Option<&str>, debug: bool) -> Result<()>
{
    print!("{} Connecting to database ... ", "→".blue());
    io::stdout().flush()?;

    let db = Database::new().await?;
    println!("{}", "✓".green());

    print!("{} Loading subscriptions ... ", "→".blue());
    io::stdout().flush()?;

    let podcasts = db.get_all_podcasts().await?;
    println!("{}", "✓".green());

    if podcasts.is_empty() == true
    {
        println!();
        println!("{} No podcast subscriptions found", "!".yellow());
        println!("  Use {} to subscribe to a podcast", "unreel subscribe <URL>".cyan());
        return Ok(());
    }

    // Filter by name if specified
    let podcasts_to_update: Vec<_> = if let Some(filter_name) = name
    {
        podcasts.into_iter().filter(|p| p.name.to_lowercase().contains(&filter_name.to_lowercase())).collect()
    }
    else
    {
        podcasts
    };

    if podcasts_to_update.is_empty() == true
    {
        println!();
        println!("{} No podcasts match '{}'", "!".yellow(), name.unwrap().yellow());
        return Ok(());
    }

    let podcast_count = podcasts_to_update.len();

    print!("{} Updating {} podcast(s) ... ", "→".blue(), podcast_count.to_string().yellow());
    io::stdout().flush()?;

    // Run updates in parallel with controlled concurrency
    let results: Vec<UpdateResult> = stream::iter(podcasts_to_update)
        .map(|podcast| {
            let db = db.clone();
            async move { update_single_podcast(db, podcast).await }
        })
        .buffer_unordered(MAX_CONCURRENT_UPDATES)
        .collect()
        .await;

    println!("{}", "✓".green());

    // Collect results with new episodes and errors
    let mut podcasts_with_new: Vec<&UpdateResult> = results.iter().filter(|r| r.success == true && r.new_episodes.is_empty() == false).collect();
    let errors: Vec<&UpdateResult> = results.iter().filter(|r| r.success == false).collect();

    // Sort by podcast name for consistent output
    podcasts_with_new.sort_by(|a, b| a.name.cmp(&b.name));

    // Count totals
    let total_new_episodes: usize = podcasts_with_new.iter().map(|r| r.new_episodes.len()).sum();
    let podcasts_updated = results.iter().filter(|r| r.success == true).count();

    // Display podcasts with new episodes
    if podcasts_with_new.is_empty() == false
    {
        println!();
        println!("{}", "New Episodes:".bold().cyan());

        for result in podcasts_with_new
        {
            println!();
            println!("  {} ({} new)", result.name.bold(), result.new_episodes.len().to_string().green());

            for episode in &result.new_episodes
            {
                if let Some(pub_date) = episode.pub_date
                {
                    let local_time = pub_date.to_zoned(jiff::tz::TimeZone::system());
                    let formatted = local_time.strftime("%b %d, %Y");
                    println!("    {} {} {}", "•".dimmed(), episode.title, format!("({})", formatted).dimmed());
                }
                else
                {
                    println!("    {} {}", "•".dimmed(), episode.title);
                }
            }
        }
    }

    // Display errors if any
    if errors.is_empty() == false
    {
        println!();
        println!("{}", "Errors:".bold().red());
        for result in &errors
        {
            println!("  {} {} {}", "✗".red(), result.name.bold(), result.error.as_deref().unwrap_or("Unknown error").red());
        }
    }

    // Display warnings if debug mode is enabled
    if debug == true
    {
        let all_warnings: Vec<_> = results.iter().flat_map(|r| r.warnings.iter().map(|w| (r.name.as_str(), w.as_str()))).collect();

        if all_warnings.is_empty() == false
        {
            println!();
            println!("{}", "Warnings:".bold().yellow());
            for (podcast_name, warning) in all_warnings
            {
                println!("  {} [{}] {}", "!".yellow(), podcast_name.dimmed(), warning.yellow());
            }
        }
    }

    // Summary
    println!();
    if total_new_episodes > 0
    {
        println!(
            "{} Updated {} podcast(s): {} new episode(s)",
            "✓".green(),
            podcasts_updated.to_string().yellow(),
            total_new_episodes.to_string().green()
        );
    }
    else
    {
        println!("{} Updated {} podcast(s): no new episodes", "✓".green(), podcasts_updated.to_string().yellow());
    }

    if errors.is_empty() == false
    {
        println!("{} {} podcast(s) failed to update", "!".yellow(), errors.len().to_string().red());
    }

    Ok(())
}

async fn handle_unsubscribe(id_or_url: Option<&str>, all: bool, force: bool) -> Result<()>
{
    print!("{} Connecting to database ... ", "→".blue());
    io::stdout().flush()?;

    let db = Database::new().await?;
    println!("{}", "✓".green());

    // Handle --all flag
    if all == true
    {
        // Get counts for confirmation message
        let podcasts = db.get_all_podcasts().await?;

        if podcasts.is_empty() == true
        {
            println!();
            println!("{} No podcast subscriptions to remove", "!".yellow());
            return Ok(());
        }

        let podcast_count = podcasts.len();
        let mut total_episodes = 0;
        for podcast in &podcasts
        {
            total_episodes += db.get_episode_count(podcast.id).await?;
        }

        // Confirm unless --force is specified
        if force == false
        {
            println!();
            println!(
                "{} This will remove {} podcast(s) and {} episode(s) from the database.",
                "!".yellow(),
                podcast_count.to_string().yellow(),
                total_episodes.to_string().yellow()
            );
            print!("{} Are you sure? [y/N] ", "?".yellow());
            io::stdout().flush()?;

            let mut input = String::new();
            io::stdin().read_line(&mut input)?;

            let confirmed = input.trim().to_lowercase();
            if confirmed != "y" && confirmed != "yes"
            {
                println!();
                println!("{} Operation cancelled", "→".blue());
                return Ok(());
            }
        }

        print!("{} Removing all subscriptions ... ", "→".blue());
        io::stdout().flush()?;

        let deleted = db.delete_all_podcasts().await?;
        println!("{}", "✓".green());

        println!();
        println!("{} Removed {} podcast(s) and {} episode(s)", "✓".green(), deleted.to_string().cyan(), total_episodes.to_string().cyan());

        return Ok(());
    }

    // Handle single podcast unsubscribe
    let Some(id_or_url) = id_or_url
    else
    {
        println!();
        println!("{} Please specify a podcast ID or URL, or use --all to remove all subscriptions", "✗".red());
        return Ok(());
    };

    print!("{} Looking up podcast ... ", "→".blue());
    io::stdout().flush()?;

    // Try to parse as ID first, otherwise treat as URL
    let podcast = if let Ok(id) = id_or_url.parse::<i64>()
    {
        db.get_podcast_by_id(id).await?
    }
    else
    {
        db.get_podcast_by_url(id_or_url).await?
    };

    let Some(podcast) = podcast
    else
    {
        println!("{}", "✗".red());
        println!();
        println!("{} Podcast not found: {}", "✗".red(), id_or_url.yellow());
        return Ok(());
    };

    println!("{}", "✓".green());

    // Get episode count before deleting
    let episode_count = db.get_episode_count(podcast.id).await?;

    print!("{} Unsubscribing from {} ... ", "→".blue(), podcast.name.bold());
    io::stdout().flush()?;

    db.delete_podcast(podcast.id).await?;

    println!("{}", "✓".green());
    println!();
    println!("{} Unsubscribed from {}", "✓".green(), podcast.name.bold().cyan());
    println!("  {}: {}", "Removed episodes".dimmed(), episode_count.to_string().dimmed());

    Ok(())
}

/// Result of importing a single podcast from OPML
struct ImportResult
{
    name:           String,
    success:        bool,
    total_episodes: usize,
    warnings:       Vec<String>,
    error:          Option<String>
}

/// Import a single podcast from an OPML entry
///
/// Downloads the feed, parses it, stores the podcast and episodes in the database.
async fn import_single_podcast(db: Database, name: String, feed_url: String) -> ImportResult
{
    // Download feed
    let content = match download_feed(&feed_url).await
    {
        | Ok(c) => c,
        | Err(e) => return ImportResult { name, success: false, total_episodes: 0, warnings: Vec::new(), error: Some(format!("Failed to download: {}", e)) }
    };

    // Parse feed
    let feed = match parse_feed(&content)
    {
        | Ok(f) => f,
        | Err(e) => return ImportResult { name, success: false, total_episodes: 0, warnings: Vec::new(), error: Some(format!("Failed to parse: {}", e)) }
    };

    // Use feed title if available, otherwise use OPML name
    let podcast_name = feed.title.as_deref().unwrap_or(&name);

    // Add podcast to database
    let podcast_id = match db.add_podcast(podcast_name, &feed_url).await
    {
        | Ok(id) => id,
        | Err(e) => return ImportResult { name, success: false, total_episodes: 0, warnings: Vec::new(), error: Some(format!("Database error: {}", e)) }
    };

    // Store all episodes and collect warnings
    let mut warnings = Vec::new();
    for item in &feed.items
    {
        let title = item.title.as_deref().unwrap_or("Untitled Episode");
        let guid = item.guid.as_deref();
        let pub_date = item.pub_date.as_ref().map(|zoned| zoned.timestamp());

        if let Ok(result) = db.add_episode(podcast_id, title, guid, pub_date).await &&
            let Some(warning) = result.warning
        {
            warnings.push(warning);
        }
    }

    // Update timestamp
    let now = jiff::Timestamp::now();
    let _ = db.update_last_download(podcast_id, now).await;

    // Return the actual podcast name from the feed
    let final_name = feed.title.unwrap_or(name);
    ImportResult { name: final_name, success: true, total_episodes: feed.items.len(), warnings, error: None }
}

async fn handle_import(file: &Path, debug: bool) -> Result<()>
{
    print!("{} Parsing OPML file {} ... ", "→".blue(), file.display().to_string().yellow());
    io::stdout().flush()?;

    let entries = parse_opml(file)?;
    println!("{}", "✓".green());

    if entries.is_empty() == true
    {
        println!();
        println!("{} No podcast feeds found in OPML file", "!".yellow());
        return Ok(());
    }

    println!("{} Found {} podcast(s) in OPML file", "→".blue(), entries.len().to_string().yellow());

    print!("{} Connecting to database ... ", "→".blue());
    io::stdout().flush()?;

    let db = Database::new().await?;
    println!("{}", "✓".green());

    // Get existing podcasts to check for duplicates
    let existing = db.get_all_podcasts().await?;
    let existing_urls: std::collections::HashSet<_> = existing.iter().map(|p| p.feed_url.clone()).collect();

    // Track original count before filtering
    let total_in_opml = entries.len();

    // Filter out already subscribed feeds
    let new_entries: Vec<_> = entries.into_iter().filter(|e| existing_urls.contains(&e.feed_url) == false).collect();

    let skipped = total_in_opml - new_entries.len();

    if new_entries.is_empty() == true
    {
        println!();
        println!("{} All {} podcast(s) are already subscribed", "✓".green(), total_in_opml.to_string().yellow());
        return Ok(());
    }

    if skipped > 0
    {
        println!("{} Skipping {} already subscribed podcast(s)", "→".blue(), skipped.to_string().yellow());
    }

    println!();
    println!("{}", format!("Importing {} new podcast(s) (up to {} in parallel):", new_entries.len(), MAX_CONCURRENT_UPDATES).bold().cyan());

    // Run imports in parallel with controlled concurrency
    let results: Vec<ImportResult> = stream::iter(new_entries)
        .map(|entry| {
            let db = db.clone();
            async move { import_single_podcast(db, entry.name, entry.feed_url).await }
        })
        .buffer_unordered(MAX_CONCURRENT_UPDATES)
        .collect()
        .await;

    // Count successes and failures
    let imported = results.iter().filter(|r| r.success == true).count();
    let failed = results.iter().filter(|r| r.success == false).count();

    // Display results
    for result in &results
    {
        println!();
        if result.success == true
        {
            println!("  {} {} ({} episodes)", "✓".green(), result.name.bold(), result.total_episodes.to_string().yellow());
        }
        else
        {
            println!("  {} {} {}", "✗".red(), result.name.bold(), result.error.as_deref().unwrap_or_default().red());
        }
    }

    // Display warnings if debug mode is enabled
    if debug == true
    {
        let all_warnings: Vec<_> = results.iter().flat_map(|r| r.warnings.iter().map(|w| (r.name.as_str(), w.as_str()))).collect();

        if all_warnings.is_empty() == false
        {
            println!();
            println!("{}", "Warnings:".bold().yellow());
            for (podcast_name, warning) in all_warnings
            {
                println!("  {} [{}] {}", "!".yellow(), podcast_name.dimmed(), warning.yellow());
            }
        }
    }

    println!();
    if failed > 0
    {
        println!("{} Import complete: {} imported, {} failed, {} skipped", "!".yellow(), imported.to_string().green(), failed.to_string().red(), skipped.to_string().yellow());
    }
    else
    {
        println!("{} Import complete: {} imported, {} skipped", "✓".green(), imported.to_string().green(), skipped.to_string().yellow());
    }

    Ok(())
}

async fn handle_export(file: &Path) -> Result<()>
{
    print!("{} Connecting to database ... ", "→".blue());
    io::stdout().flush()?;

    let db = Database::new().await?;
    println!("{}", "✓".green());

    print!("{} Loading subscriptions ... ", "→".blue());
    io::stdout().flush()?;

    let podcasts = db.get_all_podcasts().await?;
    println!("{}", "✓".green());

    if podcasts.is_empty() == true
    {
        println!();
        println!("{} No podcast subscriptions to export", "!".yellow());
        return Ok(());
    }

    print!("{} Generating OPML ... ", "→".blue());
    io::stdout().flush()?;

    // Build OPML content
    let mut opml = String::new();
    opml.push_str("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
    opml.push_str("<opml version=\"2.0\">\n");
    opml.push_str("  <head>\n");
    opml.push_str("    <title>Podcast Subscriptions</title>\n");
    opml.push_str("  </head>\n");
    opml.push_str("  <body>\n");

    for podcast in &podcasts
    {
        // Escape XML special characters in name and URL
        let escaped_name = escape_xml(&podcast.name);
        let escaped_url = escape_xml(&podcast.feed_url);
        opml.push_str(&format!("    <outline text=\"{}\" type=\"rss\" xmlUrl=\"{}\" />\n", escaped_name, escaped_url));
    }

    opml.push_str("  </body>\n");
    opml.push_str("</opml>\n");

    println!("{}", "✓".green());

    print!("{} Writing to {} ... ", "→".blue(), file.display().to_string().yellow());
    io::stdout().flush()?;

    std::fs::write(file, opml)?;
    println!("{}", "✓".green());

    println!();
    println!("{} Exported {} podcast(s) to {}", "✓".green(), podcasts.len().to_string().cyan(), file.display().to_string().cyan());

    Ok(())
}

/// Escape XML special characters
fn escape_xml(s: &str) -> String
{
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&apos;")
}
