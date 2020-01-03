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
module tetraworld;

import arsd.terminal;

import std.algorithm;
import std.random;
import std.range;

import bsp;
import display;
import map;
import vector;
import world;

/**
 * Viewport representation.
 */
struct ViewPort(Map)
    if (is4DArray!Map)
{
    World       w;
    Vec!(int,4) dim;
    Vec!(int,4) pos;

    /// Constructor.
    this(World _w, Vec!(int,4) _dim, Vec!(int,4) _pos)
    {
        w = _w;
        dim = _dim;
        pos = _pos;
    }

    /**
     * Returns a 4D array of dchar representing the current view of the map
     * given the current viewport settings.
     */
    @property auto curView()
    {
        return w.map
            .fmap!((pos, tile) {
                // Objects replace floor tiles
                auto p = pos in w.objects;
                if (p !is null)
                    tile = *p;

                // Highlight tiles along axial directions from player.
                if (iota(4).fold!((c,i) => c + !!(pos[i] == w.playerPos[i]))(0)
                    >= 3)
                {
                    tile.fg = cast(Color)(Color.blue | Bright);
                }
                return tile;
            })
            .submap(region(pos, pos + dim));
    }

    /**
     * Translates the viewport by the given displacement.
     */
    void move(Vec!(int,4) displacement)
    {
        pos += displacement;
    }

    /**
     * Translate the view so that the given point lies at the center of the
     * viewing volume.
     */
    void centerOn(Vec!(int,4) pt)
    {
        pos = pt - dim/2;
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
    bool wantQuit;

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
                            wantQuit = true;
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

void play()
{
    import vector;
    auto term = Terminal(ConsoleOutputType.cellular);
    auto input = RealTimeConsoleInput(&term, ConsoleInputFlags.raw);

    term.clear();
    auto disp = bufferedDisplay(&term);
    auto screenRect = region(vec(disp.width, disp.height));
    auto msgRect = region(screenRect.min,
                          vec(screenRect.max[0], 1));
    auto msgBox = subdisplay(&disp, msgRect);

    void message(A...)(string fmt, A args)
    {
        msgBox.moveTo(0,0);
        msgBox.writef(fmt, args);
    }

    message("Welcome to Tetraworld!");

    World world = newGame([ 13, 13, 13, 13 ]);

    auto optVPSize = optimalViewportSize(screenRect.max - vec(0,2));

    auto viewport = ViewPort!GameMap(world, optVPSize, vec(0,0,0,0));
    viewport.centerOn(world.playerPos);

    auto maprect = screenRect.centeredRegion(renderSize(viewport.curView));
    auto mapview = subdisplay(&disp, maprect);
    static assert(hasColor!(typeof(mapview)));

    //drawBox(&disp, region(maprect.min - vec(1,1),
    //                      maprect.max + vec(1,1)));

    void refresh()
    {
        auto curview = viewport.curView;
        mapview.renderMap(curview);

        disp.hideCursor();
        if (curview.reg.contains(world.playerPos))
        {
            auto cursorPos = renderingCoors(curview,
                                            world.playerPos - viewport.pos);
            if (region(vec(mapview.width, mapview.height)).contains(cursorPos))
            {
                mapview.moveTo(cursorPos[0], cursorPos[1]);
                disp.showCursor();
            }
        }

        disp.flush();
    }

    InputEventHandler inputHandler;

    void movePlayer(Vec!(int,4) displacement)
    {
        auto newPos = world.playerPos + displacement;
        if (world.map[newPos].ch == '/')
            return; // movement blocked

        if (world.map[newPos].ch == '@')
        {
            //message("You see the exit portal here.");
            inputHandler.wantQuit = true;
        }

        // FIXME: this needs to be done in a consistent way
        auto pl = world.objects[world.playerPos];
        world.objects.remove(world.playerPos);
        world.playerPos = newPos;
        world.objects[world.playerPos] = pl;

        viewport.centerOn(world.playerPos);
        refresh();
    }

    void moveView(Vec!(int,4) displacement)
    {
        viewport.move(displacement);
        refresh();
    }

    inputHandler.bind('i', (dchar) { movePlayer(vec(-1,0,0,0)); });
    inputHandler.bind('m', (dchar) { movePlayer(vec(1,0,0,0)); });
    inputHandler.bind('h', (dchar) { movePlayer(vec(0,-1,0,0)); });
    inputHandler.bind('l', (dchar) { movePlayer(vec(0,1,0,0)); });
    inputHandler.bind('o', (dchar) { movePlayer(vec(0,0,-1,0)); });
    inputHandler.bind('n', (dchar) { movePlayer(vec(0,0,1,0)); });
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

    refresh();
    while (!inputHandler.wantQuit)
    {
        inputHandler.handleGlobalEvent(input.nextEvent());
    }

    term.clear();
}

/**
 * Main program.
 */
void main()
{
    play();
}

// vim:set ai sw=4 ts=4 et:
