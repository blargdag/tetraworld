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

struct Rectangle
{
    int x, y, width, height;
}

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
                    default:
                        break;
                }
            }
            break;

        default:
            break;
    }
}

void drawBox(T)(ref T display, Rectangle box)
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
    foreach (y; 1 .. box.height-1)
    {
        display.moveTo(box.x, y);
        display.writef("%s", chain(
            boxChars[Vert].repeat(1),
            dchar(' ').repeat(box.width-2),
            boxChars[Vert].repeat(1)
        ));
    }

    // Bottom rows
    display.moveTo(box.x, box.y);
    display.writef("%s", chain(
        boxChars[LowerLeft].repeat(1),
        boxChars[Horiz].repeat(box.width-2),
        boxChars[LowerRight].repeat(1)
    ));
}

void main()
{
    auto term = Terminal(ConsoleOutputType.cellular);
    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    term.clear();
    drawBox(term, Rectangle(0, 0, term.width, term.height));

    addListener(&handleGlobalEvent);

    term.flush();
    loop();
}

// vim:set ai sw=4 ts=4 et:
