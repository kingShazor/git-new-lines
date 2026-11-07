const std = @import("std");
const epoch = std.time.epoch;

const day_count = 10;
const seconds_per_day: u64 = 24 * 60 * 60;

pub fn main(init: std.process.Init) void {
    const allocator = init.arena.allocator();
    const io = init.io;

    var counts: [day_count]i128 = @splat(0);
    const now_seconds: u64 = @intCast(@divTrunc(std.Io.Clock.real.now(io).nanoseconds, 1_000_000_000));
    const today = now_seconds / seconds_per_day;

    var result = std.process.run(allocator, io, .{
        .argv = &.{
            "git",
            "log",
            "--since=10 days ago",
            "--no-merges",
            "--no-renames",
            "--format=COMMIT:%ct",
            "--numstat",
        },
    }) catch |err| {
        std.debug.print("Fehler beim Aufruf von git: {s}\n", .{@errorName(err)});
        return;
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (!result.term.success()) {
        std.debug.print("git log ist fehlgeschlagen: {s}", .{result.stderr});
        return;
    }

    parseNumstat(result.stdout, today, &counts);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    writer.writeAll("Datum\tDelta (+/- Zeilen)\n") catch return;
    var total: i128 = 0;
    for (0..day_count) |index| {
        const day = today - (day_count - 1 - index);
        const date = epoch.EpochDay{ .day = @intCast(day) };
        const year_day = date.calculateYearDay();
        const month_day = year_day.calculateMonthDay();
        const delta = counts[index];
        const delta_sign: []const u8 = if (delta < 0) "-" else "+";
        const delta_magnitude: u128 = @intCast(if (delta < 0) -delta else delta);
        writer.print("{d:0>4}-{d:0>2}-{d:0>2}\t{s}{d}\n", .{
            year_day.year,
            month_day.month.numeric(),
            @as(u8, @intCast(month_day.day_index)) + 1,
            delta_sign,
            delta_magnitude,
        }) catch return;
        total += counts[index];
    }
    const average_sign: []const u8 = if (total < 0) "-" else "+";
    const average_magnitude: u128 = @intCast(if (total < 0) -total else total);
    writer.print("Durchschnitt pro Tag (10 Tage): {s}{d}.{d} Zeilen\n", .{
        average_sign,
        average_magnitude / day_count,
        average_magnitude % day_count,
    }) catch return;
    writer.flush() catch return;
}

fn parseNumstat(output: []const u8, today: u64, counts: *[day_count]i128) void {
    var commit_day: ?u64 = null;
    var lines = std.mem.splitScalar(u8, output, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "COMMIT:")) {
            const timestamp = std.fmt.parseInt(u64, line[7..], 10) catch {
                commit_day = null;
                continue;
            };
            commit_day = timestamp / seconds_per_day;
            continue;
        }

        const first_tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
        const second_tab = std.mem.indexOfScalarPos(u8, line, first_tab + 1, '\t') orelse continue;
        if (!isSourceFile(line[second_tab + 1 ..])) continue;

        const additions = std.fmt.parseInt(u64, line[0..first_tab], 10) catch continue;
        const deletions = std.fmt.parseInt(u64, line[first_tab + 1 .. second_tab], 10) catch continue;
        const day = commit_day orelse continue;
        const first_day = today - (day_count - 1);
        if (day >= first_day and day <= today) {
            counts[@intCast(day - first_day)] += @as(i128, @intCast(additions)) - @as(i128, @intCast(deletions));
        }
    }
}

fn isSourceFile(path: []const u8) bool {
    const basename = if (std.mem.lastIndexOfScalar(u8, path, '/')) |slash|
        path[slash + 1 ..]
    else
        path;
    const dot = std.mem.lastIndexOfScalar(u8, basename, '.') orelse return false;
    const extension = basename[dot..];

    const extensions = .{
        ".js", ".jsx", ".mjs", ".cjs", // JavaScript
        ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", // C++
        ".zig", // Zig
        ".lua", // Lua
        ".fish", // fish
        ".sh", ".bash", // Bash
    };
    inline for (extensions) |candidate| {
        if (std.ascii.eqlIgnoreCase(extension, candidate)) return true;
    }
    return false;
}

test "numstat calculates net changes only for source files in range" {
    var counts: [day_count]i128 = @splat(0);
    const log = "COMMIT:86400\n3\t1\toldest.zig\n10\t0\tREADME.md\n-\t-\timage.png\nCOMMIT:864001\n2\t5\tnew.js\n";

    parseNumstat(log, 10, &counts);

    try std.testing.expectEqual(@as(i128, 2), counts[0]);
    try std.testing.expectEqual(@as(i128, -3), counts[9]);
}

test "source file filter recognizes requested languages only" {
    try std.testing.expect(isSourceFile("src/app.jsx"));
    try std.testing.expect(isSourceFile("src/main.CPP"));
    try std.testing.expect(isSourceFile("scripts/build.bash"));
    try std.testing.expect(!isSourceFile("docs/README.md"));
    try std.testing.expect(!isSourceFile("assets/logo.svg"));
}
