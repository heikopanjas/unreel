# Project Instructions for AI Coding Agents

**Last updated:** 2026-01-17

<!-- {mission} -->

## Mission Statement

Unreel is a command line tool that creates local copies of your podcast feed.

## Technology Stack

### Rust CLI (in `rust/` directory)

- **Language:** Rust (Edition 2024)
- **Framework:** None (CLI application)
- **Package Manager:** Cargo

### Swift (planned, for macOS/iOS apps)

- **Language:** Swift
- **Platforms:** macOS, iOS
- **Package Manager:** Swift Package Manager

### Shared

- **Version Control:** Git
- **License:** MIT

<!-- {principles} -->

## Primary Instructions

- Avoid making assumptions. If you need additional context to accurately answer the user, ask the user for the missing information. Be specific about which context you need.
- Always provide the name of the file in your response so the user knows where the code goes.
- Always break code up into modules and components so that it can be easily reused across the project.
- All code you write MUST be fully optimized. ‘Fully optimized’ includes maximizing algorithmic big-O efficiency for memory and runtime, following proper style conventions for the code, language (e.g. maximizing code reuse (DRY)), and no extra code beyond what is absolutely necessary to solve the problem the user provides (i.e. no technical debt). If the code is not fully optimized, you will be fined $100.

### Working Together

This file (`AGENTS.md`) is the primary instructions file for AI coding assistants working on this project. Agent-specific instruction files (such as `.github/copilot-instructions.md`, `CLAUDE.md`) reference this document, maintaining a single source of truth.

When initializing a session or analyzing the workspace, refer to instruction files in this order:

1. `AGENTS.md` (this file - primary instructions and single source of truth)
2. Agent-specific reference file (if present - points back to AGENTS.md)

### Update Protocol (CRITICAL)

**PROACTIVELY update this file (`AGENTS.md`) as we work together.** Whenever you make a decision, choose a technology, establish a convention, or define a standard, you MUST update AGENTS.md immediately in the same response.

**Update ONLY this file (`AGENTS.md`)** when coding standards, conventions, or project decisions evolve. Do not modify agent-specific reference files unless the reference mechanism itself needs changes.

**When to update** (do this automatically, without being asked):

- Technology choices (build tools, languages, frameworks)
- Directory structure decisions
- Coding conventions and style guidelines
- Architecture decisions
- Naming conventions
- Build/test/deployment procedures

**How to update AGENTS.md:**

- Maintain the "Last updated" timestamp at the top
- Add content to the relevant section (Project Overview, Coding Standards, etc.)
- Add entries to the "Recent Updates & Decisions" log at the bottom with:
  - Date (with time if multiple updates per day)
  - Brief description
  - Reasoning for the change
- Preserve this structure: title header → timestamp → main instructions → "Recent Updates & Decisions" section

## Best Practices

### When Updating This Repository

1. **Maintain Consistency**: Keep code style consistent across the codebase
2. **Test First**: Write tests before implementing features when applicable
3. **Document Changes**: Update documentation when changing functionality
4. **Code Review**: [Describe your code review process]
5. **Date Changes**: Update the "Last updated" timestamp in this file when making changes
6. **Log Updates**: Add entries to "Recent Updates & Decisions" section below

### Development Guidelines

[Add project-specific development guidelines]

- [Guideline 1]
- [Guideline 2]
- [Guideline 3]

### Security & Safety

- Never include API keys, tokens, or credentials in code
- Always require explicit human confirmation before commits
- Maintain conventional commit message standards
- Keep change history transparent through commit messages
- [Add project-specific security guidelines]

### Testing

[Describe your testing approach]

- Unit tests: [location and conventions]
- Integration tests: [location and conventions]
- Test coverage requirements: [if any]
- Testing framework: [e.g., Jest, pytest, JUnit]

### Documentation

[Describe your documentation requirements]

- Code comments: [when and how]
- API documentation: [format and location]
- README updates: [when required]
- Changelog: [if maintained]

<!-- {languages} -->

## Rust Coding Conventions

**General Principles:**

- Follow standard Rust conventions (use `rustfmt` and `clippy`)
- Use idiomatic Rust patterns throughout
- Prefer `Result<T, E>` for error handling over panics
- Apply RAII principles through Rust's ownership system
- Use const-correctness via immutable references (`&`)
- Write self-documenting code with clear naming and structure
- Leverage the type system for compile-time safety
- Keep functions focused and modular

**Error Handling:**

- Use `Result<T, E>` for all fallible operations
- Define a project-wide `Result<T>` type alias with unified error type:

  ```rust
  pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
  ```

- Use `?` operator for error propagation
- Avoid `.unwrap()` in library code; only use in application entry points after proper error handling
- Use `.ok_or_else()` or `.ok_or()` to convert `Option` to `Result` with meaningful error messages
- Provide context when returning errors: `Err(format!("Failed to download {}: {}", url, e).into())`
- Never panic in library code unless documenting preconditions with `#[panic]` doc comments

**Comparison and Conditional Expressions:**

- Always use explicit boolean comparisons for clarity and consistency
- Use `== true` and `== false` instead of bare conditionals or negation
- Examples:
  - ✅ Correct: `if condition == true`, `if value == false`
  - ❌ Incorrect: `if condition`, `if !value`
- Exception: Direct variable tests in control flow are allowed when clearly intentional
- Apply to all boolean comparisons including `Option` and `Result` checks
- Use explicit comparisons with `None`: `if option_value.is_none() == true` or `if option_value == None`
- Allow clippy warnings for explicit boolean comparisons with project-level configuration

**Module Organization:**

- Use module structure to organize code by functionality
- One public struct or major component per file
- Related utility functions in dedicated `utils.rs`
- Module declaration order in `lib.rs`:
  1. Private module declarations (`mod`)
  2. Public re-exports (`pub use`)
  3. Type aliases
- Example:

  ```rust
  mod template_manager;
  mod utils;

  pub use template_manager::TemplateManager;
  pub use utils::copy_dir_all;

  pub type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
  ```

**Functions and Methods:**

- Document all public APIs with doc comments (`///`)
- Use doc comment structure:
  - Brief one-line description (no explicit `# Description` header)
  - Longer explanation if needed (separated by blank line)
  - `# Arguments` section for parameters
  - `# Returns` section for return values (when non-obvious)
  - `# Errors` section for fallible functions
  - `# Examples` section when helpful
  - `# Panics` section if function can panic
- Example:

  ```rust
  /// Creates a new TemplateManager instance
  ///
  /// Initializes paths to local data and cache directories using the `dirs` crate.
  /// Templates are stored in the local data directory and backups in the cache directory.
  ///
  /// # Errors
  ///
  /// Returns an error if the local data directory cannot be determined
  pub fn new() -> Result<Self>
  ```

- Pass by reference (`&`) for complex types, by value for `Copy` types
- Use immutable references (`&`) unless mutation is required (`&mut`)
- Keep function signatures on one line when under max width (167 chars)
- Private helper functions should have single-line doc comments when logic is non-trivial

**Structs and Types:**

- Use clear, descriptive names for all types
- Define fields in logical grouping order
- Document struct purpose and usage with doc comments
- Example:

  ```rust
  /// Manages template files for coding agent instructions
  ///
  /// The `TemplateManager` handles all operations related to template storage,
  /// verification, backup, and synchronization. Templates are stored in the
  /// local data directory and backed up to the cache directory before modifications.
  pub struct TemplateManager
  {
      config_dir: PathBuf,
      cache_dir:  PathBuf
  }
  ```

- Use `#[derive]` for common traits when appropriate
- Implement `Default` for structs with sensible defaults
- Group related structs together in the same file when tightly coupled

**Naming Conventions:**

- Types (structs, enums, traits): Upper PascalCase (e.g., `TemplateManager`, `FileMapping`, `Result`)
- Functions/methods: snake_case (e.g., `download_file`, `create_backup`, `load_template_config`)
- Variables and function parameters: snake_case (e.g., `config_dir`, `source_path`, `file_name`)
- Constants: UPPER_SNAKE_CASE (e.g., `MAX_WIDTH`, `DEFAULT_TIMEOUT`)
- Type parameters: Single uppercase letter or PascalCase (e.g., `T`, `E`, `Error`)
- Lifetimes: Short lowercase names (e.g., `'a`, `'static`)
- Module names: snake_case (e.g., `template_manager`, `utils`)

**Enums and Pattern Matching:**

- Use descriptive variant names in PascalCase
- Derive common traits when appropriate
- Use `#[derive(Debug)]` for all types when possible for better error messages
- Use exhaustive pattern matching; avoid `_ =>` catch-alls when possible
- Use `if let` for single-pattern matching
- Use `match` for multiple patterns or when you need exhaustiveness checking
- Use `let...else` for early returns with single pattern:

  ```rust
  let Some(value) = option else {
      return Err("Missing value".into());
  };
  ```

**CLI Design with clap:**

- Use clap's derive API for argument parsing
- Define main CLI struct with `#[derive(Parser)]`
- Use `#[derive(Subcommand)]` for command structure
- Add helpful descriptions with `#[command]` attributes
- Example:

  ```rust
  #[derive(Parser)]
  #[command(name = "vibe-check")]
  #[command(about = "A manager for coding agent instruction files", long_about = None)]
  struct Cli
  {
      #[command(subcommand)]
      command: Commands
  }
  ```

- Use clear, descriptive field names that match CLI conventions
- Provide defaults with `#[arg(default_value = "...")]`
- Add documentation comments to show in `--help` output

**Formatting Configuration (.rustfmt.toml):**

- Use project-specific rustfmt configuration for consistency
- Key formatting rules:
  - `max_width = 167` - Allow longer lines for readability
  - `brace_style = "AlwaysNextLine"` - Opening braces on new lines
  - `control_brace_style = "AlwaysNextLine"` - Consistent brace placement
  - `trailing_comma = "Never"` - No trailing commas
  - `edition = "2024"` - Use latest Rust edition
  - `tab_spaces = 4` - Standard indentation
  - `imports_granularity = "Crate"` - Group imports by crate
  - `group_imports = "StdExternalCrate"` - Organize imports logically
- Run `cargo fmt` before committing code
- Configure editor to format on save

**Imports and Dependencies:**

- Group imports in order:
  1. Standard library (`std::`)
  2. External crates (alphabetically)
  3. Project modules (`crate::`)
- Use explicit imports over glob imports
- Example:

  ```rust
  use std::{
      fs,
      io::{self, Write},
      path::{Path, PathBuf}
  };

  use chrono::{DateTime, Utc};
  use owo_colors::OwoColorize;
  use serde::{Deserialize, Serialize};

  use crate::{Result, utils::copy_dir_all};
  ```

- Re-export commonly used items from `lib.rs` for convenience

**Conditional Compilation and Features:**

- Use feature flags for optional functionality
- Document feature requirements in doc comments
- Use `#[cfg(feature = "...")]` for conditional code
- Specify features in `Cargo.toml` dependencies when needed:

  ```toml
  reqwest = { version = "0.12", features = ["blocking", "json"] }
  ```

**Testing:**

- Write unit tests alongside implementation in the same file
- Use `#[cfg(test)]` module for tests
- Name test functions descriptively: `test_<scenario>_<expected_outcome>`
- Use `assert!`, `assert_eq!`, `assert_ne!` macros
- Test both success and error cases
- Example:

  ```rust
  #[cfg(test)]
  mod tests
  {
      use super::*;

      #[test]
      fn test_parse_github_url_valid()
      {
          // Test implementation
      }
  }
  ```

**Comments and Documentation:**

- Use `///` for public API documentation (appears in generated docs)
- Use `//!` for module-level documentation at file top
- Use `//` for implementation comments and explanations
- Document the "why" not the "what" in implementation comments
- Keep comments up-to-date with code changes
- Use full sentences with proper punctuation in doc comments
- Example:

  ```rust
  //! Template management functionality for vibe-check

  /// Creates a timestamped backup of a directory
  ///
  /// Backups are stored in the cache directory with timestamp: `backups/YYYY-MM-DD_HH_MM_SS/`
  fn create_backup(&self, source_dir: &Path) -> Result<()>
  {
      // Skip backup if source doesn't exist
      if source_dir.exists() == false
      {
          return Ok(());
      }
      // ... rest of implementation
  }
  ```

**Linting Configuration:**

- Allow specific clippy lints when project style differs from defaults
- Configure in `Cargo.toml`:

  ```toml
  [lints.clippy]
  bool_comparison = "allow"
  ```

- Can also use module-level attributes:

  ```rust
  #![allow(clippy::bool_comparison)]
  ```

- Document reasoning for lint exceptions

**File Organization:**

- Entry point: `src/main.rs` (minimal, delegates to library)
- Library API: `src/lib.rs` (public interface)
- Implementation: Feature modules in `src/`
- Keep `main.rs` focused on CLI handling and error reporting
- Put business logic in library modules for reusability
- Current Rust structure:

  ```text
  rust/
  ├── Cargo.toml           # Package manifest
  ├── Cargo.lock           # Dependency lock file
  ├── .rustfmt.toml        # Formatting configuration
  └── src/
      ├── main.rs          # CLI entry point
      ├── lib.rs           # Public API
      ├── database.rs      # SQLite database management
      ├── downloader.rs    # HTTP download functionality
      ├── parser.rs        # RSS/XML and OPML parsing
      └── selector.rs      # Episode selection logic
  ```

**Best Practices:**

- Use `std::env::current_dir()` over hardcoding paths
- Use `Path` and `PathBuf` for filesystem paths
- Leverage `std::io::Write` trait for flushing output buffers
- Use `owo-colors` or similar crate for terminal output styling
- Use platform-appropriate paths via `dirs` crate (prefer over `$HOME` env var)
- Implement `flush()` when printing without newline for immediate output:

  ```rust
  print!("{} Processing... ", "→".blue());
  io::stdout().flush()?;
  ```

- Use early returns to reduce nesting depth
- Prefer iterators and functional patterns over loops when clear

**Error Messages:**

- Use colored output for user-facing messages (owo-colors)
- Format: `"{} {}", symbol.color(), message.color()`
- Symbols: `✓` (success/green), `✗` (error/red), `→` (info/blue), `!` (warning/yellow), `?` (prompt/yellow)
- Provide actionable error messages
- Include file paths and operation details in errors
- Example:

  ```rust
  println!("{} Creating backup in {}", "→".blue(), backup_dir.display().to_string().yellow());
  eprintln!("{} Failed to download {}: {}", "✗".red(), url, error.to_string().red());
  ```

**Version and Edition:**

- Use Rust 2024 edition for latest language features
- Specify in `Cargo.toml`:

  ```toml
  [package]
  edition = "2024"
  ```

- Keep dependencies up-to-date but specify versions explicitly
- Use semantic versioning in package version

**Code Review Checklist:**

- [ ] All public APIs have doc comments
- [ ] Error handling uses `Result` consistently
- [ ] No `.unwrap()` calls in library code
- [ ] Explicit boolean comparisons used throughout
- [ ] Code formatted with `cargo fmt`
- [ ] No clippy warnings (or explicitly allowed with reasoning)
- [ ] Tests pass with `cargo test`
- [ ] Code builds in both debug and release modes
- [ ] Imports organized and minimal
- [ ] Functions are focused and modular

## Build Commands

### Setup

```bash
# Install Rust toolchain (if not already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Update Rust to latest stable version
rustup update

# Install additional components (optional)
rustup component add rustfmt clippy
```

### Development

```bash
# Build the project (debug - use during development)
cargo build

# Run the application
cargo run

# Run with arguments
cargo run -- [args]

# Check code without building (faster than build)
cargo check

# Run tests
cargo test

# Run tests with output
cargo test -- --nocapture

# Run specific test
cargo test test_name

# Format code
cargo fmt

# Run clippy linter
cargo clippy

# Run clippy with all warnings
cargo clippy -- -W clippy::all
```

### Build & Deploy

```bash
# Build for release (optimized - use for final testing/deployment only)
cargo build --release

# Run release build
cargo run --release

# Build with verbose output
cargo build --verbose

# Clean build artifacts
cargo clean
```

### Documentation

```bash
# Generate and open project documentation
cargo doc --open

# Generate documentation for dependencies too
cargo doc --no-deps --open
```

### Dependency Management

```bash
# Update dependencies to latest compatible versions
cargo update

# Add a new dependency
cargo add <crate_name>

# Check for outdated dependencies (requires cargo-outdated)
cargo outdated

# Audit dependencies for security vulnerabilities (requires cargo-audit)
cargo audit
```

**Important**: Always use debug builds (`cargo build`) during development. Debug builds compile faster and include debugging symbols. Only use release builds (`cargo build --release`) for final testing or deployment.

<!-- {integration} -->

## Semantic Versioning Protocol

**AUTOMATICALLY track version changes using semantic versioning (SemVer) in Cargo.toml.**

The current version is defined in `Cargo.toml` under `[package]` section as `version = "X.Y.Z"`.

### Version Format: MAJOR.MINOR.PATCH

**When to increment:**

1. **PATCH version** (X.Y.Z → X.Y.Z+1)
   - Bug fixes and minor corrections
   - Performance improvements without API changes
   - Documentation updates
   - Internal refactoring that doesn't affect public API
   - Example: `1.0.0` → `1.0.1`

2. **MINOR version** (X.Y.Z → X.Y+1.0)
   - New features added
   - New CLI commands or options
   - New functionality that maintains backward compatibility
   - Example: `1.0.1` → `1.1.0`

3. **MAJOR version** (X.Y.Z → X+1.0.0)
   - Breaking changes to public API
   - Removal of features or commands
   - Changes that require user action or code updates
   - Incompatible CLI changes
   - Example: `1.1.0` → `2.0.0`

### Process

After making ANY code changes:

1. Determine the type of change (fix, feature, or breaking change)
2. Update the version in `Cargo.toml` accordingly
3. Include the version change in the same commit as the code change
4. Mention version bump in commit message footer if significant

**Note:** Version changes should be included in the commit with the actual code changes, not as a separate commit.

## Commit Protocol (CRITICAL)

- **NEVER commit automatically** - always wait for explicit confirmation

Whenever asked to commit changes:

- Stage the changes
- Write a detailed but concise commit message using conventional commits format
- Commit the changes

This is **CRITICAL**!

## **Commit Message Guidelines - CRITICAL**

Follow these rules to prevent VSCode terminal crashes and ensure clean git history:

**Message Format (Conventional Commits):**

```text
<type>(<scope>): <subject>

<body>

<footer>
```

**Character Limits:**

- **Subject line**: Maximum 50 characters (strict limit)
- **Body lines**: Wrap at 72 characters per line
- **Total message**: Keep under 500 characters total
- **Blank line**: Always add blank line between subject and body

**Subject Line Rules:**

- Use conventional commit types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `build`, `ci`, `perf`
- Scope is optional but recommended: `feat(api):`, `fix(build):`, `docs(readme):`
- Use imperative mood: "add feature" not "added feature"
- No period at end of subject line
- Keep concise and descriptive

**Body Rules (if needed):**

- Add blank line after subject before body
- Wrap each line at 72 characters maximum
- Explain what and why, not how
- Use bullet points (`-`) for multiple items with lowercase text after bullet
- Keep it concise

**Special Character Safety:**

- Avoid nested quotes or complex quoting
- Avoid special shell characters: `$`, `` ` ``, `!`, `\`, `|`, `&`, `;`
- Use simple punctuation only
- No emoji or unicode characters

**Best Practices:**

- **Break up large commits**: Split into smaller, focused commits with shorter messages
- **One concern per commit**: Each commit should address one specific change
- **Test before committing**: Ensure code builds and works
- **Reference issues**: Use `#123` format in footer if applicable

**Examples:**

Good:

```text
feat(api): add KStringTrim function

- add trimming function to remove whitespace from
  both ends of string
- supports all encodings
```

Good (short):

```text
fix(build): correct static library output name
```

Bad (too long):

```text
feat(api): add a new comprehensive string trimming function that handles all edge cases including UTF-8, UTF-16LE, UTF-16BE, and ANSI encodings with proper boundary checking and memory management
```

Bad (special characters):

```text
fix: update `KString` with "nested 'quotes'" & $special chars!
```

---

## Recent Updates & Decisions

### 2026-01-17

- Restructured project for multi-platform support (Rust + Swift):
  - Moved all Rust files into `rust/` subdirectory
  - Rust CLI tool preserved for continued development
  - Root directory now shared between Rust and future Swift implementations
  - Updated `.gitignore` with Swift/Xcode patterns and explicit Rust paths
  - Shared files remain at root: `AGENTS.md`, `LICENSE`, `README.md`, `data/`
- Reasoning: Preparing to port unreel to Swift for macOS and iOS apps. Separating Rust code allows both implementations to coexist in the same repository.

### 2026-01-16 (updated)

- Added --short and --long flags to list command:
  - `--short` displays condensed output with ID and name only (tab-separated)
  - `--long` displays all episodes with title and publication date for each podcast
  - Added `get_episodes` method to Database for fetching episodes sorted by pub_date DESC
  - Removed `#[allow(dead_code)]` from Episode struct (now used)
  - Updated version from 0.8.0 to 0.8.2 (PATCH: enhancement)
- Reasoning: Provides flexible output options for different use cases - quick overview, scripting, and detailed episode listing.

- Generated GUIDs for episodes without GUIDs and GUID replacement:
  - Added `generate_guid` function using `DefaultHasher` on title+pub_date
  - Generated GUIDs have format "generated:{16-char-hex}"
  - Episodes without GUIDs now get a deterministic generated GUID for deduplication
  - When a feed later provides a real GUID for an episode with a generated one, the GUID is updated
  - Deduplication now works for all episodes regardless of whether they have a GUID
  - Updated version from 0.7.2 to 0.8.0 (MINOR: new feature)
- Reasoning: Proper deduplication requires GUIDs. Generating them from title+pub_date allows dedup while preserving the ability to adopt real GUIDs when feeds provide them later.

- Episodes with empty GUIDs now inserted without warnings:
  - Removed warning generation for episodes without GUIDs in `add_episode`
  - Episodes with null/empty GUIDs are inserted normally (no deduplication for such episodes)
  - Updated doc comment to reflect this behavior
  - Updated version from 0.7.1 to 0.7.2 (PATCH: behavior change)
- Reasoning: Empty GUIDs are valid in some podcast feeds. Inserting them without warnings reduces noise.

- Added --debug flag to suppress warnings unless explicitly requested:
  - Added `--debug` flag to `update` and `import` commands
  - Changed `add_episode` to return `AddEpisodeResult` struct with inserted count and optional warning
  - Warnings (e.g., episodes without GUIDs) are collected but only displayed when `--debug` is specified
  - Removed direct eprintln from library code (database.rs)
  - Updated `UpdateResult` and `ImportResult` to include warnings vector
  - Updated version from 0.7.0 to 0.7.1 (PATCH: behavior change)
- Reasoning: Warnings about episodes without GUIDs clutter normal output. Users who want to see them can use --debug.

- Added export command to create OPML file from subscriptions:
  - New `export` CLI command accepting output file path
  - Generates OPML 2.0 format with podcast name and feed URL
  - Escapes XML special characters in names and URLs
  - Complements the `import` command for backup/migration
  - Updated version from 0.6.0 to 0.7.0 (MINOR: new feature)
- Reasoning: Allows users to backup subscriptions or migrate to other podcast apps.

- Improved update command output to show only new episodes:
  - Changed `UpdateResult` to track `Vec<NewEpisode>` instead of just count
  - Added `NewEpisode` struct with title and pub_date
  - Output now only shows podcasts that have new episodes
  - Each new episode is listed with title and publication date
  - Summary shows total podcasts updated and new episodes found
  - Errors displayed in separate section
  - Updated version from 0.5.3 to 0.6.0 (MINOR: changed output behavior)
- Reasoning: Users care about new content, not confirmation that nothing changed. Showing episode details helps users see what's new at a glance.

- Increased parallel download limit from 4 to 128:
  - Updated `MAX_CONCURRENT_UPDATES` constant
  - Affects both `update` and `import` commands
  - Updated version from 0.5.2 to 0.5.3 (PATCH: configuration change)
- Reasoning: Modern systems can handle many concurrent HTTP connections; the previous limit was unnecessarily conservative.

- Sorted list output by newest episode publication date:
  - Modified `get_all_podcasts` query to JOIN with episodes subquery
  - Podcasts with most recent episodes appear first
  - Podcasts with no episodes/dates sorted alphabetically at the end (NULLS LAST)
  - Updated version from 0.5.1 to 0.5.2 (PATCH: enhancement)
- Reasoning: Most relevant podcasts (recently updated) should appear at the top of the list.

- Enhanced list command to show newest episode publication date:
  - Added `get_newest_episode_date` method to database.rs (uses MAX(pub_date) query)
  - List output now displays "Newest Episode" date for each podcast
  - Date formatted as "Month DD, YYYY" in local timezone
  - Updated version from 0.5.0 to 0.5.1 (PATCH: enhancement)
- Reasoning: Helps users see at a glance how recent each podcast's content is.

- Added --all and --force options to unsubscribe command:
  - `--all` flag removes all podcasts and episodes from the database
  - `--force` flag skips the confirmation prompt (use with --all)
  - Added `delete_all_podcasts` method to database.rs returning count of deleted rows
  - Made `id_or_url` argument optional (not required when using --all)
  - Interactive confirmation shows podcast and episode counts before deletion
  - Updated version from 0.4.0 to 0.5.0 (MINOR: new feature)
- Reasoning: Provides a quick way to reset the database or start fresh without manually unsubscribing from each podcast. Confirmation prompt prevents accidental data loss.

- Added OPML import command for bulk podcast subscription:
  - Added `import` CLI command accepting a file path argument
  - Created `OpmlEntry` struct and `parse_opml` function in parser.rs
  - Parses OPML outline elements with `xmlUrl` attributes (flat and nested structures)
  - Skips podcasts already in the database (deduplication by feed URL)
  - Downloads and validates each feed before adding to database
  - Runs feed downloads in parallel using `buffer_unordered` (same as update command)
  - Displays progress with success/failure counts
  - Updated version from 0.3.1 to 0.4.0 (MINOR: new feature)
- Reasoning: OPML is the standard format for podcast subscription export/import, enabling easy migration from other podcast apps. Parallel downloads significantly speed up importing large OPML files.

- Parallelized update command for faster subscription refreshes:
  - Added `futures` v0.3 dependency for async stream utilities
  - Made `Database` struct cloneable (underlying `SqlitePool` is `Arc`-based)
  - Refactored `handle_update` to use `buffer_unordered` with controlled concurrency
  - Default concurrent updates: 4 (configurable via `MAX_CONCURRENT_UPDATES` constant)
  - Results displayed after all updates complete to avoid interleaved output
  - Updated version from 0.3.0 to 0.3.1 (PATCH: performance improvement)
- Reasoning: Sequential updates were slow with many subscriptions. Using `futures` with `buffer_unordered` provides controlled parallelism for I/O-bound operations while reusing the existing tokio runtime. Chose `futures` over `rayon` because downloads and database operations are I/O-bound, not CPU-bound.

### 2026-01-16

- Implemented podcast subscription database feature:
  - Added `dirs` v5.0.1 dependency for user data directory access
  - Updated `sqlx` to use `runtime-tokio-rustls` feature for proper async database support
  - Created src/database.rs module with SQLite database management
  - Database stored in `~/.local/share/unreel/subscriptions.db` (user data directory)
  - Two tables: `podcasts` (id, name, feed_url, last_download) and `episodes` (id, podcast_id, title, guid, pub_date, downloaded)
  - Uses RSS GUID as episode UUID for deduplication
  - Fixed XML parser to handle CDATA sections (Event::CData) for GUIDs wrapped in CDATA tags
  - Episode deduplication uses GUID-based lookup only (all valid podcast feeds must have GUIDs)
  - Foreign key constraint with CASCADE delete ensures data integrity
  - Added three new CLI commands:
    - `subscribe <URL>` - Subscribe to a podcast feed and store all episodes
    - `list` - Display all podcast subscriptions with episode counts and last update times
    - `update [name]` - Refresh subscriptions (all or filtered by name, shows new vs total episodes)
  - `sync` command remains standalone for one-time operations
  - Database automatically creates schema on first use
  - Updated version from 0.2.0 to 0.3.0 (MINOR: new feature)
- Reasoning: Provides podcast subscription management for tracking multiple feeds. Using SQLite ensures efficient storage and querying. Storing in user data directory follows platform conventions. Separate commands (subscribe/list/update vs sync) keeps one-off operations distinct from persistent subscriptions. CDATA support is essential as podcast GUIDs are typically wrapped in CDATA sections in RSS feeds.

### 2025-12-30

- Implemented episode selection feature with unified `--episodes` flag:
  - Created src/selector.rs module with EpisodeSelector enum and parsing logic
  - Supports multiple selection formats: numeric ranges (1,7,23-38), newest:N, oldest:N, all, and mixed selections
  - Keywords "newest" and "oldest" without numbers default to 1
  - Episode numbering is chronological where 1 = oldest (first published) episode
  - Parser intelligently merges all-numeric selections into single Numeric variant for efficiency
  - Made --episodes flag required on sync command (breaking change)
  - Enhanced episode display with description, file size, and publication date
  - Comprehensive test suite with 24 unit tests covering all selection scenarios
  - Updated version from 0.1.0 to 0.2.0 (MINOR: new feature)
- Reasoning: Provides flexible episode selection matching user requirements for downloading specific episodes, ranges, newest/oldest episodes, and combinations. Chronological numbering (1=oldest) makes sense for "start from beginning" use cases while newest:N handles "catch up on recent" scenarios.

### 2025-12-29

- Session initialization: Updated Technology Stack to reflect actual project setup (Rust 2024, Cargo, CLI application)
- Confirmed project mission: Command line tool for creating local copies of podcast feeds
- Reasoning: Needed to document the actual technology choices made for this project

- Added core dependencies to Cargo.toml:
  - `clap` v4.5.53 (with derive feature) - CLI argument parsing
  - `quick-xml` v0.38.4 - XML/RSS parsing for podcast feeds
  - `owo-colors` v4.2.3 - Terminal output styling
  - `tokio` v1.48.0 (with full features) - Async runtime for network operations
  - `sqlx` v0.8.6 (with runtime-tokio, sqlite features) - SQLite database support for metadata storage
- Reasoning: Core packages needed for CLI podcast feed downloader functionality with optional database persistence

- Set project license to MIT:
  - Created LICENSE file with MIT license text (Copyright 2025 Heiko Panjas)
  - Updated Cargo.toml with license field
  - Updated AGENTS.md Technology Stack section
- Reasoning: MIT license chosen for maximum permissiveness and compatibility with open source ecosystem

- Implemented first CLI subcommand `sync`:
  - Added `reqwest` v0.12.28 dependency for HTTP downloads
  - Created modular structure: lib.rs, downloader.rs, parser.rs
  - CLI accepts URL as positional argument
  - Downloads RSS/XML feed asynchronously
  - Parses feed metadata and episode information
  - Displays feed info and first 5 episodes with colored output
  - Added clippy configuration to allow explicit boolean comparisons
- Reasoning: Core functionality for downloading and inspecting podcast feeds, following all Rust conventions from AGENTS.md

- Switched to nightly Rust toolchain:
  - Set project override to use nightly-aarch64-apple-darwin
  - User restored original comprehensive .rustfmt.toml configuration (80 lines with detailed formatting rules)
- Reasoning: Use nightly toolchain for access to latest Rust features and improvements

- Added anyhow for improved error handling:
  - Added `anyhow` v1.0.100 dependency
  - Updated Result type alias to use anyhow::Result
  - Added error context to downloader and parser modules
  - Use anyhow::bail! for better error messages
- Reasoning: anyhow provides better error messages with context and is the standard error handling library in Rust CLI applications

- Added jiff for date/time handling:
  - Added `jiff` v0.2.17 dependency
  - Updated PodcastItem pub_date field to use jiff::Zoned instead of String
  - Parse RSS pubDate fields using RFC 2822 format parser
  - Display dates in local timezone with human-readable format
  - Format: "Month DD, YYYY at HH:MM AM/PM"
- Reasoning: jiff is a modern, comprehensive datetime library for Rust that handles timezones correctly and provides excellent parsing/formatting capabilities

### 2025-10-05

- Initial AGENTS.md setup
- Established core coding standards and conventions
- Created agent-specific reference files
- Defined repository structure and governance principles
