/// Configuration module
/// Configuration parameters can be set in two ways:
/// - config file
/// - environment variables
///
/// Enviroment variables has priority over config file settings.
/// In other words, first data is read from config file, then from enviroment variables and final config is result of both of them.
const std = @import("std");
const log = std.log;
const fs = std.fs;

const Self = @This();

const ConfigError = error{
    ConfigAlreadyInitialized,
    InvalidEnvironmentVariable,
    ConfigWasNotInitialized,
};

/// Returns config object.
/// This function returns error only if config was not initialized.
pub fn getConfig() ConfigError!Config {
    if (Self.config) |c| {
        return c;
    } else {
        return ConfigError.ConfigWasNotInitialized;
    }
}

/// Loads config from provided config file and enviroment variables.
/// If file doesn't exists and createDefaultFile is set to true then this function will ignore this fact but on any other error the error will be returned
/// To create automatically file, if possible, with default config set last parameter to true.
pub fn initConfig(allocator: std.mem.Allocator, configPath: ?[]const u8, createDefaultFile: bool) !void {
    Self.arena = std.heap.ArenaAllocator.init(allocator);

    if (Self.config != null) {
        return ConfigError.ConfigAlreadyInitialized;
    }

    var createFile = false;

    if (configPath) |path| {
        if (fs.cwd().openFile(path, .{})) |file| {
            defer file.close();
            Self.config = try readConfigFromFile(arena.allocator(), file);
        } else |err| {
            if (err == fs.File.OpenError.FileNotFound and createDefaultFile) {
                createFile = true;
            } else {
                return err;
            }
        }
    }

    if (Self.config == null) {
        Self.config = .{};
    }

    // Sanity check --------------\/
    if (createFile and configPath != null) {
        writeConfigToFile(allocator, configPath.?) catch |err| {
            log.warn("Failed to create config file: {any}", .{err});
        };
    }

    try initFromEnv();
}

fn readConfigFromFile(allocator: std.mem.Allocator, file: fs.File) !Config {
    const data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(data);
    const parsed = try std.json.parseFromSliceLeaky(
        Config,
        allocator,
        data,
        .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
    );
    return parsed;
}

fn writeConfigToFile(allocator: std.mem.Allocator, path: []const u8) !void {
    const data = try std.json.stringifyAlloc(
        allocator,
        Self.config,
        .{ .whitespace = .indent_2 },
    );
    defer allocator.free(data);
    const file = try fs.cwd().createFile(path, .{ .exclusive = true });
    try file.writeAll(data);
}

fn initFromEnv() ConfigError!void {
    if (Self.config == null) {
        Self.config = .{};
    }

    // I am sure there's a way to do this automatically with reflection
    // but I am too lazy to learn about zig's reflection.

    loadSliceEnv([]const u8, "HOST", &config.?.host);
    try loadIntEnv(u16, "PORT", &config.?.port);
    loadSliceEnv(?[]const u8, "UNIX_SOCKET", &config.?.unixSocket);
    try loadIntEnv(u16, "THREADS", &config.?.threads);
    try loadIntEnv(u32, "MAX_JOURNAL_LINES", &config.?.maxJournalLines);
    try loadBooleanEnv("FEATURE_QUERY_JOURNAL", &config.?.features.queryJournal);
}

fn loadBooleanEnv(name: []const u8, target: *bool) ConfigError!void {
    if (std.posix.getenv(name)) |val| {
        if (std.ascii.eqlIgnoreCase(val, "true") or std.ascii.eqlIgnoreCase(val, "yes")) {
            target.* = true;
        } else if (std.ascii.eqlIgnoreCase(val, "false") or std.ascii.eqlIgnoreCase(val, "no")) {
            target.* = false;
        } else {
            log.err("Config variable {s} must be boolean. Allowed values are: true, false, yes, no. Provided value: {s}", .{ name, val });
            return ConfigError.InvalidEnvironmentVariable;
        }
    }
}

fn loadSliceEnv(comptime T: type, name: []const u8, target: *T) void {
    if (std.posix.getenv(name)) |val| {
        target.* = val;
    }
}

fn loadIntEnv(comptime T: type, name: []const u8, target: *T) ConfigError!void {
    if (std.posix.getenv(name)) |val| {
        target.* = std.fmt.parseInt(T, val, 10) catch {
            log.err(
                "{s} enviroment variable must be valid {s} integer. Provided value: {s}",
                .{ name, @typeName(T), val },
            );
            return ConfigError.InvalidEnvironmentVariable;
        };
    }
}

var config: ?Config = null;
var arena: std.heap.ArenaAllocator = undefined;

pub const Config = struct {
    /// host is ignored if unix socket is set
    /// env: HOST
    host: []const u8 = "127.0.0.1",

    /// port is ignored if unix socket is set
    /// env: PORT
    port: u16 = 1337,

    /// If unix socket is not null then host and port are ignored
    /// env: UNIX_SOCKET
    unixSocket: ?[]const u8 = null,

    /// How many threads should be use to handle requests
    /// More threads -> more memory consumtion.
    /// If set to 0 then it will be set to all logical processors
    /// env: THREADS
    threads: u16 = 0,

    /// How many journal lines can single request get at most
    /// To disable limit set it to 0.
    /// Higher value means higher memory usage, I don't recommend setting it above 10000.
    /// env: MAX_JOURNAL_LINES
    maxJournalLines: u32 = 1000,

    /// enable/disable various features
    /// env: FEATURE_<FEATURE>, look below:
    features: Features = .{},
};

pub const Features = struct {
    /// If set to false then /queryJournal endpoint will return 403.
    /// env: FEATURE_QUERY_JOURNAL
    queryJournal: bool = true,
};
