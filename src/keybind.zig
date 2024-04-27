pub const normal_keybinds = [_]KeyBind{
    bind("i", .none, normal.enterInsertMode),
    bind("a", .none, normal.enterInsertModeAfter),
    bind("x", .none, normal.deleteChar),
    bind("h", .none, all.cursorLeft),
    bind("j", .none, all.cursorDown),
    bind("k", .none, all.cursorUp),
    bind("l", .none, all.cursorRight),
    bind("<C-w>", .key, normal.windowNamespace),
    bind("c", .text_object, normal.change),
    bind("d", .text_object, normal.delete),
    bind(":", .none, normal.enterCommandMode),
};
pub const command_keybinds = [_]KeyBind{
    bind("<C-b>", .none, all.cursorLeft),
    bind("<C-f>", .none, all.cursorRight),
    bind("CR", .none, command.runCommand),
    bind("ESC", .none, command.enterNormalMode),
};
pub const insert_keybinds = [_]KeyBind{
    bind("ESC", .none, insert.enterNormalMode),
    bind("<C-c>", .none, insert.enterNormalMode),
    bind("<C-w>", .none, insert.deleteWord),
};

const KeybindFuncArgumentFlavor = union(enum) {
    none,
    key,
    text_object,
};

fn parseKey(comptime s: []const u8) Key {
    assert(s.len > 0);
    if (s.len == 1) {
        const char = s[0];
        return .{
            .codepoint = @enumFromInt(std.ascii.toLower(char)),
            .modifiers = .{
                .shift = std.ascii.isUpper(char),
            },
        };
    } else {
        // modifier
        if (s[0] == '<') {
            assert(s[s.len - 1] == '>');
            const inner_str = s[1 .. s.len - 1];
            const modifier_char = inner_str[0];
            var modifiers = Modifiers{};
            switch (modifier_char) {
                'C' => modifiers.ctrl = true,
                'A' => modifiers.alt = true,
                'S' => modifiers.super = true,
                else => unreachable,
            }
            assert(inner_str[1] == '-');
            const codepoint_str = inner_str[2..];
            const is_upper, const codepoint = parseCodepoint(codepoint_str);
            modifiers.shift = is_upper;
            return .{
                .codepoint = codepoint,
                .modifiers = modifiers,
            };
            // special
        } else {
            return .{ .codepoint = std.meta.stringToEnum(Codepoint, s).? };
        }
    }
}

fn parseCodepoint(codepoint_str: []const u8) struct { bool, Codepoint } {
    // check if it's a special keyword
    if (std.meta.stringToEnum(Codepoint, codepoint_str)) |special_codepoint| return .{
        false, @bitCast(
            special_codepoint,
        ),
    };
    assert(codepoint_str.len == 1);
    const codepoint = codepoint_str[0];
    assert(codepoint <= 0xFF);
    return .{
        std.ascii.isUpper(@intCast(codepoint)),
        @enumFromInt(std.ascii.toLower(@intCast(codepoint))),
    };
}

pub const Codepoint = enum(u21) {
    ESC = vaxis.Key.escape,
    CR = vaxis.Key.enter,
    BS = vaxis.Key.backspace,
    _,
};
pub const Key = packed struct {
    codepoint: Codepoint,
    modifiers: Modifiers = .{},
    pub fn fromVaxisKey(key: vaxis.Key) Key {
        return .{
            .modifiers = key.mods,
            .codepoint = @enumFromInt(key.codepoint),
        };
    }
    pub fn getUniqueId(key: Key) std.meta.Int(.unsigned, @bitSizeOf(Key)) {
        return @bitCast(key);
    }
    pub fn getUniqueIdFromString(comptime s: []const u8) std.meta.Int(.unsigned, @bitSizeOf(Key)) {
        const key = parseKey(s);
        return @bitCast(key);
    }
};

fn bind(comptime s: []const u8, comptime arg_flavor: KeybindFuncArgumentFlavor, comptime func: anytype) KeyBind {
    const key = parseKey(s);
    return KeyBind.init(key, arg_flavor, &func);
}

const KeyBind = struct {
    key: Key,
    arg_flavor: KeybindFuncArgumentFlavor,
    function: *const anyopaque,
    pub fn init(key: Key, comptime arg_flavor: KeybindFuncArgumentFlavor, func: anytype) KeyBind {
        const func_type = std.meta.Child(@TypeOf(func));
        switch (arg_flavor) {
            .none => assert(func_type == KeyBindFunctionNoArgs),
            .key => assert(func_type == KeyBindFunctionKeyArg),
            .text_object => assert(func_type == KeyBindFunctionTextObjectArg),
        }
        return .{
            .key = key,
            .arg_flavor = arg_flavor,
            .function = func,
        };
    }
};

pub const TextObject = union(enum) {
    word,
    letter,
    end_of_line,
    full_line,
    find_until: u8,
    find_including: u8,
};

const KeyBindHandlerState = union(enum) {
    waiting_for_key_arg,
    waiting_for_text_object: std.BoundedArray(u8, MAX_TEXT_OBJECT_LEN),
    waiting_for_keybinding,
};
pub const KeyBindHandler = struct {
    state: KeyBindHandlerState = .waiting_for_keybinding,
    function: *const anyopaque = undefined,
    pub fn handleKeyPress(kbh: *KeyBindHandler, ctx: *Ctx, allocator: Allocator, key: Key) !enum { consumed, not_consumed } {
        switch (kbh.state) {
            .waiting_for_text_object => |*cur| {
                const function: *const KeyBindFunctionTextObjectArg = @alignCast(@ptrCast(kbh.function));
                const cp = @intFromEnum(key.codepoint);
                // not a valid codepoint for a text object, so fail here
                if (cp > 0xFF) {
                    kbh.state = .waiting_for_keybinding;
                    kbh.function = undefined;
                }
                cur.append(@intCast(cp)) catch unreachable;

                const current_str = cur.slice();
                const last_char_idx = current_str.len - 1;
                var found_partial = false;
                const text_object_strs = std.meta.fields(TextObjectTextRepresentation);
                inline for (text_object_strs) |text_object| {
                    const str = text_object.name;
                    if (str[last_char_idx] == current_str[last_char_idx]) {
                        // if this was the last character of the text object
                        if (last_char_idx + 1 == str.len) {
                            const text_object_tag: std.meta.Tag(TextObject) = @enumFromInt(text_object.value);
                            const actual_text_object = @unionInit(TextObject, @tagName(text_object_tag), {});
                            try function(ctx, allocator, actual_text_object);
                            kbh.state = .waiting_for_keybinding;
                            kbh.function = undefined;
                        }
                        found_partial = true;
                        break;
                    }
                }
                // it doesn't match any text objects
                if (!found_partial) {
                    kbh.state = .waiting_for_keybinding;
                    kbh.function = undefined;
                }
            },
            .waiting_for_key_arg => {
                const function: *const KeyBindFunctionKeyArg = @alignCast(@ptrCast(kbh.function));
                try function(ctx, allocator, key);
                kbh.state = .waiting_for_keybinding;
                kbh.function = undefined;
            },
            .waiting_for_keybinding => {
                const available_bindings = switch (ctx.mode) {
                    .normal => &normal_keybinds,
                    .insert => &insert_keybinds,
                    .command => &command_keybinds,
                };

                for (available_bindings) |binding| {
                    if (std.meta.eql(binding.key, key)) {
                        switch (binding.arg_flavor) {
                            .key => {
                                kbh.state = .waiting_for_key_arg;
                                kbh.function = binding.function;
                            },
                            .text_object => {
                                kbh.state = .{ .waiting_for_text_object = .{} };
                                kbh.function = binding.function;
                            },
                            .none => {
                                const function: *const KeyBindFunctionNoArgs = @alignCast(@ptrCast(binding.function));
                                try function(ctx, allocator);
                            },
                        }
                        break;
                    }
                } else {
                    return .not_consumed;
                }
            },
        }
        return .consumed;
    }
};

const TextObjectTextRepresentation = blk: {
    const TextObjectEnum = std.meta.Tag(TextObject);
    const typeinfo = @typeInfo(TextObjectEnum).Enum;
    var fields = std.BoundedArray(std.builtin.Type.EnumField, typeinfo.fields.len){};
    for (typeinfo.fields) |field| {
        const name = switch (@field(TextObject, field.name)) {
            .word => "w",
            .letter => "l",
            .end_of_line => "$",
            .full_line, .find_until, .find_including => continue,
        };
        fields.append(.{
            .name = name,
            .value = field.value,
        }) catch unreachable;
    }
    break :blk @Type(.{
        .Enum = .{
            .tag_type = typeinfo.tag_type,
            .fields = fields.slice(),
            .decls = &.{},
            .is_exhaustive = true,
        }
    });
};

const MAX_TEXT_OBJECT_LEN = blk: {
    var max = 0;
    for (@typeInfo(TextObjectTextRepresentation).Enum.fields) |text_object| {
        const len = text_object.name.len;
        if (len > max) max = len;
    }
    break :blk max;
};

const ErrSet = error{OutOfMemory};
const KeyBindFunctionNoArgs = fn (*Ctx, Allocator) ErrSet!void;
const KeyBindFunctionKeyArg = fn (*Ctx, Allocator, Key) ErrSet!void;
const KeyBindFunctionTextObjectArg = fn (*Ctx, Allocator, TextObject) ErrSet!void;
const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const vaxis = @import("vaxis");
const Modifiers = vaxis.Key.Modifiers;
const Ctx = @import("Ctx.zig");

const insert = @import("keybindings/insert.zig");
const normal = @import("keybindings/normal.zig");
const command = @import("keybindings/command.zig");
const all = @import("keybindings/all.zig");
