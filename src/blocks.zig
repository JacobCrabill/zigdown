const std = @import("std");

const zd = struct {
    usingnamespace @import("utils.zig");
    usingnamespace @import("tokens.zig");
    usingnamespace @import("lexer.zig");
    usingnamespace @import("inlines.zig");
    usingnamespace @import("leaves.zig");
    usingnamespace @import("containers.zig");
};

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Lexer = zd.Lexer;
const TokenType = zd.TokenType;
const Token = zd.Token;
const TokenList = zd.TokenList;

const ContainerType = zd.ContainerType;
const ContainerData = zd.ContainerData;
const LeafType = zd.LeafType;
const LeafData = zd.LeafData;

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

/// A Block may be a Container or a Leaf.
/// The Block is the basic unit of the Markdown AST.
pub const Block = union(BlockType) {
    const Self = @This();
    Container: Container,
    Leaf: Leaf,

    /// Create a new Container of the given type
    pub fn initContainer(alloc: Allocator, kind: ContainerType, col: usize) Block {
        return .{ .Container = Container.init(alloc, kind, col) };
    }

    /// Create a new Leaf of the given type
    pub fn initLeaf(alloc: Allocator, kind: LeafType, col: usize) Block {
        return .{ .Leaf = Leaf.init(alloc, kind, col) };
    }

    pub fn deinit(self: *Block) void {
        switch (self.*) {
            inline else => |*b| b.deinit(),
        }
    }

    pub fn allocator(self: Block) Allocator {
        return switch (self) {
            inline else => |b| b.alloc,
        };
    }

    pub fn start_col(self: Block) usize {
        return switch (self) {
            inline else => |b| b.start_col,
        };
    }

    pub fn isContainer(self: Block) bool {
        return self == .Container;
    }

    pub fn isLeaf(self: Block) bool {
        return self == .Leaf;
    }

    pub fn container(self: *Self) *Container {
        return &self.Container;
    }

    pub fn leaf(self: *Self) *Leaf {
        return &self.Leaf;
    }

    pub fn isOpen(self: Self) bool {
        return switch (self) {
            inline else => |b| b.open,
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

/// A Container can contain one or more Blocks
pub const Container = struct {
    const Self = @This();
    alloc: Allocator,
    content: ContainerData,
    open: bool = true,
    children: ArrayList(Block),
    start_col: usize = 0, // The starting column of the first line of this block

    pub fn init(alloc: Allocator, kind: ContainerType, col: usize) Self {
        var block = Container{
            .alloc = alloc,
            .content = undefined,
            .children = ArrayList(Block).init(alloc),
            .start_col = col,
        };

        block.content = switch (kind) {
            .Document => ContainerData{ .Document = {} },
            .Quote => ContainerData{ .Quote = {} },
            .List => ContainerData{ .List = zd.List{} },
            .ListItem => ContainerData{ .ListItem = zd.ListItem{} },
            .Table => ContainerData{ .Table = zd.Table{} },
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
        for (self.children.items, 0..) |child, i| {
            if (child.isOpen()) {
                //child.close();
                self.children.items[i].close();
            }
        }
        self.open = false;
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

/// A Leaf contains only Inline content
pub const Leaf = struct {
    const Self = @This();
    alloc: Allocator,
    content: LeafData,
    raw_contents: ArrayList(Token),
    inlines: ArrayList(Inline),
    open: bool = true,
    start_col: usize = 0, // The starting column of the first line of this block

    pub fn init(alloc: Allocator, kind: LeafType, col: usize) Leaf {
        return Leaf{
            .alloc = alloc,
            .raw_contents = ArrayList(Token).init(alloc),
            .inlines = ArrayList(Inline).init(alloc),
            .start_col = col,
            .content = blk: {
                switch (kind) {
                    .Break => break :blk .{ .Break = {} },
                    .Code => break :blk .{ .Code = zd.Code.init(alloc) },
                    .Heading => break :blk .{ .Heading = zd.Heading.init(alloc) },
                    .Paragraph => break :blk .{ .Paragraph = {} },
                }
            },
        };
    }

    pub fn deinit(self: *Self) void {
        self.content.deinit();
        self.raw_contents.deinit();
        for (self.inlines.items) |*item| {
            item.deinit();
        }
        self.inlines.deinit();
    }

    pub fn addInline(self: *Self, item: Inline) !void {
        try self.inlines.append(item);
    }

    /// Append a chunk of Text to our inlines
    pub fn addText(self: *Self, text: Text) !void {
        try self.inlines.append(zd.Inline.initWithContent(self.alloc, .{ .text = text }));
    }

    /// Append a Link to the contents Paragraph
    pub fn addLink(self: *Self, link: Link) !void {
        try self.inlines.append(zd.Inline.initWithContent(self.alloc, .{ .link = link }));
    }

    pub fn close(self: *Self) void {
        self.open = false;
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

pub fn isBreak(block: Block) bool {
    if (!block.isLeaf()) return false;
    return block.Leaf.content == zd.LeafType.Break;
}

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

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
// Helper Functions
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
    var root = Block.initContainer(alloc, .Document, 0);

    // Create a List container
    var list = Block.initContainer(alloc, .List, 0);

    // Create a ListItem
    var list_item = Block.initContainer(alloc, .ListItem, 2);

    // Create a Paragraph
    var paragraph = Block.initLeaf(alloc, .Paragraph, 4);

    // Create some Text
    const text1 = Text{ .text = "Hello, " };
    const text2 = Text{ .text = "World", .style = .{ .bold = true } };
    var text3 = Text{ .text = "!" };
    text3.style.bold = true;
    text3.style.italic = true;

    // Create a Link
    var link = zd.Link.init(alloc);
    link.url = "www.google.com";
    try link.text.append(Text{ .text = "Google", .style = .{ .underline = true } });

    // Add the Text and the Link to the Paragraph
    try std.testing.expect(isLeaf(paragraph));
    try paragraph.Leaf.addText(text1);
    try paragraph.Leaf.addText(text2);
    try paragraph.Leaf.addText(text3);
    try paragraph.Leaf.addLink(link);

    // Add the Paragraph to the ListItem
    try std.testing.expect(isContainer(list_item));
    try list_item.addChild(paragraph);

    // Add the ListItem to the List
    try std.testing.expect(isContainer(list));
    try list.addChild(list_item);

    // Add the List to the Document
    try root.addChild(list);

    // Try craeting a Table with 2 cols and 1 row
    // Create another Paragraph
    var table = Block.initContainer(alloc, .Table, 0);
    table.Container.content.Table.ncol = 2;

    var para2 = Block.initLeaf(alloc, .Paragraph, 4);
    const text4 = Text{ .text = "Hello, " };
    try para2.Leaf.addText(text4);

    var para3 = Block.initLeaf(alloc, .Paragraph, 4);
    const text5 = Text{ .text = "World" };
    try para3.Leaf.addText(text5);

    try table.addChild(para2);
    try table.addChild(para3);

    try root.addChild(table);

    return root;
}

test "Basic AST Construction" {
    std.debug.print("\n", .{});

    const alloc = std.testing.allocator;

    var root = try createTestAst(alloc);
    defer root.deinit();
}

test "Print basic AST" {
    std.debug.print("\n", .{});

    const alloc = std.testing.allocator;

    var root = try createTestAst(alloc);
    defer root.deinit();

    root.print(0);
}

test "Render basic AST" {
    std.debug.print("\n", .{});
    const alloc = std.testing.allocator;

    const stderr = std.io.getStdErr().writer();
    var renderer = htmlRenderer(stderr, alloc);
    defer renderer.deinit();

    var root = try createTestAst(alloc);
    defer root.deinit();

    try renderer.renderBlock(root);
}

const html = @import("render_html.zig");

fn htmlRenderer(out_stream: anytype, alloc: Allocator) html.HtmlRenderer(@TypeOf(out_stream)) {
    return html.HtmlRenderer(@TypeOf(out_stream)).init(out_stream, alloc);
}
