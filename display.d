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

import rect;

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
    Rectangle rect;

    ///
    void moveTo(int x, int y)
    in { assert(x + rect.x < parent.width && y + rect.y < parent.height); }
    body
    {
        parent.moveTo(x + rect.x, y + rect.y);
    }

    ///
    void writef(A...)(string fmt, A args) { parent.writef(fmt, args); }

    ///
    @property auto width() { return rect.width; }

    ///
    @property auto height() { return rect.height; }
}

unittest
{
    import arsd.terminal;
    static assert(isGridDisplay!(SubDisplay!(arsd.terminal.Terminal)));
}

/// Convenience method for constructing a SubDisplay.
auto subdisplay(T)(T display, Rectangle rect)
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
void drawBox(T)(T display, Rectangle box)
    if (isGridDisplay!T)
in { assert(box.width >= 2 && box.height >= 2); }
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

    // Top row
    display.moveTo(box.x, box.y);
    display.writef("%s", chain(
        boxChars[UpperLeft].repeat(1),
        boxChars[Horiz].repeat(box.width-2),
        boxChars[UpperRight].repeat(1)
    ));

    // Middle rows
    foreach (y; 1 .. box.height)
    {
        display.moveTo(box.x, box.y + y);
        display.writef("%s", boxChars[Vert]);
        display.moveTo(box.x + box.width - 1, box.y + y);
        display.writef("%s", boxChars[Vert]);
    }

    // Bottom rows
    display.moveTo(box.x, box.y + box.height - 1);
    display.writef("%s", chain(
        boxChars[LowerLeft].repeat(1),
        boxChars[Horiz].repeat(box.width-2),
        boxChars[LowerRight].repeat(1)
    ));
}

// vim:set ai sw=4 ts=4 et:
