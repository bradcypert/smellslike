# Setup Guide

## Quick Start

### 1. Configure Discord Webhooks

Create Discord webhooks for each channel you want to post to:

1. Go to your Discord server settings
2. Navigate to Integrations → Webhooks
3. Click "New Webhook"
4. Choose the channel and copy the webhook URL
5. Repeat for each channel (blog, go-news, zig-news, videos)

### 2. Local Testing

#### Dry Run Mode (Recommended First!)

Test without posting to Discord and build your initial state file:

```bash
zig build
export DRY_RUN=true
./zig-out/bin/smellslike
```

This will:
- ✅ Fetch and parse all feeds
- ✅ Show what would be posted
- ✅ Build the `state.json` file
- ❌ NOT post to Discord

Perfect for:
- Initial setup and testing
- Adding new feeds
- Verifying feed URLs work
- Building state before going live

#### Real Run

Set environment variables:

```bash
export DISCORD_BLOG_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK"
export DISCORD_GO_NEWS_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK"
export DISCORD_ZIG_NEWS_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK"
export DISCORD_YT_WEBHOOK="https://discord.com/api/webhooks/YOUR_WEBHOOK"
```

Run without dry mode:

```bash
unset DRY_RUN  # or export DRY_RUN=false
./zig-out/bin/smellslike
```

### 3. GitHub Actions Setup

#### Add Repository Secrets

Go to your GitHub repository → Settings → Secrets and variables → Actions → New repository secret

Add these four secrets:
- `DISCORD_BLOG_WEBHOOK`
- `DISCORD_GO_NEWS_WEBHOOK`
- `DISCORD_ZIG_NEWS_WEBHOOK`
- `DISCORD_YT_WEBHOOK`

#### Commit and Push

```bash
git add .
git commit -m "Add feed processor with duplicate detection"
git push
```

#### Enable GitHub Actions

1. Go to the Actions tab in your repository
2. Enable workflows if prompted
3. The workflow will run automatically every 6 hours
4. You can also trigger it manually with "Run workflow"

## How Duplicate Detection Works

### Initial Run
On the first run (when `state.json` has `last_run_timestamp: 0`):
- Only posts items from the last 7 days
- Prevents flooding Discord with old items
- Builds initial state

### Subsequent Runs
On later runs:
- Only posts items published since `last_run_timestamp`
- Checks if item ID is in `posted_items` list
- Skips duplicates and old items

### State File
The `state.json` file is automatically:
- Loaded at startup
- Updated with new items
- Saved after processing
- Committed back to the repository by GitHub Actions

## Adding New Feeds

1. Choose the appropriate channel file in `src/channels/`
2. Add the feed URL on a new line
3. Commit and push (or wait for next scheduled run)

Example:
```bash
echo "https://example.com/feed.xml" >> src/channels/zig-news.txt
git add src/channels/zig-news.txt
git commit -m "Add new Zig feed"
git push
```

## Monitoring

### Check Logs
1. Go to Actions tab
2. Click on the latest "Process Feeds" run
3. Expand "Run feed processor" step

### Verify State
Check `state.json` after a run:
```bash
git pull
cat state.json
```

## Troubleshooting

### Items Not Posting
- Check Discord webhook URLs are correct
- Verify feed URLs are accessible
- Check GitHub Actions logs for errors
- Ensure `state.json` is being committed

### Duplicate Posts
- Check `state.json` is being committed and pulled
- Verify item IDs are being captured correctly
- Check timestamp parsing for feed dates

### Old Items Posting
- The first run posts items from last 7 days
- Later runs only post new items
- Clear `state.json` if you need to reset

### GitHub Actions Not Running
- Check workflow file syntax
- Verify repository permissions allow Actions
- Check secrets are configured
- Enable Actions in repository settings

## Customization

### Change Schedule
Edit `.github/workflows/feed-processor.yml`:
```yaml
on:
  schedule:
    - cron: '0 */6 * * *'  # Every 6 hours
    # Examples:
    # - cron: '0 * * * *'    # Every hour
    # - cron: '*/30 * * * *' # Every 30 minutes
    # - cron: '0 8 * * *'    # Daily at 8am UTC
```

### Add New Channel
1. Create new channel file: `src/channels/my-channel.txt`
2. Add feed URLs (one per line)
3. Add webhook to `Env` struct in `src/main.zig`
4. Add environment variable
5. Update `getWebhookForChannel()` function
6. Add secret to GitHub Actions

### Adjust Time Window
Edit `shouldPost()` in `src/main.zig`:
```zig
// Change 7 days to desired number
const one_week_ago = std.time.timestamp() - (7 * 24 * 60 * 60);
```

### Change State Retention Period
Edit `State` struct in `src/main.zig`:
```zig
const RETENTION_DAYS = 30;  // Keep posted items for 30 days
```

This controls how long item IDs are kept in `state.json`. After this period, they're automatically removed on next load. Shorter retention = smaller state file, but risk of reposting very old items if they reappear in feeds.
