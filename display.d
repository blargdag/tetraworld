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
                        is(typeof(T.moveTo(0,0))) &&
                        is(typeof(T.writef("%s", "")));

unittest
{
    import arsd.terminal;
    static assert(isGridDisplay!(arsd.terminal.Terminal));
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
    in { assert((vec(x,y) + rect.lowerBound) in rect); }
    body
    {
        parent.moveTo((vec(x,y) + rect.lowerBound).byComponent);
    }

    ///
    void writef(A...)(string fmt, A args) { parent.writef(fmt, args); }

    ///
    @property auto width() { return rect.lowerBound[0]; }

    ///
    @property auto height() { return rect.lowerBound[1]; }
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
in { assert(box.length!0 >= 2 && box.length!1 >= 2); }
body
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

    auto bx = box.lowerBound[0];
    auto by = box.lowerBound[1];
    auto width = box.length!0;
    auto height = box.length!1;

    // Top row
    display.moveTo(box.lowerBound.byComponent);
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

private struct DispBuffer
{
    import std.uni;

    private struct Cell
    {
        // Type.Full is for normal (single-cell) graphemes. HalfLeft means this
        // cell is the left half of a double-celled grapheme; HalfRight means
        // this cell is the right half of a double-celled grapheme.
        enum Type { Full, HalfLeft, HalfRight }
        Type type;
        Grapheme grapheme;
    }

    private static struct Line
    {
        Cell[] contents;
        int dirtyStart, dirtyEnd;
    }

    private Line[] lines;

    Grapheme* opIndex(int x, int y)
    {
        if (y < 0 || y >= lines.length ||
            x < 0 || x >= lines[y].contents.length)
            return null;

        if (lines[y].contents[x].type == Cell.Type.HalfRight)
        {
            assert(x > 0);
            return &lines[y].contents[x-1].grapheme;
        }
        else
            return &lines[y].contents[x].grapheme;
    }

    void opIndexAssign(ref Grapheme g, int x, int y)
    {
        if (y < 0 || x < 0) return;
        if (y >= lines.length)
            lines.length = y+1;

        assert(y < lines.length);
        if (x >= lines[y].contents.length)
            lines[y].contents.length = g[0].isWide() ? x+2 : x+1;

        final switch (lines[y].contents[x].type)
        {
            case Cell.Type.HalfLeft:
                assert(lines[y].contents.length > x+1);
                lines[y].contents[x+1].type = Cell.Type.Full;
                lines[y].contents[x+1].grapheme = Grapheme(" ");
                goto case Cell.Type.Full;

            case Cell.Type.HalfRight:
                assert(x > 0);
                lines[y].contents[x-1].type = Cell.Type.Full;
                lines[y].contents[x-1].grapheme = Grapheme(" ");
                goto case Cell.Type.Full;

            case Cell.Type.Full:
                lines[y].contents[x].grapheme = g;
                if (isWide(g[0]))
                {
                    lines[y].contents[x].type = Cell.Type.HalfLeft;
                    lines[y].contents[x++].type = Cell.Type.HalfRight;
                }
                else
                    lines[y].contents[x].type = Cell.Type.Full;
        }
    }
}

/**
 * A buffered wrapper around a grid-based display.
 */
struct BufferedDisplay(Display)
    if (isGridDisplay!Display)
{
    import std.uni;

    private Display    disp;
    private DispBuffer buf;

    private Vec!(int,2) cursor;

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
        import std.string : format;
        string data = fmt.format(args);

        int x = cursor[0];
        int y = cursor[1];
        foreach (g; data.byGrapheme)
        {
            if (!g[0].isGraphical)
            {
                // TBD: interpret \n, \t, etc..
                continue;
            }

            // Clip against boundaries of underlying display
            if (x < 0 || x >= disp.width || y < 0 || y >= disp.height)
                continue;

            buf[x,y] = g;
        }
    }

    /**
     * Flushes the buffered changes to the underlying display.
     */
    void flush()
    {
        // TBD
    }

    /**
     * Mark entire buffer as dirty so that the next call to .flush will repaint
     * the entire display.
     * Note: This method does NOT immediately update the underlying display;
     * the actual repainting will not happen until the next call to .flush.
     */
    void repaint()
    {
        // TBD
    }
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
    bufDisp.writef("Ж");
}

version(none)
unittest
{
    // Test code for what happens when double-width characters are stricken
    // over.
    import arsd.eventloop;
    import arsd.terminal;

    auto term = Terminal(ConsoleOutputType.cellular);
    term.clear();
    term.moveTo(0,10);
    term.writef("%s", "廳");
    term.moveTo(0,11);
    term.writef("%s", "廳");

    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    addListener((InputEvent event) {
        if (event.type != InputEvent.Type.CharacterEvent) return;
        auto ev = event.get!(InputEvent.Type.CharacterEvent);
        switch (ev.character)
        {
            case 'q':
                arsd.eventloop.exit();
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
    });

    term.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
