///////////////////////////////////////////////////////////////////////////////
/// DEPRECATED - see blocks.zig instead
///////////////////////////////////////////////////////////////////////////////

const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

///////////////////////////////////////////////////////////////////////////////
/// High-Level Block Types
///////////////////////////////////////////////////////////////////////////////

pub const BlockType = enum(u8) {
    Container,
    Leaf,
};

/// Generic Block type. The AST is contructed from this type.
pub const Block = union(enum(u8)) {
    leaf: LeafBlock,
    container: ContainerBlock,

    /// Convert the given ContainerBlock to a new Block
    pub fn initContainer(alloc: Allocator, kind: ContainerType) Block {
        return .{ .container = ContainerBlock.init(alloc, kind) };
    }

    /// Convert the given LeafBlock to a new Block
    pub fn initLeaf(alloc: Allocator, kind: LeafType) Block {
        return .{ .leaf = LeafBlock.Init(alloc, kind) };
    }

    pub fn deinit(self: *Block) void {
        switch (self.*) {
            inline else => |*b| b.deinit(),
        }
    }

    pub fn print(self: *const Block, depth: usize) void {
        switch (self.*) {
            inline else => |b| b.print(depth),
        }
    }

    pub fn addChild(self: *Block, child: Block) !void {
        switch (self.*) {
            .container => |*b| try b.addChild(child),
            .leaf => @panic("Cannot add a Block child to a LeafBlock!"),
        }
    }

    pub fn addInline(self: *Block, item: Inline) !void {
        switch (self.*) {
            .leaf => |*b| try b.addInline(item),
            .container => @panic("Cannot add an Inline to a ContainerBlock!"),
        }
    }
};

pub const LeafType = enum(u8) {
    line_break,
    heading,
    para,
    code,
    //     - Breaks
    //     - Headings
    //     - Code blocks
    //     - Link reference definition (e.g. [foo]: url "title")
    //     - Paragraph ('Text')
};

pub const LeafData = union(LeafType) {
    line_break: LineBreak,
    heading: Heading,
    para: Paragraph,
    code: Code,
    //     - Breaks
    //     - Headings
    //     - Code blocks
    //     - Link reference definition (e.g. [foo]: url "title")
    //     - Paragraph ('Text')
};

/// A LeafBlock is a Block which contains no child Blocks
pub const LeafBlock = struct {
    alloc: Allocator,
    content: LeafData = undefined,
    inlines: ArrayList(Inline),

    pub fn init(alloc: Allocator, content: LeafData) LeafBlock {
        return .{
            .alloc = alloc,
            .content = content,
            .inlines = ArrayList(Inline).init(alloc),
        };
    }

    pub fn initBlock(alloc: Allocator, content: LeafData) Block {
        return .{
            .leaf = LeafBlock.init(alloc, content),
        };
    }

    pub fn deinit(self: *LeafBlock) void {
        // todo: deinit each inline
        self.inlines.deinit();
    }

    pub fn addInline(self: *LeafBlock, item: Inline) !void {
        try self.inlines.append(item);
    }

    pub fn print(self: *const LeafBlock, depth: usize) void {
        printIndent(depth);

        std.debug.print("LeafBlock: {s} with {d} inlines\n", .{
            @tagName(self.content),
            self.inlines.items.len,
        });

        for (self.inlines.items) |item| {
            item.print(depth + 1);
        }
    }
};

pub const ContainerType = union(enum(u8)) {
    document: void, // Container type for the root element of a document
    quote: Quote,
    list: List,
    list_item: ListItem,
};

/// Containers are blocks which contain other blocks, including other Containers
pub const ContainerBlock = struct {
    alloc: Allocator,
    open: bool = false,
    content: ContainerType,
    children: ArrayList(Block),

    /// Initialize a new ContainerBlock
    pub fn init(alloc: Allocator, content: ContainerType) ContainerBlock {
        return .{
            .alloc = alloc,
            .open = true,
            .content = content,
            .children = ArrayList(Block).init(alloc),
        };
    }

    /// Initialize a new Block as a ContainerBlock
    pub fn initBlock(alloc: Allocator, content: ContainerType) Block {
        return .{
            .container = ContainerBlock.init(alloc, content),
        };
    }

    pub fn deinit(self: *ContainerBlock) void {
        for (self.children.items) |*child| {
            child.deinit();
        }
        self.children.deinit();
    }

    pub fn print(self: *const ContainerBlock, depth: usize) void {
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

    pub fn addChild(self: *ContainerBlock, child: Block) !void {
        try self.children.append(child);
    }
};

pub const Inline = union(enum(u8)) {
    text: Text,
    link: Link,
    image: Image,

    pub fn print(self: *const Inline, depth: usize) void {
        printIndent(depth);
        std.debug.print("Inline {s}: ", .{@tagName(self.*)});
        switch (self.*) {
            inline else => |item| item.print(0),
        }
    }
};

///////////////////////////////////////////////////////////////////////////////
/// Leaf Block Implementations
///////////////////////////////////////////////////////////////////////////////

pub const LineBreak = struct {};
pub const Heading = struct {};
pub const Paragraph = struct {};
pub const Code = struct {};

///////////////////////////////////////////////////////////////////////////////
/// Container Block Implementations
///////////////////////////////////////////////////////////////////////////////

pub const Quote = struct {
    level: u8 = 0, // TODO: This may be unnecessary
};
pub const List = struct {};
pub const ListItem = struct {};

///////////////////////////////////////////////////////////////////////////////
/// Inline Implementations
///////////////////////////////////////////////////////////////////////////////

pub const Text = struct {
    pub const Style = struct {
        bold: bool = false,
        emph: bool = false,
        under: bool = false,
        strike: bool = false,
    };
    style: Style = Style{},
    text: []const u8 = undefined, // The Text does not own the string(??)

    pub fn print(self: *const Text, depth: usize) void {
        printIndent(depth);
        std.debug.print("Text: {s} [Style: {any}]\n", .{ self.text, self.style });
    }
};

/// Hyperlink
pub const Link = struct {
    url: []const u8,
    text: Paragraph, // ?? what should this REALLY be? ArrayList(Text)?

    pub fn print(self: *const Link, depth: usize) void {
        printIndent(depth);
        std.debug.print("Link to {s}\n", .{self.url});
    }
};

/// Image Link
pub const Image = struct {
    src: []const u8,
    alt: Paragraph, // ??

    pub fn print(self: *const Image, depth: usize) void {
        printIndent(depth);
        std.debug.print("Image: {s}\n", .{self.src});
    }
};

/// Auto-link
pub const Autolink = struct {
    url: []const u8,

    pub fn print(self: *const Autolink, depth: usize) void {
        printIndent(depth);
        std.debug.print("Autolink: {s}\n", .{self.url});
    }
};

///////////////////////////////////////////////////////////////////////////////
/// Helper Functions
///////////////////////////////////////////////////////////////////////////////

pub fn printAST(block: Block) void {
    block.print(0);
}

pub fn printIndent(depth: usize) void {
    var i: usize = 0;
    while (i < depth) : (i += 1) {
        std.debug.print("  ", .{});
    }
}

pub fn isContainer(block: Block) bool {
    return block == .container;
}

pub fn isLeaf(block: Block) bool {
    return block == .leaf;
}

///////////////////////////////////////////////////////////////////////////////
// Tests
///////////////////////////////////////////////////////////////////////////////

test "Basic AST Construction" {
    std.debug.print("\n", .{});

    var alloc = std.testing.allocator;

    // Create the Document root
    var root = ContainerBlock.initBlock(alloc, ContainerType{ .document = {} });
    defer root.deinit();

    // Create a List container
    var list = ContainerBlock.initBlock(alloc, ContainerType{ .list = List{} });

    // Create a ListItem
    var list_item = ContainerBlock.initBlock(alloc, .{ .list_item = ListItem{} });

    // Create a Paragraph
    var paragraph = LeafBlock.initBlock(alloc, LeafData{ .para = Paragraph{} });

    // Create some Text
    var text1 = Inline{ .text = Text{ .text = "Hello, " } };
    var text2 = Inline{ .text = Text{ .text = "World", .style = .{ .bold = true } } };
    var text3 = Inline{ .text = Text{ .text = "!" } };
    text3.text.style.emph = true;

    // Add the Text to the Paragraph
    try std.testing.expect(isLeaf(paragraph));
    try paragraph.addInline(text1);
    try paragraph.addInline(text2);
    try paragraph.addInline(text3);

    // Add the Paragraph to the ListItem
    try std.testing.expect(isContainer(list_item));
    try list_item.addChild(paragraph);

    // Add the ListItem to the List
    try std.testing.expect(isContainer(list));
    try list.addChild(list_item);

    // Add the List to the Document
    try root.addChild(list);

    root.print(0);
}
