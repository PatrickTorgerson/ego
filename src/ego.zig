// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2024 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub const parse = @import("parse.zig");
pub const irgen = @import("irgen.zig");
pub const debugtrace = @import("debugtrace.zig");
pub const AnyWriter = @import("AnyWriter.zig");

test {
    std.testing.refAllDecls(@This());
}

test "fail" {
    std.log.info("testing 1 2 3", .{});
    try std.testing.expectEqualStrings("one", "two");
}
