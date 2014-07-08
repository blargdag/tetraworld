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
 * Map representation.
 */
struct Map
{
    enum opDollar(int n) = 7;
    dchar opIndex(int w, int x, int y, int z)
    {
        import vec : vec;
        if (vec(w,x,y,z) == vec(3,3,3,3)) return '@';
        if (w < 2 || w >= 5 || x < 2 || x >= 5 ||
            y < 2 || y >= 5 || z < 2 || z >= 5)
        {
            return '/';
        }
        return '.';
    }
}
static assert(is4DArray!Map && is(ElementType!Map == dchar));

/**
 * Viewport representation.
 */
struct MapView
{
    Map map;
    SubMap!Map view;

    this(Map _map)
    {
        map = _map;
    }
}

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
    auto map = Map();
    auto vismap = map.submap(vec(1,1,1,2), vec(5,5,5,5));
    auto maprect = screenRect.centerRect(vismap.renderSize.expand);
    auto mapview = subdisplay(&term, maprect);
    renderMap(mapview, vismap);

    drawBox(&term, Rectangle(maprect.x-1, maprect.y-1,
                             maprect.width+2, maprect.height+2));

    addListener(&handleGlobalEvent);

    term.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
