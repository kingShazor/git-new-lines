const std = @import("std");
const epoch = std.time.epoch;

const day_count = 10;
const seconds_per_day: u64 = 24 * 60 * 60;

pub fn main(init: std.process.Init) void {
    const allocator = init.arena.allocator();
    const io = init.io;

    const args = init.minimal.args.toSlice(allocator) catch {
        std.debug.print("Fehler beim Lesen der Argumente.\n", .{});
        return;
    };
    if (args.len == 2 and (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h"))) {
        printUsage();
        return;
    }
    const days = parseDayCount(args) catch {
        printUsage();
        return;
    };

    const now_seconds: u64 = @intCast(@divTrunc(std.Io.Clock.real.now(io).nanoseconds, 1_000_000_000));
    const today = now_seconds / seconds_per_day;
    if (days > today + 1) {
        std.debug.print("Die Tagesanzahl darf höchstens {d} betragen.\n", .{today + 1});
        return;
    }

    const counts = allocator.alloc(i128, days) catch {
        std.debug.print("Nicht genug Speicher für {d} Tage.\n", .{days});
        return;
    };
    @memset(counts, 0);
    const since_arg = std.fmt.allocPrint(allocator, "--since={d} days ago", .{days}) catch {
        std.debug.print("Fehler beim Erstellen des Git-Parameters.\n", .{});
        return;
    };

    var result = std.process.run(allocator, io, .{
        .argv = &.{
            "git",
            "log",
            since_arg,
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

    parseNumstat(result.stdout, today, counts);

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const writer = &stdout_file_writer.interface;

    writer.writeAll("Datum\tDelta (+/- Zeilen)\n") catch return;
    var total: i128 = 0;
    for (0..days) |index| {
        const day = today - (days - 1 - index);
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
    const divisor: u128 = @intCast(days);
    const average_hundredths_unrounded = average_magnitude * 100 / divisor;
    const remainder = average_magnitude * 100 % divisor;
    const average_hundredths = average_hundredths_unrounded + @as(u128, @intFromBool(remainder * 2 >= divisor));
    writer.print("Durchschnitt pro Tag ({d} Tage): {s}{d}.{d:0>2} Zeilen\n", .{
        days,
        average_sign,
        average_hundredths / 100,
        average_hundredths % 100,
    }) catch return;
    writer.flush() catch return;
}

fn printUsage() void {
    std.debug.print("Verwendung: cl [--days N | -n N]\nStandard: {d} Tage\n", .{day_count});
}

fn parseDayCount(args: []const [:0]const u8) error{InvalidArguments}!usize {
    if (args.len == 1) return day_count;

    var value: []const u8 = undefined;
    if (args.len == 3 and (std.mem.eql(u8, args[1], "--days") or std.mem.eql(u8, args[1], "-n"))) {
        value = args[2];
    } else if (args.len == 2 and std.mem.startsWith(u8, args[1], "--days=")) {
        value = args[1][7..];
    } else {
        return error.InvalidArguments;
    }

    const days = std.fmt.parseInt(usize, value, 10) catch return error.InvalidArguments;
    if (days == 0) return error.InvalidArguments;
    return days;
}

fn parseNumstat(output: []const u8, today: u64, counts: []i128) void {
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
        const first_day = today - (counts.len - 1);
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

test "day count argument defaults and validates options" {
    try std.testing.expectEqual(@as(usize, 10), try parseDayCount(&.{"cl"}));
    try std.testing.expectEqual(@as(usize, 30), try parseDayCount(&.{ "cl", "--days", "30" }));
    try std.testing.expectEqual(@as(usize, 7), try parseDayCount(&.{ "cl", "-n", "7" }));
    try std.testing.expectEqual(@as(usize, 14), try parseDayCount(&.{ "cl", "--days=14" }));
    try std.testing.expectError(error.InvalidArguments, parseDayCount(&.{ "cl", "--days", "0" }));
}

test "source file filter recognizes requested languages only" {
    try std.testing.expect(isSourceFile("src/app.jsx"));
    try std.testing.expect(isSourceFile("src/main.CPP"));
    try std.testing.expect(isSourceFile("scripts/build.bash"));
    try std.testing.expect(!isSourceFile("docs/README.md"));
    try std.testing.expect(!isSourceFile("assets/logo.svg"));
}
