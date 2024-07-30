/// containers.zig
/// Container Block type implementations
const std = @import("std");

/// Containers are Blocks which contain other Blocks
pub const ContainerType = enum(u8) {
    Document, // The Document is the root container
    Quote,
    List, // Can only contain ListItems
    ListItem, // Can only be contained by a List
};

pub const ContainerData = union(ContainerType) {
    Document: void,
    Quote: void,
    List: List,
    ListItem: ListItem,
};

/// List blocks contain only ListItems
/// However, we will use the base Container type's 'children' field to
/// store the list items for simplicity, as the ListItems are Container blocks
/// which can hold any kind of Block.
pub const List = struct {
    pub const Kind = enum {
        unordered,
        ordered,
        task,
    };
    // ordered: bool = false,
    kind: Kind = .unordered,
    start: usize = 1, // Starting number, if ordered list
};

/// Single ListItem - Only needed for Task lists
pub const ListItem = struct {
    checked: bool = false, // 󱗜  or 🗹
};
