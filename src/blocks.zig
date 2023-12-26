const std = @import("std");

/// TODO: rm
var allocator = std.heap.page_allocator;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inline.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

const InlineType = zd.InlineType;

pub const BlockType = enum(u8) {
    Container,
    Leaf,
};

pub const ContainerBlockType = enum(u8) {
    Document, // The Document is the root container
    Quote,
    List, // Can only contain ListItems
    ListItem, // Can only be contained by a List
};

pub const LeafBlockType = enum(u8) {
    Break,
    Code,
    Heading,
    Paragraph,
    Reference,
};

// A Block may be a Container or a Leaf
pub const Block = union(BlockType) {
    const Self = @This();
    Container: ContainerBlock,
    Leaf: LeafBlock,

    /// Convert the given ContainerBlock to a new Block
    pub fn initContainer(alloc: Allocator, kind: ContainerBlockType) Block {
        return .{ .Container = ContainerBlock.init(alloc, kind) };
    }

    /// Convert the given LeafBlock to a new Block
    pub fn initLeaf(leaf: LeafBlock) Block {
        return .{ .Leaf = leaf };
    }

    pub fn deinit(self: *Block) void {
        switch (self.*) {
            inline else => |*b| b.deinit(),
        }
    }

    pub fn handleLine(self: *Self, line: []const Token) bool {
        return switch (self.*) {
            inline else => |*b| b.handleLine(line),
        };
    }

    pub fn close(self: *Self) void {
        switch (self.*) {
            inline else => |*b| b.close(),
        }
    }

    pub fn addChild(self: *Self, child: Block) !void {
        switch (self.*) {
            .Leaf => return error.NotAContainer,
            .Container => |*c| try c.addChild(child),
        }
    }

    pub fn addInline(self: *Self, item: Inline) !void {
        switch (self.*) {
            .Container => return error.NotALeaf,
            .Leaf => |*c| try c.addInline(item),
        }
    }
};

/// Common data used by all Block types
pub const BlockConfig = struct {
    closed: bool = false, // Whether the block is "closed" or not
    alloc: Allocator,
};

pub const Inline = struct {
    const Self = @This();
    alloc: Allocator,
    kind: InlineType,
    closed: bool = false,
    contents: ArrayList([]Token), // List of Token slices comprising the block's contents

    pub fn init(alloc: Allocator, kind: InlineType) !Inline {
        return .{
            .alloc = alloc,
            .kind = kind,
            .contents = try ArrayList([]Token).init(alloc),
        };
    }
};

/// A ContainerBlock can contain one or more Blocks (Container OR Leaf)
pub const ContainerBlock = struct {
    const Self = @This();
    alloc: Allocator,
    kind: ContainerBlockType,
    closed: bool = false,
    children: ArrayList(Block),

    pub fn init(alloc: Allocator, kind: ContainerBlockType) Self {
        return .{
            .alloc = alloc,
            .kind = kind,
            .children = ArrayList(Block).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.children.items) |child| {
            child.deinit();
            // TODO: Need to free all children, or no?
            self.alloc.destroy(child);
        }
        self.children.deinit();
    }

    pub fn addChild(self: *Self, child: Block) !void {
        try self.children.append(child);
    }

    pub fn handleLine(self: *Self, line: []const Token) bool {
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

        if (self.children.getLastOrNull()) |child| {
            if (child.handleLine(trimmed_line)) {
                return true;
            } else {
                // child.close(); // TODO
            }
        }
        // Child did not accept this line (or no children yet)
        // Determine which kind of Block this line should be

        // TODO

        // If the returned type is not a valid child type, return false to
        // indicate that our parent should handle it
        return false;
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
};

/// A LeafBlock contains only Inlines
pub const LeafBlock = struct {
    const Self = @This();
    alloc: Allocator,
    kind: LeafBlockType,
    closed: bool = false,
    inlines: ArrayList(Inline),

    pub fn init(alloc: Allocator, kind: LeafBlockType) LeafBlock {
        return .{
            .alloc = alloc,
            .kind = kind,
            .inlines = ArrayList(Inline).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.inlines.items) |item| {
            item.deinit();
        }
        self.inlines.deinit();
    }

    pub fn addInline(self: *Self, item: Inline) !void {
        try self.inlines.append(item);
    }

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        _ = self;
        return true;
    }
};

////////////////////////////////////////////////////////////////////////////////
// Custom data for specific subtypes
////////////////////////////////////////////////////////////////////////////////

pub const Reference = struct {};
pub const Break = struct {};

pub const Quote = struct {
    level: u8 = 0,
    text: Text = undefined,
    config: BlockConfig = undefined,
};

pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
    strike: bool = false,
};

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    style: TextStyle = TextStyle{},
    text: []const u8 = undefined,
};

////////////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////

test "CommonMark strategy" {
    // Setup
    const text: []const u8 = "# Heading";
    var alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, text);
    var tokens_array = try lexer.tokenize();
    defer tokens_array.deinit();
    var tokens: []Token = tokens_array.items;
    var cursor: usize = 0;

    // Create empty document; parse first line into the start of a new Block
    var document = Block.initContainer(alloc, .Document);
    // defer document.deinit();
    const first_line = getLine(tokens, cursor);
    if (first_line == null) {
        // empty document?
        return;
    }
    cursor += first_line.?.len;

    var open_block: *Block = try alloc.create(Block);
    open_block.* = try parseBlockFromLine(first_line.?);
    try document.blocks.append(open_block);

    if (first_line.?.len == tokens.len) // Only one line in the text
        return;

    while (getLine(tokens, cursor)) |line| {
        // First see if the current open block of the document can accept this line
        if (!open_block.handleLine(line)) {
            // This line cannot continue the current open block; close and continue
            // Close the current open block (child of the Document)
            open_block.close();

            // Append a new Block to the document
            open_block = try alloc.create(Block);
            open_block.* = try parseBlockFromLine(line);
            try document.blocks.append(open_block);
        } else {
            // The line belongs with this block
            // TODO: Add line to block
        }

        // This line has been handled, one way or another; continue to the next line
        cursor += line.len;
    }
}

//////////////////////////////////////////////////////////////////////////

/// Return the index of the next BREAK token, or EOF
fn nextBreak(tokens: []Token, idx: usize) usize {
    if (idx >= tokens.len)
        return tokens.len;

    for (tokens[idx..], idx..) |tok, i| {
        if (tok.kind == .BREAK)
            return i;
    }

    return tokens.len;
}

// Return a slice of the tokens from the cursor to the next line break (or EOF)
fn getLine(tokens: []Token, cursor: usize) ?[]Token {
    if (cursor >= tokens.len) return null;
    const end = @min(nextBreak(tokens, cursor) + 1, tokens.len);
    return tokens[cursor..end];
}

/// Given a raw line of Tokens, determine what kind of Block should be created
fn parseBlockFromLine(line: []Token) !Block {
    _ = line;
    //return .{ .Leaf = .{ .break = zd.Break{}, }, };
    return error.Unimplemented;
}

/// Check if the given line is a continuation line for a Quote block
fn isContinuationLineQuote(line: []const Token) bool {
    // if the line follows the pattern: [ ]{0,1,2,3}[>]+
    //    (0 to 3 leading spaces followed by at least one '>')
    // then it can be part of the current Quote block.
    //
    // Otherwise, if it is Paragraph lazy continuation line,
    // it can also be a part of the Quote block
    var leading_ws: u8 = 0;
    for (line) |tok| {
        switch (tok.kind) {
            .SPACE => leading_ws += 1,
            .INDENT => leading_ws += 2,
            .GT, .WORD, .BREAK => return true,
            else => return false,
        }

        if (leading_ws > 3)
            return false;
    }

    return false;
}

/// Check if the given line is a continuation line for a paragraph
fn isContinuationLineParagraph(line: []const Token) bool {
    if (line.len == 0) return true;

    for (line) |tok| {
        switch (tok.kind) {
            .SPACE, .INDENT => {},
            .GT, .PLUS, .MINUS => return false,
            else => return true,
        }
    }
    return true;
}

test "Quote block continuation lines" {
    const data =
        \\# Header!
        \\## Header 2
        \\### Header 3...
        \\#### ...and Header 4
        \\
        \\  some *generic* text _here_, with formatting!
        \\  including ***BOLD italic*** text!
        \\  Note that the renderer should automaticallly wrap text for us
        \\  at some parameterizeable wrap width
        \\
        \\after the break...
        \\
        \\> Quote line
        \\> Another quote line
        \\> > And a nested quote
        \\
        \\```
        \\code
        \\```
        \\
        \\And now a list:
        \\
        \\+ foo
        \\+ fuzz
        \\    + no indents yet
        \\- bar
        \\
        \\
        \\1. Numbered lists, too!
        \\2. 2nd item
        \\2. not the 2nd item
    ;

    var alloc = std.testing.allocator;
    var lexer = Lexer.init(alloc, data);
    var tokens = try lexer.tokenize();
    defer tokens.deinit();

    // Now process every line!
    var cursor: usize = 0;
    while (getLine(tokens.items, cursor)) |line| {
        zd.printTypes(line);
        const continues: bool = isContinuationLineQuote(line);
        std.debug.print(" ^-- Could continue a Quote block? {}\n", .{continues});
        cursor += line.len;
    }
}

// TODO:
// Refactor from Sections to Blocks and Inlines
// See: https://spec.commonmark.org/0.30/#blocks-and-inlines
// Blocks: Container or Leaf
//   Leaf Blocks:
//     - Breaks
//     - Code blocks
//     - Headings
//     - Paragraph ('Text')
//     - Link reference definition (e.g. [foo]: url "title")
//   Container Blocks:
//     - Quote
//     - List (ordered or bullet)
//     - List items
// Inlines:
//   - Styled text:
//     - Italic
//     - Bold
//     - Underline
//   - Code span
//   - Links (e.g. [text](url))
//   - Images
//   - Autolinks (e.g. <google.com>)
//   - Line breaks
