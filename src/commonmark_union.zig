const std = @import("std");

var allocator = std.heap.page_allocator;

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("markdown.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

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

pub const InlineType = enum(u8) {
    Autolink,
    Codespan,
    Image,
    Linebreak,
    Link,
    Text,
};

// A Block may be a Container or a Leaf
pub const Block = union(BlockType) {
    const Self = @This();
    Container: ContainerBlock,
    Leaf: LeafBlock,

    /// Convert the given ContainerBlock to a new Block
    pub fn initContainer(container: ContainerBlock) Block {
        return .{ .Container = container };
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
};

pub const Inline = union(InlineType) {
    text: zd.Text,
    codespan: zd.Code,
    image: zd.Image,
    link: zd.Link,
    autolink: zd.Autolink,
    linebreak: void,
};

/// Common data used by all Block types
pub const BlockConfig = struct {
    closed: bool = false, // Whether the block is "closed" or not
    alloc: Allocator,
};

pub const ContainerBlock = union(ContainerBlockType) {
    const Self = @This();
    Document: Document,
    Quote: zd.Quote,
    List: zd.List,

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        _ = self;
        //return switch (self) {
        //    inline else => |*b| b.handleLine(line),
        //};
        return true;
    }
};

pub const LeafBlockNew = union(LeafBlockType) {
    const Self = @This();
    Heading: zd.Heading, // todo
    Code: zd.Code,
    Reference: Reference, // todo
    Paragraph: zd.TextBlock, // todo
    Break: Break, // todo

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        return switch (self.*) {
            //.Code => |*c| c.handleLine(line),
            inline else => true,
        };
    }
};

pub const Document = struct {
    const Self = @This();
    alloc: Allocator,
    blocks: ArrayList(*Block), // TODO: may be able to use 'Block' instead of '*Block'

    pub fn init(alloc: Allocator) Self {
        return .{
            .alloc = alloc,
            .blocks = ArrayList(*Block).init(alloc),
        };
    }

    pub fn handleLine(self: *Self, line: []const Token) !void {
        if (self.blocks.items.len > 0) {
            // Get open node (last block in list)
            var open_block = self.blocks.getLast();
            if (open_block.handleLine(line)) {
                return;
            }
        }

        // Open block did not accept line, or no blocks yet
        // Parse line into new block; append to blocks
        var new_block: *Block = try self.alloc.create(Block);
        new_block.* = try parseNewBlock(line);
        try self.blocks.append(new_block);
    }
};

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
    var document = Document.init(alloc);
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
