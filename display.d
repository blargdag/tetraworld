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
                        is(typeof(T.init.moveTo(0,0))) &&
                        is(typeof(T.init.writef("%s", "")));

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

private struct DispBuffer
{
    import std.uni;

    struct Cell
    {
        // Type.Full is for normal (single-cell) graphemes. HalfLeft means this
        // cell is the left half of a double-celled grapheme; HalfRight means
        // this cell is the right half of a double-celled grapheme.
        enum Type : ubyte { Full, HalfLeft, HalfRight }

        Type type;
        bool dirty;
        Grapheme grapheme;

        version(unittest)
        void toString(scope void delegate(const(char)[]) sink)
        {
            import std.algorithm : copy;
            copy(grapheme[], sink);
        }
    }

    static struct Line
    {
        Cell[] contents;
        bool dirty;

        /**
         * Returns: Range of chars in this line.
         */
        auto byChar()
        {
            import std.array : array;
            import std.algorithm : filter, map, joiner;

            return contents.filter!((ref c) => c.type != Cell.Type.HalfRight)
                           .map!((ref c) => (c == c.init) ? spaceGrapheme[]
                                                          : c.grapheme[])
                           .joiner;
        }
    }

    private Line[] lines;

    /**
     * Lookup a grapheme in the buffer.
     */
    Grapheme opIndex(int x, int y)
    {
        if (y < 0 || y >= lines.length ||
            x < 0 || x >= lines[y].contents.length)
        {
            // Unassigned areas default to empty space
            return spaceGrapheme;
        }

        if (lines[y].contents[x].type == Cell.Type.HalfRight)
        {
            assert(x > 0);
            return lines[y].contents[x-1].grapheme;
        }
        else
            return lines[y].contents[x].grapheme;
    }

    /**
     * Write a single grapheme into the buffer.
     */
    void opIndexAssign(ref Grapheme g, int x, int y)
    in { assert(isGraphical(g[0])); }
    body
    {
        if (y < 0 || x < 0) return;
        if (y >= lines.length)
            lines.length = y+1;

        assert(y < lines.length);
        if (x >= lines[y].contents.length)
            lines[y].contents.length = g[0].isWide() ? x+2 : x+1;

        void stomp(int x, int y)
        {
            assert(y >= 0 && y < lines.length &&
                   x >= 0 && x < lines[y].contents.length);

            final switch (lines[y].contents[x].type)
            {
                case Cell.Type.HalfLeft:
                    assert(lines[y].contents.length > x+1);
                    lines[y].contents[x+1].type = Cell.Type.Full;
                    lines[y].contents[x+1].grapheme = spaceGrapheme;
                    return;

                case Cell.Type.HalfRight:
                    assert(x > 0);
                    lines[y].contents[x-1].type = Cell.Type.Full;
                    lines[y].contents[x-1].grapheme = spaceGrapheme;
                    return;

                case Cell.Type.Full:
                    // No need to do anything here; the subsequent write will
                    // overwrite this cell.
                    return;
            }
        }

        auto contents = lines[y].contents;
        if (contents[x].grapheme == g &&
            contents[x].type != Cell.Type.HalfRight)
        {
            // Written character identical to what's in buffer; nothing to do.
            return;
        }

        lines[y].dirty = true;
        contents[x].dirty = true;

        stomp(x, y);
        contents[x].grapheme = g;

        if (g[0].isWide())
        {
            stomp(x+1, y);
            contents[x].type = Cell.Type.HalfLeft;
            contents[x+1].grapheme = Grapheme.init;
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
                    lines[y].contents[x].grapheme[].copy(sink);
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
              .filter!(a => a[1].dirty);
    }
}

version(unittest)
private void dump(DispBuffer buf)
{
    import std.stdio;
    foreach (i, line; buf.lines)
    {
        writefln("%2d: >%s<", i, line.byChar());
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

            buf[x,y] = g;

            x += g[0].isWide() ? 2 : 1;
        }
    }

    /**
     * Flushes the buffered changes to the underlying display.
     */
    void flush()
    {
        foreach (e; buf.byDirtyLines)
        {
            // For now, just repaint the entire line
            auto linenum = e[0];
            auto line = e[1];

            assert(line.dirty);
            assert(linenum <= int.max);
            disp.moveTo(0, cast(int)linenum);
            disp.writef("%s", line.byChar());
            line.dirty = false;
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
        foreach (e; buf.lines)
        {
            e.dirty = true;
        }
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
    bufDisp.writef("Живу\n尓是");

    import std.algorithm : equal;
    assert(bufDisp.buf[0,0][].equal("Ж"));
    assert(bufDisp.buf[1,0][].equal("и"));
    assert(bufDisp.buf[2,0][].equal("в"));
    assert(bufDisp.buf[3,0][].equal("у"));
    assert(bufDisp.buf[4,0][].equal(" "));
    assert(bufDisp.buf[0,1][].equal("尓"));
    assert(bufDisp.buf[1,1][].equal("尓"));
    assert(bufDisp.buf[2,1][].equal("是"));
    assert(bufDisp.buf[3,1][].equal("是"));

    bufDisp.moveTo(1,1);
    bufDisp.writef("大");
    assert(bufDisp.buf[0,1][].equal(" "));
    assert(bufDisp.buf[1,1][].equal("大"));
    assert(bufDisp.buf[2,1][].equal("大"));
    assert(bufDisp.buf[3,1][].equal(" "));

    bufDisp.moveTo(3,0);
    bufDisp.writef("и");
    assert(bufDisp.buf[3,0][].equal("и"));

    import std.array : appender;
    import std.format : formattedWrite;
    auto app = appender!string();
    app.formattedWrite("%s", bufDisp.buf);
    assert(app.data == "Живи\n 大 \n");

    // Test byDirtyLines() and Line.byChar().
    import std.algorithm : equal;
    import std.typecons : tuple;
    auto dirtyLines = bufDisp.buf.byDirtyLines;
    auto expectedLines = [
        tuple(0, "Живи"),
        tuple(1, " 大 ")
    ];
    assert(equal!((a,b) => a[0]==b[0] && equal(a[1].byChar(), b[1]))
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
        Tuple!(int,int,string) expected[];

        void moveTo(int x, int y) { cursor = vec(x,y); }
        void writef(A...)(string fmt, A args)
        {
            auto str = format(fmt, args);

            assert(!expected.empty);
            assert(cursor == vec(expected[0][0], expected[0][1]),
                   "Expecting cursor at (%d,%d), actual at (%d,%d)"
                   .format(expected[0][0], expected[0][1],
                           cursor.byComponent));
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
    bufDisp.writef("尓是");

    bufDisp.disp.expected = [
        tuple(0, 1, " Разцветал"),
        tuple(0, 3, " 尓是大人"),
    ];
    bufDisp.buf.dump();
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    // Test overwriting of existing content.
    bufDisp.moveTo(1,3);
    bufDisp.writef("他");
    bufDisp.disp.expected = [
        tuple(0, 3, " 他是大人"),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    // Test stomping of wide characters
    bufDisp.moveTo(0,3);
    bufDisp.writef("他");
    bufDisp.disp.expected = [
        tuple(0, 3, "他 是大人"),
    ];
    bufDisp.flush();
    assert(bufDisp.disp.expected.empty);
    assert(bufDisp.buf.byDirtyLines.empty);

    bufDisp.moveTo(4,3);
    bufDisp.writef("x");
    bufDisp.disp.expected = [
        tuple(0, 3, "他  x大人"),
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


version(none)
unittest
{
	("龘\n\t龘1\u2060a\u0308Ш ж\u0301\u0325\u200Bи\u200DвI\u0334"~
	 "\0D\u0338\u0321o\u0330\n\tu\u0313\u0338\u0330\n5\u035A\n"~
	 "ΐ\u032E 尓１２３1\u033023")
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

// vim:set ai sw=4 ts=4 et:
