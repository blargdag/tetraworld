/**
 * Module for dealing with abstract grid-based displays.
 *
 * A grid-based display is any object that supports the moveTo and writef
 * methods for setting the position of the output cursor and writing formatted
 * string output, and has .width and .height attributes that describe the
 * dimensions of the display.
 *
 * Code that produces grid-based output can be templatized to work with any
 * grid-based display object, and thus work for arbitrary display-like objects.
 *
 * This module also provides some primitives for constructing display buffers
 * and deriving a subdisplay from another display, thus achieving position
 * independence and buffer transparency in code that outputs to displays.
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
module display;

import std.range.primitives;
import vector;

/**
 * Statically checks if a given type is a grid-based output display.
 *
 * A grid-based output display is any type T for which the following code is
 * valid:
 *------
 * void f(T, A...)(T term, int x, int y, A args) {
 *     assert(x < term.width);  // has .width attribute
 *     assert(y < term.height); // has .height attribute
 *     term.moveTo(x, y);       // can position output cursor
 *     term.writef("%s", args); // can output formatted strings
 * }
 *------
 */
enum isGridDisplay(T) = is(typeof(int.init < T.init.width)) &&
                        is(typeof(int.init < T.init.height)) &&
                        is(typeof(T.init.moveTo(0,0))) &&
                        is(typeof(T.init.writef("%s", "")));

unittest
{
    import arsd.terminal;
    static assert(isGridDisplay!(arsd.terminal.Terminal));
}

/**
 * true if T is a grid display that supports the .showCursor and .hideCursor
 * methods.
 */
enum canShowHideCursor(T) = isGridDisplay!T &&
                            is(typeof(T.init.showCursor())) &&
                            is(typeof(T.init.hideCursor()));

/**
 * true if T is a grid-based display that supports color.
 *
 * A display that supports color is one that has a .color method that accepts
 * two ushort parameters, corresponding to foreground and background colors.
 */
template hasColor(T)
    if (isGridDisplay!T)
{
    enum hasColor = is(typeof(T.init.color(ushort.init, ushort.init)));
}

/**
 * true if T is a grid-based display that supports the .clear operation.
 */
template canClear(T)
    if (isGridDisplay!T)
{
    enum canClear = is(typeof(T.init.clear()));
}

/**
 * A wrapper around an existing display that represents a rectangular subset of
 * it. The .moveTo primitive is wrapped to translate input coordinates into
 * actual coordinates on the display.
 */
struct SubDisplay(T)
    if (isGridDisplay!T)
{
    T parent;
    Region!(int,2) rect;

    ///
    void moveTo(int x, int y)
        in (rect.contains(vec(x,y) + rect.min))
    {
        auto target = vec(x,y) + rect.min;
        parent.moveTo(target[0], target[1]);
    }

    ///
    void writef(A...)(string fmt, A args) { parent.writef(fmt, args); }

    ///
    @property auto width() { return rect.max[0] - rect.min[0]; }

    ///
    @property auto height() { return rect.max[1] - rect.min[1]; }
}

unittest
{
    import arsd.terminal;
    static assert(isGridDisplay!(SubDisplay!(arsd.terminal.Terminal)));
}

/// Convenience method for constructing a SubDisplay.
auto subdisplay(T)(T display, Region!(int,2) rect)
    if (isGridDisplay!T)
{
    return SubDisplay!T(display, rect);
}

/**
 * Draws a box of the specified position and dimensions to the given display.
 * Params:
 *  display = A grid-based output display satisfying isGridDisplay.
 *  box = a Rectangle specifying the position and dimensions of the box to be
 *  drawn.
 */
void drawBox(T)(T display, Region!(int,2) box)
    if (isGridDisplay!T)
    in (box.length!0 >= 2 && box.length!1 >= 2)
{
    enum
    {
        UpperLeft = 0,
        UpperRight = 1,
        LowerLeft = 2,
        LowerRight = 3,
        Horiz = 4,
        Vert = 5,
        BreakLeft = 6,
        BreakRight = 7
    }
    static immutable dstring thinBoxChars   = "┌┐└┘─│┤├"d;
    static immutable dstring doubleBoxChars = "╔╗╚╝═║╡╞"d;

    import std.array : replicate;
    import std.range : chain, repeat;

    alias boxChars = thinBoxChars; // for now

    auto bx = box.min[0];
    auto by = box.min[1];
    auto width = box.length!0;
    auto height = box.length!1;

    // Top row
    display.moveTo(box.min[0], box.min[1]);
    display.writef("%s", chain(
        boxChars[UpperLeft].repeat(1),
        boxChars[Horiz].repeat(width-2),
        boxChars[UpperRight].repeat(1)
    ));

    // Middle rows
    foreach (y; 1 .. height)
    {
        display.moveTo(bx, by + y);
        display.writef("%s", boxChars[Vert]);
        display.moveTo(bx + width - 1, by + y);
        display.writef("%s", boxChars[Vert]);
    }

    // Bottom rows
    display.moveTo(bx, by + height - 1);
    display.writef("%s", chain(
        boxChars[LowerLeft].repeat(1),
        boxChars[Horiz].repeat(width-2),
        boxChars[LowerRight].repeat(1)
    ));
}

/**
 * Returns: true if the given character occupies two cells in the display grid,
 * false otherwise.
 */
bool isWide(dchar ch) @safe pure nothrow
{
    // WARNING: DO NOT MODIFY THIS FUNCTION BY HAND: it has been auto-generated
    // by the uniwidth utility based on data in the Unicode Standard's
    // EastAsianWidth.txt file. Any fixes should be done there instead, and the
    // code replaced by the new output.
    if(ch < 63744)
    {
        if(ch < 12880)
        {
            if(ch < 11904)
            {
                if(ch < 4352) return false;
                if(ch < 4448) return true;
                if(ch == 9001 || ch == 9002) return true;
                return false;
            }
            else if (ch < 12351) return true;
            else
            {
                if(ch < 12353) return false;
                if(ch < 12872) return true;
                return false;
            }
        }
        else if (ch < 19904) return true;
        else
        {
            if(ch < 43360)
            {
                if(ch < 19968) return false;
                if(ch < 42183) return true;
                return false;
            }
            else if (ch < 43389) return true;
            else
            {
                if(ch < 44032) return false;
                if(ch < 55204) return true;
                return false;
            }
        }
    }
    else if (ch < 64256) return true;
    else
    {
        if(ch < 65504)
        {
            if(ch < 65072)
            {
                if(ch < 65040) return false;
                if(ch < 65050) return true;
                return false;
            }
            else if (ch < 65132) return true;
            else
            {
                if(ch < 65281) return false;
                if(ch < 65377) return true;
                return false;
            }
        }
        else if (ch < 65511) return true;
        else
        {
            if(ch < 127488)
            {
                if(ch == 110592 || ch == 110593) return true;
                return false;
            }
            else if (ch < 127570) return true;
            else
            {
                if(ch < 131072) return false;
                if(ch < 262142) return true;
                return false;
            }
        }
    }
}

unittest
{
    import std.string : format;

    foreach (dchar ch; "一二三石１２３\u2329\u232A")
        assert(ch.isWide(),
               format("Should be wide but isn't: %s (U+%04X)", ch, ch));

    foreach (dchar ch; "123abcШаг\u2328\u232B")
        assert(!ch.isWide(),
               format("Shouldn't be wide but is: %s (U+%04X)", ch, ch));
}

/* Lame hackery due to Grapheme slices being unable to survive past the
 * lifetime of the Grapheme itself, and the fact that CTFE can't handle unions
 * so we have to initialize this at runtime.
 */
private import std.uni : Grapheme;
private Grapheme spaceGrapheme;
static this()
{
    spaceGrapheme = Grapheme(" ");
}

enum ColorType
{
    none, basic16, truecolor
}

private struct DispBuffer(ColorType colorType)
{
    static assert(colorType != ColorType.truecolor,
                  "Truecolor not implemented yet");

    import std.uni;

    /**
     * A colored grapheme.
     */
    struct Glyph
    {
        Grapheme g;
        static if (colorType == ColorType.basic16)
            ushort fg, bg;
    }

    struct Cell
    {
        // Type.Full is for normal (single-cell) graphemes. HalfLeft means this
        // cell is the left half of a double-celled grapheme; HalfRight means
        // this cell is the right half of a double-celled grapheme.
        enum Type : ubyte { Full, HalfLeft, HalfRight }

        Type type;
        Glyph glyph;

        version(unittest)
        void toString(scope void delegate(const(char)[]) sink)
        {
            import std.algorithm : copy;
            copy(glyph.g[], sink);
        }
    }

    static struct Line
    {
        Cell[] contents;
        uint dirtyStart = uint.max, dirtyEnd;

        /**
         * Returns: Range of Glyphs on this line.
         *
         * Bugs: Due to std.uni.Grapheme's bogonity, we have to return Glyph*'s
         * as elements instead of Glyph, so that no Grapheme copying is done.
         * So you may have to explicitly dereference elements if you expect
         * Glyph's.
         */
        auto byGlyph()()
        {
            return byGlyphImpl(0, cast(uint) contents.length);
        }

        /**
         * Returns: Range of dirty Glyphs on this line.
         *
         * Bugs: Due to std.uni.Grapheme's bogonity, we have to return Glyph*'s
         * as elements instead of Glyph, so that no Grapheme copying is done.
         * So you may have to explicitly dereference elements if you expect
         * Glyph's.
         */
        auto byDirtyGlyph()()
        {
            return byGlyphImpl(dirtyStart, dirtyEnd);
        }

        private auto byGlyphImpl(uint start, uint end)
        {
            import std.array : array;
            import std.algorithm : filter, map;

            return contents[start .. end]
                .filter!((ref c) => c.type != Cell.Type.HalfRight)
                .map!((ref c) => &c.glyph);

            static assert(is(ElementType!(typeof(return)) == Glyph*));
        }

        /**
         * Mark a column as dirty.
         *
         * Note that since we only track a single dirty segment, this may cause
         * more than one column to be marked dirty.
         */
        void markDirty(int x)
        {
            import std.algorithm : min, max;
            dirtyStart = min(x, dirtyStart);
            dirtyEnd = max(x+1, dirtyEnd);
        }

        /**
         * Mark entire line as dirty.
         */
        void markAllDirty()
        {
            dirtyStart = 0;
            dirtyEnd = cast(uint) contents.length;
        }

        void markAllClean()
        {
            dirtyStart = uint.max;
            dirtyEnd = 0;
        }
    }

    private Line[] lines;

    /**
     * Lookup a grapheme in the buffer.
     */
    Glyph opIndex(int x, int y)
    {
        if (y < 0 || y >= lines.length ||
            x < 0 || x >= lines[y].contents.length)
        {
            // Unassigned areas default to empty space
            static if (colorType == ColorType.basic16)
                return Glyph(spaceGrapheme, 0, 0);
            else
                return Glyph(spaceGrapheme);
        }

        if (lines[y].contents[x].type == Cell.Type.HalfRight)
        {
            assert(x > 0);
            return lines[y].contents[x-1].glyph;
        }
        else
            return lines[y].contents[x].glyph;
    }

    /**
     * Write a single grapheme into the buffer.
     */
    void opIndexAssign(Glyph gl, int x, int y)
        in (isGraphical(gl.g[0]))
    {
        if (y < 0 || x < 0) return;
        if (y >= lines.length)
            lines.length = y+1;

        assert(y < lines.length);
        if (x >= lines[y].contents.length)
            lines[y].contents.length = gl.g[0].isWide() ? x+2 : x+1;

        void stomp(int x, int y)
        {
            assert(y >= 0 && y < lines.length &&
                   x >= 0 && x < lines[y].contents.length);

            lines[y].markDirty(x);
            final switch (lines[y].contents[x].type)
            {
                case Cell.Type.HalfLeft:
                    assert(lines[y].contents.length > x+1);
                    lines[y].markDirty(x+1);
                    lines[y].contents[x+1].type = Cell.Type.Full;
                    lines[y].contents[x+1].glyph.g = spaceGrapheme;
                    static if (colorType == ColorType.basic16)
                    {
                        lines[y].contents[x+1].glyph.fg = gl.fg;
                        lines[y].contents[x+1].glyph.bg = gl.bg;
                    }
                    return;

                case Cell.Type.HalfRight:
                    assert(x > 0);
                    lines[y].markDirty(x-1);
                    lines[y].contents[x-1].type = Cell.Type.Full;
                    lines[y].contents[x-1].glyph.g = spaceGrapheme;
                    static if (colorType == ColorType.basic16)
                    {
                        lines[y].contents[x-1].glyph.fg = gl.fg;
                        lines[y].contents[x-1].glyph.bg = gl.bg;
                    }
                    return;

                case Cell.Type.Full:
                    // No need to do anything here; the subsequent write will
                    // overwrite this cell.
                    return;
            }
        }

        auto contents = lines[y].contents;
        if (contents[x].glyph == gl &&
            contents[x].type != Cell.Type.HalfRight)
        {
            // Written character identical to what's in buffer; nothing to do.
            return;
        }

        stomp(x, y);
        contents[x].glyph = gl;

        if (gl.g[0].isWide())
        {
            stomp(x+1, y);
            contents[x].type = Cell.Type.HalfLeft;
            contents[x+1].glyph.g = Grapheme.init;
            static if (colorType == ColorType.basic16)
            {
                contents[x+1].glyph.fg = gl.fg;
                contents[x+1].glyph.bg = gl.bg;
            }
            contents[x+1].type = Cell.Type.HalfRight;
        }
        else
            contents[x].type = Cell.Type.Full;
    }

    /**
     * Dump contents of buffer to sink.
     */
    version(unittest)
    void toString(scope void delegate(const(char)[]) sink)
    {
        foreach (y; 0 .. lines.length)
        {
            foreach (x; 0 .. lines[y].contents.length)
            {
                import std.algorithm : copy;
                if (lines[y].contents[x].type != Cell.Type.HalfRight)
                    lines[y].contents[x].glyph.g[].copy(sink);
            }
            sink("\n");
        }
    }

    /**
     * Returns: Input range of tuples of line numbers and buffer lines marked
     * dirty.
     */
    auto byDirtyLines()
    {
        import std.algorithm : filter, map;
        import std.range : zip, sequence;

        return zip(sequence!"n", lines.map!((ref a) => &a))
              .filter!(a => a[1].dirtyStart < a[1].dirtyEnd);
    }
}

version(unittest)
private void dump(Disp)(Disp buf)
    if (is(Disp == DispBuffer!c, ColorType c))
{
    import std.algorithm : map;
    import std.conv : to;
    import std.stdio;
    foreach (i, line; buf.lines)
    {
        writefln("%2d: >%s<", i, line.byGlyph().map!(gl => gl.g[].to!string));
    }
}

/**
 * A buffered wrapper around a grid-based display.
 */
struct BufferedDisplay(Display)
    if (isGridDisplay!Display)
{
    import std.uni;

    private Display disp;

    static if (hasColor!Display)
        private DispBuffer!(ColorType.basic16) buf;
    else
        private DispBuffer!(ColorType.none) buf;

    private Vec!(int,2) cursor;
    static if (canShowHideCursor!Display)
        private bool cursorHidden;

    /**
     * Dimensions of the underlying display.
     */
    @property auto width() { return disp.width; }
    @property auto height() { return disp.height; } /// ditto

    /**
     * Moves internal cursor position in the buffer.
     *
     * Note: Does not move actual cursor in underlying display until .flush is
     * called.
     */
    void moveTo(int x, int y)
    {
        cursor = vec(x,y);
    }

    private void writefImpl(string data)
    {
        int x = cursor[0];
        int y = cursor[1];
        foreach (g; data.byGrapheme)
        {
            if (!g[0].isGraphical)
            {
                // TBD: interpret \n, \t, etc..
                switch (g[0])
                {
                    case '\n':
                        x = 0;
                        y++;
                        break;

                    case '\t':
                        x = (x + 8) & ~7;
                        break;

                    default:
                        break;
                }
                continue;
            }

            // Clip against boundaries of underlying display
            if (x < 0 || x >= disp.width || y < 0 || y >= disp.height)
                continue;

            static if (hasColor!Display)
                buf[x,y] = buf.Glyph(g, curFg, curBg);
            else
                buf[x,y] = buf.Glyph(g);

            x += g[0].isWide() ? 2 : 1;
        }

        // Update cursor position
        cursor[0] = x;
        cursor[1] = y;
    }

    /**
     * Writes output to buffer at current internal cursor position.
     *
     * The internal cursor is updated to one past the last character output.
     *
     * Note: No output is written to the underlying display until .flush is
     * called. If any of the characters output are the same as what's in the
     * buffer, those characters will not be rewritten to the display by .flush.
     */
    void writef(A...)(string fmt, A args)
    {
        import std.format : format;
        writefImpl(fmt.format(args));
    }

    /**
     * Flushes the buffered changes to the underlying display.
     */
    void flush()
    {
        // Hide cursor during refresh, to avoid flickering artifacts.
        static if (canShowHideCursor!Display)
            disp.hideCursor();

        static if (hasColor!Display)
        {
            ushort fg = curFg, bg = curBg;
            disp.color(fg, bg);
        }

        foreach (e; buf.byDirtyLines)
        {
            auto linenum = e[0];
            auto line = e[1];

            assert(line.dirtyStart < line.dirtyEnd);
            assert(linenum <= int.max);

            disp.moveTo(line.dirtyStart, cast(int)linenum);

            import std.algorithm : joiner, map;
            static if (hasColor!Display)
            {
                foreach (gl; line.byDirtyGlyph())
                {
                    if (fg != gl.fg || bg != gl.bg)
                    {
                        fg = gl.fg;
                        bg = gl.bg;
                        disp.color(fg, bg);
                    }
                    disp.writef("%s", gl.g[]);
                }
            }
            else
                disp.writef("%s", line.byDirtyGlyph()
                                      .map!(gl => gl.g[])
                                      .joiner);

            line.markAllClean();
        }

        // Update physical cursor position to latest virtual position.
        static if (canShowHideCursor!Display)
        {
            if (!cursorHidden)
            {
                disp.moveTo(cursor[0], cursor[1]);
                disp.showCursor();
            }
        }
    }

    /**
     * Mark entire buffer as dirty so that the next call to .flush will repaint
     * the entire display.
     * Note: This method does NOT immediately update the underlying display;
     * the actual repainting will not happen until the next call to .flush.
     */
    void repaint()
    {
        foreach (ref e; buf.lines)
        {
            e.markAllDirty();
        }
    }

    static if (canShowHideCursor!Display)
    {
        void showCursor() { cursorHidden = false; }
        void hideCursor() { cursorHidden = true; }
    }

    /**
     * Clears the buffer and also the underlying display.
     *
     * Bugs: This takes effect immediately, rather than at the next call to
     * .flush.
     */
    void clear()
    {
        buf.lines.length = disp.height;
        foreach (j; 0 .. disp.height)
        {
            buf.lines[j].contents.length = disp.width;
            foreach (i; 0 .. disp.width)
            {
                static if (hasColor!Display)
                    buf[i, j] = buf.Glyph(spaceGrapheme, curFg, curBg);
                else
                    buf[i, j] = buf.Glyph(spaceGrapheme);
            }
        }

        static if (canClear!Display)
        {
            disp.clear();
            foreach (ref e; buf.lines)
            {
                e.markAllClean();
            }
        }
        else
        {
            flush();
        }
    }

    static if (hasColor!Display)
    {
        private ushort curFg, curBg;

        /**
         * Set current foreground/background color for grapheme assignments.
         */
        void color(ushort fg, ushort bg)
        {
            curFg = fg;
            curBg = bg;
        }
    }

    static assert(isGridDisplay!(typeof(this)));
}

/**
 * Convenience function for constructing a buffered display.
 * Returns: BufferedDisplay wrapping the given display.
 */
auto bufferedDisplay(Disp)(Disp disp)
{
    return BufferedDisplay!Disp(disp);
}

unittest
{
    struct TestDisplay
    {
        enum width = 80;
        enum height = 24;
        void moveTo(int x, int y) {}
        void writef(A...)(string fmt, A args) {}
    }
    BufferedDisplay!TestDisplay bufDisp;
    bufDisp.writef("Живу\n你是");

    import std.algorithm : equal;
    assert(bufDisp.buf[0,0].g[].equal("Ж"));
    assert(bufDisp.buf[1,0].g[].equal("и"));
    assert(bufDisp.buf[2,0].g[].equal("в"));
    assert(bufDisp.buf[3,0].g[].equal("у"));
    assert(bufDisp.buf[4,0].g[].equal(" "));
    assert(bufDisp.buf[0,1].g[].equal("你"));
    assert(bufDisp.buf[1,1].g[].equal("你"));
    assert(bufDisp.buf[2,1].g[].equal("是"));
    assert(bufDisp.buf[3,1].g[].equal("是"));

    bufDisp.moveTo(1,1);
    bufDisp.writef("大");
    assert(bufDisp.buf[0,1].g[].equal(" "));
    assert(bufDisp.buf[1,1].g[].equal("大"));
    assert(bufDisp.buf[2,1].g[].equal("大"));
    assert(bufDisp.buf[3,1].g[].equal(" "));

    bufDisp.moveTo(3,0);
    bufDisp.writef("и");
    assert(bufDisp.buf[3,0].g[].equal("и"));

    import std.array : appender;
    import std.format : formattedWrite;
    auto app = appender!string();
    app.formattedWrite("%s", bufDisp.buf);
    assert(app.data == "Живи\n 大 \n");

    // Test byDirtyLines() and Line.byGlyph().
    import std.algorithm : equal;
    import std.typecons : tuple;
    auto dirtyLines = bufDisp.buf.byDirtyLines;
    auto expectedLines = [
        tuple(0, "Живи"),
        tuple(1, " 大 ")
    ];

    import std.algorithm : map;
    import std.uni : byGrapheme;
    assert(equal!((a,b) => a[0]==b[0] &&
                  equal(a[1].byGlyph().map!(gl => *gl),
                        b[1].byGrapheme.map!(ch => bufDisp.buf.Glyph(ch))))
                 (dirtyLines, expectedLines));
}

unittest
{
    import std.array;
    import std.typecons;
    import std.string : format;

    struct TestDisplay
    {
        enum width = 10;
        enum height = 4;
        Vec!(int,2) cursor;
        Tuple!(int,int,string)[] expected;

        void moveTo(int x, int y) { cursor = vec(x,y); }
        void writef(A...)(string fmt, A args)
        {
            auto str = format(fmt, args);

            assert(!expected.empty);
            assert(cursor == vec(expected[0][0], expected[0][1]),
                   "Expecting cursor at (%d,%d), actual at (%d,%d)"
                   .format(expected[0][0], expected[0][1],
                           cursor[0], cursor[1]));
            assert(str == expected[0][2], "Expecting >%s<, got >%s<"
                                          .format(expected[0][2], str));
            expected.popFront();
        }
    }
    static assert(isGridDisplay!TestDisplay);
    BufferedDisplay!TestDisplay bufDisp;

    // Test construction of lines piecemeal
    bufDisp.moveTo(1,1);
    bufDisp.writef("Раз");
    bufDisp.moveTo(5,3);
    bufDisp.writef("大人");
    bufDisp.moveTo(4,1);
    bufDisp.writef("цветали"); // note: last letter should be clipped
    bufDisp.moveTo(1,3);
    bufDisp.writef("你是");

    bufDisp.disp.expected = [
        tuple(1, 1, "Разцветал"),
        tuple(1, 3, "你是大人"),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    // Test overwriting of existing content.
    bufDisp.moveTo(1,3);
    bufDisp.writef("他");
    bufDisp.disp.expected = [
        tuple(1, 3, "他"),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    // Test stomping of wide characters
    bufDisp.moveTo(0,3);
    bufDisp.writef("他");
    bufDisp.disp.expected = [
        tuple(0, 3, "他 "),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    bufDisp.moveTo(4,3);
    bufDisp.writef("x");
    bufDisp.disp.expected = [
        tuple(3, 3, " x"),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);
}

version(none)
unittest
{
    // Test code for what happens when double-width characters are stricken
    // over.
    import arsd.terminal;

    auto term = Terminal(ConsoleOutputType.cellular);
    term.clear();
    term.moveTo(0,10);
    term.writef("%s", "廳");
    term.moveTo(0,11);
    term.writef("%s", "廳");

    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    term.flush();

    bool quit;
    while (!quit)
    {
        auto event = input.nextEvent();
        if (event.type != InputEvent.Type.CharacterEvent) continue;

        auto ev = event.get!(InputEvent.Type.CharacterEvent);
        switch (ev.character)
        {
            case 'q':
                quit = true;
                break;
            case '0':
                term.moveTo(0,11);
                term.writef("廳");
                break;
            case '1':
                term.moveTo(0,11);
                term.writef("x");
                break;
            case '2':
                term.moveTo(1,11);
                term.writef("x");
                break;
            case '3':
                term.moveTo(5,10);
                term.writef("廳長");
                term.moveTo(6,11);
                term.writef("廳長");
                break;
            case '4':
                term.moveTo(7,11);
                term.writef("驪");
                break;
            default:
                break;
        }
    }

    term.clear();
}

version(none)
unittest
{
    import std.algorithm, std.format, std.stdio, std.uni;

    ("龘\n\t龘1\u2060a\u0308Ш ж\u0301\u0325\u200Bи\u200DвI\u0334"~
     "\0D\u0338\u0321o\u0330\n\tu\u0313\u0338\u0330\n5\u035A\n"~
     "ΐ\u032E 你１２３1\u033023")
        .byGrapheme
        .map!((g) {
            string s;
            if (isGraphical(g[0]))
                s ~= "graph[%d]: %s".format(g.length, g[]);
            else
                s ~= "nongrph[%d]:".format(g.length);
            s ~= "(%(U+%04X %))".format(g[]);

            if (isGraphical(g[0]))
                s ~= " %s".format(g[0].isWide ?
                            "wide" : "narrow");
            return s;
        })
        .joiner("\n")
        .writeln;
}

// Cache tester
unittest
{
    class TestDisplay
    {
        enum width = 8;
        enum height = 3;

        dchar[width*height] impl;
        Vec!(int,2) cursor;

        this()
        {
            foreach (ref ch; impl) { ch = ' '; }
        }
        void moveTo(int x, int y) { cursor = vec(x,y); }
        void writef(A...)(string fmt, A args)
        {
            import std.format : format;
            auto str = format(fmt, args);
            foreach (dchar ch; str)
            {
                assert(cursor[0] < width && cursor[1] < height);
                impl[cursor[0] + width*cursor[1]] = ch;
                cursor[0]++;
            }
        }
    }
    static assert(isGridDisplay!TestDisplay);

    auto disp = new TestDisplay;
    assert(disp.impl == "        "~
                        "        "~
                        "        ");

    // Test per-line cache: lines should not be written until .flush is called.
    auto bufDisp = bufferedDisplay(disp);
    bufDisp.clear();
    bufDisp.moveTo(0, 0);
    bufDisp.writef("abcdefgh");
    assert(disp.impl == "        "~ // not updated until .flush is called
                        "        "~
                        "        ");
    bufDisp.flush();
    assert(disp.impl == "abcdefgh"~
                        "        "~
                        "        ");

    // Untouched lines should not be updated.
    bufDisp.moveTo(0, 1);
    bufDisp.writef("01234567");
    disp.impl[0] = 'X';     // canary
    assert(disp.impl == "Xbcdefgh"~
                        "        "~
                        "        ");
    bufDisp.flush();
    assert(disp.impl == "Xbcdefgh"~ // buffer unaware of canary
                        "01234567"~
                        "        ");

    // .repaint forces update of all lines
    bufDisp.repaint();
    bufDisp.flush();
    assert(disp.impl == "abcdefgh"~ // .repaint overwrites canary
                        "01234567"~
                        "        ");

    // Test partial line caching: if only middle of line updated, only dirty
    // segment should be updated.  For efficiency, we only track a single
    // segment; the overhead of jumping between segments on a single line seems
    // not worthwhile.
    disp.impl[0] = 'X';
    disp.impl[8] = 'Y';
    disp.impl[15] = 'Z';
    disp.impl[16] = 'W';
    assert(disp.impl == "Xbcdefgh"~ // canaries
                        "Y123456Z"~
                        "W       ");
    bufDisp.moveTo(1, 1);
    bufDisp.writef("Ойойой");
    bufDisp.flush();
    assert(disp.impl == "Xbcdefgh"~ // buffer unaware of canaries
                        "YОйойойZ"~
                        "W       ");

    bufDisp.repaint();
    bufDisp.flush();
    assert(disp.impl == "abcdefgh"~ // canaries gone
                        "0Ойойой7"~
                        "        ");

    // Test matching of existing characters
    disp.impl[16] = '^';
    disp.impl[23] = '$';
    assert(disp.impl == "abcdefgh"~
                        "0Ойойой7"~
                        "^      $");
    bufDisp.moveTo(0, 2);
    bufDisp.writef("   ha   ");
    bufDisp.flush();
    assert(disp.impl == "abcdefgh"~
                        "0Ойойой7"~
                        "^  ha  $"); // buffer unaware of canaries
}

// Color tester
unittest
{
    class ColorDisp
    {
        enum width = 8;
        enum height = 3;

        dchar[width*height] text;
        ushort[width*height] fgs;
        ushort[width*height] bgs;

        Vec!(int,2) cursor;
        ushort fg, bg;

        this()
        {
            text[] = ' ';
        }
        void moveTo(int x, int y) { cursor = vec(x,y); }
        void writef(A...)(string fmt, A args)
        {
            import std.format : format;
            auto str = format(fmt, args);
            foreach (dchar ch; str)
            {
                assert(cursor[0] < width && cursor[1] < height);
                text[cursor[0] + width*cursor[1]] = ch;
                fgs[cursor[0] + width*cursor[1]] = fg;
                bgs[cursor[0] + width*cursor[1]] = bg;
                cursor[0]++;
            }
        }
        void color(ushort _fg, ushort _bg)
        {
            fg = _fg;
            bg = _bg;
        }
    }
    static assert(isGridDisplay!ColorDisp);
    static assert(hasColor!ColorDisp);

    auto disp = new ColorDisp;
    assert(disp.text == "        "~
                        "        "~
                        "        ");

    auto bufDisp = bufferedDisplay(disp);
    bufDisp.clear();

    // Basic color test
    bufDisp.moveTo(0, 0);
    bufDisp.writef("abcd");
    bufDisp.color(1, 2);
    bufDisp.writef("efgh");
    bufDisp.moveTo(2, 2);
    bufDisp.writef("bleh");
    bufDisp.color(3, 4); // should not affect .flush
    bufDisp.flush();
    assert(disp.text == "abcdefgh"~
                        "        "~
                        "  bleh  ");
    assert(disp.fgs == [ 0,0,0,0,1,1,1,1,
                         0,0,0,0,0,0,0,0,
                         0,0,1,1,1,1,0,0 ]);
    assert(disp.bgs == [ 0,0,0,0,2,2,2,2,
                         0,0,0,0,0,0,0,0,
                         0,0,2,2,2,2,0,0 ]);

    // Color overwrite test
    bufDisp.moveTo(2, 0);
    bufDisp.writef("HAHA");
    bufDisp.flush();
    assert(disp.text == "abHAHAgh"~
                        "        "~
                        "  bleh  ");
    assert(disp.fgs == [ 0,0,3,3,3,3,1,1,
                         0,0,0,0,0,0,0,0,
                         0,0,1,1,1,1,0,0 ]);
    assert(disp.bgs == [ 0,0,4,4,4,4,2,2,
                         0,0,0,0,0,0,0,0,
                         0,0,2,2,2,2,0,0 ]);

    // Same text, different colors overwrite test
    bufDisp.color(5, 6);
    bufDisp.moveTo(0, 1);
    bufDisp.writef("  ");
    bufDisp.moveTo(1, 2);
    bufDisp.writef(" ble");
    bufDisp.flush();
    assert(disp.text == "abHAHAgh"~
                        "        "~
                        "  bleh  ");
    assert(disp.fgs == [ 0,0,3,3,3,3,1,1,
                         5,5,0,0,0,0,0,0,
                         0,5,5,5,5,1,0,0 ]);
    assert(disp.bgs == [ 0,0,4,4,4,4,2,2,
                         6,6,0,0,0,0,0,0,
                         0,6,6,6,6,2,0,0 ]);

    // Identical write test
    disp.text[] = 'X';    // canaries
    disp.fgs[] = 0;
    disp.bgs[] = 0;
    assert(disp.text == "XXXXXXXX"~
                        "XXXXXXXX"~
                        "XXXXXXXX");
    assert(disp.fgs == [ 0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0 ]);
    assert(disp.bgs == [ 0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0 ]);

    bufDisp.moveTo(4, 0);
    bufDisp.color(3, 4);
    bufDisp.writef("HA");
    bufDisp.color(1, 2);
    bufDisp.writef("gh");

    bufDisp.moveTo(1, 1);
    bufDisp.color(5, 6);
    bufDisp.writef(" ");

    bufDisp.moveTo(3, 2);
    bufDisp.writef("l");

    bufDisp.moveTo(7, 2); // non-identical write
    bufDisp.color(7, 8);
    bufDisp.writef("O");

    bufDisp.flush();

    assert(disp.text == "XXXXXXXX"~ // buffer unaware of canaries
                        "XXXXXXXX"~
                        "XXXXXXXO");
    assert(disp.fgs == [ 0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,7 ]);
    assert(disp.bgs == [ 0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,0,
                         0,0,0,0,0,0,0,8 ]);

    bufDisp.repaint();
    bufDisp.flush();
    assert(disp.text == "abHAHAgh"~ // state now resynced
                        "        "~
                        "  bleh O");
    assert(disp.fgs == [ 0,0,3,3,3,3,1,1,
                         5,5,0,0,0,0,0,0,
                         0,5,5,5,5,1,0,7 ]);
    assert(disp.bgs == [ 0,0,4,4,4,4,2,2,
                         6,6,0,0,0,0,0,0,
                         0,6,6,6,6,2,0,8 ]);
}

// vim:set ai sw=4 ts=4 et:
