# Unreel

> A Rust CLI tool for creating local copies of podcast feeds

Unreel is a command-line tool that downloads and parses podcast RSS feeds, making it easy to archive and inspect your favorite podcasts locally.

## Features

- 📥 **Download RSS feeds** - Fetch podcast feeds from any URL
- 🔍 **Parse podcast metadata** - Extract feed information and episode details
- 🕐 **Smart date handling** - Parses RFC 2822 dates and converts to local timezone
- 🎨 **Beautiful output** - Color-coded terminal display with progress indicators
- ⚡ **Fast & async** - Built with Tokio for efficient concurrent operations
- 🦀 **Written in Rust** - Safe, fast, and reliable

## Installation

### From Source

```bash
git clone git@github.com:heikopanjas/unreel.git
cd unreel
cargo build --release
```

The binary will be available at `target/release/unreel`.

## Usage

### Sync a Podcast Feed

Download and display information about a podcast feed:

```bash
unreel sync "https://feeds.megaphone.fm/vergecast"
```

This will:
- Download the RSS feed from the specified URL
- Parse the feed metadata (title, description, link)
- Display episode information including:
  - Episode titles
  - Publication dates (in your local timezone)
  - Audio file URLs
- Show a preview of the 5 most recent episodes

### Example Output

```
→ Downloading feed from https://feeds.megaphone.fm/vergecast ... ✓
→ Parsing feed ... ✓

Feed Information:
  Title: The Vergecast
  Description: The Vergecast is the flagship podcast from The Verge...
  Link: https://www.theverge.com/the-vergecast

✓ 955 episodes found

Recent Episodes:

  1. Version History: iPhone 4
     Published: December 28, 2025 at 11:00 AM

  2. The Vergecast RAM Holiday Spec-Tacular
     Published: December 23, 2025 at 11:00 AM

  ...
```

## Technology Stack

- **[Rust](https://www.rust-lang.org/)** (Edition 2024) - Systems programming language
- **[Tokio](https://tokio.rs/)** - Async runtime
- **[Clap](https://github.com/clap-rs/clap)** - Command-line argument parsing
- **[reqwest](https://github.com/seanmonstar/reqwest)** - HTTP client
- **[quick-xml](https://github.com/tafia/quick-xml)** - XML/RSS parser
- **[jiff](https://github.com/BurntSushi/jiff)** - Date and time library
- **[anyhow](https://github.com/dtolnay/anyhow)** - Error handling
- **[owo-colors](https://github.com/jam1garner/owo-colors)** - Terminal colors

## Development

### Requirements

- Rust (nightly toolchain)
- Cargo

### Building

```bash
cargo build
```

### Running Tests

```bash
cargo test
```

### Code Quality

```bash
# Format code
cargo fmt

# Run linter
cargo clippy
```

## Project Structure

```
unreel/
├── src/
│   ├── main.rs          # CLI entry point
│   ├── lib.rs           # Public API
│   ├── downloader.rs    # Feed downloading
│   └── parser.rs        # RSS/XML parsing
├── Cargo.toml           # Dependencies
├── LICENSE              # MIT License
└── README.md            # This file
```

## Roadmap

- [ ] Download episode audio files
- [ ] SQLite database for episode tracking
- [ ] Resume interrupted downloads
- [ ] Filter episodes by date range
- [ ] Export feed data to JSON
- [ ] Support for multiple feed formats

## License

MIT License - see [LICENSE](LICENSE) for details

Copyright © 2025 Heiko Panjas

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Author

**Heiko Panjas**
- GitHub: [@heikopanjas](https://github.com/heikopanjas)
