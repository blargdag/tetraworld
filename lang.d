/**
 * Miscellaneous language utilities.
 *
 * Copyright: (C) 2012-2021  blargdag@quickfur.ath.cx
 *
 * This file is part of Tetraworld.
 *
 * Tetraworld is free software: you can redistribute it and/or modify it under
 * the terms of the GNU General Public License as published by the Free
 * Software Foundation, either version 2 of the License, or (at your option)
 * any later version.
 *
 * Tetraworld is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * Tetraworld.  If not, see <http://www.gnu.org/licenses/>.
 */
module lang;

import std.range.primitives;

/**
 * Lazily iterates over a string by grapheme, while keeping track of the
 * current offset and grapheme count.
 */
struct IndexedGraphemeRange
{
    private const(char)[] s;
    private size_t i;

    this(const(char)[] str)
    {
        s = str;
        i = 0;
    }

    @property bool empty() { return i == s.length; }

    @property size_t offset() { return i; }

    @property auto front()
    {
        static struct Front
        {
            dchar ch;
            size_t offset;
        }

        import std.utf : decodeFront;
        auto tmp = s[i .. $];
        return Front(tmp.decodeFront, i);
    }

    void popFront()
    {
        import std.uni : graphemeStride;
        i += s.graphemeStride(i);
    }

    @property typeof(this) save() { return this; }

    static assert(isForwardRange!(typeof(this)));
}

/**
 * Returns: A lazy range of cumulative grapheme counts and indices into the
 * given string representing word breaks, including the end of the string.
 *
 * BUGS: Replace this with UAX #14.
 */
auto wordBreaks(const(char)[] str)
{
    static struct Result
    {
        private IndexedGraphemeRange r;
        private size_t offset, count;

        bool empty = true;

        this(const(char)[] s)
        {
            r = IndexedGraphemeRange(s);
            empty = false; // we always return at least one element
            next();
        }

        @property auto front()
        {
            static struct Front
            {
                size_t offset, count;
            }
            return Front(offset, count);
        }

        private void next()
        {
            import std.uni : isWhite;

            // Skip initial spaces
            while (!r.empty && r.front.ch.isWhite)
            {
                r.popFront;
                count++;
            }

            // Find transition from non-white to white
            while (!r.empty && !r.front.ch.isWhite)
            {
                r.popFront;
                count++;
            }

            offset = r.offset;
        }

        void popFront()
            in(!this.empty)
        {
            if (r.empty)
            {
                empty = true;
                return;
            }
            next();
        }
    }
    return Result(str);
}

/**
 * Lazily word-wraps a paragraph to fit a certain width, with optional initial
 * indentation and hanging indentation.
 *
 * If the input contains an overly-long word that doesn't fit the wrap width, a
 * line break will be inserted in the middle of the word at the wrap width in
 * order to force it to wrap. No attempt at hyphenation is made.
 *
 * Parameters:
 *  str = The string to wrap.
 *  wrapWidth = The maximum width per line. This includes the initial
 *      indentation, so this parameter must be greater than indent as well as
 *      indent + hangingIndent.
 *  indent = The number of spaces to insert in front of each line.
 *  hangingIndent = The number of additional spaces to insert in front of first
 *      line. If this is a negative number, the first line will have this many
 *      spaces deleted from its indent, producing a hanging indent. It is an
 *      error if hangingIndent + indent < 0.
 *
 * Returns: an input range of strings representing wrapped lines. Note that the
 * trailing newline is NOT included.
 */
auto wordWrap(const(char)[] str, int wrapWidth, int indent = 0,
              int hangingIndent = 0)
    in (wrapWidth > indent)
    in (indent + hangingIndent >= 0)

    // Note: the following is NOT redundant because hangingIndent may be
    // negative.
    in (wrapWidth > indent + hangingIndent)
{
    import std.array;
    import std.range : isForwardRange;
    import std.string : format, stripRight;

    static struct Result
    {
        private const(char)[] src, prefix;
        private int width;

        bool empty = true;
        const(char)[] front;

        this(const(char)[] str, int wrapWidth, int indent, int hangingIndent)
        {
            src = str;
            prefix = " ".replicate(indent);
            width = wrapWidth - indent;
            empty = false;

            if (hangingIndent != 0)
            {
                auto initialWidth = wrapWidth - indent - hangingIndent;
                assert(initialWidth >= 0);
                wrapNext(initialWidth, " ".replicate(indent + hangingIndent));
            }
            else
                wrapNext(width, prefix);
        }

        private void wrapNext(int width, const(char)[] prefix)
        {
            if (src.empty)
            {
                empty = true;
                return;
            }

            // Find nearest wrapping point
            long lastWordBreak = long.min;
            auto r = src.wordBreaks;
            while (!r.empty && r.front.count <= width)
            {
                lastWordBreak = r.front.offset;
                r.popFront;
            }

            if (lastWordBreak != long.min)
            {
                // Wrap.
                front = prefix ~ src[0 .. lastWordBreak];
                src = src[lastWordBreak .. $];

                import std.uni : isWhite;
                while (!src.empty && src.front.isWhite)
                    src.popFront();
            }
            else
            {
                // Couldn't find a suitable linebreak; just force break at max
                // width.
                import std.range : drop;
                auto i = IndexedGraphemeRange(src).drop(width).offset;
                front = prefix ~ src[0 .. i];
                src = src[i .. $];
            }
        }

        void popFront()
        {
            wrapNext(width, prefix);
        }

        @property typeof(this) save() { return this; }
    }
    static assert(isForwardRange!Result);

    return Result(str, wrapWidth, indent, hangingIndent);
}

version(unittest)
{
    import std.algorithm;
    import std.stdio;
}

unittest
{
    auto str = "* This is a very long string that is going to be wrapped to "~
                 "multiple lines, with indentation, no less.";
    auto r = wordWrap(str, 20, 2);
    auto expected = [
        "  * This is a very",
        "  long string that",
        "  is going to be",
        "  wrapped to",
        "  multiple lines,",
        "  with indentation,",
        "  no less."
    ];
    assert(equal(r, expected));
}

unittest
{
    auto str = "AnOverlyLongStringWithNoGoodWrappingPoints";
    auto r = wordWrap(str, 20, 0);
    auto expected = [
        "AnOverlyLongStringWi",
        "thNoGoodWrappingPoin",
        "ts"
    ];
    assert(equal(r, expected));
}

unittest
{
    // Test initial extra indents.
    auto str = "This is a paragraph whose first line should have an extra "~
               "indentation.";
    auto r = wordWrap(str, 25, 2, 2);
    auto expected = [
        "    This is a paragraph",
        "  whose first line should",
        "  have an extra",
        "  indentation."
    ];
    assert(equal(r, expected));
}

unittest
{
    // Test hanging indents.
    auto str = "* This is a line we wish to have hanging indent for.";
    auto r = wordWrap(str, 20, 2, -2);
    auto expected = [
        "* This is a line we",
        "  wish to have",
        "  hanging indent",
        "  for."
    ];
    assert(equal(r, expected));
}

unittest
{
    // Test some corner cases and unusual inputs.
    auto str = "This is a test for  multiple spaces at   the breakpoints.";
    auto r = wordWrap(str, 19);
    auto expected = [
        "This is a test for",
        "multiple spaces at",
        "the breakpoints."
    ];
    assert(equal(r, expected));
}

unittest
{
    // Test non-ASCII wrapping.
    auto str = "В начале было Слово, и Слово было у Бога, и Слово было Бог.";
    auto r = wordWrap(str, 20);
    auto expected = [
        "В начале было Слово,",
        "и Слово было у Бога,",
        "и Слово было Бог."
    ];
    assert(equal(r, expected));
}

unittest
{
    // Test multi-codepoint graphemes
    auto str = "В нача\u0301ле было Сло\u0301во, и Сло\u0301во было у "~
               "Бо\u0301га, и Сло\u0301во было Бо\u0301г.";
    auto r = wordWrap(str, 20);
    auto expected = [
        "В нача\u0301ле было Сло\u0301во,",
        "и Сло\u0301во было у Бо\u0301га,",
        "и Сло\u0301во было Бо\u0301г."
    ];
    assert(equal(r, expected));
}

// vim: set ts=4 sw=4 et ai:
