/// zigdown.zig
/// Zig representation of Markdown objects.
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Markdown = struct {
    sections: ArrayList(Section) = undefined,
    alloc: Allocator = undefined,

    // Initialize a new Markdown file
    pub fn init(allocator: Allocator) Markdown {
        return Markdown{
            .sections = ArrayList(Section).init(allocator),
            .alloc = allocator,
        };
    }

    // Deallocate all heap memory
    pub fn deinit(self: *Markdown) void {
        for (self.sections.items, 0..) |_, i| {
            self.sections.items[i].deinit();
        }
        self.sections.deinit();
    }

    // Append a section to the Markdown file
    pub fn append(self: *Markdown, sec: Section) !void {
        try self.sections.append(sec);
    }
};

pub const SectionType = enum {
    heading,
    code,
    list,
    numlist,
    quote,
    plaintext,
    textblock,
    linebreak,
};

//pub const Section = union(enum) {
pub const Section = union(SectionType) {
    heading: Heading,
    code: Code,
    list: List,
    numlist: NumList,
    quote: Quote,
    plaintext: Text,
    textblock: TextBlock,
    linebreak: Break,

    pub fn deinit(self: *Section) void {
        switch (self.*) {
            .heading => {},
            .code => {},
            .list => {
                self.list.deinit();
            },
            .numlist => {
                self.numlist.deinit();
            },
            .quote => {
                self.quote.deinit();
            },
            .textblock => {
                self.textblock.deinit();
            },
            .plaintext => {},
            .linebreak => {},
        }
    }
};

/// Single Heading line of a given level.
/// No additional formatting applied to the text of the heading.
pub const Heading = struct {
    level: u8 = 1,
    text: []const u8,
};

/// Code block (unformatted text)
/// TODO: Plug in syntax highlighter eventually...
pub const Code = struct {
    language: []const u8,
    text: []const u8,
};

/// Bulleted (unordered) list
pub const List = struct {
    alloc: Allocator,
    level: u8,
    lines: ArrayList(TextBlock),

    pub fn init(alloc: Allocator) List {
        return .{
            .alloc = alloc,
            .level = 0,
            .lines = ArrayList(TextBlock).init(alloc),
        };
    }

    pub fn deinit(self: *List) void {
        for (self.lines.items, 0..) |_, i| {
            self.lines.items[i].deinit();
        }

        self.lines.deinit();
    }

    pub fn addLine(self: *List) !*TextBlock {
        var tb = try self.lines.addOne();
        tb.text = ArrayList(Text).init(self.alloc);
        return tb;
    }
};

/// Numbered list
pub const NumList = struct {
    level: u8,
    lines: ArrayList(TextBlock),

    pub fn deinit(self: *NumList) void {
        for (self.lines.items, 0..) |_, i| {
            self.lines.items[i].deinit();
        }

        self.lines.deinit();
    }
};

/// Quote block
/// Text inside may have formatting applied
pub const Quote = struct {
    level: u8,
    textblock: TextBlock,

    pub fn deinit(self: *Quote) void {
        self.textblock.deinit();
    }
};

/// Single line/paragragh break
pub const Break = struct {};

pub const TextStyle = struct {
    bold: bool = false,
    italic: bool = false,
    underline: bool = false,
};

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    style: TextStyle = TextStyle{},
    text: []const u8 = undefined,
};

/// Block of multiple sections of formatted text
/// Example: "plain and **bold** text together"
pub const TextBlock = struct {
    text: ArrayList(Text),

    pub fn init(alloc: std.mem.Allocator) TextBlock {
        return TextBlock{ .text = ArrayList(Text).init(alloc) };
    }

    pub fn deinit(self: *TextBlock) void {
        self.text.deinit();
    }
};
