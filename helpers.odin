package md4o

import "base:runtime"
/* MD4Odin: Markdown parser for Odin, based on MD4C (http://github.com/mity/md4c)
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

import fmt "core:fmt"
import strings "core:strings"
import mem "core:mem"
import utf8 "core:unicode/utf8"

/* Logging and assertions for debugging. */
when ODIN_DEBUG {
    MD_LOG :: #force_inline proc(msg: string, type: LOG_TYPES = LOG_TYPES.DEBUG) {
        colors := [4]string{"0;41", "1;31", "1;33", "1;34"} // Fatal, Error, Warning, Debug
        prefixes := [4]string{"[FATAL]: ", "[ERROR]: ", "[WARNING]: ", "[DEBUG]: "}
        if int(type) < int(LOG_TYPES.WARNING) {
            fmt.eprintfln("\033[%sm%s%s\033[0m", colors[int(type)], prefixes[int(type)], msg)
        } else {
            fmt.printfln("\033[%sm%s%s\033[0m", colors[int(type)], prefixes[int(type)], msg)
        }
    }

    MD_ASSERT :: #force_inline proc(cond: bool, exp: string = #caller_expression(cond), loc := #caller_location) {
        if !cond {
            assert(cond, exp, loc)
        }
    }
} else {
    MD_LOG :: #force_inline proc(msg: string) {
        // No-op
    }

    MD_ASSERT :: #force_inline proc(cond: bool, exp: string = #caller_expression(cond), loc := #caller_location) {
        // No-op
    }
}

/* Temporary buffer management.
 * Ensures ctx.buffer has at least 'sz' bytes allocated.
 * Returns 0 on success, -1 on allocation failure. */
MD_TEMP_BUFFER :: proc(ctx: ^MD_CTX, sz: SZ) -> runtime.Allocator_Error #optional_allocator_error{
    
    if sz > ctx.alloc_buffer {
        new_buffer_size: SZ = (sz + sz / 2 + 128) & ~SZ(127) // Grow by 1.5x + 256 bytes, align to 256 bytes
        new_buffer, err := make([]MD_CHAR, new_buffer_size)
        switch err {
            case .None :
                if ctx.buffer != nil {
                    delete(ctx.buffer^)
                    ctx.buffer = nil
                }
                ctx.buffer = &new_buffer
                ctx.alloc_buffer = new_buffer_size

            case .Out_Of_Memory :
                MD_LOG("Out of memory allocating temporary buffer.", .FATAL)
            
            case .Invalid_Pointer :
                MD_LOG("Invalid pointer when allocating temporary buffer.", .FATAL)

            case .Invalid_Argument :
                MD_LOG("Invalid argument when allocating temporary buffer.", .FATAL)

            case .Mode_Not_Implemented :
                MD_LOG("Mode not implemented when allocating temporary buffer.", .FATAL)
        }
    }
}

/* Parser callback helpers.
 * These replace the C macros for calling parser callbacks with error checking.
 * Returns 0 on success, or the error code from the callback. */

MD_ENTER_BLOCK :: #force_inline proc(ctx: ^MD_CTX, type: MD_BLOCKTYPE, arg: rawptr) -> int {
    ret := ctx.parser.enter_block^(type, arg, ctx.userdata)
    if ret != 0 {
        MD_LOG("Aborted from enter_block() callback.", .ERROR)
    }
    return ret
}

MD_LEAVE_BLOCK :: #force_inline proc(ctx: ^MD_CTX, type: MD_BLOCKTYPE, arg: rawptr) -> int {
    ret := int(ctx.parser.leave_block^(type, arg, ctx.userdata))
    if ret != 0 {
        MD_LOG("Aborted from leave_block() callback.", .ERROR)
    }
    return ret
}

MD_ENTER_SPAN :: #force_inline proc(ctx: ^MD_CTX, type: MD_SPANTYPE, arg: rawptr) -> int {
    ret := int(ctx.parser.enter_span^(type, arg, ctx.userdata))
    if ret != 0 {
        MD_LOG("Aborted from enter_span() callback.", .ERROR)
    }
    return ret
}

MD_LEAVE_SPAN :: #force_inline proc(ctx: ^MD_CTX, type: MD_SPANTYPE, arg: rawptr) -> int {
    ret := int(ctx.parser.leave_span^(type, arg, ctx.userdata))
    if ret != 0 {
        MD_LOG("Aborted from leave_span() callback.", .ERROR)
    }
    return ret
}

MD_TEXT :: #force_inline proc(ctx: ^MD_CTX, type: MD_TEXTTYPE, str: string, size: SZ) -> int {
    if size > 0 {
        // We use a local to be able to take its address
        local_str := str
        ret := int(ctx.parser.text^(type, &local_str, size, ctx.userdata))
        if ret != 0 {
            MD_LOG("Aborted from text() callback.", .ERROR)
            return ret
        }
    }
    return 0
}

MD_TEXT_INSECURE :: #force_inline proc(ctx: ^MD_CTX, type: MD_TEXTTYPE, str: string, size: SZ) -> int {
    if size > 0 {
        ret := md_text_with_null_replacement(ctx, type, str, size)
        if ret != 0 {
            MD_LOG("Aborted from text() callback.", .ERROR)
            return ret
        }
    }
    return 0
}

md_lookup_line :: proc(off: OFF, lines: []MD_LINE, p_line_index: ^MD_SIZE) -> ^MD_LINE {
    lo, hi, pivot: MD_SIZE
    line: ^MD_LINE
    
    lo = 0
    hi = len(lines) - 1
    for lo <= hi {
        pivot = (lo + hi) / 2
        line = &lines[pivot]

        if off < line.beg {
            if hi == 0 || lines[hi - 1].end < off {
                if p_line_index != nil {
                    p_line_index^ = pivot
                }
                return line
            }
            hi = pivot - 1
        } else if  off > line.end {
            lo = pivot + 1
        } else {
            if p_line_index != nil {
                p_line_index^ = pivot
            }
            return line
        }
    }
    
    return nil
}



/**********************************
 ***  Character Classification  ***
 **********************************/

/* String helper - finds rune in string and returns pointer to that rune.
 * Equivalent to C's strchr/wcschr. Returns nil if not found. */
md_strrune :: proc(str: MD_STR, ch: rune) -> ^rune {
    str_bytes := transmute([]u8)str
    byte_offset := 0
    for r in str {
        if r == ch {
            return cast(^rune)raw_data(str_bytes[byte_offset:])
        }
        // Advance byte offset by the size of this rune
        _, size := strings.decode_rune(str_bytes[byte_offset:])
        byte_offset += size
    }
    return nil
}

 /* Character accessors. */
CH :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> rune {
    return off <= len(ctx.text) ? ctx.text[off] : 0
}

STR :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> MD_STR {
    return ctx.text[off:]
}

/* Character classification.
 * Note we assume ASCII compatibility of code points < 128 here. */

ISIN_ :: #force_inline proc(ch: rune, ch_min: rune, ch_max: rune) -> bool {
    return ch_min <= ch && ch <= ch_max
}

ISANYOF_ :: #force_inline proc(ch: rune, palette: string) -> bool {
    return ch != '\x00' && strings.contains_rune(palette, ch)
}

ISANYOF2_ :: #force_inline proc(ch: rune, ch1: rune, ch2: rune) -> bool {
    return ch == ch1 || ch == ch2
}

ISANYOF3_ :: #force_inline proc(ch: rune, ch1: rune, ch2: rune, ch3: rune) -> bool {
    return ch == ch1 || ch == ch2 || ch == ch3
}

ISASCII_ :: #force_inline proc(ch: rune) -> bool {
    return ch <= 0x7
}

ISBLANK_ :: #force_inline proc(ch: rune) -> bool {
    return ISANYOF2_(ch, ' ', '\t')
}

ISNEWLINE_ :: #force_inline proc(ch: rune) -> bool {
    return ISANYOF2_(ch, '\r', '\n')
}

ISWHITESPACE_ :: #force_inline proc(ch: rune) -> bool {
    return ISBLANK_(ch) || ISANYOF2_(ch, '\v', '\f')
}

ISCNTRL_ :: #force_inline proc(ch: rune) -> bool {
    return ch <= 0x1F || ch == 0x7F
}

ISPUNCT_ :: #force_inline proc(ch: rune) -> bool {
    return ISIN_(ch, 0x21, 0x2F) || ISIN_(ch, 0x3A, 0x40) || ISIN_(ch, 0x5B, 0x60) || ISIN_(ch, 0x7B, 0x7E)
}

ISUPPER_ :: #force_inline proc(ch: rune) -> bool {
    return ISIN_(ch, 'A', 'Z')
}

ISLOWER_ :: #force_inline proc(ch: rune) -> bool {
    return ISIN_(ch, 'a', 'z')
}

ISALPHA_ :: #force_inline proc(ch: rune) -> bool {
    return ISUPPER_(ch) || ISLOWER_(ch)
}

ISDIGIT_ :: #force_inline proc(ch: rune) -> bool {
    return ISIN_(ch, '0', '9')
}

ISXDIGIT_ :: #force_inline proc(ch: rune) -> bool {
    return ISDIGIT_(ch) || ISIN_(ch, 'A', 'F') || ISIN_(ch, 'a', 'f')
}

ISALNUM_ :: #force_inline proc(ch: rune) -> bool {
    return ISALPHA_(ch) || ISDIGIT_(ch)
}

// Offset-based versions that call CH(off)
ISANYOF :: #force_inline proc(ctx: ^MD_CTX, off: OFF, palette: string) -> bool {
    return ISANYOF_(CH(ctx, off), palette)
}

ISANYOF2 :: #force_inline proc(ctx: ^MD_CTX, off: OFF, ch1: rune, ch2: rune) -> bool {
    return ISANYOF2_(CH(ctx, off), ch1, ch2)
}

ISANYOF3 :: #force_inline proc(ctx: ^MD_CTX, off: OFF, ch1: rune, ch2: rune, ch3: rune) -> bool {
    return ISANYOF3_(CH(ctx, off), ch1, ch2, ch3)
}

ISASCII :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISASCII_(CH(ctx, off))
}

ISBLANK :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISBLANK_(CH(ctx, off))
}

ISNEWLINE :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISNEWLINE_(CH(ctx, off))
}

ISWHITESPACE :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISWHITESPACE_(CH(ctx, off))
}

ISCNTRL :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISCNTRL_(CH(ctx, off))
}

ISPUNCT :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISPUNCT_(CH(ctx, off))
}

ISUPPER :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISUPPER_(CH(ctx, off))
}

ISLOWER :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISLOWER_(CH(ctx, off))
}

ISALPHA :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISALPHA_(CH(ctx, off))
}

ISDIGIT :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISDIGIT_(CH(ctx, off))
}

ISXDIGIT :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISXDIGIT_(CH(ctx, off))
}

ISALNUM :: #force_inline proc(ctx: ^MD_CTX, off: OFF) -> bool {
    return ISALNUM_(CH(ctx, off))
}

// Case insensitive check of string equality
md_ascii_case_eq :: proc(s1: MD_STR, s2: MD_STR) -> bool {
    if len(s1) != len(s2) { return false }
    i := 0
    for {
        //Decode the next rune and it's size in bytes from s1
        r1 := s1[i]
        //Decode the next rune and it's size in bytes from s2
        r2 := s2[i]

        //compare the runes in a case insensitive manner
        if ISLOWER_(r1) { r1 += ('A' - 'a') }
        if ISLOWER_(r2) { r2 += ('A' - 'a') }
        if r1 != r2 { return false }
        i += 1
    }
    return true
}

md_ascii_eq :: proc(s1: MD_STR, s2: MD_STR) -> bool {
    return runtime.string_eq(s1, s2)
}

md_text_with_null_replacement :: proc(ctx: ^MD_CTX, type: MD_TEXTTYPE, str: MD_STR) -> int {
    index: OFF = 0
    ret: int = 0

    for {
        // Find next null character
        for index < len(str) && str[index] != 0 {
            index += 1
        }

        // Process text before null character
        if index > 0 {
            ret = int(ctx.parser.text^(type, &text_to_send, off, ctx.userdata))
            if ret != 0 {
                return ret
            }

            remaining_str = remaining_str[off:]
            remaining_size -= off
        }

        // Done if we've processed everything
        if remaining_size == 0 {
            return 0
        }

        // Send null character replacement
        null_str := ""
        ret = int(ctx.parser.text^(MD_TEXTTYPE.NULLCHAR, &null_str, 1, ctx.userdata))
        if ret != 0 {
            return ret
        }
        
        remaining_str = remaining_str[1:]
        remaining_size -= 1
    }
}

/* Binary search over sorted "map" of codepoints. Consecutive sequences
 * of codepoints may be encoded in the map by just using the
 * (MIN_CODEPOINT | 0x40000000) and (MAX_CODEPOINT | 0x80000000).
 *
 * Returns index of the found record in the map (in the case of ranges,
 * the minimal value is used); or -1 on failure. */
md_unicode_bsearch__ :: proc(codepoint: u32, arr_map: ^[]u32) -> int {
    beg: int
    end: int
    pivot_beg, pivot_end: int
    arr_size := len(arr_map)
    beg = 0
    end = arr_size - 1
    for beg <= end {
        /* Pivot may be a range, not just a single value. */
        pivot_beg = (beg + end) / 2
        pivot_end = pivot_beg
        if arr_map[pivot_end] & 0x40000000 != 0 {
            pivot_end += 1
        }
        if arr_map[pivot_beg] & 0x80000000 != 0 {
            pivot_beg -= 1
        }

        if codepoint < (arr_map[pivot_beg] & 0x00ffffff) {
            end = pivot_beg - 1
        } else if codepoint > (arr_map[pivot_end] & 0x00ffffff) {
            beg = pivot_end + 1
        } else {
            return pivot_beg
        }
    }

    return -1
}



map_builder :: #force_inline proc(args: ..u32) -> (uni_map:^[]u32, err: runtime.Allocator_Error) #optional_allocator_error{
    result: []u32
    err: runtime.Allocator_Error
    result, err = make([]u32, len(args))

    if err != .None {
        return nil, err
    }

    for i: int = 0; i < len(args); i += 1 {
        result[i] = args[i]
    }

    ptr := new([]u32)
    ptr^ = result
    return ptr, err
}

R :: #force_inline proc(cp_min: u32, cp_max: u32) -> (min:u32, max:u32) {
    min = cp_min | 0x40000000
    max = cp_max | 0x80000000
    return
}

md_is_unicode_whitespace__ :: proc(ctx:^MD_CTX, codepoint: u32) -> (ret: bool , err: runtime.Allocator_Error) #optional_allocator_error{
    // Initialize the Unicode whitespace map on first use
    err = .None
    unicode_map: []u32
    if ctx.unicode_maps.whitespace == nil {
        unicode_map, err = map_builder(
            0x0020, 0x0085, 0x00A0, 0x1680, // Space, NEXT LINE, NBSP, OGHAM SPACE MARK
            R(0x2000, 0x200A), // EN QUAD to HAIR SPACE
            R(0x2028, 0x2029), // LINE SEPARATOR, PARAGRAPH SEPARATOR
            0x202F, 0x205F, 0x3000 // NARROW NO-BREAK SPACE, MEDIUM MATHEMATICAL SPACE, IDEOGRAPHIC SPACE
        )

        if err != .None {
            MD_LOG("error allocating Unicode whitespace map.")
            return false, err
        }

        ctx.unicode_maps.whitespace = &unicode_map
    }

    if codepoint <= 0x7F {
        return ISWHITESPACE_(cast(rune)codepoint), err
    }

    return md_unicode_bsearch__(codepoint, ctx.unicode_maps.whitespace) != -1, err
}

md_is_unicode_punct__ :: proc(ctx:^MD_CTX, codepoint: u32) -> (ret: bool , err: runtime.Allocator_Error) #optional_allocator_error{
    // Initialize the Unicode punctuation map on first use
    err = .None
    if ctx.unicode_maps.punctuation == nil {
        unicode_map, u_err = map_builder(
            R(0x00A1, 0x00A9), R(0x00AB, 0x00AC), R(0x00AE,0x00B1), 0x00B4, R(0x00B6,0x00B8), 0x00BB, 0x00BF, 0x00D7, 0x00F7, R(0x02C2,0x02C5), R(0x02D2,0x02DF), R(0x02E5,0x02EB), 0x02ED, 
            R(0x02EF,0x02FF), 0x0375, 0x037E, R(0x0384,0x0385), 0x0387, 0x03f6, 0x0482, R(0x055A,0x055F), R(0x0589,0x058A), R(0x058D,0x058F), 0x05BE, 0x05C0, 0x05C3, 0x05C6, 
            R(0x05F3,0x05F4), R(0x0606,0x060F), 0x061B, R(0x061D,0x061F), R(0x066A,0x066D), 0x06D4, 0x06DE, 0x06E9, R(0x06FD,0x06FE), R(0x0700,0x070D), R(0x07F6,0x07F9), R(0x07FE,0x07FF), 
            R(0x0830,0x083E), 0x085E, 0x0888, R(0x0964,0x0965), 0x0970, R(0x09f2,0x09F3), R(0x09FA, 0x09FB), 0x09FD, 0x0A76, R(0x0AF0,0x0AF1), 0x0B70, R(0x0BF3,0x0BFA), 0x0C77, 0x0C7F, 
            0x0C84, 0x0D4F, 0x0D79, 0x0DF4, 0x0E3F, 0x0E4F, R(0x0E5A,0x0E5B), R(0x0F01,0x0F17), R(0x0F1A,0x0F1F), 0x0F34, 0x0F36, 0x0F38, R(0x0F3A,0x0F3D), 0x0F85, R(0x0FBE,0x0FC5), 
            R(0x0FC7,0x0FCC), R(0x0FCE,0x0FDA), R(0x104A,0x104F), R(0x109E,0x109F), 0x10FB, R(0x1360,0x1368), R(0x1390,0x1399), 0x1400, R(0x166D,0x166E), R(0x169B,0x169C), R(0x16EB,0x16ED), 
            R(0x1735,0x1736), R(0x17D4,0x17D6), R(0x17D8,0x17DB), R(0x1800,0x180A), 0x1940, R(0x1944,0x1945), R(0x19DE,0x19FF), R(0x1A1E,0x1A1F), R(0x1AA0,0x1AA6), R(0x1AA8,0x1AAD), 
            R(0x1B5A,0x1B6A), R(0x1B74,0x1B7E), R(0x1BFC,0x1BFF), R(0x1C3B,0x1C3F), R(0x1C7E,0x1C7F), R(0x1CC0,0x1CC7), 0x1CD3, 0x1FBD, R(0x1FBF,0x1FC1), R(0x1FCD,0x1FCF), R(0x1FDD,0x1FDF), 
            R(0x1FED,0x1FEF), R(0x1FFD,0x1FFE), R(0x2010,0x2027), R(0x2030, 0x205E), R(0x2030,0x205e), R(0x207A,0x207E), R(0x208A,0x208E), R(0x20A0,0x20C0), R(0x2100,0x2101), 
            R(0x2103,0x2106), R(0x2108,0x2109), 0x2114, R(0x2116,0x2118), R(0x211E,0x2123), 0x2125, 0x2127, 0x2129, 0x212E, R(0x213A,0x213B), R(0x2140,0x2144), R(0x214A,0x214D), 0x214F, 
            R(0x218A,0x218B), R(0x2190,0x2426), R(0x2440,0x244A), R(0x249C,0x24E9), R(0x2500,0x2775), R(0x2794,0x2B73), R(0x2B76,0x2B95), R(0x2B97,0x2BFF), R(0x2CE5,0x2CEA), 
            R(0x2CF9,0x2CFC), R(0x2CFE,0x2CFF), 0x2D70, R(0x2E00, 0x2E7F), R(0x2E80,0x2E99), R(0x2E9B,0x2EF3), R(0x2F00,0x2FD5), R(0x2FF0,0x2FFF), R(0x3001,0x3004), R(0x3008,0x3020), 
            0x3030, R(0x3036,0x3037), R(0x303D,0x303F), R(0x309B,0x309C), 0x30A0, 0x30FB, R(0x3190,0x3191), R(0x3196,0x319F), R(0x31C0,0x31E3), 0x31EF, R(0x3200,0x321E), R(0x322A,0x3247), 
            0x3250, R(0x3260,0x327F), R(0x328A,0x32B0), R(0x32C0,0x33FF), R(0x4DC0,0x4DFF), R(0xA490,0xA4C6), R(0xA4FE,0xA4FF), R(0xA60D,0xA60F), 0xA673, 0xA67E, R(0xA6F2,0xA6F7), 
            R(0xA700,0xA716), R(0xA720,0xA721), R(0xA789,0xA78A), R(0xA828,0xA82B), R(0xA836,0xA839), R(0xA874,0xA877), R(0xA8CE,0xA8CF), R(0xA8F8,0xA8FA), 0xA8FC, R(0xA92E,0xA92F), 0xA95F, 
            R(0xA9C1,0xA9CD), R(0xA9DE,0xA9DF), R(0xAA5C,0xAA5F), R(0xAA77,0xAA79), R(0xAADE,0xAADF), R(0xAAF0,0xAAF1), 0xAB5B, R(0xAB6A,0xAB6B), 0xABEB, 0xFB29, R(0xFBB2,0xFBC2), 
            R(0xFD3E,0xFD4F), 0xFDCF, R(0xFDFC,0xFDFF), R(0xFE10,0xFE19), R(0xFE30,0xFE52), R(0xFE54,0xFE66), R(0xFE68,0xFE6B), R(0xFF01,0xFF0F), R(0xFF1A,0xFF20), R(0xFF3B,0xFF40), 
            R(0xFF5B,0xFF65), R(0xFFE0,0xFFE6), R(0xFFE8,0xFFEE), R(0xFFFC,0xFFFD), R(0x10100,0x10102), R(0x10137,0x1013F), R(0x10179,0x10189), R(0x1018C,0x1018E), R(0x10190,0x1019C), 
            0x101A0, R(0x101D0,0x101FC), 0x1039F, 0x103D0, 0x1056F, 0x10857, R(0x10877,0x10878), 0x1091F, 0x1093F, R(0x10A50,0x10A58), 0x10A7F, 0x10AC8, R(0x10AF0,0x10AF6), R(0x10B39,0x10B3F), 
            R(0x10B99,0x10B9C), 0x10EAD, R(0x10F55,0x10F59), R(0x10F86,0x10F89), R(0x11047,0x1104D), R(0x110BB,0x110BC), R(0x110BE,0x110C1), R(0x11140,0x11143), R(0x11174,0x11175), 
            R(0x111C5,0x111C8), 0x111CD, 0x111DB, R(0x111DD,0x111DF), R(0x11238,0x1123D), 0x112A9, R(0x1144B,0x1144F), R(0x1145A,0x1145B), 0x1145D, 0x114C6, R(0x115C1,0x115D7), 
            R(0x11641,0x11643), R(0x11660,0x1166C), 0x116B9, R(0x1173C,0x1173F), 0x1183B, R(0x11944,0x11946), 0x119E2, R(0x11A3F,0x11A46), R(0x11A9A,0x11A9C), R(0x11A9E,0x11AA2), 
            R(0x11B00,0x11B09), R(0x11C41,0x11C45), R(0x11C70,0x11C71), R(0x11EF7,0x11EF8), R(0x11F43,0x11F4F), R(0x11FD5,0x11FF1), 0x11FFF, R(0x12470,0x12474), R(0x12FF1,0x12FF2), 
            R(0x16A6E,0x16A6F), 0x16AF5, R(0x16B37,0x16B3F), R(0x16B44,0x16B45), R(0x16E97,0x16E9A), 0x16FE2, 0x1BC9C, 0x1BC9F, R(0x1CF50,0x1CFC3), R(0x1D000,0x1D0F5), R(0x1D100,0x1D126), 
            R(0x1D129,0x1D164), R(0x1D16A,0x1D16C), R(0x1D183,0x1D184), R(0x1D18C,0x1D1A9), R(0x1D1AE,0x1D1EA), R(0x1D200,0x1D241), 0x1D245, R(0x1D300,0x1D356), 0x1D6C1, 0x1D6DB, 0x1D6FB, 
            0x1D715, 0x1D735, 0x1D74F, 0x1D76F, 0x1D789, 0x1D7A9, 0x1D7C3, R(0x1D800,0x1D9FF), R(0x1DA37,0x1DA3A), R(0x1DA6D,0x1DA74), R(0x1DA76,0x1DA83), R(0x1DA85,0x1DA8B), 0x1E14F, 0x1E2FF, 
            R(0x1E95E,0x1E95F), 0x1ECAC, 0x1ECB0, 0x1ED2E, R(0x1EEF0,0x1EEF1), R(0x1F000,0x1F02B), R(0x1F030,0x1F093), R(0x1F0A0,0x1F0AE), R(0x1F0B1,0x1F0BF), R(0x1F0C1,0x1F0CF), 
            R(0x1F0D1,0x1F0F5), R(0x1F10D,0x1F1AD), R(0x1F1E6,0x1F202), R(0x1F210,0x1F23B), R(0x1F240,0x1F248), R(0x1F250,0x1F251), R(0x1F260,0x1F265), R(0x1F300,0x1F6D7), R(0x1F6DC,0x1F6EC), 
            R(0x1F6F0,0x1F6FC), R(0x1F700,0x1F776), R(0x1F77B,0x1F7D9), R(0x1F7E0,0x1F7EB), 0x1F7F0, R(0x1F800,0x1F80B), R(0x1F810,0x1F847), R(0x1F850,0x1F859), R(0x1F860,0x1F887), 
            R(0x1F890,0x1F8AD), R(0x1F8B0,0x1F8B1), R(0x1F900,0x1FA53), R(0x1FA60,0x1FA6D), R(0x1FA70,0x1FA7C), R(0x1FA80,0x1FA88), R(0x1FA90,0x1FABD), R(0x1FABF,0x1FAC5), R(0x1FACE,0x1FADB), 
            R(0x1FAE0,0x1FAE8), R(0x1FAF0,0x1FAF8), R(0x1FB00,0x1FB92), R(0x1FB94,0x1FBCA))

        if u_err != .None {
            MD_LOG("error allocating Unicode punctuation map.")
            return false, u_err
        }
    }

    if codepoint <= 0x7F {
        return ISPUNCT_(cast(rune)codepoint), u_err
    }

    return md_unicode_bsearch__(codepoint, ctx.unicode_maps.punctuation) != -1, u_err
}

md_get_unicode_fold_info :: proc(ctx: ^MD_CTX, codepoint: u32, info: ^MD_UNICODE_FOLD_INFO) {
    if ctx.unicode_maps.fold_map_1 == nil {
        unicode_map, err := map_builder(
            R(0x0041,0x005A), 0x00B5, R(0x00C0,0x00D6), R(0x00D8,0x00DE), R(0x0100,0x012E), R(0x0132,0x0136), R(0x0139,0x0147), R(0x014A,0x0176), 0x0178, R(0x0179,0x017D), 0x017F, 0x0181, 0x0182,
            0x0184, 0x0186, 0x0187, 0x0189, 0x018A, 0x018B, 0x018E, 0x018F, 0x0190, 0x0191, 0x0193, 0x0194, 0x0196, 0x0197, 0x0198, 0x019C, 0x019D, 0x019F, R(0x01A0,0x01A4), 0x01A6, 0x01A7, 0x01A9, 
            0x01AC, 0x01AE, 0x01AF, 0x01B1, 0x01B2, 0x01B3, 0x01B5, 0x01B7, 0x01B8, 0x01BC, 0x01C4, 0x01C5, 0x01C7, 0x01C8, 0x01CA, R(0x01CB,0x01DB), R(0x01DE,0x01EE), 0x01F1, 0x01F2, 0x01F4, 0x01F6, 
            0x01f7, R(0x01F8,0x021E), 0x0220, R(0x0222,0x0232), 0x023A, 0x023B, 0x023D, 0x023E, 0x0241, 0x0243, 0x0244, 0x0245, R(0x0246,0x024E), 0x0345, 0x0370, 0x0372, 0x0376, 0x037F,0x0386, 
            R(0x0388,0x038A), 0x038C, 0x038E, 0x038F, R(0x0391,0x03A1), R(0x03A3,0x03AB), 0x03C2, 0x03CF, 0x03D0, 0x03D1, 0x03D5, 0x03D6, R(0x03D8,0x03EE), 0x03F0, 0x03F1, 0x03F4, 0x03F5, 0x03F7, 
            0x03F9, 0x03FA, R(0x03FD,0x03FF), R(0x0400,0x040F), R(0x0410,0x042F), R(0x0460,0x0480), R(0x048A,0x04BE), 0x04C0, R(0x04C1,0x04CD), R(0x04D0,0x052E), R(0x0531,0x0556), R(0x10A0,0x10C5), 
            0x10C7, 0x10CD, R(0x13F8,0x13FD), 0x1C80, 0x1C81, 0x1C82, 0x1C83, 0x1C84, 0x1C85, 0x1C86, 0x1C87, 0x1C88, R(0x1C90,0x1CBA), R(0x1CBD,0x1CBF), R(0x1E00,0x1E94), 0x1E9B, R(0x1EA0,0x1EFE), 
            R(0x1F08,0x1F0F), R(0x1F18,0x1F1D), R(0x1F28,0x1F2F), R(0x1F38,0x1F3F), R(0x1F48,0x1F4D), 0x1F59, 0x1F5B, 0x1F5D, 0x1F5F, R(0x1F68,0x1F6F), 0x1FB8, 0x1FB9, 0x1FBA, 0x1FBB, 0x1FBE, 
            R(0x1FC8,0x1FCB), 0x1FD8, 0x1FD9, 0x1FDA, 0x1FDB, 0x1FE8, 0x1FE9, 0x1FEA, 0x1FEB, 0x1FEC, 0x1FF8, 0x1FF9, 0x1FFA, 0x1FFB, 0x2126, 0x212A, 0x212B, 0x2132, R(0x2160,0x216F), 0x2183, 
            R(0x24B6,0x24CF), R(0x2C00,0x2C2F), 0x2C60, 0x2C62, 0x2C63, 0x2C64, R(0x2C67,0x2C6B), 0x2C6D, 0x2C6E, 0x2C6F, 0x2C70, 0x2C72, 0x2C75, 0x2C7E, 0x2C7F, R(0x2C80,0x2CE2), 0x2CEB, 0x2CED, 
            0x2CF2, R(0xA640,0xA66C), R(0xA680,0xA69A), R(0xA722,0xA72E), R(0xA732,0xA76E), 0xA779, 0xA77B, 0xA77D, R(0xA77E,0xA786), 0xA78B, 0xA78D, 0xA790, 0xA792, R(0xA796,0xA7A8), 0xA7AA, 0xA7AB, 
            0xA7AC, 0xA7AD, 0xA7AE, 0xA7B0, 0xA7B1, 0xA7B2, 0xA7B3, R(0xA7B4,0xA7C2), 0xA7C4, 0xA7C5, 0xA7C6, 0xA7C7, 0xA7C9, 0xA7D0, 0xA7D6, 0xA7D8, 0xA7F5, R(0xAB70,0xABBF), R(0xFF21,0xFF3A), 
            R(0x10400,0x10427), R(0x104B0,0x104D3), R(0x10570,0x1057A), R(0x1057C,0x1058A), R(0x1058C,0x10592), 0x10594, 0x10595, R(0x10C80,0x10CB2), R(0x118A0,0x118BF), R(0x16E40,0x16E5F), R(0x1E900,0x1E921)
        )

        if err != .None {
            MD_LOG("error allocating Unicode case fold map.")
            return
        }

        ctx.unicode_maps.fold_map_1 = &unicode_map
    }

    if ctx.unicode_maps.fold_map_1_data == nil {
        unicode_map, err := map_builder(
            0x0061, 0x007A, 0x03BC, 0x00E0, 0x00F6, 0x00F8, 0x00FE, 0x0101, 0x012F, 0x0133, 0x0137, 0x013A, 0x0148, 0x014B, 0x0177, 0x00FF, 0x017A, 0x017E, 0x0073, 0x0253, 0x0183, 0x0185, 0x0254, 0x0188, 
            0x0256, 0x0257, 0x018C, 0x01DD, 0x0259, 0x025B, 0x0192, 0x0260, 0x0263, 0x0269, 0x0268, 0x0199, 0x026F, 0x0272, 0x0275, 0x01A1, 0x01A5, 0x0280, 0x01A8, 0x0283, 0x01AD, 0x0288, 0x01B0, 0x028A, 
            0x028B, 0x01B4, 0x01B6, 0x0292, 0x01B9, 0x01BD, 0x01C6, 0x01C6, 0x01C9, 0x01C9, 0x01CC, 0x01CC, 0x01DC, 0x01DF, 0x01EF, 0x01F3, 0x01F3, 0x01F5, 0x0195, 0x01BF, 0x01F9, 0x021F, 0x019E, 0x0223, 
            0x0233, 0x2C65, 0x023C, 0x019A, 0x2C66, 0x0242, 0x0180, 0x0289, 0x028C, 0x0247, 0x024F, 0x03B9, 0x0371, 0x0373, 0x0377, 0x03F3, 0x03AC, 0x03AD, 0x03AF, 0x03CC, 0x03CD, 0x03CE, 0x03B1, 0x03C1, 
            0x03C3, 0x03CB, 0x03C3, 0x03D7, 0x03B2, 0x03B8, 0x03C6, 0x03C0, 0x03D9, 0x03EF, 0x03BA, 0x03C1, 0x03B8, 0x03B5, 0x03F8, 0x03F2, 0x03FB, 0x037B, 0x037D, 0x0450, 0x045F, 0x0430, 0x044F, 0x0461, 
            0x0481, 0x048B, 0x04BF, 0x04CF, 0x04C2, 0x04CE, 0x04D1, 0x052F, 0x0561, 0x0586, 0x2D00, 0x2D25, 0x2D27, 0x2D2D, 0x13F0, 0x13F5, 0x0432, 0x0434, 0x043E, 0x0441, 0x0442, 0x0442, 0x044A, 0x0463, 
            0xA64B, 0x10D0, 0x10FA, 0x10FD, 0x10FF, 0x1E01, 0x1E95, 0x1E61, 0x1EA1, 0x1EFF, 0x1F00, 0x1F07, 0x1F10, 0x1F15, 0x1F20, 0x1F27, 0x1F30, 0x1F37, 0x1F40, 0x1F45, 0x1F51, 0x1F53, 0x1F55, 0x1F57, 
            0x1F60, 0x1F67, 0x1FB0, 0x1FB1, 0x1F70, 0x1F71, 0x03B9, 0x1F72, 0x1F75, 0x1FD0, 0x1FD1, 0x1F76, 0x1F77, 0x1FE0, 0x1FE1, 0x1F7A, 0x1F7B, 0x1FE5, 0x1F78, 0x1F79, 0x1F7C, 0x1F7D, 0x03C9, 0x006B, 
            0x00E5, 0x214E, 0x2170, 0x217F, 0x2184, 0x24D0, 0x24E9, 0x2C30, 0x2C5F, 0x2C61, 0x026B, 0x1D7D, 0x027D, 0x2C68, 0x2C6C, 0x0251, 0x0271, 0x0250, 0x0252, 0x2C73, 0x2C76, 0x023F, 0x0240, 0x2C81, 
            0x2CE3, 0x2CEC, 0x2CEE, 0x2CF3, 0xA641, 0xA66D, 0xA681, 0xA69B, 0xA723, 0xA72F, 0xA733, 0xA76F, 0xA77A, 0xA77C, 0x1D79, 0xA77F, 0xA787, 0xA78C, 0x0265, 0xA791, 0xA793, 0xA797, 0xA7A9, 0x0266, 
            0x025C, 0x0261, 0x026C, 0x026A, 0x029E, 0x0287, 0x029D, 0xAB53, 0xA7B5, 0xA7C3, 0xA794, 0x0282, 0x1D8E, 0xA7C8, 0xA7CA, 0xA7D1, 0xA7D7, 0xA7D9, 0xA7F6, 0x13A0, 0x13EF, 0xFF41, 0xFF5A, 0x10428, 
            0x1044F, 0x104D8, 0x104FB, 0x10597, 0x105A1, 0x105A3, 0x105B1, 0x105B3, 0x105B9, 0x105BB, 0x105BC, 0x10CC0, 0x10CF2, 0x118C0, 0x118DF, 0x16E60, 0x16E7F, 0x1E922, 0x1E943)

        if err != .None {
            MD_LOG("error allocating Unicode case fold map data.")
            return
        }

        ctx.unicode_maps.fold_map_1_data = &unicode_map
    }

    if ctx.unicode_maps.fold_map_2 == nil {
        unicode_map, err := map_builder(
            0x00DF, 0x0130, 0x0149, 0x01F0, 0x0587, 0x1e96, 0x1E97, 0x1E98, 0x1E99, 0x1E9A, 0x1E9E, 0x1F50, R(0x1F80,0x1F87), R(0x1F88,0x1F8F), R(0x1F90,0x1F97), R(0x1F98,0x1F9F), R(0x1FA0,0x1FA7), 
            R(0x1FA8,0x1FAF), 0x1FB2, 0x1FB3, 0x1FB4, 0x1FB6, 0x1FBC, 0x1FC2, 0x1FC3, 0x1FC4, 0x1FC6, 0x1FCC, 0x1FD6, 0x1FE4, 0x1FE6, 0x1FF2, 0x1FF3, 0x1FF4, 0x1FF6, 0x1FFC, 0xFB00, 0xFB01, 0xFB02, 
            0xFB05, 0xFB06, 0xFB13, 0xFB14, 0xFB15, 0xFB16, 0xFB17)
        
        if err != .None {
            MD_LOG("error allocating Unicode case fold map 2.")
            return
        }

        ctx.unicode_maps.fold_map_2 = &unicode_map
    }

    if ctx.unicode_maps.fold_map_2_data == nil {
        unicode_map, err := map_builder(
            0x0073,0x0073, 0x0069,0x0307, 0x02BC,0x006E, 0x006A,0x030C, 0x0565,0x0582, 0x0068,0x0331, 0x0074,0x0308, 0x0077,0x030A, 0x0079,0x030A, 0x0061,0x02BE, 0x0073,0x0073, 0x03C5,0x0313, 0x1F00,0x03B9, 
            0x1F07,0x03B9, 0x1F00,0x03B9, 0x1F07,0x03B9, 0x1F20,0x03B9, 0x1F27,0x03B9, 0x1F20,0x03B9, 0x1F27,0x03B9, 0x1F60,0x03B9, 0x1F67,0x03B9, 0x1F60,0x03B9, 0x1F67,0x03B9, 0x1F70,0x03B9, 0x03B1,0x03B9, 
            0x03AC,0x03B9, 0x03B1,0x0342, 0x03B1,0x03B9, 0x1F74,0x03B9, 0x03B7,0x03B9, 0x03AE,0x03B9, 0x03B7,0x0342, 0x03B7,0x03B9, 0x03B9,0x0342, 0x03C1,0x0313, 0x03C5,0x0342, 0x1F7C,0x03B9, 0x03C9,0x03B9, 
            0x03CE,0x03B9, 0x03C9,0x0342, 0x03C9,0x03B9, 0x0066,0x0066, 0x0066,0x0069, 0x0066,0x006C, 0x0073,0x0074, 0x0073,0x0074, 0x0574,0x0576, 0x0574,0x0565, 0x0574,0x056B, 0x057E,0x0576, 0x0574,0x056D
        )

        if err != .None {
            MD_LOG("error allocating Unicode case fold map 2 data.")
            return
        }

        ctx.unicode_maps.fold_map_2_data = &unicode_map
    }

    if ctx.unicode_maps.fold_map_3 == nil {
        unicode_map, err := map_builder(
            0x0390, 0x03B0, 0x1F52, 0x1F54, 0x1F56, 0x1FB7, 0x1FC7, 0x1FD2, 0x1FD3, 0x1FD7, 0x1FE2, 0x1FE3, 0x1FE7, 0x1FF7, 0xFB03, 0xFB04)
        
        if err != .None {
            MD_LOG("error allocating Unicode case fold map 3.")
            return
        }

        ctx.unicode_maps.fold_map_3 = &unicode_map
    }

    if ctx.unicode_maps.fold_map_3_data == nil {
        unicode_map, err := map_builder(
            0x03b9,0x0308,0x0301, 0x03c5,0x0308,0x0301, 0x03c5,0x0313,0x0300, 0x03c5,0x0313,0x0301, 0x03c5,0x0313,0x0342, 0x03b1,0x0342,0x03b9, 0x03b7,0x0342,0x03b9, 0x03b9,0x0308,0x0300,
            0x03b9,0x0308,0x0301, 0x03b9,0x0308,0x0342, 0x03c5,0x0308,0x0300, 0x03c5,0x0308,0x0301, 0x03c5,0x0308,0x0342, 0x03c9,0x0342,0x03b9, 0x0066,0x0066,0x0069, 0x0066,0x0066,0x006c)

        if err != .None {
            MD_LOG("error allocating Unicode case fold map 3 data.")
            return
        }

        ctx.unicode_maps.fold_map_3_data = &unicode_map
    }

    FOLD_MAP_LIST := [3]struct {
        uni_map: ^[]u32,
        data: ^[]u32,
        n_codepoints: u32,
    } {
        { ctx.unicode_maps.fold_map_1, ctx.unicode_maps.fold_map_1_data, 1 },
        { ctx.unicode_maps.fold_map_2, ctx.unicode_maps.fold_map_2_data, 2 },
        { ctx.unicode_maps.fold_map_3, ctx.unicode_maps.fold_map_3_data, 3 },
    }

    if codepoint <= 0x7F {
        info.codepoints[0] = codepoint
        if ISUPPER_(rune(codepoint)) {
            info.codepoints[0] += ('a' - 'A')
        }
        info.n_codepoints = 1
        return
    }

    i: int = 0

    for i; i < len(FOLD_MAP_LIST); i += 1 {
        idx: int = md_unicode_bsearch__(codepoint, FOLD_MAP_LIST[i].uni_map)

        if idx >= 0 {
            info.n_codepoints = entry.n_codepoints
            
            // Basic copy
            for j: u32 = 0; j < FOLD_MAP_LIST[i].n_codepoints; j+=1 {
                 info.codepoints[j] = FOLD_MAP_LIST[i].data[uint(idx) * uint(FOLD_MAP_LIST[i].n_codepoints) + uint(j)]
            }

            if FOLD_MAP_LIST[i].uni_map[idx] != codepoint {
                // The found mapping maps whole range of codepoints,
                // i.e. we have to offset info->codepoints[0] accordingly.
                 
                if (FOLD_MAP_LIST[i].uni_map[idx] & 0x00ffffff + 1) == info.codepoints[0] {
                    // Alternating type of the range.
                    // info->codepoints[0] = codepoint + ((codepoint & 0x1) == (map[index] & 0x1) ? 1 : 0);
                    info.codepoints[0] = codepoint + ((codepoint & 0x1) == (FOLD_MAP_LIST[i].uni_map[idx] & 0x1) ? 1 : 0)
                } else {
                    // Range to range kind of mapping.
                    // info->codepoints[0] += (codepoint - (map[index] & 0x00ffffff));
                    info.codepoints[0] += (codepoint - (FOLD_MAP_LIST[i].uni_map[idx] & 0x00ffffff))
                }
            }
            return
        }
    }

    // Default: fold to itself
    info.codepoints[0] = codepoint
    info.n_codepoints = 1
}

IS_UNICODE_WHITESPACE_ :: proc(ctx: ^MD_CTX, codepoint: u32) -> bool {
    return md_is_unicode_whitespace__(ctx, codepoint)
}

IS_UNICODE_WHITESPACE :: proc(ctx: ^MD_CTX, offset: OFF) -> bool {

}