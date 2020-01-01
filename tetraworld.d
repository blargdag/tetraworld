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

/**
 * Map representation.
 */
struct GameMap
{
    // For initial testing only; this should be replaced with a proper object
    // system.
    private Vec!(int,4) playerPos;

    private MapNode tree;
    private alias R = Region!(int,4);
    private R bounds;

    this(int[4] _dim)
    {
        bounds.min = vec(0, 0, 0, 0);
        bounds.max = _dim;

        tree = genBsp!MapNode(bounds,
            (R r) => r.volume > 24 + uniform(0, 80),
            (R r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                            .pickOne(invalidAxis),
            (R r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
                invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
        );
        genCorridors(tree, bounds);
        resizeRooms(tree, bounds);
        placePlayer(tree, bounds);
    }

    /**
     * Randomly select a map location to place player.
     */
    private void placePlayer(MapNode node, R bounds)
    {
        if (node.isLeaf)
        {
            foreach (i; 0 .. 4)
            {
                assert(node.interior.length(i) >= 3);
                playerPos[i] = uniform(node.interior.min[i] + 1,
                                       node.interior.max[i] - 1);
            }
            return;
        }
        if (uniform(0, 2) == 0)
            placePlayer(node.left, leftRegion(bounds, node.axis, node.pivot));
        else
            placePlayer(node.right, rightRegion(bounds, node.axis,
                                                node.pivot));
    }

    @property int opDollar(int i)() { return bounds.max[i]; }

    dchar opIndex(int[4] pos...)
    {
        import std.math : abs;

        if (vec(pos) == playerPos) return '&';

        // FIXME: should be a more efficient way to do this
        dchar ch = '/';
        foreachFiltRoom(tree, bounds, (R r) => r.contains(vec(pos)),
            (MapNode node, R r) {
                auto rr = node.interior;
                if (iota(4).fold!((b, i) => b && rr.min[i] < pos[i] &&
                                            pos[i] + 1 < rr.max[i])(true))
                {
                    ch = '.';
                    return 1;
                }

                foreach (d; node.doors)
                {
                    if (pos[] == d.pos)
                    {
                        ch = '#';
                        return 1;
                    }
                }

                ch = '/';
                return 1;
            }
        );
        return ch;
    }
}
static assert(is4DArray!GameMap && is(CellType!GameMap == dchar));

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

    // Map test
    auto map = GameMap([ 15, 15, 15, 15 ]);

    auto optVPSize = optimalViewportSize(screenRect.max - vec(0,2));

    auto viewport = ViewPort!GameMap(&map, optVPSize, vec(0,0,0,0));
    viewport.centerOn(map.playerPos);

    auto maprect = screenRect.centeredRegion(renderSize(viewport.curView));
    auto mapview = subdisplay(&disp, maprect);

    //drawBox(&disp, region(maprect.min - vec(1,1),
    //                      maprect.max + vec(1,1)));

    void refresh()
    {
        auto curview = viewport.curView;
        mapview.renderMap(curview);

        disp.hideCursor();
        if (curview.reg.contains(map.playerPos))
        {
            auto cursorPos = renderingCoors(curview,
                                            map.playerPos - viewport.pos);
            if (region(vec(mapview.width, mapview.height)).contains(cursorPos))
            {
                mapview.moveTo(cursorPos[0], cursorPos[1]);
                disp.showCursor();
            }
        }

        disp.flush();
    }

    void movePlayer(Vec!(int,4) displacement)
    {
        auto newPos = map.playerPos + displacement;
        if (map[newPos] == '/')
            return; // movement blocked
        map.playerPos = newPos;

        viewport.centerOn(map.playerPos);
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
    disp.flush();
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
