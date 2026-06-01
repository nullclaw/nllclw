const std = @import("std");

pub const FixedWindow = struct {
    limit: u32,
    window_seconds: i64 = 60,
    window_active: bool = false,
    window_start: i64 = 0,
    count: u32 = 0,

    pub fn allow(self: *FixedWindow, now: i64) bool {
        if (self.limit == 0) return true;
        if (!self.window_active or now < self.window_start or elapsed(self.window_start, now) >= self.window_seconds) {
            self.window_active = true;
            self.window_start = now;
            self.count = 0;
        }
        if (self.count >= self.limit) return false;
        self.count += 1;
        return true;
    }
};

fn elapsed(start: i64, now: i64) i64 {
    return std.math.sub(i64, now, start) catch std.math.maxInt(i64);
}

test "fixed window rate limiter resets after window" {
    var limiter: FixedWindow = .{ .limit = 2 };
    try std.testing.expect(limiter.allow(100));
    try std.testing.expect(limiter.allow(101));
    try std.testing.expect(!limiter.allow(102));
    try std.testing.expect(limiter.allow(160));
}

test "fixed window does not treat epoch zero as an inactive sentinel" {
    var limiter: FixedWindow = .{ .limit = 1 };
    try std.testing.expect(limiter.allow(0));
    try std.testing.expect(!limiter.allow(0));
    try std.testing.expect(limiter.allow(60));
}

test "fixed window handles clock rollback and arithmetic extremes" {
    var limiter: FixedWindow = .{ .limit = 1 };
    try std.testing.expect(limiter.allow(std.math.maxInt(i64)));
    try std.testing.expect(limiter.allow(std.math.minInt(i64)));
    try std.testing.expect(!limiter.allow(std.math.minInt(i64)));
}
