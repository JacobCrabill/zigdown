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
    \\*,
    \\*::before,
    \\*::after {
    \\  box-sizing: border-box;
    \\}
;

pub const default_colors =
    \\body {
    \\--color-black: #292930;
    \\--color-red: #ef6487;
    \\--color-green: #5eca89;
    \\--color-blue: #65aef7;
    \\--color-yellow: #ffff00;
    \\--color-cyan: #60EEDD;
    \\--color-white: #ffffff;
    \\--color-magenta: #eca5cb;
    \\--color-darkyellow: #aeac30;
    \\--color-purplegrey: #aa82fa;
    \\--color-mediumgrey: #707070;
    \\--color-darkgrey: #404040;
    \\--color-darkred: #802020;
    \\--color-orange: #ff9700;
    \\--color-coral: #d7649b;
    \\--color-default: #d0e0ff;
    \\--color-text: #d0e0ff;
    \\}
;

pub const default_background =
    \\body {
    \\  background-image: none;
    \\  background-color: var(--color-black);
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

pub const default_selection =
    \\*::selection {
    \\    background: var(--color-blue);
    \\    color: var(--color-black);
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
    \\/* Image centered on page */
    \\.image {
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
    \\  color: var(--color-green);
    \\  margin-top: 20px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\  border-bottom: 1px solid var(--color-green);
    \\}
;

pub const default_heading_3 =
    \\h3 {
    \\  color: var(--color-white);
    \\  margin-top: 16px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\  border-bottom: 1px solid var(--color-white);
    \\}
;

pub const default_heading_4 =
    \\h4 {
    \\  color: var(--color-white);
    \\  margin-top: 16px;
    \\  margin-bottom: 0px;
    \\  font-family: "Nova Flat";
    \\  border-bottom: 1px dashed var(--color-white);
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
    \\    list-style-type: "\2705  "; /* ✅ */
    \\  }
    \\}
;

pub const default_task_item_unchecked_class =
    \\ul.task_list {
    \\  li.task_unchecked {
    \\    list-style-type: "\2B1C  "; /* ⬜ */
    \\  }
    \\}
;

pub const default_inline_code =
    \\code {
    \\  background-color: var(--color-darkgrey);
    \\  color: var(--color-purplegrey);
    \\  font-size: 18px;
    \\  margin-top: 10px;
    \\  margin-bottom: 10px;
    \\}
;

pub const default_table =
    \\.md_table {
    \\  tr, td, th {
    \\    border: 2px solid var(--color-default);
    \\  }
    \\  th {
    \\    background-color: var(--color-mediumgrey);
    \\    color: var(--color-green);
    \\  }
    \\  td {
    \\    background-color: var(--color-darkgrey);
    \\  }
    \\}
;

pub const default_link =
    \\a {
    \\    color: var(--color-cyan);
    \\    text-decoration: none;
    \\    padding: 0.05em;
    \\
    \\    &:visited {
    \\        color: var(--color-magenta);
    \\
    \\        &:hover {
    \\            background: var(--color-magenta);
    \\        }
    \\    }
    \\
    \\    &:hover {
    \\        text-decoration: underline;
    \\        background: var(--color-blue);
    \\        color: var(--color-black);
    \\    }
    \\}
;

pub const default_blockquote =
    \\blockquote {
    \\    background: var(--color-darkgrey);
    \\    color: var(--color-text);
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
    \\  color: var(--color-purplegrey);
    \\  font-family: monospace;
    \\  background-color: var(--color-darkgrey);
    \\  padding: 10px 12px; /* top/bottom, left/right */
    \\  margin-top: 10px;
    \\  margin-bottom: 10px;
    \\}
;

pub const default_directive_class =
    \\.directive {
    \\  h1 {
    \\    color: var(--color-white);
    \\    font-size: 1.17em;
    \\    position: relative !important;
    \\    margin: 0 !important;
    \\    text-align: left;
    \\    padding-left: 15px;
    \\    padding-right: 15px;
    \\    padding-top: 5px !important;
    \\    padding-bottom: 5px !important;
    \\    background-color: var(--color-red);
    \\    width: 100%;
    \\  }
    \\  p {
    \\    margin-top: 10px;
    \\    margin-bottom: 10px;
    \\    padding-top: 10px;
    \\    padding-bottom: 10px;
    \\    padding-left: 10px;
    \\    padding-right: 10px;
    \\  }
    \\  border: 1px solid var(--color-red);
    \\  background-color: var(--color-darkgrey);
    \\  color: var(--color-white);
    \\  /* border-radius: 1ch; */
    \\}
;
