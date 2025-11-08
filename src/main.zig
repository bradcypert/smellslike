const std = @import("std");
const updog = @import("updog");

const STATE_FILE = "state.json";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const dry_run = checkDryRun();
    if (dry_run) {
        std.debug.print("   DRY RUN MODE - No Discord posts will be made\n", .{});
        std.debug.print("   (Set DRY_RUN=false or unset to post for real)\n\n", .{});
    }

    var env = try Env.init(allocator, dry_run);
    defer env.deinit(allocator);

    var state = try State.load(allocator);
    defer state.deinit();

    std.debug.print("Starting feed processor...\n", .{});
    std.debug.print("Last run: {d}\n", .{state.last_run_timestamp});
    std.debug.print("Tracked items: {d}\n", .{state.posted_items.count()});

    try processAllChannels(allocator, &env, &state, dry_run);

    state.last_run_timestamp = std.time.timestamp();
    try state.save();

    if (dry_run) {
        std.debug.print("\n   Dry run complete! {d} items would be posted\n", .{state.new_items_count});
        std.debug.print("   State file updated. Run without DRY_RUN to post for real.\n", .{});
    } else {
        std.debug.print("Done! New items posted: {d}\n", .{state.new_items_count});
    }
}

fn checkDryRun() bool {
    const dry_run_env = std.process.getEnvVarOwned(std.heap.page_allocator, "DRY_RUN") catch return false;
    defer std.heap.page_allocator.free(dry_run_env);

    if (std.mem.eql(u8, dry_run_env, "true") or std.mem.eql(u8, dry_run_env, "1")) {
        return true;
    }
    return false;
}

fn processAllChannels(allocator: std.mem.Allocator, env: *const Env, state: *State, dry_run: bool) !void {
    const channels_dir = try std.fs.cwd().openDir("src/channels", .{ .iterate = true });
    var dir = channels_dir;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".txt")) continue;

        try processChannel(allocator, env, state, dir, entry.name, dry_run);
    }
}

fn processChannel(allocator: std.mem.Allocator, env: *const Env, state: *State, dir: std.fs.Dir, filename: []const u8, dry_run: bool) !void {
    std.debug.print("\nProcessing channel: {s}\n", .{filename});

    const webhook = try getWebhookForChannel(env, filename);

    const file = try dir.openFile(filename, .{});
    defer file.close();

    const contents = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(contents);

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, &std.ascii.whitespace);
        if (trimmed.len == 0) continue;
        if (std.mem.startsWith(u8, trimmed, "//")) continue;

        const url = extractUrl(trimmed);
        if (url.len > 0) {
            try processFeed(allocator, webhook, url, state, dry_run);
        }
    }
}

fn extractUrl(line: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, line, '.')) |dot_idx| {
        if (dot_idx > 0 and std.ascii.isDigit(line[dot_idx - 1])) {
            return std.mem.trim(u8, line[dot_idx + 1 ..], &std.ascii.whitespace);
        }
    }
    return line;
}

fn getWebhookForChannel(env: *const Env, filename: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, filename, "bradcypert-blog") != null) {
        return env.blog_webhook;
    } else if (std.mem.indexOf(u8, filename, "bradcypert-videos") != null) {
        return env.yt_webhook;
    } else if (std.mem.indexOf(u8, filename, "go-news") != null) {
        return env.go_news_webhook;
    } else if (std.mem.indexOf(u8, filename, "zig-news") != null) {
        return env.zig_news_webhook;
    }
    return error.UnknownChannel;
}

fn processFeed(allocator: std.mem.Allocator, webhook: []const u8, url: []const u8, state: *State, dry_run: bool) !void {
    std.debug.print("  Fetching: {s}\n", .{url});

    const feed_data = fetchUrl(allocator, url) catch |err| {
        std.debug.print("  Failed to fetch: {}\n", .{err});
        return;
    };
    defer allocator.free(feed_data);

    var parser = updog.Parser.init(allocator);
    var feed = parser.parse(feed_data) catch |err| {
        std.debug.print("  Failed to parse: {}\n", .{err});
        return;
    };
    defer feed.deinit();

    std.debug.print("  Feed: {s} ({d} items)\n", .{ feed.title, feed.items.items.len });

    for (feed.items.items) |item| {
        if (item.title) |title| {
            const item_id = item.id orelse item.url orelse title;

            if (state.isPosted(item_id)) {
                std.debug.print("  Skipping duplicate: {s}\n", .{title});
                continue;
            }

            if (try state.shouldPost(item.date_published)) {
                if (dry_run) {
                    std.debug.print("  [DRY RUN] Would post: {s}\n", .{title});
                } else {
                    postToDiscord(allocator, webhook, title, item.url, item.summary) catch |err| {
                        std.debug.print("  Failed to post to Discord: {}\n", .{err});
                        std.debug.print("  Continuing with next item...\n", .{});
                        continue;
                    };
                    std.debug.print("  Posted: {s}\n", .{title});
                }
                try state.markAsPosted(item_id);
                state.new_items_count += 1;
            } else {
                std.debug.print("  Skipping old item: {s}\n", .{title});
            }
        }
    }
}

fn fetchUrl(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const uri = try std.Uri.parse(url);

    var allocating = std.Io.Writer.Allocating.init(allocator);
    defer allocating.deinit();

    const result = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .response_writer = &allocating.writer,
    });

    if (result.status != .ok) {
        return error.HttpError;
    }

    return try allocating.toOwnedSlice();
}

fn postToDiscord(allocator: std.mem.Allocator, webhook_url: []const u8, title: []const u8, url: ?[]const u8, summary: ?[]const u8) !void {
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(allocator);

    const writer = content.writer(allocator);
    try writer.print("New Post:\n**{s}**\n", .{title});
    if (summary) |s| {
        const truncated = if (s.len > 500) s[0..500] else s;
        // TODO: This needs to support more HTML entities
        const output_Size = std.mem.replacementSize(u8, truncated, "&#39;", "'");
        const output_buffer = try allocator.alloc(u8, output_Size);
        defer allocator.free(output_buffer);
        _ = std.mem.replace(u8, truncated, "&#39;", "'", output_buffer);
        try writer.print("\n{s}\n", .{output_buffer});
    }
    if (url) |u| {
        try writer.print("\nRead more at: {s}\n", .{u});
    }

    const Payload = struct {
        content: []const u8,
    };

    const payload = Payload{ .content = content.items };

    var json_contents = std.Io.Writer.Allocating.init(allocator);
    defer json_contents.deinit();

    try std.json.Stringify.value(payload, .{}, &json_contents.writer);

    // std.debug.print("  Webhook URL: {s}\n", .{webhook_url});
    std.debug.print("  Payload: {s}\n", .{json_contents.written()});

    const uri = try std.Uri.parse(webhook_url);

    const max_retries = 3;
    var retry: u32 = 0;
    while (retry < max_retries) : (retry += 1) {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var allocating = std.Io.Writer.Allocating.init(allocator);
        defer allocating.deinit();

        const result = client.fetch(.{
            .method = .POST,
            .location = .{ .uri = uri },
            .payload = json_contents.written(),
            .keep_alive = false,
            .response_writer = &allocating.writer,
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "application/json" },
            },
        }) catch |err| {
            std.debug.print("  Discord request failed (attempt {}/{}): {}\n", .{ retry + 1, max_retries, err });
            if (retry + 1 < max_retries) {
                std.Thread.sleep(std.time.ns_per_s * (@as(u64, 1) << @intCast(retry)));
                continue;
            }
            return err;
        };

        if (result.status == .ok or result.status == .no_content) {
            return;
        } else if (result.status == .too_many_requests) {
            std.debug.print("  Rate limited by Discord\n", .{});
            if (retry + 1 < max_retries) {
                std.Thread.sleep(std.time.ns_per_s * 5);
                continue;
            }
            return error.RateLimited;
        } else {
            std.debug.print("  Discord webhook failed with status: {}\n", .{result.status});
            return error.WebhookFailed;
        }
    }
}

const Env = struct {
    blog_webhook: []u8,
    go_news_webhook: []u8,
    zig_news_webhook: []u8,
    yt_webhook: []u8,

    pub fn init(allocator: std.mem.Allocator, dry_run: bool) !@This() {
        if (dry_run) {
            return .{
                .blog_webhook = try allocator.dupe(u8, "dry-run-webhook"),
                .go_news_webhook = try allocator.dupe(u8, "dry-run-webhook"),
                .zig_news_webhook = try allocator.dupe(u8, "dry-run-webhook"),
                .yt_webhook = try allocator.dupe(u8, "dry-run-webhook"),
            };
        }

        return .{
            .blog_webhook = try std.process.getEnvVarOwned(allocator, "DISCORD_BLOG_WEBHOOK"),
            .go_news_webhook = try std.process.getEnvVarOwned(allocator, "DISCORD_GO_NEWS_WEBHOOK"),
            .zig_news_webhook = try std.process.getEnvVarOwned(allocator, "DISCORD_ZIG_NEWS_WEBHOOK"),
            .yt_webhook = try std.process.getEnvVarOwned(allocator, "DISCORD_YT_WEBHOOK"),
        };
    }

    pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
        allocator.free(self.blog_webhook);
        allocator.free(self.go_news_webhook);
        allocator.free(self.zig_news_webhook);
        allocator.free(self.yt_webhook);
    }
};

const State = struct {
    allocator: std.mem.Allocator,
    last_run_timestamp: i64,
    posted_items: std.StringHashMap(i64),
    new_items_count: usize,

    const RETENTION_DAYS = 30;
    const POST_WINDOW_DAYS = 7;

    const StateData = struct {
        last_run_timestamp: i64,
        posted_items: []PostedItem,
    };

    const PostedItem = struct {
        id: []const u8,
        posted_at: i64,
    };

    pub fn load(allocator: std.mem.Allocator) !State {
        var posted_items = std.StringHashMap(i64).init(allocator);
        var last_run_timestamp: i64 = 0;

        const file = std.fs.cwd().openFile(STATE_FILE, .{}) catch |err| {
            if (err == error.FileNotFound) {
                std.debug.print("No state file found, starting fresh\n", .{});
                return State{
                    .allocator = allocator,
                    .last_run_timestamp = 0,
                    .posted_items = posted_items,
                    .new_items_count = 0,
                };
            }
            return err;
        };
        defer file.close();

        const contents = try file.readToEndAlloc(allocator, 10 * 1024 * 1024);
        defer allocator.free(contents);

        const parsed = std.json.parseFromSlice(StateData, allocator, contents, .{}) catch |err| {
            std.debug.print("Failed to parse state file: {}, starting fresh\n", .{err});
            return State{
                .allocator = allocator,
                .last_run_timestamp = 0,
                .posted_items = posted_items,
                .new_items_count = 0,
            };
        };
        defer parsed.deinit();

        last_run_timestamp = parsed.value.last_run_timestamp;

        const cutoff = std.time.timestamp() - (RETENTION_DAYS * 24 * 60 * 60);
        var kept_count: usize = 0;
        var removed_count: usize = 0;

        for (parsed.value.posted_items) |item| {
            if (item.posted_at >= cutoff) {
                const owned_id = try allocator.dupe(u8, item.id);
                try posted_items.put(owned_id, item.posted_at);
                kept_count += 1;
            } else {
                removed_count += 1;
            }
        }

        if (removed_count > 0) {
            std.debug.print("Cleaned up {d} old entries (kept {d})\n", .{ removed_count, kept_count });
        }

        return State{
            .allocator = allocator,
            .last_run_timestamp = last_run_timestamp,
            .posted_items = posted_items,
            .new_items_count = 0,
        };
    }

    pub fn save(self: *const State) !void {
        const file = try std.fs.cwd().createFile(STATE_FILE, .{});
        defer file.close();

        var item_list: std.ArrayList(PostedItem) = .empty;
        defer item_list.deinit(self.allocator);

        var iterator = self.posted_items.iterator();
        while (iterator.next()) |entry| {
            try item_list.append(self.allocator, .{
                .id = entry.key_ptr.*,
                .posted_at = entry.value_ptr.*,
            });
        }

        const state_data = StateData{
            .last_run_timestamp = self.last_run_timestamp,
            .posted_items = item_list.items,
        };

        var buffer: [1024]u8 = undefined;

        var writer = file.writer(&buffer);
        const w = &writer.interface;
        var stringify: std.json.Stringify = .{
            .writer = w,
            .options = .{ .whitespace = .indent_2 },
        };
        try stringify.write(state_data);
        try w.flush();
    }

    pub fn deinit(self: *State) void {
        var iterator = self.posted_items.keyIterator();
        while (iterator.next()) |key| {
            self.allocator.free(key.*);
        }
        self.posted_items.deinit();
    }

    pub fn isPosted(self: *const State, item_id: []const u8) bool {
        return self.posted_items.contains(item_id);
    }

    pub fn markAsPosted(self: *State, item_id: []const u8) !void {
        const owned_id = try self.allocator.dupe(u8, item_id);
        const now = std.time.timestamp();
        try self.posted_items.put(owned_id, now);
    }

    pub fn shouldPost(self: *const State, date_published: ?[]const u8) !bool {
        _ = self;
        const cutoff = std.time.timestamp() - (POST_WINDOW_DAYS * 24 * 60 * 60);
        return try isNewerThan(date_published, cutoff);
    }
};

fn isNewerThan(date_str: ?[]const u8, timestamp: i64) !bool {
    if (date_str == null) return false;

    const parsed_time = parseDate(date_str.?) catch return false;
    return parsed_time >= timestamp;
}

fn parseDate(date_str: []const u8) !i64 {
    return parseRFC2822(date_str) catch parseRFC3339(date_str);
}

fn parseRFC2822(date_str: []const u8) !i64 {
    // Example: "Wed, 10 Sep 2025 00:00:00 +0000"
    if (date_str.len < 20) return error.InvalidDate;

    // Find the day number (after first comma and space)
    const comma_pos = std.mem.indexOfScalar(u8, date_str, ',') orelse return error.InvalidDate;
    if (comma_pos + 2 >= date_str.len) return error.InvalidDate;

    var pos = comma_pos + 2;
    while (pos < date_str.len and date_str[pos] == ' ') pos += 1;

    const day_start = pos;
    while (pos < date_str.len and std.ascii.isDigit(date_str[pos])) pos += 1;
    if (day_start == pos) return error.InvalidDate;
    const day = try std.fmt.parseInt(u8, date_str[day_start..pos], 10);

    while (pos < date_str.len and date_str[pos] == ' ') pos += 1;

    const month_start = pos;
    while (pos < date_str.len and std.ascii.isAlphabetic(date_str[pos])) pos += 1;
    if (month_start == pos) return error.InvalidDate;
    const month_str = date_str[month_start..pos];
    const month = try parseMonth(month_str);

    while (pos < date_str.len and date_str[pos] == ' ') pos += 1;

    const year_start = pos;
    while (pos < date_str.len and std.ascii.isDigit(date_str[pos])) pos += 1;
    if (year_start == pos) return error.InvalidDate;
    const year = try std.fmt.parseInt(i32, date_str[year_start..pos], 10);

    while (pos < date_str.len and date_str[pos] == ' ') pos += 1;

    if (pos + 8 > date_str.len) return error.InvalidDate;
    const hour = try std.fmt.parseInt(u8, date_str[pos .. pos + 2], 10);
    const minute = try std.fmt.parseInt(u8, date_str[pos + 3 .. pos + 5], 10);
    const second = try std.fmt.parseInt(u8, date_str[pos + 6 .. pos + 8], 10);

    const days_since_epoch = @as(i64, year - 1970) * 365 +
        @divFloor(year - 1969, 4) -
        @divFloor(year - 1901, 100) +
        @divFloor(year - 1601, 400) +
        daysBeforeMonth(month, isLeapYear(year)) +
        (day - 1);

    return days_since_epoch * 86400 +
        @as(i64, hour) * 3600 +
        @as(i64, minute) * 60 +
        second;
}

fn parseMonth(month_str: []const u8) !u8 {
    const months = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };
    for (months, 0..) |m, i| {
        if (std.mem.eql(u8, month_str, m)) {
            return @as(u8, @intCast(i + 1));
        }
    }
    return error.InvalidMonth;
}

fn parseRFC3339(date_str: []const u8) !i64 {
    if (date_str.len < 19) return error.InvalidDate;

    const year = try std.fmt.parseInt(i32, date_str[0..4], 10);
    const month = try std.fmt.parseInt(u8, date_str[5..7], 10);
    const day = try std.fmt.parseInt(u8, date_str[8..10], 10);
    const hour = try std.fmt.parseInt(u8, date_str[11..13], 10);
    const minute = try std.fmt.parseInt(u8, date_str[14..16], 10);
    const second = try std.fmt.parseInt(u8, date_str[17..19], 10);

    const days_since_epoch = @as(i64, year - 1970) * 365 +
        @divFloor(year - 1969, 4) -
        @divFloor(year - 1901, 100) +
        @divFloor(year - 1601, 400) +
        daysBeforeMonth(month, isLeapYear(year)) +
        (day - 1);

    return days_since_epoch * 86400 +
        @as(i64, hour) * 3600 +
        @as(i64, minute) * 60 +
        second;
}

fn isLeapYear(year: i32) bool {
    return (@rem(year, 4) == 0 and @rem(year, 100) != 0) or (@rem(year, 400) == 0);
}

fn daysBeforeMonth(month: u8, leap: bool) i64 {
    const days = [_]i64{ 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 };
    if (month <= 1 or month > 12) return 0;
    var result = days[month - 1];
    if (leap and month > 2) result += 1;
    return result;
}
