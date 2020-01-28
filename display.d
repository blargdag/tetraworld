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
enum isDisplay(T) = is(typeof(int.init < T.init.width)) &&
                    is(typeof(int.init < T.init.height)) &&
                    is(typeof(T.init.moveTo(0,0))) &&
                    is(typeof(T.init.writef("%s", "")));

unittest
{
    import arsd.terminal;
    static assert(isDisplay!(arsd.terminal.Terminal));
}

/**
 * true if T is a grid display that supports the .showCursor and .hideCursor
 * methods.
 */
enum canShowHideCursor(T) = isDisplay!T &&
                            is(typeof(T.init.showCursor())) &&
                            is(typeof(T.init.hideCursor()));

/**
 * true if T is a grid-based display that supports color.
 *
 * A display that supports color is one that has a .color method that accepts
 * two ushort parameters, corresponding to foreground and background colors.
 */
template hasColor(T)
    if (isDisplay!T)
{
    enum hasColor = is(typeof(T.init.color(ushort.init, ushort.init)));
}

/**
 * true if T is a grid-based display that supports the .clear operation.
 */
template canClear(T)
    if (isDisplay!T)
{
    enum canClear = is(typeof(T.init.clear()));
}

/**
 * true if T is a grid-based display that has .cursorX and cursorY.
 */
template hasCursorXY(T)
    if (isDisplay!T)
{
    enum hasCursorXY = is(typeof(T.init.cursorX) : int) &&
                       is(typeof(T.init.cursorY) : int);
}

/**
 * true if T is a grid-based display that has a .flush method.
 */
enum hasFlush(T) = isDisplay!T && is(typeof(T.init.flush()));

/**
 * A wrapper around an existing display that represents a rectangular subset of
 * it. The .moveTo primitive is wrapped to translate input coordinates into
 * actual coordinates on the display.
 */
struct SubDisplay(T)
    if (isDisplay!T)
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

    static if (hasColor!T)
        void color(ushort fg, ushort bg) { parent.color(fg, bg); }

    static if (hasCursorXY!T)
    {
        @property int cursorX() { return parent.cursorX - rect.min[0]; }
        @property int cursorY() { return parent.cursorY - rect.min[1]; }
    }

    static if (canShowHideCursor!T)
    {
        void showCursor() { parent.showCursor(); }
        void hideCursor() { parent.hideCursor(); }
    }

    void clear()
    {
        foreach (j; rect.min[1] .. rect.max[1])
        {
            parent.moveTo(rect.min[0], j);
            foreach (i; rect.min[0] .. rect.max[0])
            {
                parent.writef("%s", " ");
            }
        }
    }

    static if (hasFlush!T)
    {
        void flush()
        {
            parent.flush();
        }
    }
}

unittest
{
    import arsd.terminal;
    static assert(isDisplay!(SubDisplay!(arsd.terminal.Terminal)));
}

/// Convenience method for constructing a SubDisplay.
auto subdisplay(T)(T display, Region!(int,2) rect)
    if (isDisplay!T)
{
    return SubDisplay!T(display, rect);
}

/**
 * A virtual sliding display overlaying an underlying display, that ignores
 * writes outside of the underlying display.
 *
 * Params:
 *  display = The underlying display.
 *  width = The width of the virtual display.
 *  height = The height of the virtual display.
 *  originX = The X coordinate of the underlying display relative to the
 *      virtual display.
 *  originY = The Y coordinate of the underlying display relative to the
 *      virtual display.
 */
struct SlidingDisplay(Disp)
    if (isDisplay!Disp)
{
    private Disp disp;
    int width, height;
    private int offX, offY;
    private int curX, curY;

    this(Disp _disp, int _width, int _height, int offsetX, int offsetY)
    {
        disp = _disp;
        width = _width;
        height = _height;
        offX = offsetX;
        offY = offsetY;
    }

    /**
     * Scroll the overlay by the given displacement.
     */
    void scroll(int dx, int dy)
    {
        offX += dx;
        offY += dy;
    }

    /**
     * Scroll the overlay to the given position.
     */
    void scrollTo(int x, int y)
    {
        offX = x;
        offY = y;
    }

    void moveTo(int x, int y)
        in (0 <= x && x < width)
        in (0 <= y && y < height)
    {
        curX = x;
        curY = y;
    }

    void writef(Args...)(string fmt, Args args)
    {
        import std.format : format;
        writefImpl(format(fmt, args));
    }

    private void writefImpl(string str)
    {
        import std.uni : byGrapheme;
        foreach (g; str.byGrapheme)
        {
            auto xreal = curX + offX;
            auto yreal = curY + offY;

            if (xreal >= 0 && xreal < disp.width &&
                yreal >= 0 && yreal < disp.height)
            {
                disp.moveTo(xreal, yreal);
                disp.writef("%s", g[]);
            }

            curX += isWide(g[0]) ? 2 : 1;
        }
    }

    static if (hasColor!Disp)
    {
        void color(ushort fg, ushort bg)
        {
            disp.color(fg, bg);
        }
    }

    @property int cursorX() { return curX; }
    @property int cursorY() { return curY; }

    static assert(isDisplay!(typeof(this)));
    static assert(hasCursorXY!(typeof(this)));
}

/// ditto
auto slidingDisplay(Disp)(Disp display, int width, int height,
                          int originX, int originY)
{
    return SlidingDisplay!Disp(display, width, height, originX, originY);
}

unittest
{
    struct TestDisp
    {
        enum width = 3;
        enum height = 3;
        char[width*height] impl;
        int curX, curY;

        void moveTo(int x, int y)
            in (x >= 0 && x < width)
            in (y >= 0 && y < height)
        {
            curX = x;
            curY = y;
        }

        void writef(Args...)(string fmt, Args args)
        {
            import std.format : format;
            foreach (ch; format(fmt, args))
            {
                impl[curX + width*curY] = ch;
                curX++;
            }
        }
    }
    TestDisp disp;
    auto sdisp = slidingDisplay(&disp, 5, 5, 0, 0);

    void drawStuff()
    {
        sdisp.moveTo(0, 0); sdisp.writef("--*--");
        sdisp.moveTo(0, 1); sdisp.writef("abcde");
        sdisp.moveTo(0, 2); sdisp.writef("12345");
        sdisp.moveTo(0, 3); sdisp.writef("VWXYZ");
        sdisp.moveTo(0, 4); sdisp.writef("--@--");
    }

    drawStuff();
    assert(disp.impl == "--*"~
                        "abc"~
                        "123");

    sdisp.scroll(0, -1);
    drawStuff();
    assert(disp.impl == "abc"~
                        "123"~
                        "VWX");

    sdisp.scroll(0, -1);
    drawStuff();
    assert(disp.impl == "123"~
                        "VWX"~
                        "--@");

    sdisp.scroll(-1, 0);
    drawStuff();
    assert(disp.impl == "234"~
                        "WXY"~
                        "-@-");

    sdisp.scroll(-1, 0);
    drawStuff();
    assert(disp.impl == "345"~
                        "XYZ"~
                        "@--");

    sdisp.scroll(0, 1);
    drawStuff();
    assert(disp.impl == "cde"~
                        "345"~
                        "XYZ");

    sdisp.scroll(1, 0);
    drawStuff();
    assert(disp.impl == "bcd"~
                        "234"~
                        "WXY");

    sdisp.scrollTo(-2, 0);
    drawStuff();
    assert(disp.impl == "*--"~
                        "cde"~
                        "345");
}

/**
 * Writes spaces to the current display from the current cursor position until
 * the end of the line.
 */
void clearToEol(T)(auto ref T display)
    if (isDisplay!T && hasCursorXY!T)
{
    foreach (i; display.cursorX .. display.width)
    {
        display.writef(" ");
    }
}

/**
 * Fills the current display with spaces starting from the current cursor
 * position until the bottom right corner of the display.
 */
void clearToEos(T)(auto ref T display)
    if (isDisplay!T && hasCursorXY!T)
{
    int startY = display.cursorY;

    display.clearToEol();
    foreach (i; startY .. display.height)
    {
        display.moveTo(0, i);
        display.clearToEol();
    }
}

/**
 * Draws a box of the specified position and dimensions to the given display.
 * Params:
 *  display = A grid-based output display satisfying isDisplay.
 *  box = a Rectangle specifying the position and dimensions of the box to be
 *  drawn.
 */
void drawBox(T)(T display, Region!(int,2) box)
    if (isDisplay!T)
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

/**
 * Returns: The display length of the string. Assumes non-graphical characters
 * have length zero, and wide characters (as classified by isWide) have length
 * 2.
 *
 * BUGS: Does NOT interpret control characters like newlines, and particularly
 * tabs.
 */
size_t displayLength(string str)
{
    import std.algorithm : map, sum;
    import std.uni : byGrapheme, isGraphical;
    return str.byGrapheme
              .map!(g => !g[0].isGraphical ? 0 :
                         g[0].isWide ? 2 : 1)
              .sum;
}

///
unittest
{
    assert("abcde".displayLength == 5);
    assert("ab\ncde".displayLength == 5);
    assert("ab\u0301cde".displayLength == 5);
    assert("ab\u0301\u0310cde".displayLength == 5);
    assert("ab\u0301\u0310\u5f35e".displayLength == 5);
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
        {
            // 256 is arsd.terminal's default (Color.DEFAULT). We copy that
            // here for transparent compatibility.
            ushort fg = 256, bg = 256;
        }
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

    void clear(uint width, uint height, ushort fg=256, ushort bg=256)
    {
        lines.length = height;
        foreach (j; 0 .. height)
        {
            lines[j].contents.length = width;
            foreach (i; 0 .. width)
            {
                static if (colorType == ColorType.basic16)
                    this[i, j] = Glyph(spaceGrapheme, fg, bg);
                else
                    this[i, j] = Glyph(spaceGrapheme);
            }
        }
    }

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
    if (isDisplay!Display)
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

    this(Display _disp)
    {
        disp = _disp;
        clear();
    }

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
        static if (hasColor!Display)
            buf.clear(disp.width, disp.height, curFg, curBg);
        else
            buf.clear(disp.width, disp.height);

        static if (canClear!Display)
        {
            static if (hasColor!Display)
                disp.color(curFg, curBg);

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
        // 256 is arsd.terminal's default (Color.DEFAULT). We copy that here
        // for transparent compatibility.
        private ushort curFg = 256, curBg = 256;

        /**
         * Set current foreground/background color for grapheme assignments.
         */
        void color(ushort fg, ushort bg)
        {
            curFg = fg;
            curBg = bg;
        }
    }

    @property int cursorX() { return cursor[0]; }
    @property int cursorY() { return cursor[1]; }

    static assert(isDisplay!(typeof(this)));
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
    static assert(isDisplay!TestDisplay);
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
    static assert(isDisplay!TestDisplay);

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
    static assert(isDisplay!ColorDisp);
    static assert(hasColor!ColorDisp);

    auto disp = new ColorDisp;
    assert(disp.text == "        "~
                        "        "~
                        "        ");

    auto bufDisp = bufferedDisplay(disp);

    // Verify arsd.terminal default colors for compatibility.
    bufDisp.flush();
    assert(disp.text == "        "~
                        "        "~
                        "        ");
    assert(disp.fgs == [ 256,256,256,256,256,256,256,256,
                         256,256,256,256,256,256,256,256,
                         256,256,256,256,256,256,256,256 ]);
    assert(disp.bgs == [ 256,256,256,256,256,256,256,256,
                         256,256,256,256,256,256,256,256,
                         256,256,256,256,256,256,256,256 ]);

    bufDisp.color(0, 0);
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

    // Cursor test: apparent cursor should not track real cursor.
    bufDisp.moveTo(0, 0);
    assert(bufDisp.cursorX == 0 && bufDisp.cursorY == 0);
    bufDisp.moveTo(2, 3);
    assert(bufDisp.cursorX == 2 && bufDisp.cursorY == 3);
}

/**
 * A Display that wraps around another Display and records method calls and
 * arguments, such that it can be saved and replayed later into a different
 * Display. Timing information is saved for faithful replay.
 */
struct Recorded(Disp,Log)
    if (isDisplay!Disp && isOutputRange!(Log, char))
{
    import core.time : MonoTime;
    import std.format : formattedWrite, format;

    private Disp disp;
    private Log log;
    private MonoTime lastStamp;

    private void timestamp()
    {
        auto now = MonoTime.currTime;
        if (lastStamp != MonoTime.init) // skip first delay
        {
            auto delay = (now - lastStamp).total!"msecs";
            if (delay > 0)
            {
                log.formattedWrite("delay %d\n", delay);
            }
        }
        lastStamp = now;
    }

    this(Disp _disp, Log _log)
    {
        disp = _disp;
        log = _log;

        log.formattedWrite("width %d\n", disp.width);
        log.formattedWrite("height %d\n", disp.height);
    }

    // These don't need to be recorded.
    @property int width() { return disp.width; }
    @property int height() { return disp.height; }

    void moveTo(int x, int y)
    {
        timestamp();
        disp.moveTo(x, y);
        log.formattedWrite("moveTo %d %d\n", x, y);
    }

    void writef(Args...)(string fmt, Args args)
    {
        timestamp();
        string str = format(fmt, args);
        disp.writef("%s", str);
        log.formattedWrite("writef %d|%s|\n", str.length, str);
    }

    static if (canShowHideCursor!Disp)
    {
        void showCursor()
        {
            timestamp();
            disp.showCursor();
            log.formattedWrite("showCursor\n");
        }

        void hideCursor()
        {
            timestamp();
            disp.hideCursor();
            log.formattedWrite("hideCursor\n");
        }
    }

    static if (hasColor!Disp)
    {
        void color(ushort fg, ushort bg)
        {
            timestamp();
            disp.color(fg, bg);

            // Assumption: arsd.terminal.Color converts to an OS-independent
            // readable string, and Bright can be OR'd with any color. We
            // represent Bright with a suffixed '*' in the output.
            import arsd.terminal : Color, Bright;
            import std.conv : to;
            bool fgBright = (fg & Bright) != 0;
            bool bgBright = (bg & Bright) != 0;
            log.formattedWrite("color %s%s %s%s\n",
                (cast(Color)(fg & ~Bright)).to!string, fgBright ? "*" : "",
                (cast(Color)(bg & ~Bright)).to!string, bgBright ? "*" : "");
        }
    }

    static if (canClear!Disp)
    {
        void clear()
        {
            timestamp();
            disp.clear();
            log.formattedWrite("clear\n");
        }
    }

    static if (hasCursorXY!Disp)
    {
        // Note: no need to log anything here, it's just an internal query.
        int cursorX() { return disp.cursorX(); }
        int cursorY() { return disp.cursorY(); }
    }
    static if (hasFlush!Disp)
    {
        void flush() { disp.flush(); }
    }
}

/// ditto
auto recorded(Disp,Log)(Disp disp, Log log)
    if (isDisplay!Disp && isOutputRange!(Log, char))
{
    return Recorded!(Disp, Log)(disp, log);
}

///
unittest
{
    struct DummyDisp
    {
        enum width = 80;
        enum height = 24;

        void moveTo(int x, int y) { }
        void writef(A...)(string fmt, A args) { }
        void showCursor() { }
        void hideCursor() { }
        void color(ushort _fg, ushort _bg) { }
        void clear() { }
    }
    DummyDisp disp;

    import core.thread : Thread;
    import core.time : dur;
    import std.array : appender;
    import arsd.terminal : Bright, Color;

    auto log = appender!string;
    auto recdisp = disp.recorded(log);
    static assert(isDisplay!(typeof(recdisp)));

    recdisp.moveTo(0, 0);
    recdisp.writef(" blah blah blah hahaha");
    recdisp.moveTo(0, 1);
    recdisp.color(Color.red, Color.cyan);
    recdisp.writef("hehehehe, Ну это да!");

    Thread.sleep(dur!"msecs"(50));
    recdisp.hideCursor();
    recdisp.moveTo(2, 3);
    recdisp.color(Color.blue | Bright, Color.white);
    recdisp.writef("Правда так??!");
    recdisp.moveTo(0, 3);
    recdisp.showCursor();

    assert(log.data ==
        "width 80\n"~
        "height 24\n"~
        "moveTo 0 0\n"~
        "writef 22| blah blah blah hahaha|\n"~
        "moveTo 0 1\n"~
        "color red cyan\n"~
        "writef 27|hehehehe, Ну это да!|\n"~
        "delay 50\n"~
        "hideCursor\n"~
        "moveTo 2 3\n"~
        "color blue* white\n"~
        "writef 22|Правда так??!|\n"~
        "moveTo 0 3\n"~
        "showCursor\n"
    );
}

/**
 * Replay to the given Display the given log saved by Recorded.
 *
 * Params:
 *  log = A log saved by Recorded.
 *  createDisp = A delegate that returns a Display of the given dimensions for
 *      the replay to happen in.
 *  delayHook = An optional delegate that implements the 'delay' directive,
 *      taking an msec argument. If not specified, defaults to
 *      core.thread.Thread.sleep.
 */
void replay(Disp,Log)(Log log,
                      Disp delegate(int width, int height) createDisp)
{
    import core.thread : Thread;
    import core.time : dur;
    replay(log, createDisp, (msecs) => Thread.sleep(dur!"msecs"(msecs)));
}

/// ditto
void replay(Disp,Log)(Log log,
                      Disp delegate(int width, int height) createDisp,
                      void delegate(int msecs) delayHook)
    if (isDisplay!Disp && isInputRange!Log &&
        is(ElementType!Log : const(char)[]))
{
    import std.algorithm : startsWith, endsWith;
    import std.conv : parse, to;
    import std.exception : enforce;

    enforce(!log.empty, "Missing width spec");
    enforce(log.front.startsWith("width "), "Invalid width spec");
    auto w = log.front[6 .. $].to!int;
    log.popFront();

    enforce(!log.empty, "Missing height spec ");
    enforce(log.front.startsWith("height "), "Invalid height spec");
    auto h = log.front[7 .. $].to!int;
    log.popFront();

    enforce(w != 0 && h != 0, "Invalid dimensions");

    auto disp = createDisp(w, h);
    while (!log.empty)
    {
        auto line = log.front;
        if (line.startsWith("moveTo "))
        {
            auto args = line[7 .. $];
            auto x = args.parse!int;

            enforce(args.startsWith(" "), "Invalid moveTo arg 1");
            args.popFront;

            auto y = args.parse!int;
            enforce(args.empty, "Invalid moveTo arg 2");

            disp.moveTo(x, y);
        }
        else if (line.startsWith("writef "))
        {
            auto args = line[7 .. $];
            auto len = args.parse!size_t;
            enforce(args.startsWith("|"), "Invalid writef arg 1");
            args.popFront;

            if (args.length == len+1)
            {
                enforce(args.endsWith("|"), "Invalid writef arg 2");
                disp.writef("%s", args[0 .. $-1]);
            }
            else
            {
                auto txt = args.idup;
                while (txt.length < len && !log.empty)
                {
                    log.popFront();
                    txt ~= "\n" ~ log.front;
                }
                enforce(txt.length == len+1, "Invalid wrapped line");
                enforce(txt[$-1] == '|', "Unterminated wrapped line");
                txt = txt[0 .. $-1];
                disp.writef("%s", txt);
            }
        }
        else if (line == "showCursor")
            disp.showCursor();
        else if (line == "hideCursor")
            disp.hideCursor();
        else if (line.startsWith("color "))
        {
            import arsd.terminal : Color, Bright;
            auto args = line[6 .. $];

            auto fg = args.parse!Color;
            if (args.startsWith("*"))
            {
                fg |= Bright;
                args.popFront();
            }

            enforce(args.startsWith(" "), "Invalid color arg 1");
            args.popFront;

            auto bg = args.parse!Color;
            if (args.startsWith("*"))
            {
                bg |= Bright;
                args.popFront();
            }

            disp.color(fg, bg);
        }
        else if (line == "clear")
            disp.clear();
        else if (line.startsWith("delay "))
        {
            auto args = line[6 .. $];
            auto msecs = args.parse!uint;

            static if (hasFlush!Disp)
                disp.flush();
            delayHook(msecs);
        }
        else if (line != "")
            throw new Exception("Unknown directive: " ~ line.idup);

        log.popFront();
    }
}

///
unittest
{
    struct DummyDisp
    {
        int width;
        int height;

        this(int w, int h) { width = w; height = h; }
        void moveTo(int x, int y) { }
        void writef(A...)(string fmt, A args) { }
        void showCursor() { }
        void hideCursor() { }
        void color(ushort _fg, ushort _bg) { }
        void clear() { }
    }

    auto input = [
        "width 80",
        "height 24",
        "moveTo 0 0",
        "writef 22| blah blah blah hahaha|",
        "moveTo 0 1",
        "color red cyan*",
        "writef 27|hehehehe, Ну это да!|",
        "delay 50",
        "clear",
        "hideCursor",
        "moveTo 2 3",
        "color blue* white",
        "writef 22|Правда так??!|",
        "moveTo 0 3",
        "showCursor",
        "moveTo 0 4",
        "writef 21|evil embedded",
        "newline|",
        "moveTo 0 5",
        "writef 18|multi",
        "newline",
        "fun!|",
        ""
    ];

    import std.array : appender, split;
    auto log = appender!string;

    DummyDisp disp;
    input.replay((w, h) {
        disp = DummyDisp(w, h);
        return disp.recorded(log);
    });

    auto lines = log.data.split("\n");
    foreach (i; 0 .. lines.length)
    {
        assert(i < input.length, lines[i] ~ " != EOF");
        assert(lines[i] == input[i], lines[i] ~ " != " ~ input[i]);
    }
    assert(lines.length == input.length);
}

/**
 * Runtime polymorphic Display object.
 */
abstract class DisplayObject
{
    @property abstract int width();
    @property abstract int height();
    abstract void moveTo(int x, int y);
    abstract void writefImpl(string s);

    final void writef(Args...)(string fmt, Args args)
    {
        import std.format : format;
        writefImpl(format(fmt, args));
    }

    bool canShowHideCursor() { return false; }
    void showCursor() { assert(0); }
    void hideCursor() { assert(0); }

    bool hasColor() { return false; }
    void color(ushort fg, ushort bg) { assert(0); }

    bool canClear() { return false; }
    void clear() { assert(0); }

    bool hasCursorXY() { return false; }
    @property int cursorX() { assert(0); }
    @property int cursorY() { assert(0); }

    bool hasFlush() { return false; }
    void flush() { assert(0); }
}

private class DisplayObjImpl(Disp) : DisplayObject
    if (isDisplay!Disp)
{
    private Disp disp;
    this(Disp _disp)
    {
        disp = _disp;
    }
    @property override int width() { return disp.width; }
    @property override int height() { return disp.height; }
    override void moveTo(int x, int y) { disp.moveTo(x, y); }
    override void writefImpl(string s) { disp.writef("%s", s); }
    static if (.canShowHideCursor!Disp)
    {
        override bool canShowHideCursor() { return true; }
        override void showCursor() { disp.showCursor(); }
        override void hideCursor() { disp.hideCursor(); }
    }
    static if (.hasColor!Disp)
    {
        override bool hasColor() { return true; }
        override void color(ushort fg, ushort bg) { disp.color(fg, bg); }
    }
    static if (.canClear!Disp)
    {
        override bool canClear() { return true; }
        override void clear() { disp.clear(); }
    }
    static if (.hasCursorXY!Disp)
    {
        override bool hasCursorXY() { return true; }
        @property override int cursorX() { return disp.cursorX; }
        @property override int cursorY() { return disp.cursorY; }
    }
    static if (.hasFlush!Disp)
    {
        override bool hasFlush() { return true; }
        override void flush() { disp.flush(); }
    }
}

/// ditto
auto displayObject(Disp)(Disp disp)
    if (isDisplay!Disp)
{
    return new DisplayObjImpl!Disp(disp);
}

unittest
{
    import arsd.terminal;
    Terminal* term;
    auto obj = displayObject(term);
}

// vim:set ai sw=4 ts=4 et:
