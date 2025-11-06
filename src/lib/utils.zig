/// utils.zig
/// Common utilities.
const std = @import("std");

const config = @import("config");
const blocks = @import("ast/blocks.zig");
const containers = @import("ast/containers.zig");
const leaves = @import("ast/leaves.zig");
const inls = @import("ast/inlines.zig");
const debug = @import("debug.zig");
const parser = @import("parser.zig");

const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const Block = blocks.Block;

const log = std.log.scoped(.utils);

pub const Vec2i = struct {
    x: usize,
    y: usize,
};

pub const LinkType = enum(u8) {
    /// A link which can be resolved to a file on the local filesystem.
    local,
    /// A remote web URL, or (potentially) a file that was not found.
    remote,
};

/// A representation of a Link for the purpose of traversing a navigation tree.
pub const NavLink = struct {
    kind: LinkType,
    text: []const u8,
    uri: []const u8,
    /// In the case of a local file path, the directory the path is relative to
    from_dir: ?std.fs.Dir = null,

    pub fn deinit(self: *const NavLink, alloc: Allocator) void {
        alloc.free(self.text);
        alloc.free(self.uri);
    }
};

pub const NavBarItem = struct {
    text: []const u8,
    uri: []const u8,
    children: std.ArrayList(NavBarItem) = .empty,
};

/// Options for converting a string representing a link path to a URI string
pub const UriOpts = struct {
    /// Whether to replace whitespace with '-' for e.g. HTML element IDs
    replace_whitespace: bool = false,
    /// Treat the URI as a fragment (prepend with '#')
    fragment: bool = false,
    /// Whether to convert the final string to lowercase or not.
    /// (Used for consistent HTML element IDs in fragment links to headings)
    lowercase: bool = false,
    /// Current directory to normalize the path relative to.
    current_dir: ?std.fs.Dir = null,
    /// Whether to convert the potentially absolute filesystem path to a path relative to current_dir
    relative: bool = false,
};

/// Check if the character is a whitespace character
pub fn isWhitespace(c: u8) bool {
    const ws_chars = " \t\r";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a line-break character
pub fn isLineBreak(c: u8) bool {
    const ws_chars = "\r\n";
    if (std.mem.indexOfScalar(u8, ws_chars, c)) |_| {
        return true;
    }

    return false;
}

/// Check if the character is a special Markdown character
pub fn isSpecial(c: u8) bool {
    const special = "*_`";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

/// Check for punctuation characters
pub fn isPunctuation(c: u8) bool {
    const special = "`~!@#$%^&*()-_=+,.<>/?;:'\"/\\[]{}|";
    if (std.mem.indexOfScalar(u8, special, c)) |_| {
        return true;
    }
    return false;
}

pub fn stdout(comptime fmt: []const u8, args: anytype) void {
    const out = std.io.getStdOut().writer();
    out.print(fmt, args) catch @panic("stdout failed!");
}

/// A simple timer that operates in seconds using f64 time points
pub const Timer = struct {
    timer_: std.time.Timer = undefined,

    pub fn start() Timer {
        return .{ .timer_ = std.time.Timer.start() catch unreachable };
    }

    pub fn read(timer: *Timer) f64 {
        const t: f64 = @floatFromInt(timer.timer_.read());
        return t / 1_000_000_000.0;
    }
};

/// Traverse the tree until a Leaf is found, and return it
pub fn getLeafNode(block: *Block) ?*Block {
    if (block.isLeaf()) {
        return block;
    }
    for (block.Container.children.items) |*child| {
        if (getLeafNode(child)) |b| {
            return b;
        }
    }
    return null;
}

/// Create a Table of Contents from a Markdown AST.
/// The returned Block is a List of plain text containing the text for each heading.
pub fn generateTableOfContents(alloc: Allocator, block: *const Block) !Block {
    std.debug.assert(block.isContainer());
    std.debug.assert(block.Container.content == .Document);
    const doc = block.Container;

    var toc = Block.initContainer(alloc, .List, 0);

    const Entry = struct {
        level: usize = 0,
        block: *Block, // The List block for this Heading level
    };
    var stack = ArrayList(Entry).init(alloc);
    defer stack.deinit();

    try stack.append(.{ .level = 1, .block = &toc });
    var last: Entry = stack.getLast();
    for (doc.children.items) |b| {
        switch (b) {
            .Container => {},
            .Leaf => |l| {
                switch (l.content) {
                    .Heading => |H| {
                        const item = try getListItemForHeading(block.allocator(), H, 0);

                        if (H.level > last.level) {
                            // Go one layer deeper
                            // Create a new List and add it as a child of the current ListItem
                            // TODO: Better handling for jumping straight from level 1 to level N
                            const cur_item: *Block = last.block.lastChild() orelse last.block;
                            const sub_toc = Block.initContainer(block.allocator(), .List, 0);
                            try cur_item.addChild(sub_toc);

                            // Push the new List onto the stack
                            try stack.append(.{ .level = H.level, .block = cur_item.lastChild().? });
                            last = stack.getLast();

                            // Add the Heading's ListItem to the new List at the tail of the stack
                            try last.block.addChild(item);
                        } else if (H.level == last.level) {
                            // Stay at current level
                            try last.block.addChild(item);
                        } else {
                            // Pop the tail off the stack until we're at the correct level
                            while (last.level > H.level) {
                                _ = stack.pop();
                                last = stack.getLast();
                            }
                            try last.block.addChild(item);
                        }
                    },
                    else => {},
                }
            },
        }
    }
    return toc;
}

/// Generate a navigation tree for an HTML site, starting from the current root block.
///
/// Follows all links and adds them to a tree, recursively following the link to the
/// referenced document if it exists locally within the site's directory tree.
pub fn generateNavigationTree(alloc: Allocator, root_dir: std.fs.Dir, root_file: []const u8, document_root: *const Block) !NavBarItem {
    std.debug.assert(document_root.isContainer());
    std.debug.assert(document_root.Container.content == .Document);

    // Grab the first level-1 Heading from the document (if it exists) and use that as the title.
    // Otherwise, use the filename as the title.
    const doc_title: []const u8 = getDocumentTitle(document_root) orelse root_file;

    // The root of our navigation tree
    var root_link: NavBarItem = .{
        .text = try alloc.dupe(u8, doc_title),
        .uri = try alloc.dupe(u8, root_file),
        .children = .empty,
    };
    errdefer {
        alloc.free(root_link.text);
        alloc.free(root_link.uri);
    }

    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    if (root_dir.realpath(root_file, &path_buf)) |abs_path| {
        alloc.free(root_link.uri);
        root_link.uri = try alloc.dupe(u8, abs_path);
    } else |_| {
        // throw the error or no?
    }

    // A 'global' list of all links which have been added to the navigation tree.
    // Used to avoid link cycles.
    const all_links: std.ArrayList(NavLink) = .empty;

    root_link.children = try generateNavBarRecurse(alloc, all_links, root_dir, document_root);

    return root_link;
}

fn generateNavBarRecurse(alloc: Allocator, global_links: std.ArrayList(NavLink), current_dir: std.fs.Dir, block: *const Block) !std.ArrayList(NavBarItem) {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    // Extract a unique list of all links within the document.
    // This performs a very basic deduplication, but it is not perfect.
    // Each returned link is either a file known to exist on the local filesystem, or a "remote" path.
    const links = try extractLinksFromDocument(arena.allocator(), current_dir, block);

    var child_links: std.ArrayList(NavBarItem) = .empty;
    errdefer child_links.deinit(alloc);

    for (links) |link| {
        var nav_item: NavBarItem = .{
            .text = try alloc.dupe(u8, link.text),
            .uri = try alloc.dupe(u8, link.uri),
            .children = .empty,
        };
        errdefer {
            alloc.free(nav_item.text);
            alloc.free(nav_item.uri);
        }

        if (link.kind == .local and std.mem.eql(u8, std.fs.path.extension(link.uri), ".md")) {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;

            const dir = link.from_dir orelse current_dir;
            if (dir.realpath(link.uri, &path_buf)) |abs_path| {
                // Replace the (possibly relative) current path with the now-absolute path
                alloc.free(nav_item.uri);
                nav_item.uri = try alloc.dupe(u8, abs_path);
            } else |_| {
                // TODO: debug log the error
            }

            // Check if this document is already part of the navigation tree (avoid cycles)
            var already_parsed: bool = false;
            for (global_links.items) |existing_link| {
                if (std.mem.eql(u8, nav_item.uri, existing_link.uri)) {
                    // We've already processed this document - skip it
                    already_parsed = true;
                }
            }

            if (!already_parsed) {
                // This is a markdown file we should follow and parse
                if (readFile(arena.allocator(), dir, nav_item.uri)) |contents| {
                    var p = parser.Parser.init(arena.allocator(), .{});
                    try p.parseMarkdown(contents);
                    const child_doc: Block = p.document;

                    // Check if the document has a title we can use for the text of the link.
                    // Otherwise, use the existing link text.
                    if (getDocumentTitle(&child_doc)) |title| {
                        alloc.free(nav_item.text);
                        nav_item.text = try alloc.dupe(u8, title);
                    }

                    // Open the parent directory of the child document
                    const child_dir_name: []const u8 = std.fs.path.dirname(nav_item.uri) orelse ".";
                    var child_dir: std.fs.Dir = try dir.openDir(child_dir_name, .{});
                    defer child_dir.close();

                    nav_item.children = try generateNavBarRecurse(alloc, global_links, child_dir, &child_doc);
                } else |_| {
                    // TODO: debug log the error
                    // ignore filesystem (or OOM) errors and just carry on without recursion
                }
            }

            try child_links.append(alloc, nav_item);
        } else {
            // If not a local Markdown file to follow, simply append the link as-is.
            try child_links.append(alloc, nav_item);
        }
    }

    return child_links;
}

test generateNavigationTree {
    const alloc = std.testing.allocator;

    var nav_root_dir = try std.fs.cwd().openDir("test/navbar", .{});
    defer nav_root_dir.close();

    var p = try parser.parseFile(alloc, nav_root_dir, "root.md");
    defer p.deinit();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const nav_tree = try generateNavigationTree(arena.allocator(), nav_root_dir, "root.md", &p.document);

    // We'll compare all file paths to the repo root
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const abs_root_path = try std.fs.cwd().realpath(".", &path_buf);

    // Root node
    try std.testing.expectEqualStrings("Navigation Tree Test Document", nav_tree.text);
    // try std.testing.expect(std.mem.endsWith(u8, nav_tree.uri, "root.md"));
    const root_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, nav_tree.uri);
    try std.testing.expectEqualStrings("test/navbar/root.md", root_relpath);

    try std.testing.expectEqual(4, nav_tree.children.items.len);

    // First child - Link to google.com
    const child1 = nav_tree.children.items[0];
    try std.testing.expectEqualStrings("Google", child1.text);
    try std.testing.expectEqualStrings("google.com", child1.uri);
    try std.testing.expectEqual(0, child1.children.items.len);

    // Second child - Local link to sub/foo.md
    const child2 = nav_tree.children.items[1];
    try std.testing.expectEqualStrings("Foo", child2.text);
    const child2_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, child2.uri);
    try std.testing.expectEqualStrings("test/navbar/sub/foo.md", child2_relpath);

    try std.testing.expectEqual(2, child2.children.items.len);

    // -- first child of child2
    const child2_1 = child2.children.items[0];
    try std.testing.expectEqualStrings("Bar", child2_1.text);
    const child2_1_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, child2_1.uri);
    try std.testing.expectEqualStrings("test/navbar/sub/bar.md", child2_1_relpath);
    try std.testing.expectEqual(2, child2_1.children.items.len);

    // -- second child of child2
    const child2_2 = child2.children.items[1];
    try std.testing.expectEqualStrings("Child Page", child2_2.text);
    const child2_2_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, child2_2.uri);
    try std.testing.expectEqualStrings("test/navbar/sub/subsub/baz.md", child2_2_relpath);
    try std.testing.expectEqual(3, child2_2.children.items.len);

    // TODO: children: sibling page bar.md; child page subsub/baz

    // Third child - Local link to sub/bar.md
    const child3 = nav_tree.children.items[2];
    try std.testing.expectEqualStrings("Bar", child3.text);
    try std.testing.expect(std.mem.endsWith(u8, child3.uri, "bar.md"));
    const child3_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, child3.uri);
    try std.testing.expectEqualStrings("test/navbar/sub/bar.md", child3_relpath);

    // Fourth child - Local link to sub/subsub/baz.md
    const child4 = nav_tree.children.items[3];
    try std.testing.expectEqualStrings("Baz with no title", child4.text);
    try std.testing.expect(std.mem.endsWith(u8, child4.uri, "baz.md"));
    const child4_relpath = try std.fs.path.relative(arena.allocator(), abs_root_path, child4.uri);
    try std.testing.expectEqualStrings("test/navbar/sub/subsub/baz.md", child4_relpath);
}

/// Extract all links from the given Document block.
/// Returns a heap-allocated list of NavLink objects (link text + URI string).
pub fn extractLinksFromDocument(alloc: Allocator, root_dir: std.fs.Dir, root: *const Block) ![]const NavLink {
    std.debug.assert(root.isContainer());
    std.debug.assert(root.Container.content == .Document);
    const doc = root.Container;

    var links: std.ArrayList(NavLink) = .empty;

    for (doc.children.items) |b| {
        try extractLinksRecurse(alloc, root_dir, &links, &b);
    }

    return try links.toOwnedSlice(alloc);
}

/// Recursively traverse a document AST, appending all links found to the 'links' ArrayList.
fn extractLinksRecurse(alloc: Allocator, current_dir: std.fs.Dir, links: *std.ArrayList(NavLink), block: *const Block) !void {
    switch (block.*) {
        .Container => |c| {
            for (c.children.items) |child| {
                try extractLinksRecurse(alloc, current_dir, links, &child);
            }
        },
        .Leaf => |l| {
            switch (l.content) {
                .Paragraph, .Heading, .Alert => {
                    for (l.inlines.items) |inl| {
                        switch (inl.content) {
                            .link => |link| {
                                // Evaluate the path; resolve to local path relative to the current dir when applicable
                                const uri = try pathToUri(alloc, link.url, .{ .current_dir = current_dir, .relative = true });

                                // De-duplicate: Check if the link already exists within the links list
                                const duplicate: bool = blk: {
                                    for (links.items) |existing_link| {
                                        if (std.mem.eql(u8, uri, existing_link.uri)) {
                                            break :blk true;
                                        }
                                    }
                                    break :blk false;
                                };

                                if (duplicate) {
                                    alloc.free(uri);
                                } else {
                                    // Merge the lihk text into a single string (The original is a list of Text items with style)
                                    var link_words = ArrayList([]const u8).init(alloc);
                                    defer link_words.deinit();
                                    for (link.text.items) |text| {
                                        try link_words.append(text.text);
                                    }
                                    const new_text: []u8 = try std.mem.concat(alloc, u8, link_words.items);

                                    // Even though pathToUri did this test already,
                                    // we need to do it again to know the result here :shrug:
                                    const link_kind: LinkType = if (current_dir.access(uri, .{ .mode = .read_only })) .local else |_| .remote;

                                    try links.append(alloc, .{
                                        .kind = link_kind,
                                        .text = new_text,
                                        .uri = uri,
                                        .from_dir = current_dir,
                                    });
                                }
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        },
    }
}

test extractLinksFromDocument {
    const alloc = std.testing.allocator;

    // ---- Inputs & Outputs

    const doc_text =
        \\# Title
        \\- [This points to a .md file in the repo to be rendered as HTML](./test/alert.html)
        \\  - lorem ipsum [Link to a web URL](www.bar.com) sit dolor
        \\  - [another url](https://jcrabill.dev)
        \\- [An HTML file that actually exists](test/html/wasm-demo.html)
        \\- [A file that doesn't exist locally](./foo/bar/baz)
        \\
        \\```
        \\[Not a link](foo.com)
        \\```
        \\![Image, Not Link](ziggy.png)
        \\[duplicate link](www.bar.com)
        \\[not duplicate, bc non-existent](foo/bar/baz)
        \\[yet another duplicate link](test/alert)
        \\
        \\> [!INFO]
        \\> Links are allowed in [github alert boxes](docs.github.com)
        \\
        \\# Links are also allowed in [headings](foo)
    ;

    const expected_links: []const NavLink = &.{
        .{ .kind = .local, .text = "This points to a .md file in the repo to be rendered as HTML", .uri = "test/alert.md" },
        .{ .kind = .remote, .text = "Link to a web URL", .uri = "www.bar.com" },
        .{ .kind = .remote, .text = "another url", .uri = "https://jcrabill.dev" },
        .{ .kind = .local, .text = "An HTML file that actually exists", .uri = "test/html/wasm-demo.html" },
        .{ .kind = .remote, .text = "A file that doesn't exist locally", .uri = "./foo/bar/baz" },
        .{ .kind = .remote, .text = "not duplicate, bc non-existent", .uri = "foo/bar/baz" },
        .{ .kind = .remote, .text = "github alert boxes", .uri = "docs.github.com" },
        .{ .kind = .remote, .text = "headings", .uri = "foo" },
    };

    // ---- Arrange

    var p = @import("parser.zig").Parser.init(alloc, .{});
    try p.parseMarkdown(doc_text);
    defer p.deinit();

    const doc = p.document;

    // ---- Act

    const links = try extractLinksFromDocument(alloc, std.fs.cwd(), &doc);
    defer {
        for (links) |link| {
            link.deinit(alloc);
        }
        alloc.free(links);
    }

    // ---- Assert

    try std.testing.expectEqual(expected_links.len, links.len);
    for (expected_links, links) |expected, actual| {
        try std.testing.expectEqual(expected.kind, actual.kind);
        try std.testing.expectEqualStrings(expected.text, actual.text);
        try std.testing.expectEqualStrings(expected.uri, actual.uri);
    }
}

/// Given a Heading node, create a ListItem Block containing a Link to that heading
/// (The Link is an Inline inside a Paragraph Leaf Block)
fn getListItemForHeading(alloc: Allocator, H: leaves.Heading, depth: usize) !Block {
    var block = Block.initContainer(alloc, .ListItem, depth);
    var text = Block.initLeaf(alloc, .Paragraph, depth);

    // HTML-encode the text and also create a URI string from it
    const new_text = try htmlEncode(alloc, H.text);
    const url = try pathToUri(alloc, H.text, .{ .replace_whitespace = true, .fragment = true, .lowercase = true });

    // Create the Link object
    var link = inls.Link{
        .alloc = alloc,
        .url = url,
        .text = ArrayList(inls.Text).init(alloc),
        .heap_url = true,
    };
    try link.text.append(inls.Text{ .alloc = alloc, .text = new_text, .style = .{ .bold = true } });

    // Create an Inline to hold the Link; add it to the Paragraph and the ListItem
    const inl = inls.Inline.initWithContent(alloc, .{ .link = link });
    try text.leaf().addInline(inl);
    try block.addChild(text);

    return block;
}

/// Convert the raw text of a path to an HTML-safe URI string.
///
/// We also replace ' ' with '-' and convert all ASCII characters to lowercase;
/// this enables us to convert arbitrary strings to URL document fragments (e.g., headings).
///
/// This will be the expected format for links in rendered HTML.
pub fn pathToUri(alloc: Allocator, in_path: []const u8, opts: UriOpts) ![]const u8 {
    var resolved_link: []u8 = try alloc.dupe(u8, in_path);
    defer alloc.free(resolved_link);

    if (opts.replace_whitespace) {
        // Replace spaces with dashes
        std.mem.replaceScalar(u8, resolved_link, ' ', '-');
    }

    if (opts.lowercase) {
        for (resolved_link) |*c| {
            c.* = std.ascii.toLower(c.*);
        }
    }

    if (opts.current_dir) |dir| blk: {
        if (@import("wasm.zig").is_wasm) break :blk; // WASM doesn't have a filesystem

        // Check if this is a filesystem path, not a web URL.
        // Attempt to resolve the path to a file relative to the current directory.
        // If it cannot be resolved, keep the original link as-is.

        // Example: dir: /site_root, path: foo/../bar.html -> /site_root/bar.md

        const is_file: bool = if (dir.access(resolved_link, .{ .mode = .read_only })) true else |_| false;

        var path_buf: [std.fs.max_path_bytes]u8 = undefined;

        // Check if this could be a URL pointing to a Markdown file to be rendered
        var is_md_link: bool = false;
        if (!is_file) {
            const extension = std.fs.path.extension(resolved_link);
            if (extension.len == 0 or std.mem.eql(u8, extension, ".html")) {
                const new_path_len: usize = resolved_link.len + 3 - extension.len;
                const old_len: usize = resolved_link.len - extension.len;

                const new_path: []u8 = path_buf[0..new_path_len];
                @memcpy(new_path[0..old_len], resolved_link[0..old_len]);
                @memcpy(new_path[new_path_len - 3 ..], ".md");

                is_md_link = if (dir.access(new_path, .{ .mode = .read_only })) true else |_| false;
                if (is_md_link) {
                    alloc.free(resolved_link);
                    resolved_link = try alloc.dupe(u8, new_path);
                }
            }
        }

        if (is_file or is_md_link) {
            // If it errors out for whatever reason, just ignore it and use the original path.
            // Note that 'realpath' returns an *absolute* filesystem path.
            const resolved_path = dir.realpath(resolved_link, &path_buf) catch resolved_link;

            if (opts.relative) {
                alloc.free(resolved_link);

                // Resolve a path relative to 'dir'.
                const current_path: []const u8 = dir.realpath(".", &path_buf) catch "";
                if (std.fs.path.relative(alloc, current_path, resolved_path)) |new_relpath| {
                    resolved_link = new_relpath;
                } else |_| {
                    // Fallback to absolute path on error
                    resolved_link = try alloc.dupe(u8, resolved_path);
                }
            } else if (std.mem.eql(u8, resolved_link, resolved_path)) {
                // If we're keeping the absolute path, and it's the same as the original link path,
                // don't realloc the string.
            } else {
                alloc.free(resolved_link);
                resolved_link = try alloc.dupe(u8, resolved_path);
            }
        }
    }

    // Create a URI string from the modified string
    const uri: std.Uri = .{
        .scheme = "",
        .user = null,
        .password = null,
        .host = null,
        .port = null,
        .path = .{ .raw = resolved_link },
        .query = null,
        .fragment = null,
    };

    const uri_s = if (opts.fragment)
        try std.fmt.allocPrint(alloc, "#{f}", .{uri.fmt(.{ .path = true })})
    else
        try std.fmt.allocPrint(alloc, "{f}", .{uri.fmt(.{ .path = true })});
    defer alloc.free(uri_s);

    return try htmlEncode(alloc, uri_s);
}

test pathToUri {
    const alloc = std.testing.allocator;

    const cwd = std.fs.cwd();

    const TestData = struct {
        input: []const u8,
        expected: []const u8,
        opts: UriOpts = .{ .relative = true },
    };

    const test_data: []const TestData = &.{
        .{ .input = "foo.md", .expected = "foo.md" },
        .{ .input = "test/alert.md", .expected = "test/alert.md", .opts = .{ .current_dir = cwd, .relative = true } },
        .{ .input = "test/alert.html", .expected = "test/alert.md", .opts = .{ .current_dir = cwd, .relative = true } },
        .{ .input = "test/alert", .expected = "test/alert.md", .opts = .{ .current_dir = cwd, .relative = true } },
        .{ .input = "test/../lua/zigdown.lua", .expected = "lua/zigdown.lua", .opts = .{ .current_dir = cwd, .relative = true } },
        .{ .input = "Hello, World", .expected = "#hello,-world", .opts = .{ .replace_whitespace = true, .lowercase = true, .fragment = true } },
        .{ .input = "Hello, World", .expected = "#hello,%20world", .opts = .{ .lowercase = true, .fragment = true } },
    };

    for (test_data) |data| {
        const actual = try pathToUri(alloc, data.input, data.opts);
        defer alloc.free(actual);
        try std.testing.expectEqualStrings(data.expected, actual);
    }
}

/// We define a document title as the first child of Document which is a level 1 Heading.
/// If the first child of the document is not a level 1 Heading, return null.
pub fn getDocumentTitle(block: *const Block) ?[]const u8 {
    if (!block.isContainer()) return null;
    if (block.Container.content != .Document) return null;

    const children = block.Container.children.items;
    if (children.len < 1) return null;

    const first_child = children[0];
    if (!first_child.isLeaf()) return null;
    if (first_child.Leaf.content != .Heading) return null;

    const heading = first_child.Leaf.content.Heading;
    if (heading.level != 1) return null;

    return heading.text;
}

/// Return whether a directive string declares a Table of Contents
pub fn isDirectiveToC(directive: []const u8) bool {
    if (std.mem.eql(u8, directive, "toc"))
        return true;
    if (std.mem.eql(u8, directive, "toctree"))
        return true;
    if (std.mem.eql(u8, directive, "table-of-contents"))
        return true;
    return false;
}

/// Given a string, return the substring after any leading whitespace
pub fn trimLeadingWhitespace(line: []const u8) []const u8 {
    for (line, 0..) |c, i| {
        switch (c) {
            ' ', '\n' => {},
            else => return line[i..],
        }
    }
    // If the line is ALL whitespace, leave a single space
    if (line.len > 0) return line[0..1];
    return line;
}

test trimLeadingWhitespace {
    try std.testing.expectEqualStrings("1234", trimLeadingWhitespace("   1234"));
    try std.testing.expectEqualStrings("1234", trimLeadingWhitespace("1234"));
    try std.testing.expectEqualStrings("", trimLeadingWhitespace(""));
    try std.testing.expectEqualStrings(" ", trimLeadingWhitespace(" "));
    try std.testing.expectEqualStrings(" ", trimLeadingWhitespace("  "));
}

/// Given a string, return the substring up to any trailing whitespace (including newlines)
pub fn trimTrailingWhitespace(line: []const u8) []const u8 {
    var i: usize = line.len;
    while (i > 0) : (i -= 1) {
        const c = line[i - 1];
        switch (c) {
            ' ', '\n' => {},
            else => return line[0..i],
        }
    }
    // If the line is ALL whitespace, leave a single space
    if (line.len > 0) return line[0..1];
    return line;
}

test trimTrailingWhitespace {
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234   "));
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234"));
    try std.testing.expectEqualStrings("1234", trimTrailingWhitespace("1234\n"));
    try std.testing.expectEqualStrings("", trimTrailingWhitespace(""));
    try std.testing.expectEqualStrings("\n", trimTrailingWhitespace(&.{'\n'}));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace(&.{ ' ', '\n' }));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace(" "));
    try std.testing.expectEqualStrings(" ", trimTrailingWhitespace("  "));
}

/// Convert from snake_case to kebab-case at comptime
pub fn toKebab(comptime string: []const u8) []const u8 {
    comptime var kebab: []const u8 = "";
    inline for (string) |ch| kebab = kebab ++ .{switch (ch) {
        '_' => '-',
        else => ch,
    }};
    return kebab;
}

/// Characters which must be HTML-encoded
pub const html_chars: []const u8 = "<>";

/// HTML-encode the given string to a new heap-allocated string.
pub fn htmlEncode(alloc: Allocator, bytes: []const u8) ![]const u8 {
    var new_size: usize = 0;
    for (bytes) |c| {
        switch (c) {
            '<', '>' => new_size += 4,
            '&' => new_size += 5,
            else => new_size += 1,
        }
    }

    var out = try ArrayList(u8).initCapacity(alloc, new_size);
    var writer = out.writer();
    for (bytes) |c| {
        switch (c) {
            '<' => writer.writeAll("&lt;") catch unreachable,
            '>' => writer.writeAll("&gt;") catch unreachable,
            '&' => writer.writeAll("&amp;") catch unreachable,
            else => writer.writeByte(c) catch unreachable,
        }
    }
    return out.items;
}

test htmlEncode {
    const TestData = struct {
        in: []const u8,
        out: []const u8,
    };
    const test_data: []const TestData = &.{
        .{ .in = "hi", .out = "hi" },
        .{ .in = "<hi", .out = "&lt;hi" },
        .{ .in = "<hi>", .out = "&lt;hi&gt;" },
        .{ .in = "foo&bar", .out = "foo&amp;bar" },
    };

    const alloc = std.testing.allocator;
    for (test_data) |data| {
        const out = try htmlEncode(alloc, data.in);
        defer alloc.free(out);
        try std.testing.expectEqualStrings(data.out, out);
    }
}

/// Helper function to read the contents of a file given a relative path.
/// Caller owns the returned memory.
pub fn readFile(alloc: Allocator, cwd: std.fs.Dir, file_path: []const u8) ![]u8 {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const realpath = try cwd.realpath(file_path, &path_buf);
    var file: std.fs.File = try cwd.openFile(realpath, .{ .mode = .read_only });
    defer file.close();
    return try file.readToEndAlloc(alloc, 1e9);
}

/// Fetch a remote file from an HTTP server at the given URL.
/// Caller owns the returned memory.
pub fn fetchFile(alloc: Allocator, url_s: []const u8, writer: *std.Io.Writer) !void {
    var client = std.http.Client{ .allocator = alloc };
    defer client.deinit();

    // Perform a one-off request and wait for the response.
    // Returns an http.Status.
    const status = client.fetch(.{
        .location = .{ .url = url_s },
        .method = .GET,
        .headers = .{ .authorization = .omit },
        .response_writer = writer,
    }) catch |err| {
        log.err("Error fetching {s}: {any}", .{ url_s, err });
        return err;
    };

    if (status.status != .ok) {
        log.err("Error fetching {s} (!ok)", .{url_s});
        return error.NoReply;
    }

    if (writer.buffered().len == 0) {
        log.err("Error fetching {s} (no bytes returned)", .{url_s});
        return error.NoReply;
    }
}

test fetchFile {
    if (!config.extra_tests) return error.SkipZigTest;
    const url = "https://picsum.photos/id/237/200/300";
    var buffer = std.Io.Writer.Allocating.init(std.testing.allocator);
    defer buffer.deinit();
    fetchFile(std.testing.allocator, url, &buffer.writer) catch return error.SkipZigTest;
}

////////////////////////////////////////////////////////////////////////////////
// Unit Tests
////////////////////////////////////////////////////////////////////////////////

test generateTableOfContents {
    const alloc = std.testing.allocator;

    // Create the Document root
    var root = Block.initContainer(alloc, .Document, 0);
    defer root.deinit();

    // Create an H1
    var h1 = Block.initLeaf(alloc, .Heading, 0);
    h1.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 1");
    h1.leaf().content.Heading.level = 1;

    // Create an H2
    var h2 = Block.initLeaf(alloc, .Heading, 0);
    h2.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 2");
    h2.leaf().content.Heading.level = 2;

    // Create an H3
    var h3 = Block.initLeaf(alloc, .Heading, 0);
    h3.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 3");
    h3.leaf().content.Heading.level = 3;

    // Create another H2
    var h22 = Block.initLeaf(alloc, .Heading, 0);
    h22.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 2-2");
    h22.leaf().content.Heading.level = 2;

    // Create another H1
    var h12 = Block.initLeaf(alloc, .Heading, 0);
    h12.leaf().content.Heading.text = try alloc.dupe(u8, "Heading 1-2");
    h12.leaf().content.Heading.level = 1;

    // Assign all Headings to the Document
    try root.addChild(h1);
    try root.addChild(h2);
    try root.addChild(h3);
    try root.addChild(h22);
    try root.addChild(h12);

    // Try creating the Table of Contents
    var toc = try generateTableOfContents(alloc, &root);
    toc.close();
    defer toc.deinit();

    var writer = std.Io.Writer.Allocating.init(alloc);
    defer writer.deinit();

    debug.setStream(&writer.writer);
    toc.print(1);

    const expected =
        \\│ Container: open: false, type: List with 2 children
        \\│ │ List Spacing: 0
        \\│ │ Container: open: false, type: ListItem with 2 children
        \\│ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ Inline content:
        \\│ │ │ │ │ Link:
        \\│ │ │ │ │ │ Text: 'Heading 1' [line: 0, col: 0]
        \\│ │ │ Container: open: false, type: List with 2 children
        \\│ │ │ │ List Spacing: 0
        \\│ │ │ │ Container: open: false, type: ListItem with 2 children
        \\│ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ Text: 'Heading 2' [line: 0, col: 0]
        \\│ │ │ │ │ Container: open: false, type: List with 1 children
        \\│ │ │ │ │ │ List Spacing: 0
        \\│ │ │ │ │ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ │ │ Text: 'Heading 3' [line: 0, col: 0]
        \\│ │ │ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ │ │ Inline content:
        \\│ │ │ │ │ │ │ Link:
        \\│ │ │ │ │ │ │ │ Text: 'Heading 2-2' [line: 0, col: 0]
        \\│ │ Container: open: false, type: ListItem with 1 children
        \\│ │ │ Leaf: open: false, type: Paragraph
        \\│ │ │ │ Inline content:
        \\│ │ │ │ │ Link:
        \\│ │ │ │ │ │ Text: 'Heading 1-2' [line: 0, col: 0]
        \\
    ;
    try std.testing.expectEqualStrings(expected, writer.written());
}
