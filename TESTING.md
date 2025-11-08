# Testing Guide

## Dry Run Mode

The application includes a dry-run mode that lets you test everything without posting to Discord.

### What Dry Run Does

✅ **Does:**
- Fetches all feeds from the internet
- Parses RSS/Atom/JSON feeds
- Checks for duplicates
- Applies time-based filtering
- Updates `state.json` with item IDs
- Shows what would be posted
- Validates your setup

❌ **Does NOT:**
- Post to Discord webhooks
- Require Discord webhook environment variables

### How to Use

```bash
# Build the application
zig build

# Run in dry-run mode
export DRY_RUN=true
./zig-out/bin/smellslike
```

### Example Output

```
🧪 DRY RUN MODE - No Discord posts will be made
   (Set DRY_RUN=false or unset to post for real)

Starting feed processor...
Last run: 0
Tracked items: 0

Processing channel: bradcypert-blog.txt
  Fetching: https://www.bradcypert.com/index.xml
  Feed: Brad Cypert's Blog (15 items)
  [DRY RUN] Would post: Understanding Zig's Comptime
  [DRY RUN] Would post: Building CLI Tools in Go
  Skipping old item: My First Blog Post from 2020
  
Processing channel: zig-news.txt
  Fetching: https://ziglang.org/news/index.xml
  Feed: Zig News (8 items)
  [DRY RUN] Would post: Zig 0.15.1 Released
  Skipping duplicate: Zig 0.15.0 Released

✅ Dry run complete! 12 items would be posted
   State file updated. Run without DRY_RUN to post for real.
```

## Common Testing Workflows

### 1. Initial Setup & State Building

```bash
# Start fresh
rm state.json

# Run dry mode to build initial state
export DRY_RUN=true
./zig-out/bin/smellslike

# Check what was tracked
cat state.json | jq '.posted_items | length'
```

**Why:** Builds your state file with recent items so you don't flood Discord on first real run.

### 2. Testing New Feeds

```bash
# Add new feed to channel file
echo "https://new-blog.com/feed.xml" >> src/channels/zig-news.txt

# Test it in dry-run mode
export DRY_RUN=true
./zig-out/bin/smellslike
```

**Why:** Verify the feed works and see what items it would post before going live.

### 3. Verify Duplicate Detection

```bash
# Run dry mode twice
export DRY_RUN=true
./zig-out/bin/smellslike
./zig-out/bin/smellslike  # Should skip all items as duplicates
```

**Why:** Confirms duplicate detection is working correctly.

### 4. Test State Cleanup

```bash
# Edit state.json to add old timestamps
# Then run to see cleanup in action
export DRY_RUN=true
./zig-out/bin/smellslike
```

**Why:** Verify old entries are being removed properly.

### 5. Test Feed Parsing

```bash
# Test individual feed parsing without full processing
curl -s "https://example.com/feed.xml" | head -50
```

**Why:** Debug feed issues before running the full processor.

## Troubleshooting Tests

### Feed Not Fetching
```bash
# Test the URL directly
curl -v "https://example.com/feed.xml"

# Common issues:
# - 403 Forbidden: Need User-Agent header (file an issue!)
# - 404 Not Found: Wrong URL
# - Timeout: Feed is down or slow
```

### Feed Not Parsing
```bash
# Check feed format
curl -s "https://example.com/feed.xml" | head -20

# Should see:
# - RSS: <rss version="2.0">
# - Atom: <feed xmlns="http://www.w3.org/2005/Atom">
# - JSON: {"version":"https://jsonfeed.org/version/1.1"
```

### No Items Would Be Posted
Possible reasons:
1. All items are duplicates (already in state)
2. All items are too old (older than 7 days on first run)
3. Feed has no items
4. Items missing required fields (title, etc.)

Check with:
```bash
cat state.json | jq '.last_run_timestamp'  # Check last run
cat state.json | jq '.posted_items | length'  # Check tracked count
```

### State Not Saving
```bash
# Check file permissions
ls -l state.json

# Check if file is writable
touch state.json
```

## Switching from Dry Run to Real

Once you've verified everything works:

```bash
# Method 1: Unset the variable
unset DRY_RUN
./zig-out/bin/smellslike

# Method 2: Set to false
export DRY_RUN=false
./zig-out/bin/smellslike

# Method 3: Don't set it at all
# (DRY_RUN is off by default)
```

**Important:** Your `state.json` from dry-run carries over! The items tracked during dry-run won't be posted again in real mode (they're already marked as posted).

## GitHub Actions Testing

### Test Workflow Locally (with act)

```bash
# Install act (https://github.com/nektos/act)
brew install act  # or your package manager

# Test the workflow
act -s DISCORD_BLOG_WEBHOOK="test" \
    -s DISCORD_GO_NEWS_WEBHOOK="test" \
    -s DISCORD_ZIG_NEWS_WEBHOOK="test" \
    -s DISCORD_YT_WEBHOOK="test"
```

### Test in GitHub (Manual Trigger)

1. Push your code
2. Go to Actions tab
3. Select "Process Feeds"
4. Click "Run workflow"
5. Check logs for any errors

### Dry Run in GitHub Actions

Add to workflow file:
```yaml
- name: Run feed processor (dry run)
  env:
    DRY_RUN: true
  run: ./zig-out/bin/smellslike
```

## Tips

### Quick Iteration
```bash
# One-liner for repeated testing
while true; do 
  export DRY_RUN=true
  ./zig-out/bin/smellslike
  echo "Press Ctrl+C to stop, Enter to run again..."
  read
done
```

### Reset Everything
```bash
# Start completely fresh
rm state.json
zig build clean
zig build
export DRY_RUN=true
./zig-out/bin/smellslike
```

### Compare Runs
```bash
# Save output for comparison
export DRY_RUN=true
./zig-out/bin/smellslike > run1.log
./zig-out/bin/smellslike > run2.log
diff run1.log run2.log
```

### Watch State File
```bash
# In one terminal
watch -n 2 'cat state.json | jq'

# In another terminal
export DRY_RUN=true
./zig-out/bin/smellslike
```
