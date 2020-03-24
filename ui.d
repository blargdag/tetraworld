/**
 * UI module
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
module ui;

import core.thread : Fiber;
import std.algorithm;
import std.array;
import std.range;

import arsd.terminal;

import components;
import display;
import fov;
import game;
import gamemap;
import store_traits;
import vector;
import world;

/**
 * Text UI configuration parameters.
 */
struct TextUiConfig
{
    int smoothscrollMsec = 80;
    string tscriptFile;
}

/**
 * Viewport representation.
 */
struct ViewPort(Map)
    if (is4DArray!Map)
{
    Vec!(int,4) dim;
    Vec!(int,4) pos;

    /// Constructor.
    this(Vec!(int,4) _dim, Vec!(int,4) _pos)
    {
        dim = _dim;
        pos = _pos;
    }

    /**
     * Returns a 4D array of dchar representing the current view of the map
     * given the current viewport settings.
     */
    @property auto curView(WorldView wv)
    {
        return wv.submap(region(pos, pos + dim));
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
 * Message buffer that accumulates in-game messages between turns, and prompts
 * player for keypress if messages overflow message window size before player's
 * next turn.
 */
struct MessageBox(Disp)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    private enum morePrompt = "--MORE--";

    private Disp impl;
    private size_t moreLen;
    private int curX = 0;

    this(Disp disp)
    {
        impl = disp;
        moreLen = morePrompt.displayLength;
    }

    private void showPrompt(void delegate() waitForKeypress)
    {
        // FIXME: this assumes impl.height==1.
        impl.moveTo(curX, 0);
        impl.color(Color.white, Color.blue);
        impl.writef("%s", morePrompt);
        waitForKeypress();

        impl.moveTo(0, 0);
        impl.clearToEol();
        curX = 0;
    }

    /**
     * Post a message to this MessageBox. If it fits in the current space,
     * print it immediately. Otherwise, display a prompt for the user to
     * acknowledge reading the previous messages first, then clear the line and
     * display this one.
     */
    void message(string str, void delegate() waitForKeypress)
    {
        auto len = str.displayLength;
        if (curX + len + moreLen >= impl.width)
        {
            showPrompt(waitForKeypress);
            assert(curX == 0);
        }

        // FIXME: this assumes impl.height==1.
        // FIXME: support the case where len > impl.width.
        impl.moveTo(curX, 0);
        impl.color(Color.DEFAULT, Color.DEFAULT);
        impl.writef("%s", str);
        impl.clearToEol();

        curX += len + 1;
    }

    /**
     * Inform this MessageBox that the player has read all messages, and the
     * next one should start from the beginning again.
     */
    void sync()
    {
        curX = 0;
    }

    /**
     * Prompt if the message box is not empty, otherwise do nothing.
     *
     * Basically, this is intended for when the game is about to quit, or the
     * message box is about to get covered up by a different mode, and we want
     * to ensure the player has read the current messages first.
     */
    void flush(void delegate() waitForKeypress)
    {
        if (curX > 0)
            showPrompt(waitForKeypress);
    }
}

/// ditto
auto messageBox(Disp)(Disp disp)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    return MessageBox!Disp(disp);
}

unittest
{
    struct TestDisp
    {
        enum width = 20;
        enum height = 1;
        char[width*height] impl;
        int curX, curY;

        void moveTo(int x, int y)
            in (x >= 0 && x < width)
            in (y >= 0 && y < height)
        {
            curX = x;
            curY = y;
        }

        void writef(Args...)(string fmt, Args args)
        {
            import std.format : format;
            foreach (ch; format(fmt, args))
            {
                impl[curX + width*curY] = ch;
                curX++;
            }
        }
        void color(ushort, ushort) {}
        @property int cursorX() { return curX; }
        @property int cursorY() { return curY; }
    }

    TestDisp disp;

    foreach (ref ch; disp.impl) { ch = ' '; }
    auto box = messageBox(&disp);

    box.message("Blehk.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blehk.              ");

    box.message("Eh?", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blehk. Eh?          ");

    box.sync();

    box.message("Blah.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blah.               ");

    box.message("Bleh.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blah. Bleh.         ");

    bool keypress;
    box.message("Kaboom.", {
        assert(disp.impl == "Blah. Bleh. --MORE--");
        keypress = true;
    });
    assert(keypress && disp.impl == "Kaboom.             ");
}

private static immutable helpText = q"ENDTEXT
Movement keys:

         i o     
         |/      
  h<- j--+--k ->l
        /|       
       n m

   i,m = up/down
   j,k = left/right
   n,o = forwards/backwards
   h,l = ana/kata

   H,I,J,K,L,M,N,O = move viewport only, does not consume turn.
   <space>         = center viewport back on player.

Commands:
   p        Pass a turn.
   z        Show inventory (does not consume a turn).
   ,        Pick up an object from the current location.
   <enter>  Activate object in current location.

Meta-commands:
   ?        Show this help.
   q        Save current progress and quit.
   Q        Delete current progress and quit.
   ^L       Repaint the screen.
ENDTEXT"
    .split('\n');

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

    private TextUiConfig cfg;

    private DisplayObject term;
    private RealTimeConsoleInput* input;
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
        return messageBox(subdisplay(&disp, msgRect));
    }
    private auto createViewport(Region!(int,2) screenRect)
    {
        auto optVPSize = optimalViewportSize(screenRect.max - vec(0,2));
        return ViewPort!GameMap(optVPSize, vec(0,0,0,0));
    }
    private auto createMapView(Region!(int,2) screenRect)
    {
        auto maprect = screenRect.centeredRegion(renderSize(viewport.dim));
        return subdisplay(&disp, maprect);
    }
    private auto createStatusView(Region!(int,2) screenRect)
    {
        auto statusrect = region(vec(screenRect.min[0], screenRect.max[1]-1),
                                 screenRect.max);
        return subdisplay(&disp, statusrect);
    }

    this(TextUiConfig config = TextUiConfig.init)
    {
        cfg = config;
    }

    void message(string str)
    {
        msgBox.message(str, {
            refresh();
            input.getch();
        });
    }

    PlayerAction getPlayerAction()
    {
        PlayerAction result;

        version(Posix)
            enum keyEnter = '\n';
        else version(Windows)
            enum keyEnter = '\r';
        else static assert(0);

        PlayerAction[dchar] keymap = [
            'i': PlayerAction.up,
            'm': PlayerAction.down,
            'h': PlayerAction.ana,
            'l': PlayerAction.kata,
            'o': PlayerAction.back,
            'n': PlayerAction.front,
            'j': PlayerAction.left,
            'k': PlayerAction.right,
            keyEnter: PlayerAction.apply,
            ',': PlayerAction.pickup,
            'p': PlayerAction.pass,
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
                    case ' ': viewport.centerOn(g.playerPos);   break;
                    case 'z': showInventory();          break;
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
                    case '?':
                        showHelp();
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
        bool visChange;
        foreach (pos; where.filter!(pos => viewport.contains(pos)))
        {
            auto viewPos = pos - viewport.pos;
            auto scrnPos = curview.renderingCoors(viewPos);
            mapview.moveTo(scrnPos[0], scrnPos[1]);
            mapview.renderCell(curview[viewPos]);
            visChange = true;
        }

        if (visChange)
        {
            if (refreshNeedsPause)
            {
                import core.thread : Thread;
                import core.time : dur;

                // FIXME: this should be factored out somewhere?
                auto cx = term.cursorX();
                auto cy = term.cursorY();
                disp.flush();
                term.moveTo(cx, cy);
                term.flush();

                Thread.sleep(dur!"msecs"(50));
            }
            refreshNeedsPause = true;
        }
    }

    void moveViewport(Vec!(int,4) center)
    {
        import std.math : abs;

        auto diff = (center - viewport.dim/2) - viewport.pos;
        if (diff[0 .. 2].map!(e => abs(e)).sum == 1)
        {
            Vec!(int,4) extension = vec(abs(diff[0]), abs(diff[1]), 0, 0);
            Vec!(int,4) offset = vec((diff[0] - 1)/2, (diff[1] - 1)/2, 0, 0);
            int dx = -diff[1];
            int dy = -diff[0];

            auto scrollview = Viewport(viewport.dim + extension,
                                       viewport.pos + offset)
                .curView(g.playerView)
                .fmap!((pos, tileId) => highlightAxialTiles(pos, tileId));

            auto scrollSize = scrollview.renderSize;
            auto steps = dx ? scrollSize[0] - mapview.width :
                              scrollSize[1] - mapview.height;
            auto scrnOffset = offset*steps;
            auto scrollDisp = slidingDisplay(mapview, scrollSize[0],
                                             scrollSize[1], scrnOffset[1],
                                             scrnOffset[0]);

            disp.hideCursor();

            // Initial frame
            int last_i = 0;
            scrollDisp.renderMap(scrollview);
            disp.flush();
            term.flush();

            import core.time : dur, MonoTime;
            auto totalTime = dur!"msecs"(cfg.smoothscrollMsec);
            auto startTime = MonoTime.currTime;
            while (MonoTime.currTime - startTime < totalTime)
            {
                auto i = cast(int)((MonoTime.currTime - startTime)*steps /
                                   totalTime);
                if (i > last_i && i < steps)
                {
                    scrollDisp.moveTo(0, 0);
                    scrollDisp.clearToEos();

                    scrollDisp.scrollTo(scrnOffset[1] + i*dx,
                                        scrnOffset[0] + i*dy);
                    scrollDisp.renderMap(scrollview);
                    disp.flush();
                    term.flush();
                    last_i = i;
                }
            }

            scrollDisp.moveTo(0, 0);
            scrollDisp.clearToEos();
        }
        else
        {
            if (refreshNeedsPause)
            {
                import core.thread : Thread;
                import core.time : dur;
                Thread.sleep(dur!"msecs"(180));
            }
        }
        viewport.centerOn(center);
        refresh();
    }

    void quitWithMsg(string msg)
    {
        message(msg);
        msgBox.flush({
            refresh();
            input.getch();
        });

        quit = true;
        quitMsg = "Game over.";
    }

    void infoScreen(const(string)[] paragraphs, string endPrompt)
    {
        // Make sure player has read all current messages first.
        msgBox.flush({
            refresh();
            input.getch();
        });

        auto scrn = pagerScreen();

        // Format paragraphs into lines
        import lang : wordWrap;
        auto lines = paragraphs.map!(p => p.wordWrap(scrn.width - 2))
                               .joiner([""])
                               .array;

        pager(scrn, lines, endPrompt, {
            gameFiber.call();
        });
        Fiber.yield();
    }

    /**
     * Like message(), but does not store the message into the log and does not
     * accumulate messages with a --MORE-- prompt.
     */
    void echo(string str)
    {
        // FIXME: probably should be in a subdisplay?
        disp.moveTo(0,0);
        disp.writef(str);
        disp.clearToEol();
    }

    /**
     * Prompts the user for a response.  Keeps the cursor positioned
     * immediately after the prompt.
     */
    void prompt(string str)
    {
        // FIXME: probably should be in a subdisplay?
        disp.moveTo(0, 0);
        disp.writef("%s", str);
        auto x = disp.cursorX;
        auto y = disp.cursorY;
        disp.clearToEol();
        disp.moveTo(x, y);
    }

    /**
     * Create a subdisplay to be used as the canvas for pager().
     */
    private auto pagerScreen()
    {
        auto width = min(80, disp.width - 6);
        auto padding = (disp.width - width) / 2;
        return subdisplay(&disp, region(vec(padding, 1),
                          vec(disp.width - padding, disp.height - 1)));
    }

    /**
     * Pager for long text.
     *
     * This function should only be called from the UI fiber; use .infoScreen
     * if calling from the Game fiber.
     */
    private void pager(S)(S scrn, const(char[])[] lines, string endPrompt,
                          void delegate() exitHook)
    {
        const(char[])[] nextLines;

        void displayPage()
        {
            scrn.hideCursor();
            scrn.color(Color.white, Color.black);

            // Can't use .clear 'cos it doesn't use color we set.
            scrn.moveTo(0, 0);
            scrn.clearToEos();

            auto linesToPrint = min(scrn.height - 2, lines.length);
            auto offsetY = (scrn.height - linesToPrint - 1)/2;
            foreach (i; 0 .. linesToPrint)
            {
                // Vertically-center texts for better visual aesthetics.
                scrn.moveTo(1, i + offsetY);
                scrn.writef("%s", lines[i]);
            }
            nextLines = lines[linesToPrint .. $];

            scrn.moveTo(1, linesToPrint + offsetY + 1);
            scrn.color(Color.white, Color.blue);
            scrn.writef("%s", nextLines.length > 0 ? "[More]" : endPrompt);
            scrn.color(Color.white, Color.black);
            scrn.showCursor();
        }

        auto infoMode = Mode(
            () {
                displayPage();
            },
            (dchar ch) {
                if (nextLines.length > 0)
                {
                    lines = nextLines;
                    displayPage();
                }
                else
                {
                    dispatch.pop();
                    disp.color(Color.DEFAULT, Color.DEFAULT);
                    disp.clear();
                    exitHook();
                }
            },
        );

        dispatch.push(infoMode);
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

    private void showHelp()
    {
        auto scrn = pagerScreen();
        pager(scrn, helpText[], "Press any key to return to game", {});
    }

    private void showInventory()
    {
        auto inven = g.getInventory();
        if (inven.length == 0)
        {
            echo("You are not carrying anything right now.");
            return;
        }

        auto scrn = pagerScreen();
        auto invenMode = Mode(
            () {
                scrn.hideCursor();
                scrn.color(Color.white, Color.black);

                // Can't use .clear 'cos it doesn't use color we set.
                scrn.moveTo(0, 0);
                scrn.clearToEos();

                scrn.moveTo(1, 1);
                scrn.writef("You are carrying:");

                foreach (i; 0 .. inven.length)
                {
                    import std.conv : to;
                    scrn.moveTo(2, (3 + i).to!int);
                    scrn.writef("%d %s", inven[i].count, inven[i].name);
                }
            },
            (dchar ch) {
                switch (ch)
                {
                    case 'q', ' ':
                        dispatch.pop();
                        disp.color(Color.DEFAULT, Color.DEFAULT);
                        disp.clear();
                        break;

                    default:
                        break;
                }
            }
        );

        dispatch.push(invenMode);
    }

    private auto getCurView()
    {
        return viewport.curView(g.playerView).fmap!((pos, tileId) =>
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
        statusview.moveTo(0, 0);
        statusview.color(Color.DEFAULT, Color.DEFAULT);
        foreach (stat; g.getStatuses())
        {
            statusview.writef("%s:%d/%d ", stat.label, stat.curval,
                              stat.maxval);
        }
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

        mapview = createMapView(screenRect);
        static assert(hasColor!(typeof(mapview)));

        statusview = createStatusView(screenRect);
    }

    string play(Game game)
    {
        auto _term = Terminal(ConsoleOutputType.cellular);
        if (cfg.tscriptFile.length > 0)
        {
            import std.stdio;
            auto f = File(cfg.tscriptFile, "w");
            term = displayObject(recorded(&_term, f.lockingBinaryWriter));
        }
        else
            term = displayObject(&_term);

        auto _input = RealTimeConsoleInput(&_term, ConsoleInputFlags.raw);
        input = &_input;
        setupUi();

        // Run game engine thread in its own fiber.
        g = game;
        gameFiber = new Fiber({
            g.run(this);
        });

        quit = false;
        gameFiber.call();

        // Main loop
        while (!quit)
        {
            disp.flush();
            refreshNeedsPause = false;
            msgBox.sync();
            dispatch.handleEvent(input.nextEvent());
        }

        term.clear();

        return quitMsg;
    }
}

// vim:set ai sw=4 ts=4 et:
