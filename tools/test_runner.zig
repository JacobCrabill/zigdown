//! Custom test runner that displays all test results
//! Courtesy of: https://gist.github.com/karlseguin/c6bea5b35e4e8d26af6f81c22cb5d76b
const std = @import("std");
const builtin = @import("builtin");

const Allocator = std.mem.Allocator;

const BORDER = "=" ** 80;

// use in custom panic handler
var current_test: ?[]const u8 = null;

pub fn main(init: std.process.Init) !void {
    var mem: [8192]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&mem);
    const allocator = fba.allocator();
    const io = init.io;

    const env = Env.initFromMap(init.environ_map);

    var slowest = SlowTracker.init(io, allocator, 5);
    defer slowest.deinit();

    var pass: usize = 0;
    var fail: usize = 0;
    var skip: usize = 0;
    var leak: usize = 0;

    var printer = Printer.init(io);
    printer.fmt("\r\x1b[0K", .{}); // beginning of line and clear to end of line

    for (builtin.test_functions, 0..) |t, idx| {
        if (isSetup(t)) {
            current_test = friendlyName(t.name);
            t.func() catch |err| {
                printer.status(.fail, "\n[{d}] setup \"{s}\" failed: {}\n", .{ idx, t.name, err });
                return err;
            };
        }
    }

    for (builtin.test_functions, 0..) |t, idx| {
        if (isSetup(t) or isTeardown(t)) {
            continue;
        }

        var status = Status.pass;
        slowest.startTiming();

        const is_unnamed_test = isUnnamed(t);
        if (env.filter) |f| {
            if (!is_unnamed_test and std.mem.indexOf(u8, t.name, f) == null) {
                continue;
            }
        }

        const friendly_name = friendlyName(t.name);
        current_test = friendly_name;
        std.testing.allocator_instance = .{};
        const result = t.func();
        current_test = null;

        if (is_unnamed_test) {
            continue;
        }

        const ns_taken = slowest.endTiming(friendly_name);

        if (std.testing.allocator_instance.deinit() == .leak) {
            leak += 1;
            printer.status(.fail, "\n{s}\n[{d}] \"{s}\" - Memory Leak\n{s}\n", .{ BORDER, idx, friendly_name, BORDER });
        }

        if (result) |_| {
            pass += 1;
        } else |err| switch (err) {
            error.SkipZigTest => {
                skip += 1;
                status = .skip;
            },
            else => {
                status = .fail;
                fail += 1;
                printer.status(.fail, "\n{s}\n[{d}] \"{s}\" - {s}\n{s}\n", .{ BORDER, idx, friendly_name, @errorName(err), BORDER });
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpErrorReturnTrace(trace);
                }
                if (env.fail_first) {
                    break;
                }
            },
        }

        if (env.verbose) {
            const ms = @as(f64, @floatFromInt(ns_taken)) / 1_000_000.0;
            printer.status(status, "[{d}] {s} ({d:.2}ms)\n", .{ idx, friendly_name, ms });
        } else {
            printer.status(status, "[{d}]", .{idx});
        }
    }

    for (builtin.test_functions) |t| {
        if (isTeardown(t)) {
            current_test = friendlyName(t.name);
            t.func() catch |err| {
                printer.status(.fail, "\nteardown \"{s}\" failed: {}\n", .{ t.name, err });
                return err;
            };
        }
    }

    const total_tests = pass + fail;
    const status = if (fail == 0) Status.pass else Status.fail;
    printer.status(status, "\n{d} of {d} test{s} passed\n", .{ pass, total_tests, if (total_tests != 1) "s" else "" });
    if (skip > 0) {
        printer.status(.skip, "{d} test{s} skipped\n", .{ skip, if (skip != 1) "s" else "" });
    }
    if (leak > 0) {
        printer.status(.fail, "{d} test{s} leaked\n", .{ leak, if (leak != 1) "s" else "" });
    }
    printer.fmt("\n", .{});
    try slowest.display(&printer);
    printer.fmt("\n", .{});
    std.process.exit(if (fail == 0) 0 else 1);
}

fn friendlyName(name: []const u8) []const u8 {
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |value| {
        if (std.mem.eql(u8, value, "test")) {
            const rest = it.rest();
            return if (rest.len > 0) rest else name;
        }
    }
    return name;
}

const Printer = struct {
    io: std.Io,
    stdout: std.Io.File,
    buf: [256]u8,

    fn init(io: std.Io) Printer {
        return .{
            .io = io,
            .stdout = std.Io.File.stdout(),
            .buf = undefined,
        };
    }

    fn fmt(self: *Printer, comptime format: []const u8, args: anytype) void {
        var stdout_writer = self.stdout.writer(self.io, &self.buf);
        stdout_writer.interface.print(format, args) catch unreachable;
        stdout_writer.flush() catch {};
    }

    fn status(self: *Printer, s: Status, comptime format: []const u8, args: anytype) void {
        var stdout_writer = self.stdout.writer(self.io, &self.buf);
        var writer = &stdout_writer.interface;
        const color = switch (s) {
            .pass => "\x1b[32m",
            .fail => "\x1b[31m",
            .skip => "\x1b[33m",
            else => "",
        };
        writer.writeAll(color) catch @panic("writeAll failed?!");
        writer.print(format, args) catch @panic("std.fmt.format failed?!");
        writer.writeAll("\x1b[0m") catch @panic("write failed?!");
        stdout_writer.flush() catch {};
    }
};

const Status = enum {
    pass,
    fail,
    skip,
    text,
};

/// A simple timer using std.Io.Clock for monotonic timing.
pub const Timer = struct {
    io: std.Io,
    timestamp: std.Io.Timestamp,

    pub fn start(io: std.Io) Timer {
        return .{
            .io = io,
            .timestamp = std.Io.Clock.awake.now(io),
        };
    }

    pub fn reset(timer: *Timer) void {
        timer.timestamp = std.Io.Clock.awake.now(timer.io);
    }

    pub fn lap(timer: *Timer) u64 {
        const elapsed = timer.timestamp.untilNow(timer.io, .awake);
        timer.reset();
        return @intCast(@max(0, elapsed.nanoseconds));
    }

    pub fn read(timer: *Timer) f64 {
        const elapsed = timer.timestamp.untilNow(timer.io, .awake);
        const t: f64 = @floatFromInt(elapsed.nanoseconds);
        return t / std.time.ns_per_s;
    }
};

const SlowTracker = struct {
    const SlowestQueue = std.PriorityDequeue(TestInfo, void, compareTiming);
    max: usize,
    allocator: Allocator,
    slowest: SlowestQueue,
    timer: Timer,

    fn init(io: std.Io, allocator: Allocator, count: u32) SlowTracker {
        const timer = Timer.start(io);
        var slowest = SlowestQueue.initContext({});
        slowest.ensureTotalCapacity(allocator, count) catch @panic("OOM");
        return .{
            .max = count,
            .allocator = allocator,
            .timer = timer,
            .slowest = slowest,
        };
    }

    const TestInfo = struct {
        ns: u64,
        name: []const u8,
    };

    fn deinit(self: *SlowTracker) void {
        self.slowest.deinit(self.allocator);
    }

    fn startTiming(self: *SlowTracker) void {
        self.timer.reset();
    }

    fn endTiming(self: *SlowTracker, test_name: []const u8) u64 {
        const ns = self.timer.lap();
        const allocator = self.allocator;

        if (self.slowest.count() < self.max) {
            // Capacity is fixed to the # of slow tests we want to track
            // If we've tracked fewer tests than this capacity, than always add
            self.slowest.push(allocator, TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
            return ns;
        }

        {
            // Optimization to avoid shifting the dequeue for the common case
            // where the test isn't one of our slowest.
            const fastest_of_the_slow = self.slowest.peekMin() orelse unreachable;
            if (fastest_of_the_slow.ns > ns) {
                // the test was faster than our fastest slow test, don't add
                return ns;
            }
        }

        // The previous fastest of our slow tests has been pushed off.
        _ = self.slowest.popMin();
        self.slowest.push(allocator, TestInfo{ .ns = ns, .name = test_name }) catch @panic("failed to track test timing");
        return ns;
    }

    fn display(self: *SlowTracker, printer: *Printer) !void {
        const count = self.slowest.count();
        printer.fmt("Slowest {d} test{s}: \n", .{ count, if (count != 1) "s" else "" });
        while (self.slowest.popMin()) |info| {
            const ms = @as(f64, @floatFromInt(info.ns)) / 1_000_000.0;
            printer.fmt("  {d:.2}ms\t{s}\n", .{ ms, info.name });
        }
    }

    fn compareTiming(context: void, a: TestInfo, b: TestInfo) std.math.Order {
        _ = context;
        return std.math.order(a.ns, b.ns);
    }
};

const Env = struct {
    verbose: bool,
    fail_first: bool,
    filter: ?[]const u8,

    fn initFromMap(map: *const std.process.Environ.Map) Env {
        return .{
            .verbose = getBool(map, "TEST_VERBOSE", true),
            .fail_first = getBool(map, "TEST_FAIL_FIRST", false),
            .filter = map.get("TEST_FILTER"),
        };
    }

    fn getBool(map: *const std.process.Environ.Map, key: []const u8, default: bool) bool {
        const val = map.get(key) orelse return default;
        return std.ascii.eqlIgnoreCase(val, "true");
    }
};

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    if (current_test) |ct| {
        std.debug.print("\x1b[31m{s}\npanic running \"{s}\"\n{s}\x1b[0m\n", .{ BORDER, ct, BORDER });
    }
    _ = error_return_trace;
    std.debug.defaultPanic(msg, ret_addr);
}

fn isUnnamed(t: std.builtin.TestFn) bool {
    const marker = ".test_";
    const test_name = t.name;
    const index = std.mem.indexOf(u8, test_name, marker) orelse return false;
    _ = std.fmt.parseInt(u32, test_name[index + marker.len ..], 10) catch return false;
    return true;
}

fn isSetup(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:beforeAll");
}

fn isTeardown(t: std.builtin.TestFn) bool {
    return std.mem.endsWith(u8, t.name, "tests:afterAll");
}
