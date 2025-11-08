# Smellslike

A Zig-based RSS/Atom/JSON feed aggregator that posts feed items to Discord channels via webhooks.

## Features

- **Multi-format feed parsing**: Supports RSS, Atom, and JSON feeds using the [updog](https://github.com/bradcypert/updog) library
- **Channel-based organization**: Each Discord channel has its own feed list
- **Automatic feed detection**: Processes all `.txt` files in `src/channels/`
- **HTTP/HTTPS support**: Fetches feeds over HTTP(S)
- **Discord webhook integration**: Posts formatted feed items to Discord
- **Duplicate detection**: Tracks posted items to avoid flooding Discord with duplicates
- **Time-based filtering**: Only posts items published since the last run (or within the last week for first run)
- **Automatic state cleanup**: Removes entries older than 30 days to prevent unbounded growth
- **Dry-run mode**: Test without posting to Discord, perfect for building initial state
- **GitHub Actions support**: Runs automatically on a schedule with state persistence

## Project Structure

```
src/
├── main.zig           # Main application logic
├── root.zig          # Library exports (if needed)
└── channels/         # Feed configuration files
    ├── bradcypert-blog.txt
    ├── bradcypert-videos.txt
    ├── go-news.txt
    └── zig-news.txt
```

## Setup

### Prerequisites

- Zig 0.15.1 or later
- Discord webhook URLs for each channel

### Environment Variables

Set the following environment variables with your Discord webhook URLs:

```bash
export DISCORD_BLOG_WEBHOOK="https://discord.com/api/webhooks/..."
export DISCORD_GO_NEWS_WEBHOOK="https://discord.com/api/webhooks/..."
export DISCORD_ZIG_NEWS_WEBHOOK="https://discord.com/api/webhooks/..."
export DISCORD_YT_WEBHOOK="https://discord.com/api/webhooks/..."
```

### Building

```bash
zig build
```

### Running

**Dry Run Mode (Testing):**
```bash
export DRY_RUN=true
zig build run
```

**Real Mode (Posts to Discord):**
```bash
zig build run
```

Or run the compiled binary directly:

```bash
./zig-out/bin/smellslike
```

See [TESTING.md](TESTING.md) for comprehensive testing guide.

## How It Works

1. **State Loading**: Loads `state.json` to check previously posted items and last run timestamp
2. **Channel Discovery**: Scans `src/channels/` for `.txt` files
3. **Feed Loading**: Reads feed URLs from each channel file (one URL per line)
4. **Feed Fetching**: Downloads feed content via HTTP(S)
5. **Feed Parsing**: Uses updog to parse RSS/Atom/JSON feeds
6. **Duplicate Detection**: Checks if item was already posted or is too old
7. **Discord Posting**: Posts new feed items to the appropriate Discord channel
8. **State Saving**: Updates `state.json` with newly posted items and current timestamp

### Channel Files

Each `.txt` file in `src/channels/` contains feed URLs (one per line):

```
https://www.bradcypert.com/index.xml
```

The filename determines which webhook is used:
- `bradcypert-blog.txt` → `DISCORD_BLOG_WEBHOOK`
- `bradcypert-videos.txt` → `DISCORD_YT_WEBHOOK`
- `go-news.txt` → `DISCORD_GO_NEWS_WEBHOOK`
- `zig-news.txt` → `DISCORD_ZIG_NEWS_WEBHOOK`

### Discord Message Format

Each feed item is posted with:
- **Title** (bolded)
- **URL** (if available)
- **Summary** (truncated to 500 characters if available)

## Duplicate Detection

The application uses a combination of strategies to prevent posting duplicate items:

### State Persistence
- Stores posted item IDs in `state.json` (committed to repository)
- Tracks last run timestamp for time-based filtering
- Survives across GitHub Actions runs

### Item Identification
Uses the following priority for unique item IDs:
1. Feed item `id` field (GUID)
2. Feed item `url` field
3. Feed item `title` as fallback

### Time-Based Filtering
- **First run**: Posts items from the last 7 days
- **Subsequent runs**: Posts items published since the last run
- Prevents posting very old items when adding new feeds

### State File Format
```json
{
  "last_run_timestamp": 1730832000,
  "posted_items": [
    {
      "id": "https://example.com/post-1",
      "posted_at": 1730831000
    },
    {
      "id": "guid:1234-5678-90ab",
      "posted_at": 1730832000
    }
  ]
}
```

### Automatic Cleanup
- Items older than 30 days are automatically removed from state
- Prevents unbounded growth of `state.json`
- Cleanup happens on load, old entries are simply not loaded
- Retention period is configurable via `State.RETENTION_DAYS`

## GitHub Actions Setup

### Secrets Configuration
Add the following secrets to your GitHub repository (Settings → Secrets and variables → Actions):

- `DISCORD_BLOG_WEBHOOK`
- `DISCORD_GO_NEWS_WEBHOOK`
- `DISCORD_ZIG_NEWS_WEBHOOK`
- `DISCORD_YT_WEBHOOK`

### Workflow Schedule
The workflow runs automatically every 6 hours. You can also trigger it manually:
1. Go to Actions tab
2. Select "Process Feeds" workflow
3. Click "Run workflow"

### State Persistence
The `state.json` file is automatically committed back to the repository after each run with the message "Update feed state [skip ci]".

## Implementation Details

### Key Functions

- `processAllChannels()`: Discovers and processes all channel files
- `processChannel()`: Processes a single channel's feeds
- `processFeed()`: Fetches, parses, posts feed with duplicate checking
- `fetchUrl()`: HTTP(S) client for downloading feeds
- `postToDiscord()`: Posts formatted content to Discord webhooks
- `getWebhookForChannel()`: Maps channel filenames to webhook URLs
- `State.load()`: Loads state from JSON file
- `State.save()`: Saves state to JSON file
- `State.isPosted()`: Checks if item was already posted
- `State.shouldPost()`: Determines if item is recent enough to post

### Dependencies

- **updog**: Feed parsing library (RSS/Atom/JSON)
  - Repository: https://github.com/bradcypert/updog

## Future Enhancements

Potential improvements for future development:

- [x] State tracking to avoid posting duplicate items
- [x] Time-based filtering for new items
- [x] File-based persistence for posted items
- [x] State cleanup (remove entries older than 30 days)
- [ ] Configurable post frequency per feed
- [ ] Error retry logic with exponential backoff
- [ ] Support for feed-specific webhook overrides
- [ ] JSON configuration file for channels/webhooks
- [ ] Rate limiting for Discord API
- [ ] Item filtering based on keywords/dates
- [ ] Better date parsing (handle more formats beyond RFC3339)

