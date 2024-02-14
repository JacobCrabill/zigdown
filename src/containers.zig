const std = @import("std");

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inlines.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

const printIndent = zd.printIndent;

///////////////////////////////////////////////////////////////////////////////
/// Container Block Implementations
/// TODO: Delete container_types.zig; relocate these to containers.zig
///////////////////////////////////////////////////////////////////////////////

/// Containers are Blocks which contain other Blocks
pub const ContainerType = enum(u8) {
    Document, // The Document is the root container
    Quote,
    List, // Can only contain ListItems
    ListItem, // Can only be contained by a List
};

pub const Quote = struct {
    level: u8 = 0, // TODO: This may be unnecessary
};

/// List blocks contain only ListItems
/// However, we will use the base Container type's 'children' field to
/// store the list items for simplicity, as the ListItems are Container blocks
/// which can hold any kind of Block.
pub const List = struct {
    ordered: bool = false,
    start: usize = 1, // Starting number, if ordered list
    // items: ArrayList(ListItem),
};

/// A ListItem may contain other Containers
pub const ListItem = struct {};

pub const ContainerData = union(ContainerType) {
    Document: void,
    Quote: Quote,
    List: List,
    ListItem: void,
};

/// A Container can contain one or more Blocks
pub const Container = struct {
    const Self = @This();
    alloc: Allocator,
    content: ContainerData,
    open: bool = true,
    children: ArrayList(Block),

    pub fn init(alloc: Allocator, kind: ContainerType) Self {
        var block = Container{
            .alloc = alloc,
            .content = undefined,
            .children = ArrayList(Block).init(alloc),
        };

        block.content = switch (kind) {
            .Document => ContainerData{ .Document = {} },
            .Quote => ContainerData{ .Quote = Quote{} },
            .List => ContainerData{ .List = List{} },
            .ListItem => ContainerData{ .ListItem = {} },
        };

        return block;
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Self, child: Block) !void {
        try self.children.append(child);
    }

    pub fn close(self: *Self) void {
        self.open = false;
    }

    pub fn handleLine(self: *Self, line: []const Token) bool {
        //
        // KINDA NEW PLAN - I'm going to need a slightly different parser fn
        // for each Block type.
        // CASE IN POINT - a List block may _only_ contain ListItem blocks.
        // Also, we need to handle Container and Leaf blocks differently.
        //
        // Many blocks should contain similar logic, but not identical.

        // First, check if the line is valid for our block type, as a
        // continuation line of our open child, or as the start of a new child
        // block

        // If the line is a valid continuation line for our type, trim the continuation
        // marker(s) off and pass it on to our last child
        // e.g.:  line         = "   > foo bar" [ indent, GT, space, word, space, word ]
        //        trimmed_line = "foo bar"  [ word, space, word ]
        var trimmed_line = line;
        if (self.isContinuationLine(line))
            trimmed_line = self.trimContinuationMarkers(line);

        // Next, check if the trimmed line
        if (!self.isLazyContinuationLine(trimmed_line))
            return false;

        // Check for an open child
        if (self.children.items.len > 0) {
            var child: *Block = &self.children.items[self.children.items.len - 1];
            if (child.handleLine(trimmed_line)) {
                return true;
            } else {
                // child.close(); // TODO
            }
        } else {
            // Child did not accept this line (or no children yet)
            // Determine which kind of Block this line should be (if we're a Container)
            // If we're a leaf, instead parse inlines...?
            if (startsNewBlock(trimmed_line)) |new_block_type| {
            const child = parseBlockFromLine(self.alloc, trimmed_line);
            try self.children.append(child);
            }
        }

        return true;

        // TODO

        // If the returned type is not a valid child type, return false to
        // indicate that our parent should handle it
        // return false;
    }

    pub fn isContinuationLine(self: *Self, line: []const Token) bool {
        _ = self;
        _ = line;
        return true;
    }

    pub fn isLazyContinuationLine(self: *Self, line: []const Token) bool {
        _ = self;
        _ = line;
        return true;
    }

    pub fn trimContinuationMarkers(self: *Self, line: []const Token) []const Token {
        return switch (self.kind) {
            .Quote => self.trimContinuationMarkersQuote(line),
            else => line,
        };
    }

    pub fn trimContinuationMarkersQuote(self: *Self, line: []const Token) []const Token {
        _ = self;
        var start: usize = 0;
        for (line, 0..) |tok, i| {
            if (!(tok.kind == .GT or tok.kind == .SPACE or tok.kind == .INDENT)) {
                start = i;
                break;
            }
        }
        return line[start..line.len];
    }

    pub fn print(self: Container, depth: u8) void {
        printIndent(depth);

        std.debug.print("Container: open: {any}, type: {s} with {d} children\n", .{
            self.open,
            @tagName(self.content),
            self.children.items.len,
        });

        for (self.children.items) |child| {
            child.print(depth + 1);
        }
    }
};
