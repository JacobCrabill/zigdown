pub const style_css = @embedFile("html/style.css");

pub const error_page =
    \\<html><body>
    \\  <link type="text/css" rel="stylesheet" href="/style.css">
    \\  <h1>Apologies! An error occurred</h1>
    \\</body></html>
;

pub const favicon = @embedFile("img/zig-zero.png");
