const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const debug = @import("../debug.zig");

const errorReturn = debug.errorReturn;
const errorMsg = debug.errorMsg;
const Logger = debug.Logger;

const toks = @import("../tokens.zig");
const inls = @import("../ast/inlines.zig");
const utils = @import("utils.zig");

const TokenType = toks.TokenType;
const Token = toks.Token;
const TokenList = toks.TokenList;

const InlineType = inls.InlineType;
const Inline = inls.Inline;
const TextStyle = @import("../theme.zig").TextStyle;

const ParserOpts = utils.ParserOpts;
const appendWords = utils.appendWords;
const appendText = utils.appendText;

/// Global logger
var g_logger = Logger{ .enabled = false };

///////////////////////////////////////////////////////////////////////////////
// Parser Struct
///////////////////////////////////////////////////////////////////////////////

/// Parse text into a Markdown document structure
///
/// Caller owns the input, unless a copy is requested via ParserOpts
pub const InlineParser = struct {
    const Self = @This();
    alloc: Allocator,
    opts: ParserOpts,
    logger: Logger,
    tokens: []Token,
    cursor: usize = 0,
    cur_token: Token,
    next_token: Token,

    pub fn init(alloc: Allocator, opts: ParserOpts) Self {
        return Self{
            .alloc = alloc,
            .opts = opts,
            .logger = Logger{ .enabled = opts.verbose },
            .tokens = undefined,
            .cursor = 0,
            .cur_token = undefined,
            .next_token = undefined,
        };
    }

    /// Reset the Parser to the default state
    pub fn reset(self: *Self) void {
        self.cursor = 0;
        self.cur_token = undefined;
        self.next_token = undefined;
    }

    /// Free any heap allocations
    pub fn deinit(self: *Self) void {
        self.reset();
    }

    ///////////////////////////////////////////////////////
    // Token & Cursor Interactions
    ///////////////////////////////////////////////////////

    /// Set the cursor value and update current and next tokens
    fn setCursor(self: *Self, cursor: usize) void {
        if (cursor >= self.tokens.items.len) {
            self.cursor = self.tokens.items.len;
            self.cur_token = toks.Eof;
            self.next_token = toks.Eof;
            return;
        }

        self.cursor = cursor;
        self.cur_token = self.tokens.items[cursor];
        if (cursor + 1 >= self.tokens.items.len) {
            self.next_token = toks.Eof;
        } else {
            self.next_token = self.tokens.items[cursor + 1];
        }
    }

    /// Advance the cursor by 'n' tokens
    fn advanceCursor(self: *Self, n: usize) void {
        self.setCursor(self.cursor + n);
    }

    ///////////////////////////////////////////////////////
    // Utility Functions
    ///////////////////////////////////////////////////////

    /// Return the index of the next BREAK token, or EOF
    fn nextBreak(self: *Self, idx: usize) usize {
        if (idx >= self.tokens.items.len)
            return self.tokens.items.len;

        for (self.tokens.items[idx..], idx..) |tok, i| {
            if (tok.kind == .BREAK)
                return i;
        }

        return self.tokens.items.len;
    }

    /// Get a slice of tokens up to and including the next BREAK or EOF
    fn getNextLine(self: *Self) ?[]const Token {
        if (self.cursor >= self.tokens.items.len) return null;
        const end = @min(self.nextBreak(self.cursor) + 1, self.tokens.items.len);
        return self.tokens.items[self.cursor..end];
    }

    ///////////////////////////////////////////////////////
    // Inline Parsers
    ///////////////////////////////////////////////////////

    /// Parse raw text content into inline content
    pub fn parseInlines(self: *Self, tokens: []const Token) !ArrayList(Inline) {
        var inlines = ArrayList(Inline).init(self.alloc);
        var style = TextStyle{};
        // TODO: make this 'scratch workspace' part of the Parser struct
        // to avoid constant re-init (use clearRetainingCapacity() instead of deinit())

        var prev_type: TokenType = .BREAK;
        var next_type: TokenType = .BREAK;
        var next_text: []const u8 = "";

        var i: usize = 0;
        while (i < tokens.len) : (i += 1) {
            const tok = tokens[i];
            if (i + 1 < tokens.len) {
                next_type = tokens[i + 1].kind;
                next_text = tokens[i + 1].text;
            } else {
                next_type = .BREAK;
                next_text = "";
            }
            switch (tok.kind) {
                .EMBOLD => {
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR => {
                    if (style.italic and style.bold) {
                        style.bold = false;
                    } else {
                        style.italic = !style.italic;
                    }
                },
                .BOLD => {
                    // TODO: Properly handle emphasis between *, **, ***, * word ** word***, etc.
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    const prev_is_ws: bool = utils.isWhitespace(prev_type);
                    const next_is_ws: bool = utils.isWhitespace(next_type) or (std.mem.indexOfAny(u8, next_text, ",.;'\"") != null);
                    if (prev_is_ws or next_is_ws) {
                        style.italic = !style.italic;
                    } else {
                        try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                    }
                },
                .TILDE => {
                    if (style.strike) {
                        // Already inside a strikethrough span — close it unconditionally.
                        style.strike = false;
                    } else if (utils.findFirstOf(tokens, i + 1, &.{.TILDE}) != null) {
                        // Only open a span when a matching closing ~ exists later in the same block.
                        style.strike = true;
                    } else {
                        // No closing ~ in scope — treat as a literal character.
                        try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                    }
                },
                .BANG, .LBRACK => {
                    const bang: bool = tok.kind == .BANG;
                    const start: usize = if (bang) i + 1 else i;
                    if (utils.validateLink(tokens[start..])) {
                        const n: usize = try self.parseLinkOrImage(&inlines, tokens[i..], bang);
                        i += n - 1;
                    } else {
                        try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                    }
                },
                .CODE_INLINE => {
                    if (utils.findFirstOf(tokens, i + 1, &.{.CODE_INLINE})) |end| {
                        // Create a codespan with position information
                        const code_start = i + 1;
                        const code_end = end;

                        if (code_start < code_end) {
                            var code_words = ArrayList([]const u8).init(self.alloc);
                            defer code_words.deinit();

                            for (tokens[code_start..code_end]) |ctok| {
                                try code_words.append(ctok.text);
                            }

                            // Merge all words into a single string
                            const new_text: []u8 = try std.mem.concat(self.alloc, u8, code_words.items);
                            defer self.alloc.free(new_text);
                            const new_text_ws = std.mem.collapseRepeats(u8, new_text, ' ');

                            const codespan = inls.Codespan{
                                .alloc = self.alloc,
                                .text = try self.alloc.dupe(u8, new_text_ws),
                            };
                            try inlines.append(Inline.initWithContent(
                                self.alloc,
                                inls.InlineData{ .codespan = codespan },
                            ));
                        }

                        i = end;
                    } else {
                        try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                    }
                },
                .LT => {
                    // Autolink
                    if (utils.findFirstOf(tokens, i + 1, &.{.GT})) |end| {
                        const link_start = i + 1;
                        const link_end = end;

                        if (link_start < link_end) {
                            var link_words = ArrayList([]const u8).init(self.alloc);
                            defer link_words.deinit();

                            for (tokens[link_start..link_end]) |ctok| {
                                try link_words.append(ctok.text);
                            }

                            // Merge all words into a single string
                            const new_text: []u8 = try std.mem.concat(self.alloc, u8, link_words.items);
                            defer self.alloc.free(new_text);

                            const autolink = inls.Autolink{
                                .alloc = self.alloc,
                                .url = try self.alloc.dupe(u8, new_text),
                                .heap_url = true,
                            };
                            try inlines.append(Inline.initWithContent(
                                self.alloc,
                                inls.InlineData{ .autolink = autolink },
                            ));
                        }

                        i = end;
                    } else {
                        try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                    }
                },
                .BREAK => {
                    if (prev_type == .SPACE or prev_type == .BREAK) continue;
                    // Treat line breaks as spaces; Don't clear the style (The renderer deals with wrapping)
                    var space_token = tok;
                    space_token.text = " ";
                    try utils.appendSingleToken(self.alloc, &inlines, space_token, style);
                },
                .SPACE => {
                    if (prev_type == .SPACE or prev_type == .BREAK) continue;
                    try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                },
                else => {
                    try utils.appendSingleToken(self.alloc, &inlines, tok, style);
                },
            }

            prev_type = tok.kind;
        }

        return inlines;
    }

    /// Parse a Hyperlink (Image or normal Link)
    /// TODO: return Inline instead of taking *inlines
    fn parseLinkOrImage(self: *Self, inlines: *ArrayList(Inline), tokens: []const Token, bang: bool) Allocator.Error!usize {
        // If an image, skip the '!'; the rest should be a valid link
        const start: usize = if (bang) 1 else 0;

        // Validate link syntax; we assume the link is on a single line
        var line: []const Token = utils.getLine(tokens, start).?;
        std.debug.assert(utils.validateLink(line));

        // Find the separating characters: '[', ']', '(', ')'
        // We already know the 1st token is '[' and that the '(' lies immediately after the '['
        // The Alt text lies between '[' and ']'
        // The URI lies between '(' and ')'
        const alt_start: usize = 1;

        // Find the right square bracket corresponding to the first left square bracket
        const rb_idx: usize = blk: {
            var bcount: i32 = 0;
            for (line, 0..) |tok, i| {
                switch (tok.kind) {
                    .RBRACK => bcount -= 1,
                    .LBRACK => bcount += 1,
                    else => {},
                }
                if (bcount == 0) break :blk i;
            }
            // This is an error.
            break :blk line.len - 1;
        };

        // Find the right paren corresponding to the first left paren
        const lp_idx: usize = rb_idx + 2;
        const rp_idx: usize = blk: {
            var pcount: i32 = 1; // start with 1 lparen immediately behind us
            for (line[lp_idx..], lp_idx..) |tok, i| {
                switch (tok.kind) {
                    .RPAREN => pcount -= 1,
                    .LPAREN => pcount += 1,
                    else => {},
                }
                if (pcount == 0) break :blk i;
            }
            // This is an error.
            break :blk line.len - 1;
        };

        const alt_text: []const Token = utils.trimTrailingWhitespace(utils.trimLeadingWhitespace(line[alt_start..rb_idx]));
        const uri_text: []const Token = utils.trimTrailingWhitespace(utils.trimLeadingWhitespace(line[lp_idx..rp_idx]));

        // Create a text block with position information
        var link_text_block = ArrayList(inls.Text).init(self.alloc);

        // Process each token in the link text individually to preserve position information
        var style = TextStyle{};

        var i: usize = 0;
        while (i < alt_text.len) : (i += 1) {
            const tok = alt_text[i];

            // Handle formatting tokens
            switch (tok.kind) {
                .EMBOLD => {
                    style.bold = !style.bold;
                    style.italic = !style.italic;
                },
                .STAR, .BOLD => {
                    style.bold = !style.bold;
                },
                .USCORE => {
                    // If it's an underscore in the middle of a word, don't toggle style with it
                    if ((i > 0 and alt_text[i - 1].kind == .WORD) and
                        (i + 1 < alt_text.len and alt_text[i + 1].kind == .WORD))
                    {
                        // Add the underscore as a regular character
                        const text = inls.Text{
                            .alloc = self.alloc,
                            .style = style,
                            .text = try self.alloc.dupe(u8, tok.text),
                            .line = tok.src.row,
                            .col = tok.src.col,
                        };
                        try link_text_block.append(text);
                    } else {
                        style.italic = !style.italic;
                    }
                },
                .TILDE => {
                    if (style.strike) {
                        style.strike = false;
                    } else if (utils.findFirstOf(alt_text, i + 1, &.{.TILDE}) != null) {
                        style.strike = true;
                    } else {
                        const text = inls.Text{
                            .alloc = self.alloc,
                            .style = style,
                            .text = try self.alloc.dupe(u8, tok.text),
                            .line = tok.src.row,
                            .col = tok.src.col,
                        };
                        try link_text_block.append(text);
                    }
                },
                .BREAK => {
                    // Treat line breaks as spaces; Don't clear the style
                    const text = inls.Text{
                        .alloc = self.alloc,
                        .style = style,
                        .text = try self.alloc.dupe(u8, " "),
                        .line = tok.src.row,
                        .col = tok.src.col,
                    };
                    try link_text_block.append(text);
                },
                else => {
                    // Add each token as its own Text object
                    const text = inls.Text{
                        .alloc = self.alloc,
                        .style = style,
                        .text = try self.alloc.dupe(u8, tok.text),
                        .line = tok.src.row,
                        .col = tok.src.col,
                    };
                    try link_text_block.append(text);
                },
            }
        }

        // Process URI text
        var uri_words = ArrayList([]const u8).init(self.alloc);
        defer uri_words.deinit();
        for (uri_text) |tok| {
            try uri_words.append(tok.text);
        }

        var inl: Inline = undefined;
        if (bang) {
            var img = inls.Image.init(self.alloc);
            img.heap_src = true;
            img.src = try std.mem.concat(self.alloc, u8, uri_words.items);
            if (std.mem.startsWith(u8, img.src, "http") or std.mem.startsWith(u8, img.src, "www.")) {
                img.kind = .web;
            }

            // Attempt to infer the image type from the extension
            if (std.mem.lastIndexOf(u8, img.src, ".")) |ext_idx| blk: {
                const src_ext = img.src[ext_idx..];
                if (src_ext.len > 4) break :blk;

                var extension_buffer: [4]u8 = undefined;
                const extension = std.ascii.lowerString(&extension_buffer, img.src[ext_idx..]);
                if (std.mem.endsWith(u8, extension, "png")) {
                    img.format = .png;
                } else if (std.mem.endsWith(u8, extension, "jpg")) {
                    img.format = .jpeg;
                } else if (std.mem.endsWith(u8, extension, "jpeg")) {
                    img.format = .jpeg;
                } else if (std.mem.endsWith(u8, extension, "svg")) {
                    img.format = .svg;
                }
            }

            img.alt = link_text_block;
            inl = Inline.initWithContent(self.alloc, .{ .image = img });
        } else {
            var link = inls.Link.init(self.alloc);
            link.heap_url = true;
            link.url = try std.mem.concat(self.alloc, u8, uri_words.items);
            link.text = link_text_block;
            inl = Inline.initWithContent(self.alloc, .{ .link = link });
        }
        try inlines.append(inl);

        return start + rp_idx + 1;
    }
};

//////////////////////////////////////////////////////////
// Tests
//////////////////////////////////////////////////////////

const Lexer = @import("../lexer.zig").Lexer;

/// Parse 'input' through the lexer and inline parser, returning the resulting inlines.
/// The caller owns the returned ArrayList and must deinit it (including each element).
fn parseInlinesFromStr(alloc: std.mem.Allocator, input: []const u8) !ArrayList(Inline) {
    var lex = Lexer{};
    var tokens = try lex.tokenize(alloc, input);
    defer tokens.deinit();
    // Strip the trailing EOF token before passing to the inline parser
    const tok_slice = if (tokens.items.len > 0 and tokens.items[tokens.items.len - 1].kind == .EOF)
        tokens.items[0 .. tokens.items.len - 1]
    else
        tokens.items;
    var parser = InlineParser.init(alloc, .{});
    return parser.parseInlines(tok_slice);
}

test "lone tilde parses as literal text, not strikethrough" {
    const alloc = std.testing.allocator;
    var inlines = try parseInlinesFromStr(alloc, "~foo");
    defer {
        for (inlines.items) |*inl| inl.deinit();
        inlines.deinit();
    }

    // No inline should carry the strikethrough style
    for (inlines.items) |inl| {
        if (inl.content == .text) {
            try std.testing.expect(!inl.content.text.style.strike);
        }
    }
    // The '~' character must appear as literal text
    var found_tilde: bool = false;
    for (inlines.items) |inl| {
        if (inl.content == .text and std.mem.eql(u8, inl.content.text.text, "~"))
            found_tilde = true;
    }
    try std.testing.expect(found_tilde);
}

test "matched tildes produce strikethrough text" {
    const alloc = std.testing.allocator;
    var inlines = try parseInlinesFromStr(alloc, "~foo~");
    defer {
        for (inlines.items) |*inl| inl.deinit();
        inlines.deinit();
    }

    // The word "foo" must be struck
    var foo_is_struck: bool = false;
    for (inlines.items) |inl| {
        if (inl.content == .text and std.mem.eql(u8, inl.content.text.text, "foo"))
            foo_is_struck = inl.content.text.style.strike;
    }
    try std.testing.expect(foo_is_struck);

    // Neither tilde should appear as literal text — both were consumed as markers
    for (inlines.items) |inl| {
        if (inl.content == .text)
            try std.testing.expect(!std.mem.eql(u8, inl.content.text.text, "~"));
    }
}

test "first tilde pair is strikethrough, trailing lone tilde is literal" {
    const alloc = std.testing.allocator;
    // "~foo~" → struck; " ~bar" → plain with literal '~'
    var inlines = try parseInlinesFromStr(alloc, "~foo~ ~bar");
    defer {
        for (inlines.items) |*inl| inl.deinit();
        inlines.deinit();
    }

    var foo_struck: bool = false;
    var bar_plain: bool = false;
    var literal_tilde: bool = false;

    for (inlines.items) |inl| {
        if (inl.content != .text) continue;
        const t = inl.content.text;
        if (std.mem.eql(u8, t.text, "foo")) foo_struck = t.style.strike;
        if (std.mem.eql(u8, t.text, "bar")) bar_plain = !t.style.strike;
        if (std.mem.eql(u8, t.text, "~")) literal_tilde = !t.style.strike;
    }

    try std.testing.expect(foo_struck);
    try std.testing.expect(bar_plain);
    try std.testing.expect(literal_tilde);
}
