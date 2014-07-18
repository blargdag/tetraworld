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
struct ViewPort
{
    Map         map;
    Vec!(int,4) dim;
    Vec!(int,4) pos;

    /// Constructor.
    this(Map _map, Vec!(int,4) _dim, Vec!(int,4) _pos)
    {
        map = _map;
        dim = _dim;
        pos = _pos;
    }

    /**
     * Returns a 4D array of dchar representing the current view of the map
     * given the current viewport settings.
     */
    @property auto curView()
    {
        return submap(map, pos, dim);
    }

    /**
     * Translates the viewport by the given displacement.
     */
    void move(Vec!(int,4) displacement)
    {
        pos += displacement;
    }
}

/**
 * Input event handler.
 *
 * Manages key bindings. In the future, will also manage stack of key handlers
 * for implementing modal dialogues.
 */
struct InputEventHandler
{
    void delegate(dchar ch)[dchar] bindings;

    /**
     * Binds a particular key to an action.
     */
    void bind(dchar key, void delegate(dchar) action)
    {
        bindings[key] = action;
    }

    /**
     * Global input event handler to be hooked up to main event loop.
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
                            if (auto handler = ev.character in bindings)
                            {
                                // Invoke user-defined action.
                                (*handler)(ev.character);
                            }
                            break;
                    }
                }
                break;

            default:
                break;
        }
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
    auto viewport = ViewPort(map, vec(5,5,5,5), vec(2,2,2,2));
    auto maprect = screenRect.centerRect(viewport.curView.renderSize.expand);
    auto mapview = subdisplay(&term, maprect);
    mapview.renderMap(viewport.curView);

    drawBox(&term, Rectangle(maprect.x-1, maprect.y-1,
                             maprect.width+2, maprect.height+2));

    void refresh()
    {
        mapview.renderMap(viewport.curView);
    }

    void moveView(Vec!(int,4) displacement)
    {
        viewport.move(displacement);
        refresh();
    }

    InputEventHandler inputHandler;
    inputHandler.bind('I', (dchar) { moveView(vec(-1,0,0,0)); });
    inputHandler.bind('M', (dchar) { moveView(vec(1,0,0,0)); });
    inputHandler.bind('H', (dchar) { moveView(vec(0,-1,0,0)); });
    inputHandler.bind('L', (dchar) { moveView(vec(0,1,0,0)); });
    inputHandler.bind('O', (dchar) { moveView(vec(0,0,-1,0)); });
    inputHandler.bind('N', (dchar) { moveView(vec(0,0,1,0)); });
    inputHandler.bind('J', (dchar) { moveView(vec(0,0,0,-1)); });
    inputHandler.bind('K', (dchar) { moveView(vec(0,0,0,1)); });
    addListener(&inputHandler.handleGlobalEvent);

    term.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
