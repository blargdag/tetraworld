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

import core.thread : Fiber;
import std.algorithm;
import std.random;
import std.range;
import std.stdio;

import arsd.terminal;

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
        TileId getDisplayedTile(Vec!(int,4) pos, ThingId terrainId)
        {
            auto r = w.store.getAllBy!Pos(Pos(pos))
                            .map!(id => w.store.get!Tiled(id))
                            .filter!(tilep => tilep !is null)
                            .map!(tilep => *tilep);
            if (!r.empty)
                return r.maxElement!(tile => tile.stackOrder)
                        .tileId;

            import terrain : emptySpace;
            if (terrainId == emptySpace.id)
            {
                // Empty space: check if it's above solid ground. If so, render
                // the top tile of the ground instead.
                import terrain : ladder;
                auto floorId = w.map[pos + vec(1,0,0,0)];
                if (floorId == ladder.id)
                    return TileId.ladderTop;
                if (w.store.get!BlocksMovement(floorId) !is null)
                    return w.store.get!Tiled(floorId).tileId;
            }
            else if (w.store.get!BlocksMovement(terrainId) !is null)
            {
                // It's impassable terrain; render as wall when not seen from
                // top.
                return TileId.wall;
            }

            return w.store.get!Tiled(terrainId).tileId;
        }

        return w.map
                .fmap!((pos, terrainId) => getDisplayedTile(pos, terrainId))
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
 * A UI interaction mode. Basically, a set of event handlers and render hooks.
 */
struct Mode
{
    void delegate() render;
    void delegate(dchar) onCharEvent;
}

/**
 * Input dispatcher.
 */
struct InputDispatcher
{
    private Mode[] modestack;

    private void setup()()
    {
        if (modestack.length == 0)
            modestack.length = 1;
    }

    /**
     * Returns: The current mode (at the top of the stack).
     */
    Mode top()
    {
        setup();
        return modestack[$-1];
    }

    /**
     * Push a new mode onto the mode stack.
     */
    void push(Mode mode)
    {
        modestack.assumeSafeAppend();
        modestack ~= mode;

        if (mode.render !is null)
            mode.render();
    }

    /**
     * Pop the current mode off the stack and revert to the previous mode.
     */
    void pop()
    {
        modestack.length--;
    }

    void handleEvent(InputEvent event)
    {
        switch (event.type)
        {
            case InputEvent.Type.KeyboardEvent:
                auto ev = event.get!(InputEvent.Type.KeyboardEvent);
                assert(top.onCharEvent !is null);
                top.onCharEvent(ev.which);
                break;

            default:
                // TBD
                return;
        }

        if (top.render !is null)
            top.render();
    }
}

enum PlayerAction
{
    none, up, down, left, right, front, back, ana, kata, apply,
}

interface GameUi
{
    void message(string msg);

    final void message(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        message(format(fmt.args));
    }

    PlayerAction getPlayerAction();

    void recenterView(Vec!(int,4) center);

    void quitWithMsg(string msg);
    final void quitWithMsg(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        quitWithMsg(format(fmt, args));
    }

    // UGLY STUFF PLZ FIX KTHX
    void notifyPlayerChange();
}

enum saveFileName = ".tetra.save";

class Game
{
    private GameUi ui;
    /*private*/ World w; // FIXME
    private Thing* player;
    private bool quit;

    Vec!(int,4) playerPos()
    {
        return w.store.get!Pos(player.id).coors;
    }

    auto numGold()
    {
        auto inv = w.store.get!Inventory(player.id);
        return inv.contents
                  .map!(id => w.store.get!Tiled(id))
                  .filter!(tp => tp !is null && tp.tileId == TileId.gold)
                  .count;
    }

    auto maxGold()
    {
        return w.store.getAll!Tiled
                      .map!(id => w.store.get!Tiled(id))
                      .filter!(tp => tp.tileId == TileId.gold)
                      .count;
    }

    // FIXME
    ulong lastEventId;
    private void doAction(alias act, Args...)(Args args)
    {
        ActionResult res = act(args);
        if (!res)
        {
            ui.message(res.failureMsg);
        }
//        else
//        {
//            foreach (ev; w.events.get(lastEventId))
//            {
//                ui.message(ev.msg);
//            }
//            lastEventId = w.events.seq;
//        }
    }

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("world", w);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.w = lf.parse!World("world");

        game.player = game.w.store.getObj(playerId);
        if (game.player is null)
            throw new Exception("Save file is corrupt!");

        // Permadeath. :-D
        import std.file : remove;
        remove(saveFileName);

        return game;
    }

    static Game newGame()
    {
        auto g = new Game;
        g.w = genNewGame([ 12, 12, 12, 12 ]);
        //game.w = newGame([ 9, 9, 9, 9 ]);
        g.player = g.w.store.createObj(
            Pos(g.w.map.randomLocation()),
            Tiled(TileId.player, 1),
            Name("You"),
            Inventory()
        );
        return g;
    }

    private void movePlayer(int[4] displacement)
    {
        doAction!move(w, player, vec(displacement));

        // TBD: this is a hack that should be replaced by a System, probably.
        {
            if (!w.store.getAllBy!Pos(Pos(playerPos))
                        .map!(id => w.store.get!Tiled(id))
                        .filter!(tp => tp !is null &&
                                 tp.tileId == TileId.portal)
                        .empty)
            {
                ui.message("You see the exit portal here.");
            }
        }

        ui.recenterView(playerPos);
    }

    private void applyFloorObj()
    {
        doAction!applyFloor(w, player);
    }

    private void portalSystem()
    {
        if (w.store.get!UsePortal(player.id) !is null)
        {
            w.store.remove!UsePortal(player);

            auto ngold = numGold();
            auto maxgold = maxGold();

            if (ngold < maxgold)
            {
                ui.message("The exit portal is here, but you haven't found "~
                           "all the gold yet.");
            }
            else
            {
                quit = true;
                import std.format : format;
                ui.quitWithMsg("Congratulations! You collected %d out of %d "~
                               "gold.", ngold, maxgold);
            }
        }
    }

    private void gravitySystem()
    {
        bool somethingFell;
        do
        {
            somethingFell = false;
            foreach (t; w.store.getAll!Pos()
                               .map!(id => w.store.getObj(id)))
            {
                auto pos = *w.store.get!Pos(t.id);
                auto floorPos = pos + vec(1,0,0,0);

                // Gravity pulls downwards as long as there is no support
                // underneath.
                if (w.store.get!SupportsWeight(w.map[floorPos]) is null)
                {
                    w.notify.fall(pos, t.id, Pos(floorPos));
                    w.store.remove!Pos(t);
                    w.store.add!Pos(t, Pos(floorPos));
                    somethingFell = true;
                }
            }
        } while (somethingFell);
    }

    void setupEventWatchers()
    {
        w.notify.climbLedge = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
                ui.notifyPlayerChange(); // FIXME: for now only
        };
        w.notify.fall = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
            {
                ui.notifyPlayerChange(); // FIXME: for now only
                ui.message("You fall!");
            }
        };
        w.notify.pickup = (Pos pos, ThingId subj, ThingId obj)
        {
            if (subj == player.id)
            {
                auto name = w.store.get!Name(obj);
                if (name !is null)
                    ui.message("You pick up the " ~ name.name ~ ".");
            }
        };
    }

    void run(GameUi _ui)
    {
        ui = _ui;
        setupEventWatchers();
        while (!quit)
        {
            gravitySystem();

            // handle player input
            final switch (ui.getPlayerAction()) with(PlayerAction)
            {
                case up:    movePlayer([-1,0,0,0]); break;
                case down:  movePlayer([1,0,0,0]);  break;
                case ana:   movePlayer([0,-1,0,0]); break;
                case kata:  movePlayer([0,1,0,0]);  break;
                case back:  movePlayer([0,0,-1,0]); break;
                case front: movePlayer([0,0,1,0]);  break;
                case left:  movePlayer([0,0,0,-1]); break;
                case right: movePlayer([0,0,0,1]);  break;
                case apply: applyFloorObj();        break;
                case none:  assert(0, "Internal error");
            }

            portalSystem();
        }
    }
}

class TextUi : GameUi
{
    import std.traits : ReturnType;

    alias MainDisplay = ReturnType!createDisp;
    alias MsgBox = ReturnType!createMsgBox;
    alias Viewport = ReturnType!createViewport;
    alias MapView = ReturnType!createMapView;
    alias StatusView = ReturnType!createStatusView;

    private Terminal* term;
    private MainDisplay disp;

    private MsgBox      msgBox;
    private Viewport    viewport;
    private MapView     mapview;
    private StatusView  statusview;

    private Game g;
    private Fiber gameFiber;
    private InputDispatcher dispatch;

    private bool quit;
    // FIXME: this is a hack. Replace with something better!
    private string quitMsg;

    private auto createDisp() { return bufferedDisplay(term); }
    private auto createMsgBox(Region!(int,2) msgRect)
    {
        return subdisplay(&disp, msgRect);
    }
    private auto createViewport(Region!(int,2) screenRect)
    {
        auto optVPSize = optimalViewportSize(screenRect.max - vec(0,2));
        return ViewPort!GameMap(g.w, optVPSize, vec(0,0,0,0));
    }
    private auto createMapView(Region!(int,2) screenRect)
    {
        auto maprect = screenRect.centeredRegion(renderSize(viewport.curView));
        return subdisplay(&disp, maprect);
    }
    private auto createStatusView(Region!(int,2) screenRect)
    {
        auto statusrect = region(vec(screenRect.min[0], screenRect.max[1]-1),
                                 screenRect.max);
        return subdisplay(&disp, statusrect);
    }

    void message(string str)
    {
        msgBox.moveTo(0,0);
        msgBox.writef(str);
        msgBox.clearToEol();
    }

    PlayerAction getPlayerAction()
    {
        PlayerAction result;

        PlayerAction[dchar] keymap = [
            'i': PlayerAction.up,
            'm': PlayerAction.down,
            'h': PlayerAction.ana,
            'l': PlayerAction.kata,
            'o': PlayerAction.back,
            'n': PlayerAction.front,
            'j': PlayerAction.left,
            'k': PlayerAction.right,
            ' ': PlayerAction.apply,
        ];

        auto mainMode = Mode(
            {
                refresh();
            },
            (dchar ch) {
                switch (ch)
                {
                    case 'I': moveView(vec(-1,0,0,0));  break;
                    case 'M': moveView(vec(1,0,0,0));   break;
                    case 'H': moveView(vec(0,-1,0,0));  break;
                    case 'L': moveView(vec(0,1,0,0));   break;
                    case 'O': moveView(vec(0,0,-1,0));  break;
                    case 'N': moveView(vec(0,0,1,0));   break;
                    case 'J': moveView(vec(0,0,0,-1));  break;
                    case 'K': moveView(vec(0,0,0,1));   break;
                    case 'q':
                        g.saveGame();
                        quit = true;
                        quitMsg = "Be seeing you!";
                        break;
                    case 'Q':
                        // TBD: confirm abandon game
                        quit = true;
                        quitMsg = "Bye!";
                        break;
                    case '\x0c':        // ^L
                        disp.repaint(); // force repaint of entire screen
                        break;
                    default:
                        if (auto cmd = ch in keymap)
                        {
                            result = *cmd;
                            dispatch.pop();
                            gameFiber.call();
                        }
                        else
                        {
                            import std.format : format;
                            import std.uni : isGraphical;

                            if (ch.isGraphical)
                                message(format("Unknown key: %s", ch));
                            else if (ch < 0x20)
                                message(format("Unknown key ^%s",
                                               cast(dchar)(ch + 0x40)));
                            else
                                message(format("Unknown key (\\u%04X)", ch));
                        }
                }
            }
        );

        dispatch.push(mainMode);
        Fiber.yield();

        assert(result != PlayerAction.none);
        return result;
    }

    void recenterView(Vec!(int,4) center)
    {
        viewport.centerOn(g.playerPos);
    }

    void quitWithMsg(string msg)
    {
        quit = true;
        quitMsg = msg;
    }

    // FIXME: this really should not be initiated by the game engine code!
    void notifyPlayerChange()
    {
        import os_sleep : milliSleep;
        refresh();
        milliSleep(180);

        recenterView(g.playerPos);
    }

    private void refreshMap()
    {
        import tile : tiles;

        auto curview = viewport.curView.fmap!((pos, tileId) {
            auto tile = tiles[tileId];

            // Highlight tiles along axial directions from player.
            auto plpos = g.playerPos - viewport.pos;
            if (iota(4).fold!((c,i) => c + !!(pos[i] == plpos[i]))(0) == 3)
            {
                if (tile.fg == Color.DEFAULT)
                    tile.fg = Color.blue;
                tile.fg |= Bright;
            }

            // Highlight potential diagonal climb destinations.
            import std.math : abs;
            auto abovePl = plpos + vec(-1,0,0,0);
            if (pos[0] == abovePl[0] &&
                iota(1,4).map!(i => abs(abovePl[i] - pos[i])).sum == 1)
            {
                if (tile.fg == Color.DEFAULT)
                    tile.fg = Color.blue;
                tile.fg |= Bright;
            }
            return tile;
        });
        mapview.renderMap(curview);

        disp.hideCursor();
        if (viewport.contains(g.playerPos))
        {
            auto cursorPos = renderingCoors(curview,
                                            g.playerPos - viewport.pos);
            if (region(vec(mapview.width, mapview.height)).contains(cursorPos))
            {
                mapview.moveTo(cursorPos[0], cursorPos[1]);
                disp.showCursor();
            }
        }
    }

    private void refreshStatus()
    {
        // TBD: this should be done elsewhere
        auto ngold = g.numGold();
        auto maxgold = g.maxGold();

        statusview.moveTo(0, 0);
        statusview.writef("$: %d/%d", ngold, maxgold);
        statusview.clearToEol();
    }

    private void refresh()
    {
        refreshStatus();
        refreshMap();

        disp.flush();
        term.flush(); // FIXME: arsd.terminal also caches!
    }

    private void moveView(Vec!(int,4) displacement)
    {
        viewport.move(displacement);
    }

    private void setupUi()
    {
        disp = createDisp();
        auto screenRect = region(vec(disp.width, disp.height));

        auto msgRect = region(screenRect.min, vec(screenRect.max[0], 1));
        msgBox = createMsgBox(msgRect);

        viewport = createViewport(screenRect);
        viewport.centerOn(g.playerPos);

        mapview = createMapView(screenRect);
        static assert(hasColor!(typeof(mapview)));

        statusview = createStatusView(screenRect);
    }

    string play(Game game, string welcomeMsg)
    {
        auto _term = Terminal(ConsoleOutputType.cellular);
        term = &_term;
        g = game;

        auto input = RealTimeConsoleInput(term, ConsoleInputFlags.raw);
        setupUi();

        // Run game engine thread in its own fiber.
        gameFiber = new Fiber({
            g.run(this);
        });

        message(welcomeMsg);

        quit = false;
        gameFiber.call();
        while (!quit)
        {
            refresh();
            dispatch.handleEvent(input.nextEvent());
        }

        term.clear();

        return quitMsg;
    }
}

/**
 * Main program.
 */
void main()
{
    Game game;
    string welcomeMsg;

    import std.file : exists;
    if (saveFileName.exists)
    {
        game = Game.loadGame();
        welcomeMsg = "Welcome back!";
    }
    else
    {
        game = Game.newGame();
        welcomeMsg = "Welcome to Tetraworld!";
    }

    auto ui = new TextUi;
    auto quitMsg = ui.play(game, welcomeMsg);

    writeln(quitMsg);
}

// vim:set ai sw=4 ts=4 et:
