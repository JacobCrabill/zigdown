//! CSS Definitions
//!
//! The fields of this struct are dumped as-is, in order, to
//! the <style> tag of the rendered HTML document.
//!
//! To more easily see the individual fields (in order to know
//! how they should be overridden), view the HTML source and look
//! for the comment "css field: <field-name>" before every section
//! corresponding to each field of this struct.
//!
//! For example, the section underneath "heading-1" will be able to
//! be overridden using the cli arg "css --heading-1 '<new h1 style>'".
const std = @import("std");
const Css = @This();

/// Style for the global 'html' and 'body' tags
html_body: []const u8 = default_html_body,

/// Color definitions to include in the 'body' style
colors: []const u8 = default_colors,

/// Background color or image for the page
background: []const u8 = default_background,

/// Font (Text) style for the body
body_font: []const u8 = default_body_font,

/// Margins and padding for the body
body_padding: []const u8 = default_body_padding,

/// Heading 1 style
heading_1: []const u8 = default_heading_1,

/// Heading 2 style
heading_2: []const u8 = default_heading_2,

/// Heading 3 style
heading_3: []const u8 = default_heading_3,

/// Heading 4 style
heading_4: []const u8 = default_heading_4,

/// Paragraph style
paragraph: []const u8 = default_paragraph,

/// Ordered (Numbered) List style
ordered_list: []const u8 = default_ordered_list,

/// Unordered List style
unordered_list: []const u8 = default_unordered_list,

/// List Item style
list_item: []const u8 = default_list_item,

/// Task List style
task_list_class: []const u8 = default_task_list_class,

/// Task List style
task_item_checked_class: []const u8 = default_task_item_checked_class,

/// Task List style
task_item_unchecked_class: []const u8 = default_task_item_unchecked_class,

/// Inline Code style
inline_code: []const u8 = default_inline_code,

/// Generic Table style
table: []const u8 = default_table,

/// Link style
link: []const u8 = default_link,

/// Block Quote style
blockquote: []const u8 = default_blockquote,

/// Selected elements style
selection: []const u8 = default_selection,

/// Title Class style
title_class: []const u8 = default_title_class,

/// Image Class style
image_class: []const u8 = default_image_class,

/// Style for code blocks (before syntax highlighting is applied to the text)
code_block_class: []const u8 = default_code_block_class,

/// Style for directive blocks
directive_class: []const u8 = default_directive_class,

// -------- Default Style Elements --------

pub const default_html_body =
    \\html, body {
    \\  height: fit-content;
    \\  overflow-wrap: break-word;
    \\}
;

pub const default_colors =
    \\body {
    \\  --color-rosewater: #f2d5cf;
    \\  --color-flamingo: #eebebe;
    \\  --color-pink: #f4b8e4;
    \\  --color-mauve: #cda1e6;
    \\  --color-red: #e78284;
    \\  --color-maroon: #ea999c;
    \\  --color-peach: #ef9f76;
    \\  --color-yellow: #eaca60;
    \\  --color-green: #96dd87;
    \\  --color-teal: #81c8be;
    \\  --color-sky: #99d1db;
    \\  --color-sapphire: #85c1dc;
    \\  --color-blue: #66aaff;
    \\  --color-lavender: #babbf1;
    \\  --color-text: #d6e0ff;
    \\  --color-subtext1: #b5bfe2;
    \\  --color-subtext0: #a5adce;
    \\  --color-overlay2: #949cbb;
    \\  --color-overlay1: #838ba7;
    \\  --color-overlay0: #737994;
    \\  --color-surface2: #626880;
    \\  --color-surface1: #51576d;
    \\  --color-surface0: #414559;
    \\  --color-base: #303446;
    \\  --color-mantle: #292c3c;
    \\  --color-crust: #232634;
    \\}
;

pub const default_background =
    \\body {
    \\  background-image: none;
    \\  background-color: var(--color-base);
    \\}
;

pub const default_body_font =
    \\body {
    \\  text-align: left;
    \\  font-family: "Ubuntu Mono";
    \\  font-size: 20px;
    \\  color: var(--color-text);
    \\}
;

pub const default_body_padding =
    \\body {
    \\  --padding-vertical: clamp(1.5em, 5vh, 2.5em);
    \\  margin: 0 auto;
    \\  max-width: min(90ch, 100%);
    \\  min-height: calc(100% - 2 * var(--padding-vertical));
    \\  padding: var(--padding-vertical) clamp(1.5em, 5vw, 2.5em);
    \\}
;

/// Global style for selected elements
pub const default_selection =
    \\*::selection {
    \\    background: var(--color-blue);
    \\    color: var(--color-base);
    \\}
;

pub const default_title_class =
    \\.title {
    \\  text-align: center;
    \\  font-size: 24px;
    \\  font-weight: bold;
    \\  font-family: "Nova Flat";
    \\  padding: 20px;
    \\}
;

pub const default_image_class =
    \\/* Basic centering of simple elements */
    \\.center {
    \\  display: block;
    \\  margin-left: auto;
    \\  margin-right: auto;
    \\  width: 50%;
    \\}
;

pub const default_heading_1 =
    \\h1 {
    \\  color: var(--color-blue);
    \\  margin-top: 20px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\}
;

pub const default_heading_2 =
    \\h2 {
    \\  color: var(--color-peach);
    \\  margin-top: 20px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\}
;

pub const default_heading_3 =
    \\h3 {
    \\  color: var(--color-green);
    \\  margin-top: 16px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\}
;

pub const default_heading_4 =
    \\h4 {
    \\  color: var(--color-mauve);
    \\  margin-top: 16px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\}
;

pub const default_paragraph =
    \\p {
    \\  margin-top: 0px;
    \\  margin-bottom: 12px;
    \\}
;

pub const default_ordered_list =
    \\ol {
    \\  margin-top: 0px;
    \\  margin-bottom: 0px;
    \\}
;

pub const default_unordered_list =
    \\ul {
    \\  margin-top: 0px;
    \\  margin-bottom: 0px;
    \\}
;

pub const default_list_item =
    \\li {
    \\    margin: 0.25em 0;
    \\}
;

pub const default_task_list_class =
    \\ul.task_list {
    \\  list-style: none outside none;
    \\}
;

pub const default_task_item_checked_class =
    \\ul.task_list {
    \\  li.task_checked {
    \\    list-style-type: "\2705 "; /* ✅ */
    \\  }
    \\}
;

pub const default_task_item_unchecked_class =
    \\ul.task_list {
    \\  li.task_unchecked {
    \\    list-style-type: "\2B1C "; /* ⬜ */
    \\  }
    \\}
;

pub const default_inline_code =
    \\code {
    \\  background-color: var(--color-mantle);
    \\  color: var(--color-lavender);
    \\  font-size: 18px;
    \\  margin-top: 10px;
    \\  margin-bottom: 10px;
    \\}
;

pub const default_table =
    \\.md_table {
    \\  tr, td, th {
    \\    border: 2px solid var(--color-subtext0);
    \\  }
    \\  th {
    \\    background-color: var(--color-mantle);
    \\    color: var(--color-green);
    \\  }
    \\  td {
    \\    background-color: var(--color-surface0);
    \\  }
    \\}
;

pub const default_link =
    \\a {
    \\    color: var(--color-sky);
    \\    text-decoration: none;
    \\    padding: 0.05em;
    \\
    \\    &:visited {
    \\        color: var(--color-mauve);
    \\
    \\        &:hover {
    \\            background: var(--color-mauve);
    \\        }
    \\    }
    \\
    \\    &:hover {
    \\        text-decoration: underline;
    \\        background: var(--color-sky);
    \\        color: var(--color-base);
    \\    }
    \\}
;

pub const default_blockquote =
    \\blockquote {
    \\    background: var(--color-crust);
    \\    color: var(--color-subtext1);
    \\    margin: 0;
    \\    margin-left: 0.75em;
    \\    max-width: fit-content;
    \\    padding: 0.5em;
    \\    font-style: italic;
    \\    margin: 0;
    \\
    \\    i {
    \\      font-style: normal;
    \\    }
    \\}
;

pub const default_code_block_class =
    \\.code_block {
    \\  color: var(--color-lavender);
    \\  font-family: monospace;
    \\  background-color: var(--color-mantle);
    \\  padding: 10px 12px; /* top/bottom, left/right */
    \\  margin-top: 10px;
    \\  margin-bottom: 10px;
    \\}
;

pub const default_directive_class =
    \\.directive {
    \\  border: 4px solid var(--color-red);
    \\  border-radius: 10px;
    \\  margin-top: 10px;
    \\  margin-bottom: 10px;
    \\  padding: 20px;
    \\  background-color: var(--color-red);
    \\  color: white;
    \\}
;
