pub const TSPoint = ts.TSPoint;
pub const TSLanguage = ts.TSLanguage;
pub const TSQueryMatch = ts.TSQueryMatch;

pub const TSParser = struct {
    inner: *ts.TSParser,
    pub fn new() !TSParser {
        return .{
            .inner = ts.ts_parser_new() orelse return error.FailedToCreateTSParser,
        };
    }
    pub fn setLanguage(parser: TSParser, language: *const ts.TSLanguage) !void {
        if (!ts.ts_parser_set_language(parser.inner, language)) return error.FailedToSetLangauge;
    }
    pub fn parseString(parser: TSParser, old_tree: ?TSTree, source: []const u8) !TSTree {
        const tree_ptr = if (old_tree) |t| t.inner else null;
        return .{
            .inner = ts.ts_parser_parse_string(
                parser.inner,
                tree_ptr,
                source.ptr,
                @intCast(source.len),
            ) orelse return error.FailedToParseString,
        };
    }
    const Encoding = enum {
        utf8,
        utf16,
    };
    pub fn parse(
        parser: TSParser,
        old_tree: ?TSTree,
        encoding: Encoding,
        payload: ?*anyopaque,
        callback: *const fn (?*anyopaque, u32, TSPoint, ?*u32) callconv(.C) [*]const u8,
    ) !TSTree {
        const tree_ptr = if (old_tree) |t| t.inner else null;
        const input: ts.TSInput = .{
            .payload = payload,
            .read = callback,
            .encoding = switch (encoding) {
                .utf8 => ts.TSInputEncodingUTF8,
                .utf16 => ts.TSInputEncodingUTF16,
            },
        };
        return .{
            .inner = ts.ts_parser_parse(parser.inner, tree_ptr, input) orelse return error.FailedToParse,
        };
    }
    pub fn delete(parser: TSParser) void {
        ts.ts_parser_delete(parser.inner);
    }
};

pub const TSQuery = struct {
    inner: *ts.TSQuery,
    const E = error{ none, syntax, node_type, field, capture, structure, language };
    pub fn new(language: *const TSLanguage, source: []const u8, error_offset: *u32) E!TSQuery {
        var error_type: ts.TSQueryError = undefined;
        const inner = ts.ts_query_new(language, source.ptr, @intCast(source.len), error_offset, &error_type);
        if (inner) |i| {
            return .{
                .inner = i,
            };
        }
        return switch (error_type) {
            ts.TSQueryErrorNone => error.none,
            ts.TSQueryErrorSyntax => error.syntax,
            ts.TSQueryErrorNodeType => error.node_type,
            ts.TSQueryErrorField => error.field,
            ts.TSQueryErrorCapture => error.capture,
            ts.TSQueryErrorStructure => error.structure,
            ts.TSQueryErrorLanguage => error.language,
            else => unreachable,
        };
    }
    pub fn delete(query: TSQuery) void {
        ts.ts_query_delete(query.inner);
    }
    pub fn captureNameForId(query: TSQuery, index: u32) []const u8 {
        var len: u32 = undefined;
        const str = ts.ts_query_capture_name_for_id(query.inner, index, &len);
        return str[0..len];
    }
};

pub const TSQueryCursor = struct {
    inner: *ts.TSQueryCursor,
    pub fn new() !TSQueryCursor {
        return .{
            .inner = ts.ts_query_cursor_new() orelse return error.FailedToCreateQueryCursor,
        };
    }
    pub fn exec(cursor: *TSQueryCursor, query: TSQuery, node: TSNode) void {
        ts.ts_query_cursor_exec(cursor.inner, query.inner, node.inner);
    }
    pub fn nextMatch(cursor: TSQueryCursor) ?TSQueryMatch {
        var match: TSQueryMatch = undefined;
        if (ts.ts_query_cursor_next_match(cursor.inner, &match)) {
            return match;
        }
        return null;
    }
};

pub const TSTree = struct {
    inner: *ts.TSTree,
    pub fn rootNode(tree: TSTree) TSNode {
        return .{
            .inner = ts.ts_tree_root_node(tree.inner),
        };
    }
    pub fn delete(tree: TSTree) void {
        ts.ts_tree_delete(tree.inner);
    }
};

pub const TSTreeCursor = struct {
    inner: ts.TSTreeCursor,
    pub fn new(node: TSNode) TSTreeCursor {
        return .{
            .inner = ts.ts_tree_cursor_new(node.inner),
        };
    }
    pub fn currentNode(cursor: TSTreeCursor) TSNode {
        return .{
            .inner = ts.ts_tree_cursor_current_node(&cursor.inner),
        };
    }
    pub fn gotoFirstChild(cursor: *TSTreeCursor) bool {
        return ts.ts_tree_cursor_goto_first_child(&cursor.inner);
    }
    pub fn gotoNextSibling(cursor: *TSTreeCursor) bool {
        return ts.ts_tree_cursor_goto_next_sibling(&cursor.inner);
    }
    pub fn gotoParent(cursor: *TSTreeCursor) bool {
        return ts.ts_tree_cursor_goto_parent(&cursor.inner);
    }
};

pub const TSNode = struct {
    inner: ts.TSNode,
    pub fn namedChild(node: TSNode, n: u32) TSNode {
        return .{
            .inner = ts.ts_node_named_child(node.inner, n),
        };
    }
    pub fn @"type"(node: TSNode) [*:0]const u8 {
        return ts.ts_node_type(node.inner);
    }
    pub fn childCount(node: TSNode) u32 {
        return ts.ts_node_child_count(node.inner);
    }
    pub fn namedChildCount(node: TSNode) u32 {
        return ts.ts_node_named_child_count(node.inner);
    }
    pub fn startByte(node: TSNode) u32 {
        return ts.ts_node_start_byte(node.inner);
    }
    pub fn endByte(node: TSNode) u32 {
        return ts.ts_node_end_byte(node.inner);
    }
    pub fn startPoint(node: TSNode) TSPoint {
        return ts.ts_node_start_point(node.inner);
    }
    pub fn endPoint(node: TSNode) TSPoint {
        return ts.ts_node_end_point(node.inner);
    }
    pub fn isNull(node: TSNode) bool {
        return ts.ts_node_is_null(node.inner);
    }
    pub fn string(node: TSNode) [*:0]const u8 {
        return ts.ts_node_string(node.inner);
    }
};

const std = @import("std");
const ts = @import("treesitter-c");
