const std = @import("std");
pub const Command = struct {
    args: type,
};
pub fn Optional(T: type) type {
    var fields = (@typeInfo(T).@"struct".fields ++ .{}).*;
    for (&fields) |*field| {
        field.type = ?field.type;
    }
    return @Type(.{
        .@"struct" = .{
            .fields = &fields,
            .layout = .auto,
            .decls = &.{},
            .is_tuple = false,
        },
    });
}
pub fn allNullOptional(T: type) Optional(T) {
    var ret: Optional(T) = undefined;
    inline for (@typeInfo(Optional(T)).@"struct".fields) |f| {
        @field(ret, f.name) = null;
    }
    return ret;
}
pub fn parse(Args: type, on: Optional(Args), input: []const [:0]const u8, arena: std.mem.Allocator, failing_arg: ?*usize) !Optional(Args) {
    var args = allNullOptional(Args);
    const Fields = std.meta.FieldEnum(Args);
    for (input, 0..) |arg, i| {
        if (!std.mem.startsWith(u8, arg, "--")) return error.UnknownArgument;
        const trimarg = arg[2..];
        const split = std.mem.indexOfScalar(u8, trimarg, '=');

        switch (std.meta.stringToEnum(Fields, if (split) |s| trimarg[0..s] else trimarg) orelse {
            if (failing_arg) |f| f.* = i;
            return error.UnknownArgument;
        }) {
            inline else => |e| {
                @field(args, @tagName(e)) = if (split) |s| std.zon.parse.fromSlice(@FieldType(Args, @tagName(e)), arena, trimarg[s + 1 ..], null, .{}) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    else => {
                        if (failing_arg) |f| f.* = i;
                        return error.BadArgumentPayload;
                    },
                } else @field(on, @tagName(e)) orelse {
                    if (failing_arg) |f| f.* = i;
                    return error.BadArgumentPayload;
                };
            },
        }
    }
    return args;
}
test "parsing an arg" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const args: []const [:0]const u8 = &.{"--name=\"different\""};
    const Args = struct {
        name: []const u8,
    };
    const parsed = try parse(Args, .{ .name = "same" }, args, arena.allocator(), null);
    try std.testing.expectEqualStrings("different", parsed.name.?);
}
test "no on value arg" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const args: []const [:0]const u8 = &.{"--i=100"};
    const Args = struct {
        i: usize,
    };
    const parsed = try parse(Args, allNullOptional(Args), args, arena.allocator(), null);
    try std.testing.expectEqual(100, parsed.i.?);
}
