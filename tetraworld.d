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
 * Main program.
 */
void main()
{
    auto term = Terminal(ConsoleOutputType.cellular);
    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    term.clear();
    auto screenRect = Rectangle(0, 0, term.width, term.height);
    auto msgRect = Rectangle(screenRect.x, screenRect.y,
                             screenRect.width, 1);
    auto msgBox = subdisplay(&term, msgRect);

    void message(A...)(string fmt, A args)
    {
        msgBox.moveTo(0,0);
        msgBox.writef(fmt, args);
    }

    message("Welcome to Tetraworld!");

    // Map test
    struct Map
    {
        enum opDollar(int n) = 5;
        dchar opIndex(int w, int x, int y, int z)
        {
            import vec : vec;
            if (vec(w,x,y,z) == vec(2,2,2,2)) return '@';
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
    auto maprect = screenRect.centerRect(map.renderSize.expand);
    auto mapview = subdisplay(&term, maprect);
    renderMap(mapview, map);

    drawBox(&term, Rectangle(maprect.x-1, maprect.y-1,
                             maprect.width+2, maprect.height+2));

    addListener(&handleGlobalEvent);

    term.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
