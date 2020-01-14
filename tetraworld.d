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

import components;
import display;
import game;
import gamemap;
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
        if (top.render !is null)
            top.render();
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

/**
 * Text-based UI implementation.
 */
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

    private bool refreshNeedsPause;

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
        msgBox.color(Color.DEFAULT, Color.DEFAULT);
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
                        promptYesNo("Really quit and permanently delete this "~
                                    "character?", (yes) {
                            if (yes)
                            {
                                quit = true;
                                quitMsg = "Bye!";
                            }
                        });
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

    void updateMap(Pos[] where...)
    {
        // Only update the on-screen tiles that have changed.
        auto curview = getCurView();
        foreach (pos; where.filter!(pos => viewport.contains(pos)))
        {
            auto viewPos = pos - viewport.pos;
            auto scrnPos = curview.renderingCoors(viewPos);
            mapview.moveTo(scrnPos[0], scrnPos[1]);
            mapview.renderCell(curview[viewPos]);
        }
    }

    void moveViewport(Vec!(int,4) center)
    {
        import std.math : abs;
        import os_sleep : milliSleep;

        auto diff = (center - viewport.dim/2) - viewport.pos;
        if (diff[0 .. 2].map!(e => abs(e)).sum == 1)
        {
            Vec!(int,4) extension;
            Vec!(int,4) offset;
            int dx, dy;
            bool isHoriz;

            if (diff == vec(1,0,0,0))
            {
                extension = vec(1,0,0,0);
                offset = vec(0,0,0,0);
                dx = 0;
                dy = -1;
            }
            else if (diff == vec(-1,0,0,0))
            {
                extension = vec(1,0,0,0);
                offset = vec(-1,0,0,0);
                dx = 0;
                dy = 1;
            }
            else if (diff == vec(0,1,0,0))
            {
                extension = vec(0,1,0,0);
                offset = vec(0,0,0,0);
                dx = -1;
                dy = 0;
                isHoriz = true;
            }
            else if (diff == vec(0,-1,0,0))
            {
                extension = vec(0,1,0,0);
                offset = vec(0,-1,0,0);
                dx = 1;
                dy = 0;
                isHoriz = true;
            }

            auto scrollview = Viewport(g.w, viewport.dim + extension,
                                       viewport.pos + offset)
                .curView
                .fmap!((pos, tileId) => highlightAxialTiles(pos, tileId));

            auto scrollSize = scrollview.renderSize;
            auto steps = isHoriz ? scrollSize[0] - mapview.width :
                                   scrollSize[1] - mapview.height;
            auto scrollDisp = slidingDisplay(mapview, scrollSize[0],
                                             scrollSize[1], offset[1]*steps,
                                             offset[0]*steps);
            disp.hideCursor();
            foreach (i; 0 .. steps)
            {
                scrollDisp.renderMap(scrollview);
                disp.flush();
                term.flush();

                milliSleep(5);
                scrollDisp.moveTo(0, 0);
                scrollDisp.clearToEos();
                scrollDisp.scroll(dx, dy);
            }
        }
        else
        {
            if (refreshNeedsPause)
            {
                milliSleep(180);
            }
        }
        viewport.centerOn(center);
        refresh();
    }

    void quitWithMsg(string msg)
    {
        quit = true;
        quitMsg = msg;
    }

    /**
     * Like message(), but does not store the message into the log and does not
     * accumulate messages with a --MORE-- prompt.
     */
    void echo(string str)
    {
        msgBox.moveTo(0,0);
        msgBox.writef(str);
        msgBox.clearToEol();
    }

    /**
     * Prompts the user for a response.  Keeps the cursor positioned
     * immediately after the prompt.
     */
    void prompt(string str)
    {
        msgBox.moveTo(0, 0);
        msgBox.writef("%s", str);
        auto x = msgBox.cursorX;
        auto y = msgBox.cursorY;
        msgBox.clearToEol();
        msgBox.moveTo(x, y);
    }

    /**
     * Pushes a Mode to the mode stack that prompts the player for a yes/no
     * response, and invokes the given callback with the answer.
     */
    private void promptYesNo(string promptStr, void delegate(bool answer) cb)
    {
        string str = promptStr ~ " [yn] ";
        auto mode = Mode(
            {
                prompt(str);
            }, (dchar key) {
                switch (key)
                {
                    case 'y':
                        dispatch.pop();
                        echo(str ~ "yes");
                        cb(true);
                        break;
                    case 'n':
                        dispatch.pop();
                        echo(str ~ "no");
                        cb(false);
                        break;

                    default:
                }
            }
        );

        dispatch.push(mode);
    }

    private auto highlightAxialTiles(Vec!(int,4) pos, TileId tileId)
    {
        import tile : tiles;
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
    }

    private auto getCurView()
    {
        return viewport.curView.fmap!((pos, tileId) =>
            highlightAxialTiles(pos, tileId));
    }

    private void refreshMap()
    {
        auto curview = getCurView();
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

        // Next refresh should pause if no intervening input event.
        refreshNeedsPause = true;
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
            disp.flush();
            refreshNeedsPause = false;
            dispatch.handleEvent(input.nextEvent());
        }

        term.clear();

        return quitMsg;
    }
}

/**
 * Main program.
 */
int main()
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
    try
    {
        auto quitMsg = ui.play(game, welcomeMsg);
        writeln(quitMsg);
        return 0;
    }
    catch (Exception e)
    {
        // Emergency save when things go wrong.
        game.saveGame();
        writefln("Error: %s", e.msg);
        return 1;
    }
}

// vim:set ai sw=4 ts=4 et:
