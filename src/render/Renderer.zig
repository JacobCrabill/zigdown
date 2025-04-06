/// Generic Renderer interface.
/// Can be used in the future to easily enable new renderer types.
const std = @import("std");

const blocks = @import("../blocks.zig");

/// The type erased pointer to the renderer implementation
ptr: *anyopaque,

/// Virtual function table of the renderer implementation
vtable: *const VTable,

pub const VTable = struct {
    /// Generic interface to render a Markdown document
    render: *const fn (*anyopaque, document: Block) RenderError!void,

    /// Generic interface to render a Markdown document
    deinit: *const fn (*anyopaque) void,
};

pub const RenderError = SystemError || AnyWriter.Error || Block.Error;

const Block = blocks.Block;
const AnyWriter = std.io.AnyWriter;

const SystemError = error{
    OutOfMemory,
    DiskQuota,
    FileTooBig,
    InputOutput,
    NoSpaceLeft,
    DeviceBusy,
    InvalidArgument,
    AccessDenied,
    BrokenPipe,
    SystemResources,
    OperationAborted,
    NotOpenForWriting,
    LockViolation,
    WouldBlock,
    ConnectionResetByPeer,
    Unexpected,
    SystemError,
};
