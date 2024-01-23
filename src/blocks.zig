const std = @import("std");

/// TODO: rm
var allocator = std.heap.page_allocator;

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

const Inline = zd.Inline;
const InlineType = zd.InlineType;

const Text = zd.Text;
const Link = zd.Link;
// const Image = zd.Image;

const printIndent = zd.printIndent;

/// Generic Block type. The AST is contructed from this type.
pub const BlockType = enum(u8) {
    Container,
    Leaf,
};

// A Block may be a Container or a Leaf
pub const Block = union(BlockType) {
    const Self = @This();
    Container: Container,
    Leaf: Leaf,

    /// Create a new Container of the given type
    pub fn initContainer(alloc: Allocator, kind: ContainerType) Block {
        return .{ .Container = Container.init(alloc, kind) };
    }

    /// Create a new Leaf of the given type
    pub fn initLeaf(alloc: Allocator, kind: LeafType) Block {
        return .{ .Leaf = Leaf.init(alloc, kind) };
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
            inline else => |*b| b.*.close(),
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

    pub fn print(self: Self, depth: u8) void {
        switch (self) {
            inline else => |b| b.print(depth),
        }
    }
};

///////////////////////////////////////////////////////////////////////////////
/// Container Block Implementations
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

        if (self.children.items.len > 0) {
            var child: *Block = &self.children.items[self.children.items.len - 1];
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

///////////////////////////////////////////////////////////////////////////////
/// Leaf Block Implementations
///////////////////////////////////////////////////////////////////////////////

/// All types of Leaf blocks that can be contained in Container blocks
pub const LeafType = enum(u8) {
    Break,
    Code,
    Heading,
    Paragraph,
    // Reference,
};

/// The type-specific content of a Leaf block
pub const LeafData = union(LeafType) {
    Break: Break,
    Code: Code,
    Heading: Heading,
    Paragraph: Paragraph,
    // Reference: Reference,

    pub fn deinit(self: *LeafData) void {
        switch (self.*) {
            .Paragraph => |*p| p.deinit(),
            inline else => {},
        }
    }

    pub fn print(self: LeafData, depth: u8) void {
        switch (self) {
            .Paragraph => |p| p.print(depth),
            inline else => {},
        }
    }
};

/// A single hard line break
pub const Break = struct {};

/// A heading with associated level
pub const Heading = struct {
    level: u8 = 1,
    text: []const u8 = undefined,
};

/// Raw code or other preformatted content
pub const Code = struct {
    language: ?[]const u8 = null,
    text: []const u8 = "",
};

/// Block of multiple sections of formatted text
/// Example:
///   plain and **bold** text, as well as [links](example.com) and `code`
pub const Paragraph = struct {
    const Self = @This();
    alloc: Allocator,
    content: ArrayList(zd.Inline),

    /// Instantiate a Paragraph
    pub fn init(alloc: std.mem.Allocator) Paragraph {
        return .{
            .alloc = alloc,
            .content = ArrayList(zd.Inline).init(alloc),
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Self) void {
        for (self.content.items) |*item| {
            item.deinit();
        }
        self.content.deinit();
    }

    /// Append a chunk of Text to the contents of the Paragraph
    pub fn addText(self: *Self, text: Text) !void {
        try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .text = text }));
    }

    /// Append a Link to the contents Paragraph
    pub fn addLink(self: *Self, link: Link) !void {
        try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .link = link }));
    }

    /// Append an Image to the contents Paragraph
    pub fn addImage(self: *Self, image: zd.Image) !void {
        try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .image = image }));
    }

    /// Append an inline code span to the contents Paragraph
    pub fn addCode(self: *Self, code: zd.Codespan) !void {
        try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .codespan = code }));
    }

    /// Append a line break to the contents Paragraph
    pub fn addBreak(self: *Self) !void {
        try self.content.append(zd.Inline.initWithContent(self.alloc, .{ .newline = {} }));
    }

    /// Append the elements of 'other' to this Paragraph
    pub fn join(self: *Self, other: *Self) void {
        try self.text.appendSlice(other.text.items);
        other.text.deinit();
    }

    /// Pretty-print the Paragraph's contents
    pub fn print(self: Self, depth: u8) void {
        for (self.content.items) |item| {
            item.print(depth);
        }
    }
};

pub const Reference = struct {};

/// A Leaf contains only Inline content
pub const Leaf = struct {
    const Self = @This();
    alloc: Allocator,
    content: LeafData,
    open: bool = true,
    // inlines: ArrayList(Inline),

    pub fn init(alloc: Allocator, kind: LeafType) Leaf {
        var leaf = Leaf{
            .alloc = alloc,
            .content = undefined,
            // .inlines = ArrayList(Inline).init(alloc),
        };

        leaf.content = blk: {
            switch (kind) {
                .Break => break :blk .{ .Break = Break{} },
                .Code => break :blk .{ .Code = Code{} },
                .Heading => break :blk .{ .Heading = Heading{} },
                .Paragraph => break :blk .{ .Paragraph = Paragraph.init(alloc) },
            }
        };

        return leaf;
    }

    pub fn deinit(self: *Self) void {
        self.content.deinit();
        // for (self.inlines.items) |*item| {
        //     item.deinit();
        // }
        // self.inlines.deinit();
    }

    // pub fn addInline(self: *Self, item: Inline) !void {
    //     try self.inlines.append(item);
    // }

    pub fn close(self: *Self) void {
        self.open = false;
    }

    pub fn handleLine(self: *Self, line: []const Token) bool {
        _ = line;
        _ = self;
        return true;
    }

    pub fn print(self: Leaf, depth: u8) void {
        printIndent(depth);

        std.debug.print("Leaf: open: {any}, type: {s}\n", .{
            self.open,
            @tagName(self.content),
        });

        self.content.print(depth + 1);
    }
};

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

// test "CommonMark strategy" {
//     // Setup
//     const text: []const u8 = "# Heading";
//     var alloc = std.testing.allocator;
//     var lexer = Lexer.init(alloc, text);
//     var tokens_array = try lexer.tokenize();
//     defer tokens_array.deinit();
//     var tokens: []Token = tokens_array.items;
//     var cursor: usize = 0;
//
//     // Create empty document; parse first line into the start of a new Block
//     var document = Block.initContainer(alloc, .Document);
//     // defer document.deinit();
//     const first_line = getLine(tokens, cursor);
//     if (first_line == null) {
//         // empty document?
//         return;
//     }
//     cursor += first_line.?.len;
//
//     var open_block = try parseBlockFromLine(first_line.?);
//     try document.addChild(open_block);
//
//     if (first_line.?.len == tokens.len) // Only one line in the text
//         return;
//
//     while (getLine(tokens, cursor)) |line| {
//         // First see if the current open block of the document can accept this line
//         if (!open_block.handleLine(line)) {
//             // This line cannot continue the current open block; close and continue
//             // Close the current open block (child of the Document)
//             open_block.close();
//
//             // Append a new Block to the document
//             open_block = try parseBlockFromLine(line);
//             try document.addChild(open_block);
//         } else {
//             // The line belongs with this block
//             // TODO: Add line to block
//         }
//
//         // This line has been handled, one way or another; continue to the next line
//         cursor += line.len;
//     }
// }

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
        const continues_quote: bool = isContinuationLineQuote(line);
        std.debug.print(" ^-- Could continue a Quote block? {}\n", .{continues_quote});
        cursor += line.len;
    }
}

// ----------------------------------------------------------------------------
// A better, more detailed content model:
//   https://github.com/syntax-tree/mdast?tab=readme-ov-file#content-model
//
// type MdastContent    = FlowContent | ListContent | PhrasingContent
// type Content         = Definition | Paragraph
// type FlowContent     = Blockquote | Code | Heading | Html | List | ThematicBreak | Content
// type ListContent     = ListItem
// type PhrasingContent = Break | Emphasis | Html | Image | ImageReference
//                      | InlineCode | Link | LinkReference | Strong | Text
//
// Node Type: SelfType > ChildType
//   Paragraph:  Content > PhrasingContent
//   Definition: Content > None                     |  [link_A]: https://example.com "Example link"
//   Blockquote: FlowContent > FlowContent
//   Code:       FlowContent > None
//   Heading:    FlowContent > PhrasingContent
//   List:       FlowContent > ListContent
//   ListItem:   ListContent > FlowContent
//   Link:       PhrasingContent > PhrasingContent  |  [Clickme](example.com)
//   LinkRef:    PhrasingContent > None             |  [See Here][link_A]
//   Image:      PhrasingContent > None             |  ![Picture](file.png)
//   ImageRef:   PhrasingContent > None             |  ![Picture][figure_A]
//   InlineCode: PhrasingContent > None             |  `foo()`
//   Break:      PhrasingContent > None
//   Text*:      PhrasingContent > None
//
// *My implementation of Text covers Bold, Strong, Emphasis, etc.
// ----------------------------------------------------------------------------

///////////////////////////////////////////////////////////////////////////////
/// Helper Functions
///////////////////////////////////////////////////////////////////////////////

pub fn printAST(block: Block) void {
    block.print(0);
}

pub fn isContainer(block: Block) bool {
    return block == .Container;
}

pub fn isLeaf(block: Block) bool {
    return block == .Leaf;
}

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

/// Manually create a useful Markdown document AST
fn createTestAst(alloc: Allocator) !Block {
    // Create the Document root
    var root = Block.initContainer(alloc, .Document);

    // Create a List container
    var list = Block.initContainer(alloc, .List);

    // Create a ListItem
    var list_item = Block.initContainer(alloc, .ListItem);

    // Create a Paragraph
    var paragraph = Block.initLeaf(alloc, .Paragraph);

    // Create some Text
    var text1 = Text{ .text = "Hello, " };
    var text2 = Text{ .text = "World", .style = .{ .bold = true } };
    var text3 = Text{ .text = "!" };
    text3.style.bold = true;
    text3.style.italic = true;

    // Create a Link
    var link = zd.Link.init(alloc);
    link.url = "www.google.com";
    try link.text.append(Text{ .text = "Google", .style = .{ .underline = true } });

    // Add the Text and the Link to the Paragraph
    try std.testing.expect(isLeaf(paragraph));
    try paragraph.Leaf.content.Paragraph.addText(text1);
    try paragraph.Leaf.content.Paragraph.addText(text2);
    try paragraph.Leaf.content.Paragraph.addText(text3);
    try paragraph.Leaf.content.Paragraph.addLink(link);

    // Add the Paragraph to the ListItem
    try std.testing.expect(isContainer(list_item));
    try list_item.addChild(paragraph);

    // Add the ListItem to the List
    try std.testing.expect(isContainer(list));
    try list.addChild(list_item);

    // Add the List to the Document
    try root.addChild(list);

    return root;
}

test "Basic AST Construction" {
    std.debug.print("\n", .{});

    var alloc = std.testing.allocator;

    var root = try createTestAst(alloc);
    defer root.deinit();
}

test "Print basic AST" {
    std.debug.print("\n", .{});

    var alloc = std.testing.allocator;

    var root = try createTestAst(alloc);
    defer root.deinit();

    root.print(0);
}

test "Render basic AST" {
    std.debug.print("\n", .{});
    var alloc = std.testing.allocator;

    const stderr = std.io.getStdErr().writer();
    var renderer = htmlRenderer(stderr, alloc);

    var root = try createTestAst(alloc);
    defer root.deinit();

    try renderer.renderBlock(root);
}

const html = @import("render_html.zig");

pub fn htmlRenderer(out_stream: anytype, alloc: Allocator) html.HtmlRenderer(@TypeOf(out_stream)) {
    return html.HtmlRenderer(@TypeOf(out_stream)).init(out_stream, alloc);
}
