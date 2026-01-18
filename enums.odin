package md4o

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
import c "core:c"

MD_ERR :: enum {
    OK = 0,
    INVALID_PARAMETER,
    OUT_OF_MEMORY,
    INTERNAL_ERROR,
    RETURN_LESS_THAN_ZERO,
}

MD_BLOCKTYPE :: enum {
    DOC = 0,    // <body> ... </body>
    QUOTE,      // <blockquote> ... </blockquote>
    UL,         // <ul> ... </ul> Detail: MD_BLOCK_UL_DETAIL
    OL,         // <ol> ... </ol> Detail: MD_BLOCK_OL_DETAIL
    LI,         // <li> ... </li> Detail: MD_BLOCK_LI_DETAIL
    HR,         // <hr>
    H,          // <h1> ... </h1>, up to level 6 Detail: MD_BLOCK_H_DETAIL
    CODE,       // <pre><code> ... </code></pre> Detail: MD_BLOCK_CODE_DETAIL NOTE: text lines within code blocks are terminated by '\n'
    HTML,       // Raw HTML block. Content is passed as-is to the callback.
    P,          // <p> ... </p>
    //NOTE: The following block types are available only if MD_FLAG_TABLES is set.
    TABLE,      // <table> ... </table> and it's contents Detail: MD_BLOCK_TABLE_DETAIL
    THEAD,      // <thead> ... </thead>
    TBODY,      // <tbody> ... </tbody>
    TR,         // <tr> ... </tr>
    TH,         // <th> ... </th> Detail: MD_BLOCK_TH_DETAIL
    TD,         // <td> ... </td> Detail: MD_BLOCK_TD_DETAIL
}

MD_SPANTYPE :: enum {
    EM,                 // <em> ... </em>
    STRONG,             // <strong> ... </strong>
    A,                  // <a href="..."> ... </a> Detail: MD_SPAN_A_DETAIL
    IMG,                // <img src="..."> Detail: MD_SPAN_IMG_DETAIL NOTE: Image text can contain nested spans and even nested images.
                        //                                                  If rendered into ALT attr of <img> tag, it is responsibility of the parser to deal with it.
    CODE,               // <code> ... </code>
    DEL,                // <del> ... </del> NOTE: Recognized only if MD_FLAG_STRIKETHROUGH is set.
    LATEXMATH,          // For recognizing inline ($) and display ($$) equations NOTE: Recognized only if MD_FLAG_LATEXMATHSPANS is set.
    LATEXMATH_DISPLAY,
    WIKILINK,           // Wiki link [[...]] NOTE: Recognized only if MD_FLAG_WIKILINKS is set.
    U,                  // <u> ... </u> NOTE: Recognized only if MD_FLAG_UNDERLINE is set.
}

MD_TEXTTYPE :: enum {
    NORMAL = 0,      // Normal text
    NULLCHAR,        // NULL character. CommonMark requires replacing NULL character with the replacement char U+FFFD, so this allows caller to do that easily.
    // line breaks NOTE: these are not sent from blocks with verbaim output (.CODE/.HTML). In such cases, '\n' is part of the text.
    BR,              // Hard line break (<br>)
    SOFTBR,          // '\n' in source text where it is not semantically meaningful (soft break)
    /* Entity
     * (a) Named entity, e.g. &nbsp;
     *     (no list of name entities is provided, anything matching the regex
     *      /&[A-Za-z][A-Za-z0-9]{1,47};/ is considered a named entity)
     * (b) Numeric entity, e.g. &#1234
     * (c) Hexadecimal entity, e.g. &#x1A3F;
     * all attempts made to maintain encoding agnosticism of MD4C. application gets verbatim entity text passed to MD_PARSER.text_callback().*/
    ENTITY,
    /* Text in a code block (.CODE) or inlined code (`code`). If inside .CODE block, includes spaces for indentation and '\n'
     * for new lines. .BR and .SOFTBR are not sent from code blocks. */
    CODE,
    // Raw HTML text. If content of raw HTML block (i.e. not an inline raw HTML), then .BR and .SOFTBR are not used, verbatim '\n's are part of the text.
    HTML,
    // Text is in an equation. Processed the same as inlined code spans (`code`).
    LATEXMATH,
}

MD_ALIGN :: enum {
    DEFAULT = 0, // unspecifed
    LEFT,
    CENTER,
    RIGHT,
}

/* Flags specifying extensions/deviations from CommonMark specification.
 *
 * By default (when MD_PARSER::flags == 0), we follow CommonMark specification.
 * The following flags may allow some extensions or deviations from it.
 */

LOG_TYPES :: enum {
    FATAL,
    ERROR,
    WARNING,
    DEBUG,
}

MD_FLAG :: enum {
    COLLAPSEWHITESPACE = 0,      /* In MD_TEXT_NORMAL, collapse non-trivial whitespace into single ' ' */
    PERMISSIVEATXHEADERS = 1,    /* Do not require space in ATX headers ( ###header ) */
    PERMISSIVEURLAUTOLINKS = 2,  /* Recognize URLs as autolinks even without '<', '>' */
    PERMISSIVEEMAILAUTOLINKS = 3,/* Recognize e-mails as autolinks even without '<', '>' and 'mailto:' */
    NOINDENTEDCODEBLOCKS = 4,    /* Disable indented code blocks. (Only fenced code works.) */
    NOHTMLBLOCKS = 5,            /* Disable raw HTML blocks. */
    NOHTMLSPANS = 6,             /* Disable raw HTML (inline). */
    TABLES = 8,                  /* Enable tables extension. */
    STRIKETHROUGH = 9,           /* Enable strikethrough extension. */
    PERMISSIVEWWWAUTOLINKS = 10, /* Enable WWW autolinks (even without any scheme prefix, if they begin with 'www.') */
    TASKLISTS = 11,              /* Enable task list extension. */
    LATEXMATHSPANS = 12,         /* Enable $ and $$ containing LaTeX equations. */
    WIKILINKS = 13,              /* Enable wiki links extension. */
    UNDERLINE = 14,              /* Enable underline extension (and disables '_' for normal emphasis). */
    HARD_SOFT_BREAKS = 15,       /* Force all soft breaks to act as hard breaks. */
}

MD_FLAGS :: bit_set[MD_FLAG; u32]

// Commonly used flag combinations
MD_FLAG_PERMISSIVEAUTOLINKS :: MD_FLAGS{.PERMISSIVEEMAILAUTOLINKS, .PERMISSIVEURLAUTOLINKS, .PERMISSIVEWWWAUTOLINKS}
MD_FLAG_NOHTML :: MD_FLAGS{.NOHTMLBLOCKS, .NOHTMLSPANS}

/* Convenient sets of flags corresponding to well-known Markdown dialects.
 *
 * Note we may only support subset of features of the referred dialect.
 * The constant just enables those extensions which bring us as close as
 * possible given what features we implement.
 *
 * ABI compatibility note: Meaning of these can change in time as new
 * extensions, bringing the dialect closer to the original, are implemented.
 */
MD_DIALECT_COMMONMARK :: MD_FLAGS{}
MD_DIALECT_GITHUB :: MD_FLAGS{.PERMISSIVEEMAILAUTOLINKS, .PERMISSIVEURLAUTOLINKS, .PERMISSIVEWWWAUTOLINKS, .TABLES, .STRIKETHROUGH, .TASKLISTS}

MD_OPENER_STACKS_TYPES :: enum {
    ASTERICK_OPENERS_oo_mod3_0 = 0,
    ASTERICK_OPENERS_oo_mod3_1,
    ASTERICK_OPENERS_oo_mod3_2,
    ASTERICK_OPENERS_oc_mod3_0,
    ASTERICK_OPENERS_oc_mod3_1,
    ASTERICK_OPENERS_oc_mod3_2,
    UNDERSCORE_OPENERS_oo_mod3_0,
    UNDERSCORE_OPENERS_oo_mod3_1,
    UNDERSCORE_OPENERS_oo_mod3_2,
    UNDERSCORE_OPENERS_oc_mod3_0,
    UNDERSCORE_OPENERS_oc_mod3_1,
    UNDERSCORE_OPENERS_oc_mod3_2,
    TILDE_OPENERS_1,
    TILDE_OPENERS_2,
    BRACKET_OPENERS,
    DOLLAR_OPENERS,
}

MD_LINE_TYPE_tag :: enum c.int{
    BLANK,
    HR,
    ATXHEADER,
    SETEXTHEADER,
    SETEXTUNDERLINE,
    INDENTEDCODE,
    FENCEDCODE,
    HTML,
    TEXT,
    TABLE,
    TABLEUNDERLINE,
}

