const std = @import("std");
const utils = @import("utils.zig");
const zd = @import("zigdown.zig");

pub fn render(parser: zd.Parser) void {
    render_begin();
    for (parser.sections.items) |section| {
        switch (section) {
            .heading => |h| render_heading(h),
            .code => |c| render_code(c),
            .list => |l| render_list(l),
            .numlist => |l| render_numlist(l),
            .quote => |q| render_quote(q),
            .plaintext => |t| render_text(t),
            .textblock => |t| render_textblock(t),
            .linebreak => render_break(),
        }
    }
    render_end();
}

fn render_begin() void {
    utils.stdout("<html><body>\n", .{});
}

fn render_end() void {
    utils.stdout("</body></html>\n", .{});
}

fn render_heading(h: zd.Heading) void {
    utils.stdout("<h{d}>{s}</h{d}>\n", .{ h.level, h.text, h.level });
}

fn render_quote(q: zd.Quote) void {
    utils.stdout("<blockquote>\n", .{});
    var i: i32 = @as(i32, q.level) - 1;
    while (i > 0) : (i -= 1) {
        utils.stdout("<blockquote>\n", .{});
    }

    render_textblock(q.textblock);

    i = @as(i32, q.level) - 1;
    while (i > 0) : (i -= 1) {
        utils.stdout("</blockquote>\n", .{});
    }
    utils.stdout("</blockquote>\n", .{});
}

fn render_code(c: zd.Code) void {
    utils.stdout("<pre><code>{s}</code></pre>\n", .{c.text});
}

fn render_list(list: zd.List) void {
    utils.stdout("<ul>\n", .{});
    for (list.lines.items) |line| {
        utils.stdout("<li>\n", .{});
        render_textblock(line);
        utils.stdout("</li>\n", .{});
    }
    utils.stdout("</ul>\n", .{});
}

fn render_numlist(list: zd.NumList) void {
    utils.stdout("<ul>\n", .{});
    for (list.lines.items) |line| {
        utils.stdout("<li>\n", .{});
        render_textblock(line);
        utils.stdout("</li>\n", .{});
    }
    utils.stdout("</ul>\n", .{});
}

fn render_text(text: zd.Text) void {
    utils.stdout("{s}\n", .{text.text});
}

fn render_break() void {
    utils.stdout("\n", .{});
}

fn render_textblock(block: zd.TextBlock) void {
    for (block.text.items) |text| {
        render_text(text);
    }
}
