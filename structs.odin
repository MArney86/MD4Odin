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


 /* String attribute.
 *
 * This wraps strings which are outside of a normal text flow and which are
 * propagated within various detailed structures, but which still may contain
 * string portions of different types like e.g. entities.
 *
 * So, for example, lets consider this image:
 *
 *     ![image alt text](http://example.org/image.png 'foo &quot; bar')
 *
 * The image alt text is propagated as a normal text via the MD_PARSER::text()
 * callback. However, the image title ('foo &quot; bar') is propagated as
 * MD_ATTRIBUTE in MD_SPAN_IMG_DETAIL::title.
 *
 * Then the attribute MD_SPAN_IMG_DETAIL::title shall provide the following:
 *  -- [0]: "foo "   (substr_types[0] == MD_TEXT_NORMAL; substr_offsets[0] == 0)
 *  -- [1]: "&quot;" (substr_types[1] == MD_TEXT_ENTITY; substr_offsets[1] == 4)
 *  -- [2]: " bar"   (substr_types[2] == MD_TEXT_NORMAL; substr_offsets[2] == 10)
 *  -- [3]: (n/a)    (n/a                              ; substr_offsets[3] == 14)
 *
 * Note that these invariants are always guaranteed:
 *  -- substr_offsets[0] == 0
 *  -- substr_offsets[LAST+1] == size
 *  -- Currently, only MD_TEXT_NORMAL, MD_TEXT_ENTITY, MD_TEXT_NULLCHAR
 *     substrings can appear. This could change only of the specification
 *     changes.*/
MD_ATTRIBUTE :: struct {
    text: MD_STR,
    size: MD_SIZE,
    substr_types: []MD_TEXTTYPE,
    substr_offsets: []MD_OFFSET,
}

/* Detailed info for .UL. */
MD_BLOCK_UL_DETAIL :: struct {
    is_tight: bool, // true if the list is tight
    mark: MD_CHAR, //Item bullet character in MarkDown source of the list ('-', '+', '*')
}

/* Detailed info for .OL. */
MD_BLOCK_OL_DETAIL :: struct {
    start: u32, // start index of the orderd list
    is_tight: bool, // true if the list is tight
    mark_delimiter: MD_CHAR, // Item delimiter character in MarkDown source of the list ('.' or ')')
}

/* Detailed info for .LI. */
MD_BLOCK_LI_DETAIL :: struct {
    is_task: bool, // can only be true if MD_FLAG_TASKLISTS is set
    task_mark: MD_CHAR, // if is_task, then one of 'x', 'X' or ' '. Otherwise undefined.
    task_mark_offset: MD_OFFSET, // if is_task, offset in the input of the rune between '[' and ']'
}

/* Detailed info for .H. */
MD_BLOCK_H_DETAIL :: struct {
    level: u32, // header level (1-5)
}

/* Detailed info for .CODE. */
MD_BLOCK_CODE_DETAIL :: struct {
    info: MD_ATTRIBUTE, // info string (can be empty)
    lang: MD_ATTRIBUTE, // language portion of the info string (can be empty)
    fence_char: MD_CHAR, // fence character used ( '`' or '~' )
}

/* Detailed info for .TABLE. */
MD_BLOCK_TABLE_DETAIL :: struct {
    col_count: u32, // number of columns
    head_row_count: u32, // number of rows in the table header (always 1)
    body_row_count: u32, // number of rows in the table body
}

/* Detailed info for .TH and .TD. */
MD_BLOCK_TD_DETAIL :: struct {
    align: MD_ALIGN,
}

/* Detailed info for .A. */
MD_SPAN_A_DETAIL :: struct {
    href: MD_ATTRIBUTE, // link destination
    title: MD_ATTRIBUTE, // link title (can be empty)
    is_autolink: bool, // true if the link is an autolink
}

/* Detailed info for .IMG. */
MD_SPAN_IMG_DETAIL :: struct {
    src: MD_ATTRIBUTE, // image source
    title: MD_ATTRIBUTE, // image title (can be empty)
}

/* Detailed info for .WIKILINK. */
MD_SPAN_WIKILINK_DETAIL :: struct {
    target: MD_ATTRIBUTE, // wiki link target
}

MD_PARSER :: struct {
    abi_version: u32, // must be 0
    flags: MD_FLAGS, // combination of MD_FLAG_*
    /* Caller provided rendering callbacks 
     * For some block/span types, more information is provided via detail struct provided throuh detail arg.
     * Last arg 'userdata' is propagated from md_parse() and available for use by the application
     * NOTE: Any string provided to the callbacks as arg or within detail structs are generally not null-terminated.
     * Any rendering callback may abort futher parsing by returning non-zero value. */
    enter_block : ^md_block_span_callback_proc,
    leave_block : ^md_block_span_callback_proc,
    enter_span : ^md_span_callback_proc,
    leave_span : ^md_span_callback_proc,
    text : ^md_text_callback_proc,
    debug_log : ^debug_logger_callback_proc, // optional debug logger callback (can be NULL). Mean't for devs not production use.
    syntax: ^syntax_callback_proc, // optional syntax callback (can be NULL). Mean't for devs not production use.
}

MD_UNICODE_FOLD_INFO_tag :: struct {
    codepoints: [3]u32,
    n_codepoints: u32,
}

MD_UNICODE_MAPS :: struct {
    whitespace: ^[]u32,
    punctuation: ^[]u32,
    fold_map_1: ^[]u32,
    fold_map_1_data: ^[]u32,
    fold_map_2: ^[]u32,
    fold_map_2_data: ^[]u32,
    fold_map_3: ^[]u32,
    fold_map_3_data: ^[]u32,
}

MD_MARKSTACK_tag :: struct {
    top: int,
}

MD_CTX_tag :: struct {
    text: ^MD_STR, //immutable (arg of md_parse())
    size: SZ, //immutable (arg of md_parse())
    parser: MD_PARSER, //immutable (arg of md_parse())
    userdata: rawptr, //immutable (arg of md_parse())
    doc_ends_with_newline: bool, // allows some optimizations when true

    //temporary helper buffer
    buffer: ^[]MD_CHAR,
    alloc_buffer: uint,

    //Reference definitions
    ref_defs: ^MD_REF_DEF,
    n_ref_defs: int,
    alloc_ref_defs: int,
    ref_def_hashtable: [^]rawptr,
    ref_def_hashtable_size: int,
    max_ref_def_output: SZ,

    //stack of inline/span markers. Only used for parsing single blocks, reused to save allocations.
    marks: ^MD_MARK,
    n_marks: int,
    alloc_marks: int,
    mark_char_map: [256]u8,
    opener_stacks: [MD_OPENER_STACKS_TYPES]MD_MARKSTACK,

    /* stack of dummies which need to call free() for pointers stored in them
     * Constructed during inline parsing, freed after entire block processed (i.e.
     * after all callbacks referring to those strings are called)*/
    ptr_stack: MD_MARKSTACK, 

    //For resolving table rows
    n_table_cell_boundaries: int,
    table_cell_boundaries_head: int,
    table_cell_boundaries_tail: int,

    //For resolving links
    unresolved_link_head: int,
    unresolved_link_tail: int,

    //For resolving raw HTML
    html_comment_horizon: OFF,
    html_proc_instr_horizon: OFF,
    html_decl_horizon: OFF,
    html_cdata_horizon: OFF,

    /* For block analysis
     * NOTE: -- It holds MD_BLOCK as well as MD_LINE structs. After each MD_BLOCK,
     *          it's (multiple) MD_LINEs follow.
     *       -- For MD_BLOCK_HTML and MD_BLOCK_CODE, MD_VERBATIM_LINEs are used instead of MD_LINEs.*/
    block_bytes: rawptr,
    current_block: ^MD_BLOCK,
    n_block_bytes: int,
    alloc_block_bytes: int,

    //For container block analysis
    containers: ^[]MD_CONTAINER,
    n_containers: int,
    alloc_containers: int,

    //Minimal indentation to call the block "indented code block".
    code_indent_offset: uint,

    //Contextual info for line analysis
    code_fence_length: SZ, // For checking closing fence length
    html_block_type: int, // For checking closing raw HTML condition
    last_line_has_list_loosening_effect: bool,
    last_list_item_starts_with_two_blank_lines: bool,

    //Unicode maps storage to reduce allocations
    unicode_maps: MD_UNICODE_MAPS,
}


MD_LINE_ANALYSIS_tag :: struct {
    type: MD_LINETYPE,
    data: uint,
    enforce_new_block: bool,
    beg: OFF,
    end: OFF,
    indent: uint,
}

MD_LINE_tag :: struct {
    beg: OFF,
    end: OFF,
}

MD_VERBATIMLINE_tag :: struct {
    beg: OFF,
    end: OFF,
    indent: OFF,
}