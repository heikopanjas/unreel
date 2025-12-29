use std::io::{self, Write};

use clap::{Parser, Subcommand};
use owo_colors::OwoColorize;
use unreel::{Result, download_feed, parse_feed};

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
    /// Download and parse a podcast feed
    Sync
    {
        /// URL of the podcast feed to sync
        url: String
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
        | Commands::Sync { url } => handle_sync(&url).await?
    }

    Ok(())
}

async fn handle_sync(url: &str) -> Result<()>
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
    println!("{} {} episodes found", "✓".green(), feed.items.len().to_string().yellow());

    // Display first few episodes as a preview
    let preview_count = std::cmp::min(5, feed.items.len());

    if preview_count > 0
    {
        println!();
        println!("{}", "Recent Episodes:".bold().cyan());

        for (i, item) in feed.items.iter().take(preview_count).enumerate()
        {
            println!();
            println!("  {}. {}", (i + 1).to_string().yellow(), item.title.as_deref().unwrap_or("(No title)").bold());

            if let Some(pub_date) = &item.pub_date
            {
                println!("     {}: {}", "Published".dimmed(), pub_date.dimmed());
            }

            if let Some(enclosure) = &item.enclosure
            {
                println!("     {}: {}", "Audio".dimmed(), enclosure.url.dimmed());
            }
        }
    }

    Ok(())
}
