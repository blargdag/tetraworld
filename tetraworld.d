/**
 * Yet another 4D world.
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

import arsd.eventloop;
import arsd.terminal;

import display;
import map;
import rect;

/**
 * Global input event handler.
 */
void handleGlobalEvent(InputEvent event)
{
    switch (event.type)
    {
        case InputEvent.Type.CharacterEvent:
            auto ev = event.get!(InputEvent.Type.CharacterEvent);
            if (ev.eventType == CharacterEvent.Type.Pressed)
            {
                switch (ev.character)
                {
                    case 'q':
                        arsd.eventloop.exit();
                        break;
                    default:
                        break;
                }
            }
            break;

        default:
            break;
    }
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
        display.writef("%s", chain(
            boxChars[Vert].repeat(1),
            dchar(' ').repeat(box.width-2),
            boxChars[Vert].repeat(1)
        ));
    }

    // Bottom rows
    display.moveTo(box.x, box.y + box.height - 1);
    display.writef("%s", chain(
        boxChars[LowerLeft].repeat(1),
        boxChars[Horiz].repeat(box.width-2),
        boxChars[LowerRight].repeat(1)
    ));
}

/**
 * Main program.
 */
void main()
{
    auto term = Terminal(ConsoleOutputType.cellular);
    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    term.clear();
    auto screenRect = Rectangle(0, 0, term.width, term.height);

    version(none)
    {
        auto msg = "Welcome to Tetraworld!";
        auto msgRect = screenRect.centerRect(cast(int)(msg.length + 4), 3);
        drawBox(&term, msgRect);
        term.moveTo(msgRect.x + 2, msgRect.y + 1);
        term.writef(msg);
    }

    // Map test
    struct Map
    {
        enum opDollar(int n) = 5;
        dchar opIndex(int w, int x, int y, int z)
        {
            if (w==2 && x==2 && y==2 && z==2) return '@';
            if (w*x*y*z == 0 ||
                w==4 || x==4 || y==4 || z==4)
            {
                return '/';
            }
            return '.';
        }
    }
    static assert(is(typeof(Map.init[0,0,0,0])));
    static assert(is(typeof(Map.init.opDollar!0) : size_t));
    static assert(is4DArray!(Map,dchar));

    auto map = Map();
    auto mapview = subdisplay(&term,
                              screenRect.centerRect(map.renderSize.expand));
    renderMap(mapview, map);

    addListener(&handleGlobalEvent);

    term.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
