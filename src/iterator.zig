// ********************************************************************************
//! https://github.com/PatrickTorgerson/ego
//! Copyright (c) 2022 Patrick Torgerson
//! ego uses the MIT license, see LICENSE for more information
// ********************************************************************************

const std = @import("std");

pub fn ReverseIter(comptime T: type) type {
    return struct {
        const This = @This();

        slice: []T,
        i: usize,

        pub fn init(slice: []T) This {
            return This {
                .slice = slice,
                .i = slice.len - 1,
            };
        }

        pub fn next(this: *This) ?T {
            // 0 -% 1 == ~@as(usize,0) > slice.len
            if(this.i >= this.slice.len)
                return null;
            // wrapping to prevent under-flow
            defer this.i -%= 1;
            return this.slice[this.i];
        }
    };
}
