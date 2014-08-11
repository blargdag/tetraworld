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
import vector;

/**
 * Map representation.
 */
struct GameMap
{
    // For initial testing only; this should be replaced with a proper object
    // system.
    Vec!(int,4) playerPos;

    Vec!(int,4) dim = vec(7,7,7,7);

    @property int opDollar(int i)() { return dim[i]; }

    dchar opIndex(int w, int x, int y, int z)
    {
        if (vec(w,y,x,z) == playerPos) return '&';
        if (vec(w,x,y,z) == vec(3,3,3,3)) return '@';
        if (vec(w,x,y,z) in region(vec(2,2,2,2), vec(5,5,5,5))) return '.';
        return '/';
    }
}
static assert(is4DArray!GameMap && is(ElementType!GameMap == dchar));

/**
 * Viewport representation.
 */
struct ViewPort(Map)
    if (is4DArray!Map)
{
    Map*        map;
    Vec!(int,4) dim;
    Vec!(int,4) pos;

    /// Constructor.
    this(Map* _map, Vec!(int,4) _dim, Vec!(int,4) _pos)
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
        return submap(*map, region(pos, pos + dim));
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
    auto disp = bufferedDisplay(&term);
    auto screenRect = region(vec(disp.width, disp.height));
    auto msgRect = region(screenRect.lowerBound,
                          vec(screenRect.upperBound[0], 1));
    auto msgBox = subdisplay(&disp, msgRect);

    void message(A...)(string fmt, A args)
    {
        msgBox.moveTo(0,0);
        msgBox.writef(fmt, args);
    }

    message("Welcome to Tetraworld!");

    // Map test
    auto map = GameMap();
    map.playerPos = vec(3,3,3,2);

    auto optVPSize = optimalViewportSize(
        (screenRect.upperBound - vec(0,2)).byComponent);
    auto viewport = ViewPort!GameMap(&map, optVPSize,
                                     map.playerPos - vec(2,2,2,2));
    auto maprect = screenRect.centeredRegion(renderSize(viewport.curView));
    auto mapview = subdisplay(&disp, maprect);

    mapview.renderMap(viewport.curView);

    //drawBox(&disp, region(maprect.lowerBound - vec(1,1),
    //                      maprect.upperBound + vec(1,1)));

    void refresh()
    {
        mapview.renderMap(viewport.curView);
        disp.flush();
    }

    void movePlayer(Vec!(int,4) displacement)
    {
        auto newPos = map.playerPos + displacement;
        if (map[newPos.byComponent] == '/')
            return; // movement blocked
        map.playerPos = newPos;
        refresh();
    }

    void moveView(Vec!(int,4) displacement)
    {
        viewport.move(displacement);
        refresh();
    }

    InputEventHandler inputHandler;
    inputHandler.bind('i', (dchar) { movePlayer(vec(-1,0,0,0)); });
    inputHandler.bind('m', (dchar) { movePlayer(vec(1,0,0,0)); });
    inputHandler.bind('o', (dchar) { movePlayer(vec(0,-1,0,0)); });
    inputHandler.bind('n', (dchar) { movePlayer(vec(0,1,0,0)); });
    inputHandler.bind('h', (dchar) { movePlayer(vec(0,0,-1,0)); });
    inputHandler.bind('l', (dchar) { movePlayer(vec(0,0,1,0)); });
    inputHandler.bind('j', (dchar) { movePlayer(vec(0,0,0,-1)); });
    inputHandler.bind('k', (dchar) { movePlayer(vec(0,0,0,1)); });
    inputHandler.bind('I', (dchar) { moveView(vec(-1,0,0,0)); });
    inputHandler.bind('M', (dchar) { moveView(vec(1,0,0,0)); });
    inputHandler.bind('H', (dchar) { moveView(vec(0,-1,0,0)); });
    inputHandler.bind('L', (dchar) { moveView(vec(0,1,0,0)); });
    inputHandler.bind('O', (dchar) { moveView(vec(0,0,-1,0)); });
    inputHandler.bind('N', (dchar) { moveView(vec(0,0,1,0)); });
    inputHandler.bind('J', (dchar) { moveView(vec(0,0,0,-1)); });
    inputHandler.bind('K', (dchar) { moveView(vec(0,0,0,1)); });
    addListener(&inputHandler.handleGlobalEvent);

    disp.flush();
    loop();

    term.clear();
}

// vim:set ai sw=4 ts=4 et:
