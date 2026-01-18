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

 import mem "core:mem"
 import utf8 "core:unicode/utf8"

md_parse :: proc(text: string, size: MD_SIZE, parser: ^MD_PARSER, userdata: rawptr) -> i32 {
    ctx : MD_CTX
    i: i32
    ret: i32

    if parser.abi_version != 0 {
        if parser.debug_log != nil {
            parser.debug_log("Unsupported abi_version.", userdata)
        }
        return -1
    }

    /* Setup context structure. */
    ctx.text = &utf8.string_to_runes(text)
    ctx.size = len(ctx.text)
    mem.copy(&ctx.parser, parser, size_of(MD_PARSER))
    ctx.userdata = userdata
    ctx.code_indent_offset = .NOINDENTEDCODEBLOCKS in ctx.parser.flags ? OFF(-1) : 4
    md_build_mark_char_map(&ctx)
    ctx.doc_ends_with_newline = (size > 0  &&  ISNEWLINE_(rune(text[size-1])))
    ctx.max_ref_def_output = uint(min(min(16 * u64(size), u64(1024 * 1024)), u64(SZ_MAX)))

    /* Reset all mark stacks and lists. */
    for i = 0; i < len(ctx.opener_stacks); i+=1 {
        ctx.opener_stacks[cast(MD_OPENER_STACKS_TYPES)i].top = -1
    }
    ctx.ptr_stack.top = -1
    ctx.unresolved_link_head = -1
    ctx.unresolved_link_tail = -1
    ctx.table_cell_boundaries_head = -1
    ctx.table_cell_boundaries_tail = -1

    /* All the work. */
    ret = md_process_doc(&ctx);

    /* Clean-up. */
    md_free_ref_defs(&ctx)
    md_free_ref_def_hashtable(&ctx)
    if ctx.buffer != nil { delete(ctx.buffer^) }
    if ctx.marks != nil { delete(ctx.marks^) } 
    //free(ctx.block_bytes) // TODO: Check if slice or rawptr
    //free(ctx.containers)
    if ctx.unicode_maps.whitespace != nil { 
        delete(ctx.unicode_maps.whitespace^) }
    if ctx.unicode_maps.punctuation != nil { delete(ctx.unicode_maps.punctuation^) }


    return ret;
}