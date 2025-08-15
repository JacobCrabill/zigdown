pub const Css = @import("html/Css.zig");

pub const error_page =
    \\<html><body>
    \\  <link type="text/css" rel="stylesheet" href="/style.css">
    \\  <h1>Apologies! An error occurred</h1>
    \\</body></html>
;

pub const favicon = @embedFile("img/zig-zero.png");

/// Baked-in font files
pub const Fonts = struct {
    pub const @"NovaFlatBook.ttf" = @embedFile("html/fonts/NovaFlat-Book.ttf");
    pub const @"NovaFlatBookOblique.ttf" = @embedFile("html/fonts/NovaFlat-BookOblique.ttf");
    pub const @"NovaFlatBold.ttf" = @embedFile("html/fonts/NovaFlat-Bold.ttf");
    pub const @"NovaFlatBoldOblique.ttf" = @embedFile("html/fonts/NovaFlat-BoldOblique.ttf");
    pub const @"RobotoMonoLight.ttf" = @embedFile("html/fonts/RobotoMono-Light.ttf");
    pub const @"RobotoMonoLightItalic.ttf" = @embedFile("html/fonts/RobotoMono-LightItalic.ttf");
    pub const @"RobotoMonoBold.ttf" = @embedFile("html/fonts/RobotoMono-Bold.ttf");
    pub const @"RobotoMonoBoldItalic.ttf" = @embedFile("html/fonts/RobotoMono-BoldItalic.ttf");
};
