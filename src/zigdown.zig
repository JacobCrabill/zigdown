const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const Parser = struct {
    sections: ArrayList(Section) = undefined,
    alloc: Allocator = undefined,

    pub fn init(allocator: Allocator) Parser {
        return Parser{
            .sections = ArrayList(Section).init(allocator),
            .alloc = allocator,
        };
    }

    pub fn deinit(self: *Parser) void {
        for (self.sections.items) |_, i| {
            self.sections.items[i].deinit();
        }
        self.sections.deinit();
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
    language: u8,
    text: []const u8,
};

/// Bulleted (unordered) list
pub const List = struct {
    level: u8,
    lines: ArrayList(TextBlock),

    pub fn deinit(self: *List) void {
        for (self.lines.items) |_, i| {
            self.lines.items[i].deinit();
        }

        self.lines.deinit();
    }
};

/// Numbered list
pub const NumList = struct {
    level: u8,
    lines: ArrayList(TextBlock),

    pub fn deinit(self: *NumList) void {
        for (self.lines.items) |_, i| {
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

/// Section of formatted text (single style)
/// Example: "plain text" or "**bold text**"
pub const Text = struct {
    style: u8,
    text: []const u8,
};

/// Block of multiple sections of formatted text
/// Example: "plain and **bold** text together"
pub const TextBlock = struct {
    text: ArrayList(Text),

    pub fn deinit(self: *TextBlock) void {
        self.text.deinit();
    }
};
