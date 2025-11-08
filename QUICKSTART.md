# Quick Start Guide

## 5-Minute Setup

### 1. Build
```bash
zig build
```

### 2. Test in Dry-Run Mode
```bash
export DRY_RUN=true
./zig-out/bin/smellslike
```

Expected output:
```
🧪 DRY RUN MODE - No Discord posts will be made
Starting feed processor...
...
✅ Dry run complete! 12 items would be posted
```

### 3. Set Up Discord Webhooks
```bash
export DISCORD_BLOG_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
export DISCORD_GO_NEWS_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
export DISCORD_ZIG_NEWS_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
export DISCORD_YT_WEBHOOK="https://discord.com/api/webhooks/YOUR_ID/YOUR_TOKEN"
```

### 4. Run for Real
```bash
unset DRY_RUN
./zig-out/bin/smellslike
```

### 5. Deploy to GitHub Actions
```bash
git add .
git commit -m "Deploy feed processor"
git push
```

Add secrets in GitHub repo settings:
- Settings → Secrets and variables → Actions
- Add all 4 Discord webhook secrets
- Workflow runs every 6 hours automatically

## Common Commands

### Test without posting
```bash
DRY_RUN=true ./zig-out/bin/smellslike
```

### Post to Discord
```bash
./zig-out/bin/smellslike
```

### Check state
```bash
cat state.json | jq
```

### Reset state
```bash
rm state.json
```

### Add new feed
```bash
echo "https://example.com/feed.xml" >> src/channels/zig-news.txt
DRY_RUN=true ./zig-out/bin/smellslike  # Test first!
```

## Files You Care About

- `src/channels/*.txt` - Feed URLs (one per line)
- `state.json` - Tracks posted items (auto-generated)
- `.github/workflows/feed-processor.yml` - GitHub Actions config

## Key Behaviors

✅ **First run:** Only posts items from last 7 days  
✅ **Later runs:** Only posts new items since last run  
✅ **Duplicates:** Automatically skipped  
✅ **Old state:** Entries older than 30 days auto-removed  
✅ **Dry run:** Test mode, doesn't post, builds state  

## Troubleshooting One-Liners

```bash
# View what would be posted without posting
DRY_RUN=true ./zig-out/bin/smellslike 2>&1 | grep "Would post"

# Count items in state
cat state.json | jq '.posted_items | length'

# See last run time (Unix timestamp)
cat state.json | jq '.last_run_timestamp'

# Test a specific feed
curl -s "https://example.com/feed.xml" | head -50

# Rebuild everything
zig build clean && zig build
```

## Getting Help

- **Full setup:** See [SETUP.md](SETUP.md)
- **Testing:** See [TESTING.md](TESTING.md)
- **Details:** See [README.md](README.md)
- **Issues:** Check GitHub Actions logs in the Actions tab
