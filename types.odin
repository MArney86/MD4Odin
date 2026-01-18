package md4o

import c "core:c"

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

// Magic to support UTF-16. Note that in order to use it, you have to define
// MD4O_USE_UTF16 as true both when building MD4Odin as well as when
// including this package in your code.


MD_CHAR :: rune
MD_STR :: []rune

MD_SIZE :: uint
MD_OFFSET :: uint
CHAR :: MD_CHAR
SZ :: MD_SIZE
OFF :: MD_OFFSET

SZ_MAX :: max(SZ)
OFF_MAX :: max(OFF)

MD_MARK :: MD_MARK_tag
MD_BLOCK :: MD_BLOCK_tag
MD_CONTAINER :: MD_CONTAINER_tag
MD_REF_DEF :: MD_REF_DEF_tag
MD_MARKSTACK :: MD_MARKSTACK_tag
MD_CTX :: MD_CTX_tag
MD_LINETYPE :: MD_LINE_TYPE_tag
MD_LINE_ANALYSIS :: MD_LINE_ANALYSIS_tag
MD_LINE :: MD_LINE_tag
MD_VERBATIMLINE :: MD_VERBATIMLINE_tag
MD_UNICODE_FOLD_INFO :: MD_UNICODE_FOLD_INFO_tag

/* Procedure types for MD_PARSER callbacks. */
md_block_span_callback_proc :: proc(type: MD_BLOCKTYPE, detail: rawptr, userdata: rawptr) -> int
md_text_callback_proc :: proc(type: MD_TEXTTYPE, text: ^MD_STR, size: MD_SIZE, userdata: rawptr) -> int
debug_logger_callback_proc :: proc(msg: ^MD_STR, userdata: rawptr)
syntax_callback_proc :: proc()
abort_callback_proc :: proc(userdata: rawptr) -> i32