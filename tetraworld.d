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
import std.stdio;

import action;
import bsp;
import components;
import display;
import gamemap;
import loadsave;
import store;
import store_traits;
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
            .fmap!((pos, floor) => w.store.getAllBy!Pos(Pos(pos))
                .map!(id => w.store.get!Tiled(id))
                .filter!(tilep => tilep !is null)
                .map!(tilep => *tilep)
                .maxElement!(tile => tile.stackOrder)(Tiled(floor, -1))
                .tile)
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

    /**
     * Returns: true if this viewport contains the given 4D location.
     */
    bool contains(Vec!(int,4) pt)
    {
        return region(pos, pos+dim).contains(pt);
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
                    if (auto handler = ev.character in bindings)
                    {
                        // Invoke user-defined action.
                        (*handler)(ev.character);
                    }
                }
                break;

            default:
                break;
        }
    }
}

enum saveFileName = ".tetra.save";

void saveGame(World world, Thing* player)
{
    auto sf = File(saveFileName, "w").lockingTextWriter.saveFile;
    sf.put("player", player.id);
    sf.put("world", world);
}

World loadGame(out Thing* player)
{
    auto lf = File(saveFileName, "r").byLine.loadFile;
    ThingId playerId = lf.parse!ThingId("player");
    auto world = lf.parse!World("world");

    player = world.store.getObj(playerId);
    if (player is null)
        throw new Exception("Save file is corrupt!");

    // Permadeath. :-D
    import std.file : remove;
    remove(saveFileName);

    return world;
}

string play(World world, Thing* player)
{
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
        msgBox.clearToEol();
    }

    message("Welcome to Tetraworld!");

    Vec!(int,4) playerPos() { return world.store.get!Pos(player.id).coors; }

    auto optVPSize = optimalViewportSize(screenRect.max - vec(0,2));

    auto viewport = ViewPort!GameMap(world, optVPSize, vec(0,0,0,0));
    viewport.centerOn(playerPos);

    auto maprect = screenRect.centeredRegion(renderSize(viewport.curView));
    auto mapview = subdisplay(&disp, maprect);
    static assert(hasColor!(typeof(mapview)));

    auto statusrect = region(vec(screenRect.min[0], screenRect.max[1]-1),
                             screenRect.max);
    auto statusview = subdisplay(&disp, statusrect);

    //drawBox(&disp, region(maprect.min - vec(1,1),
    //                      maprect.max + vec(1,1)));

    void refreshMap()
    {
        auto curview = viewport.curView.fmap!((pos, tile) {
            // Highlight tiles along axial directions from player.
            auto plpos = playerPos - viewport.pos;
            if (iota(4).fold!((c,i) => c + !!(pos[i] == plpos[i]))(0) >= 3)
            {
                if (tile.fg == Color.DEFAULT)
                    tile.fg = Color.blue;
                tile.fg |= Bright;
            }
            return tile;
        });
        mapview.renderMap(curview);

        disp.hideCursor();
        if (viewport.contains(playerPos))
        {
            auto cursorPos = renderingCoors(curview,
                                            playerPos - viewport.pos);
            if (region(vec(mapview.width, mapview.height)).contains(cursorPos))
            {
                mapview.moveTo(cursorPos[0], cursorPos[1]);
                disp.showCursor();
            }
        }

        disp.flush();
    }

    void refreshStatus()
    {
        // TBD: this should be done elsewhere
        auto inv = world.store.get!Inventory(player.id);
        auto ngold = inv.contents
                        .map!(id => world.store.get!Tiled(id))
                        .filter!(tp => tp !is null && tp.tile.ch == '$')
                        .count;
        auto maxgold = world.store.getAll!Tiled
                        .map!(id => world.store.get!Tiled(id))
                        .filter!(tp => tp.tile.ch == '$')
                        .count;

        statusview.moveTo(0, 0);
        statusview.writef("$: %d/%d", ngold, maxgold);
        statusview.clearToEol();
    }


    void refresh()
    {
        refreshStatus();
        refreshMap(); // should be last
    }

    InputEventHandler inputHandler;

    ulong lastEventId = world.events.seq;
    void doAction(alias act, Args...)(Args args)
    {
        ActionResult res = act(args);
        if (!res)
        {
            message(res.failureMsg);
        }
        else
        {
            foreach (ev; world.events.get(lastEventId))
            {
                message(ev.msg);
            }
            lastEventId = world.events.seq;
        }
        refresh();
    }

    void movePlayer(Vec!(int,4) displacement)
    {
        doAction!move(world, player, displacement);

        // TBD: this is a hack that should be replaced by a System, probably.
        {
            if (!world.store.getAllBy!Pos(Pos(playerPos))
                            .map!(id => world.store.get!Tiled(id))
                            .filter!(tp => tp !is null && tp.tile.ch == '@')
                            .empty)
            {
                message("You see the exit portal here.");
            }
        }

        viewport.centerOn(playerPos);
        refresh();
    }

    void moveView(Vec!(int,4) displacement)
    {
        viewport.move(displacement);
        refresh();
    }

    void applyFloorObj()
    {
        doAction!applyFloor(world, player);
    }

    bool quit;

    // FIXME: this is a hack. Replace with something better!
    string quitMsg;

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
    inputHandler.bind(' ', (dchar) { applyFloorObj(); });
    inputHandler.bind('q', (dchar) {
        saveGame(world, player);
        quit = true;
        quitMsg = "Be seeing you!";
    });
    inputHandler.bind('Q', (dchar) {
        // TBD: confirm abandon game
        quit = true;
        quitMsg = "Bye!";
    });

    refresh();
    while (!quit)
    {
        inputHandler.handleGlobalEvent(input.nextEvent());

        // FIXME: this is a hack. What's the better way of doing this??
        if (world.store.get!UsePortal(player.id) !is null)
        {
            quit = true;
            quitMsg = "You have won!";
        }
    }

    term.clear();

    return quitMsg;
}

/**
 * Main program.
 */
void main()
{
    World  world;
    Thing* player;

    import std.file : exists;
    if (saveFileName.exists)
    {
        world = loadGame(player);
    }
    else
    {
        //world = newGame([ 13, 13, 13, 13 ]);
        world = newGame([ 8, 8, 8, 8 ]);
        player = world.store.createObj(
            Pos(world.map.randomLocation()),
            Tiled(ColorTile('&', Color.DEFAULT, Color.DEFAULT), 1),
            Name("You"),
            Inventory()
        );
    }

    auto quitMsg = play(world, player);
    writeln(quitMsg);
}

// vim:set ai sw=4 ts=4 et:
