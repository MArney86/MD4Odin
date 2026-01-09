package md4o
/*
 * MD4Odin: Markdown parser for Odin, based on MD4C (http://github.com/mity/md4c)
 * (http://github.com/MArney86/MD4Odin)
 *
 * Original Copyright (c) 2016-2024 Martin Mitáš
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
 * IN THE SOFTWARE.
 */

TRUE :: true
FALSE :: false

MD4O_USE_UTF16 :: FALSE
MD4O_USE_ASCII :: FALSE

when !MD4O_USE_ASCII && !MD4O_USE_UTF16 {
    MD4O_USE_UTF8 :: TRUE
} else {
    MD4O_USE_UTF8 :: FALSE
}

// Magic to support UTF-16. Note that in order to use it, you have to define
// MD4O_USE_UTF16 as true both when building MD4Odin as well as when
// including this package in your code.
when MD4O_USE_UTF16 {
    when ODIN_OS == .Windows {
        // On Windows, use u16 (equivalent to WCHAR)
        MD_CHAR :: u16
    } else {
        #panic("MD4O_USE_UTF16 is only supported on Windows.")
    }
} else {
    // Default to u8 (char equivalent)
    MD_CHAR :: u8   
}

// Magic for making wide literals with MD4O_USE_UTF16.
// In Odin, we use compile-time when statements instead of preprocessor macros.
// String literals are UTF-8 by default, UTF-16 requires explicit conversion.
CHAR :: distinct u16 when MD4O_USE_UTF16 else u8
/******************************
 ***  Some internal limits  ***
 ******************************/

/* We limit code span marks to lower than 32 backticks. This solves the
 * pathologic case of too many openers, each of different length: Their
 * resolving would be then O(n^2). */
CODESPAN_MARK_MAXLEN :: 32

/* We limit column count of tables to prevent quadratic explosion of output
 * from pathological input of a table thousands of columns and thousands
 * of rows where rows are requested with as little as single character
 * per-line, relying on us to "helpfully" fill all the missing "<td></td>". */
TABLE_MAXCOLCOUNT :: 128

// Misc. macros converted to Odin idioms
// Note: Odin has built-in len() for arrays, max()/min() for comparisons,
// and true/false for booleans. These are provided for API compatibility.

// MD_LOG - logging helper
// Call the debug_log callback if it exists
@(private)
md_log :: proc(ctx: ^MD_CTX, msg: string) {
    if ctx.parser.debug_log != nil {
        ctx.parser.debug_log(msg, ctx.userdata)
    }
}

// MD_ASSERT - assertion with debug support
when ODIN_DEBUG {
    md_assert :: proc(cond: bool, loc := #caller_location) {
        if !cond {
            // In debug mode, log the assertion failure and panic
            // Note: You'll need to implement MD_CTX access for full logging
            panic("Assertion failed", loc)
        }
    }
    
    md_unreachable :: proc(loc := #caller_location) -> ! {
        panic("Unreachable code reached", loc)
    }
} else {
    md_assert :: #force_inline proc(cond: bool) {
        // In release mode, give a hint to the compiler
        if !cond {
            unreachable()
        }
    }
    
    md_unreachable :: #force_inline proc() -> ! {
        unreachable()
    }
}