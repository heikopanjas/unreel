//! Database management for podcast subscriptions
//!
//! Manages SQLite database for storing podcast subscriptions and episode metadata.

use std::hash::{DefaultHasher, Hash, Hasher};

use anyhow::Context;
use jiff::Timestamp;
use sqlx::{Row, SqlitePool, sqlite::SqlitePoolOptions};

use crate::Result;

/// Generate a GUID from episode title and publication date
///
/// Used when an episode has no GUID in the feed. Creates a deterministic
/// identifier based on the episode's title and publication date.
fn generate_guid(title: &str, pub_date: Option<i64>) -> String
{
    let mut hasher = DefaultHasher::new();
    title.hash(&mut hasher);
    pub_date.hash(&mut hasher);
    format!("generated:{:016x}", hasher.finish())
}

/// Represents a podcast subscription
#[derive(Debug, Clone)]
pub struct Podcast
{
    pub id:            i64,
    pub name:          String,
    pub feed_url:      String,
    pub last_download: Option<Timestamp>
}

/// Represents a podcast episode
#[derive(Debug, Clone)]
pub struct Episode
{
    pub id:         i64,
    pub podcast_id: i64,
    pub title:      String,
    pub guid:       String,
    pub pub_date:   Option<Timestamp>,
    pub downloaded: bool
}

/// Result of adding an episode
#[derive(Debug)]
pub struct AddEpisodeResult
{
    /// Number of episodes inserted (1 if new, 0 if existing)
    pub inserted: i64,
    /// Warning message if any (e.g., episode without GUID)
    pub warning:  Option<String>
}

/// Database manager for podcast subscriptions
///
/// This struct is cheaply cloneable as the underlying `SqlitePool` is `Arc`-based.
#[derive(Clone)]
pub struct Database
{
    pool: SqlitePool
}

impl Database
{
    /// Create a new database instance
    ///
    /// Opens or creates the SQLite database in the user's data directory
    /// and initializes the schema if needed.
    ///
    /// # Errors
    ///
    /// Returns an error if the database cannot be opened or schema creation fails
    pub async fn new() -> Result<Self>
    {
        let db_path = Self::get_db_path()?;

        // Ensure parent directory exists
        if let Some(parent) = db_path.parent()
        {
            std::fs::create_dir_all(parent).context("Failed to create data directory")?;
        }

        let db_url = format!("sqlite://{}?mode=rwc", db_path.display());

        let pool = SqlitePoolOptions::new().max_connections(5).connect(&db_url).await.context(format!("Failed to connect to database at {}", db_url))?;

        let db = Self { pool };

        // Initialize schema
        db.init_schema().await?;

        Ok(db)
    }

    /// Get the database file path
    ///
    /// Returns the path to the SQLite database file in the user's data directory
    fn get_db_path() -> Result<std::path::PathBuf>
    {
        let data_dir = dirs::data_dir().context("Could not determine user data directory")?;

        let unreel_dir = data_dir.join("unreel");
        Ok(unreel_dir.join("subscriptions.db"))
    }

    /// Initialize database schema
    ///
    /// Creates the podcasts and episodes tables if they don't exist
    async fn init_schema(&self) -> Result<()>
    {
        // Create podcasts table
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS podcasts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                feed_url TEXT NOT NULL UNIQUE,
                last_download INTEGER
            )
            "#
        )
        .execute(&self.pool)
        .await
        .context("Failed to create podcasts table")?;

        // Create episodes table
        sqlx::query(
            r#"
            CREATE TABLE IF NOT EXISTS episodes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                podcast_id INTEGER NOT NULL,
                title TEXT NOT NULL,
                guid TEXT,
                pub_date INTEGER,
                downloaded INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (podcast_id) REFERENCES podcasts(id) ON DELETE CASCADE
            )
            "#
        )
        .execute(&self.pool)
        .await
        .context("Failed to create episodes table")?;

        // Create unique index on guid only when it's not NULL
        sqlx::query(
            r#"
            CREATE UNIQUE INDEX IF NOT EXISTS idx_episodes_podcast_guid
            ON episodes(podcast_id, guid) WHERE guid IS NOT NULL
            "#
        )
        .execute(&self.pool)
        .await
        .context("Failed to create unique index")?;

        // Create index on podcast_id for faster lookups
        sqlx::query(
            r#"
            CREATE INDEX IF NOT EXISTS idx_episodes_podcast_id
            ON episodes(podcast_id)
            "#
        )
        .execute(&self.pool)
        .await
        .context("Failed to create index")?;

        Ok(())
    }

    /// Add or update a podcast subscription
    ///
    /// If the podcast already exists (by feed_url), it updates the name.
    /// Returns the podcast ID.
    ///
    /// # Arguments
    ///
    /// * `name` - The podcast name
    /// * `feed_url` - The RSS feed URL
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn add_podcast(&self, name: &str, feed_url: &str) -> Result<i64>
    {
        let result = sqlx::query(
            r#"
            INSERT INTO podcasts (name, feed_url, last_download)
            VALUES (?, ?, NULL)
            ON CONFLICT(feed_url) DO UPDATE SET name = excluded.name
            RETURNING id
            "#
        )
        .bind(name)
        .bind(feed_url)
        .fetch_one(&self.pool)
        .await
        .context("Failed to add podcast")?;

        let id: i64 = result.get(0);
        Ok(id)
    }

    /// Update the last download timestamp for a podcast
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    /// * `timestamp` - The download timestamp
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn update_last_download(&self, podcast_id: i64, timestamp: Timestamp) -> Result<()>
    {
        let unix_timestamp = timestamp.as_second();

        sqlx::query(
            r#"
            UPDATE podcasts
            SET last_download = ?
            WHERE id = ?
            "#
        )
        .bind(unix_timestamp)
        .bind(podcast_id)
        .execute(&self.pool)
        .await
        .context("Failed to update last download timestamp")?;

        Ok(())
    }

    /// Add or update an episode
    ///
    /// If the episode already exists (by GUID), it updates the metadata.
    /// If it's a new episode, it inserts it.
    ///
    /// Episodes without GUIDs (or with empty GUIDs) get a generated GUID based on
    /// title and publication date for deduplication. If a feed later provides a real
    /// GUID for an episode that previously had a generated one, the GUID is updated.
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    /// * `title` - The episode title
    /// * `guid` - The episode GUID from RSS feed (may be empty/missing)
    /// * `pub_date` - The publication date
    ///
    /// # Returns
    ///
    /// Returns `AddEpisodeResult` with inserted count and optional warning
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn add_episode(&self, podcast_id: i64, title: &str, guid: Option<&str>, pub_date: Option<Timestamp>) -> Result<AddEpisodeResult>
    {
        let pub_date_unix = pub_date.map(|ts| ts.as_second());
        let has_real_guid = guid.is_some() == true && guid.unwrap().is_empty() == false;

        if has_real_guid == true
        {
            let g = guid.unwrap();

            // Check if episode with this GUID already exists
            let exists: bool = sqlx::query_scalar(
                r#"
                SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)
                "#
            )
            .bind(podcast_id)
            .bind(g)
            .fetch_one(&self.pool)
            .await
            .context("Failed to check for existing episode")?;

            if exists == true
            {
                // Update existing episode metadata
                sqlx::query(
                    r#"
                    UPDATE episodes
                    SET title = ?, pub_date = ?
                    WHERE podcast_id = ? AND guid = ?
                    "#
                )
                .bind(title)
                .bind(pub_date_unix)
                .bind(podcast_id)
                .bind(g)
                .execute(&self.pool)
                .await
                .context("Failed to update episode")?;

                return Ok(AddEpisodeResult { inserted: 0, warning: None });
            }

            // Check if there's an episode with a generated GUID that matches this title+pub_date
            // If so, update its GUID to the real one
            let generated = generate_guid(title, pub_date_unix);
            let has_generated: bool = sqlx::query_scalar(
                r#"
                SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)
                "#
            )
            .bind(podcast_id)
            .bind(&generated)
            .fetch_one(&self.pool)
            .await
            .context("Failed to check for generated GUID")?;

            if has_generated == true
            {
                // Update the generated GUID to the real one
                sqlx::query(
                    r#"
                    UPDATE episodes
                    SET guid = ?, title = ?, pub_date = ?
                    WHERE podcast_id = ? AND guid = ?
                    "#
                )
                .bind(g)
                .bind(title)
                .bind(pub_date_unix)
                .bind(podcast_id)
                .bind(&generated)
                .execute(&self.pool)
                .await
                .context("Failed to update episode GUID")?;

                return Ok(AddEpisodeResult { inserted: 0, warning: None });
            }

            // Insert new episode with real GUID
            sqlx::query(
                r#"
                INSERT INTO episodes (podcast_id, title, guid, pub_date, downloaded)
                VALUES (?, ?, ?, ?, 0)
                "#
            )
            .bind(podcast_id)
            .bind(title)
            .bind(g)
            .bind(pub_date_unix)
            .execute(&self.pool)
            .await
            .context("Failed to add episode")?;

            return Ok(AddEpisodeResult { inserted: 1, warning: None });
        }

        // No real GUID - generate one from title and pub_date
        let generated = generate_guid(title, pub_date_unix);

        // Check if episode with generated GUID already exists
        let exists: bool = sqlx::query_scalar(
            r#"
            SELECT EXISTS(SELECT 1 FROM episodes WHERE podcast_id = ? AND guid = ?)
            "#
        )
        .bind(podcast_id)
        .bind(&generated)
        .fetch_one(&self.pool)
        .await
        .context("Failed to check for existing episode")?;

        if exists == true
        {
            // Update existing episode metadata
            sqlx::query(
                r#"
                UPDATE episodes
                SET title = ?, pub_date = ?
                WHERE podcast_id = ? AND guid = ?
                "#
            )
            .bind(title)
            .bind(pub_date_unix)
            .bind(podcast_id)
            .bind(&generated)
            .execute(&self.pool)
            .await
            .context("Failed to update episode")?;

            return Ok(AddEpisodeResult { inserted: 0, warning: None });
        }

        // Insert new episode with generated GUID
        sqlx::query(
            r#"
            INSERT INTO episodes (podcast_id, title, guid, pub_date, downloaded)
            VALUES (?, ?, ?, ?, 0)
            "#
        )
        .bind(podcast_id)
        .bind(title)
        .bind(&generated)
        .bind(pub_date_unix)
        .execute(&self.pool)
        .await
        .context("Failed to add episode")?;

        Ok(AddEpisodeResult { inserted: 1, warning: None })
    }

    /// Get all podcasts sorted by newest episode date
    ///
    /// Podcasts are sorted by the publication date of their newest episode (descending).
    /// Podcasts with no episodes or no publication dates appear last, sorted by name.
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn get_all_podcasts(&self) -> Result<Vec<Podcast>>
    {
        let rows = sqlx::query(
            r#"
            SELECT p.id, p.name, p.feed_url, p.last_download
            FROM podcasts p
            LEFT JOIN (
                SELECT podcast_id, MAX(pub_date) as newest_date
                FROM episodes
                WHERE pub_date IS NOT NULL
                GROUP BY podcast_id
            ) e ON p.id = e.podcast_id
            ORDER BY e.newest_date DESC NULLS LAST, p.name ASC
            "#
        )
        .fetch_all(&self.pool)
        .await
        .context("Failed to fetch podcasts")?;

        let podcasts = rows
            .into_iter()
            .map(|row| {
                let id: i64 = row.get(0);
                let name: String = row.get(1);
                let feed_url: String = row.get(2);
                let last_download_unix: Option<i64> = row.get(3);

                let last_download = last_download_unix.map(|ts| Timestamp::from_second(ts).unwrap());

                Podcast { id, name, feed_url, last_download }
            })
            .collect();

        Ok(podcasts)
    }

    /// Get a podcast by feed URL
    ///
    /// # Arguments
    ///
    /// * `feed_url` - The RSS feed URL
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails or podcast not found
    pub async fn get_podcast_by_url(&self, feed_url: &str) -> Result<Option<Podcast>>
    {
        let row = sqlx::query(
            r#"
            SELECT id, name, feed_url, last_download
            FROM podcasts
            WHERE feed_url = ?
            "#
        )
        .bind(feed_url)
        .fetch_optional(&self.pool)
        .await
        .context("Failed to fetch podcast")?;

        let podcast = row.map(|row| {
            let id: i64 = row.get(0);
            let name: String = row.get(1);
            let feed_url: String = row.get(2);
            let last_download_unix: Option<i64> = row.get(3);

            let last_download = last_download_unix.map(|ts| Timestamp::from_second(ts).unwrap());

            Podcast { id, name, feed_url, last_download }
        });

        Ok(podcast)
    }

    /// Get episode count for a podcast
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn get_episode_count(&self, podcast_id: i64) -> Result<i64>
    {
        let row = sqlx::query(
            r#"
            SELECT COUNT(*) as count
            FROM episodes
            WHERE podcast_id = ?
            "#
        )
        .bind(podcast_id)
        .fetch_one(&self.pool)
        .await
        .context("Failed to count episodes")?;

        let count: i64 = row.get(0);
        Ok(count)
    }

    /// Get all episodes for a podcast sorted by publication date (newest first)
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn get_episodes(&self, podcast_id: i64) -> Result<Vec<Episode>>
    {
        let rows = sqlx::query(
            r#"
            SELECT id, podcast_id, title, guid, pub_date, downloaded
            FROM episodes
            WHERE podcast_id = ?
            ORDER BY pub_date DESC NULLS LAST
            "#
        )
        .bind(podcast_id)
        .fetch_all(&self.pool)
        .await
        .context("Failed to fetch episodes")?;

        let episodes = rows
            .into_iter()
            .map(|row| {
                let id: i64 = row.get(0);
                let podcast_id: i64 = row.get(1);
                let title: String = row.get(2);
                let guid: String = row.get::<Option<String>, _>(3).unwrap_or_default();
                let pub_date_unix: Option<i64> = row.get(4);
                let downloaded: bool = row.get::<i32, _>(5) != 0;

                let pub_date = pub_date_unix.and_then(|ts| Timestamp::from_second(ts).ok());

                Episode { id, podcast_id, title, guid, pub_date, downloaded }
            })
            .collect();

        Ok(episodes)
    }

    /// Get the publication date of the newest episode for a podcast
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    ///
    /// # Returns
    ///
    /// Returns the newest episode's publication date, or None if no episodes have dates
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn get_newest_episode_date(&self, podcast_id: i64) -> Result<Option<Timestamp>>
    {
        let row = sqlx::query(
            r#"
            SELECT MAX(pub_date) as newest
            FROM episodes
            WHERE podcast_id = ? AND pub_date IS NOT NULL
            "#
        )
        .bind(podcast_id)
        .fetch_one(&self.pool)
        .await
        .context("Failed to get newest episode date")?;

        let newest_unix: Option<i64> = row.get(0);
        let newest = newest_unix.and_then(|ts| Timestamp::from_second(ts).ok());

        Ok(newest)
    }

    /// Get a podcast by ID
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn get_podcast_by_id(&self, podcast_id: i64) -> Result<Option<Podcast>>
    {
        let row = sqlx::query(
            r#"
            SELECT id, name, feed_url, last_download
            FROM podcasts
            WHERE id = ?
            "#
        )
        .bind(podcast_id)
        .fetch_optional(&self.pool)
        .await
        .context("Failed to fetch podcast")?;

        let podcast = row.map(|row| {
            let id: i64 = row.get(0);
            let name: String = row.get(1);
            let feed_url: String = row.get(2);
            let last_download_unix: Option<i64> = row.get(3);

            let last_download = last_download_unix.map(|ts| Timestamp::from_second(ts).unwrap());

            Podcast { id, name, feed_url, last_download }
        });

        Ok(podcast)
    }

    /// Delete a podcast and all its episodes
    ///
    /// Episodes are automatically deleted due to CASCADE foreign key constraint.
    ///
    /// # Arguments
    ///
    /// * `podcast_id` - The podcast ID to delete
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn delete_podcast(&self, podcast_id: i64) -> Result<()>
    {
        sqlx::query(
            r#"
            DELETE FROM podcasts
            WHERE id = ?
            "#
        )
        .bind(podcast_id)
        .execute(&self.pool)
        .await
        .context("Failed to delete podcast")?;

        Ok(())
    }

    /// Delete all podcasts and episodes from the database
    ///
    /// Removes all podcast subscriptions. Episodes are automatically deleted
    /// due to CASCADE foreign key constraint.
    ///
    /// # Returns
    ///
    /// Returns the number of podcasts deleted
    ///
    /// # Errors
    ///
    /// Returns an error if the database operation fails
    pub async fn delete_all_podcasts(&self) -> Result<u64>
    {
        let result = sqlx::query(
            r#"
            DELETE FROM podcasts
            "#
        )
        .execute(&self.pool)
        .await
        .context("Failed to delete all podcasts")?;

        Ok(result.rows_affected())
    }
}
