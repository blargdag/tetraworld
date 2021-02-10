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
import std.conv : to;
import std.format : format;
import std.range;
import std.traits;

import arsd.terminal;

import components;
import dir;
import display;
import fov;
import game;
import gamemap;
import hiscore;
import store_traits;
import vector;
import widgets;
import world;

/**
 * Text UI configuration parameters.
 */
struct TextUiConfig
{
    int smoothscrollMsec = 80;
    string tscriptFile;
    MapStyle mapStyle;
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
   d        Drop an item.
   p        Pass a turn.
   ;        Look at objects on the floor where you are.
   ,        Pick up an object from the current location.
   <tab>    Manage your equipment.
   <enter>  Activate object in current location.

Meta-commands:
   ?        Show this help.
   q        Save current progress and quit.
   Q        Delete current progress and quit.
   ^L       Repaint the screen.
   ^O       Configure game options.
ENDTEXT"
    .split('\n');

private enum ident(alias Memb) = __traits(identifier, Memb);

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
    private HiScore quitScore;

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

    /**
     * Display UI to prompt player to select one item out of many. If only one
     * item is in the list, that item is picked by default without further
     * prompting.  If there are no given targets, the emptyPrompt message is
     * displayed and the callback is not invoked.
     */
    private void selectTarget(string promptStr, InventoryItem[] targets,
                              void delegate(InventoryItem item) cb,
                              string emptyPrompt)
    {
        if (targets.empty)
        {
            message(emptyPrompt);
            return;
        }
        if (targets.length == 1)
        {
            cb(targets.front);
            return;
        }

        inventoryUi(targets, promptStr, [
            SelectButton([keyEnter], "pick", true, (i) { cb(targets[i]); }),
            SelectButton(['q'], "abort", true, null),
        ]);
    }

    private void configOpts()
    {
        int descWidth;

        struct Option
        {
            string desc;
            size_t valMaxLen;
            string delegate() value;
            void delegate() edit;

            size_t displayLength()
            {
                return desc.displayLength + 1 + valMaxLen;
            }
            void render(S)(S scrn, Color fg, Color bg)
            {
                scrn.color(Color.black, Color.white);
                scrn.writef("%-*s ", descWidth, desc);
                scrn.color(fg, bg);
                scrn.writef("%s", value());
                scrn.clearToEol();
            }
        }

        Option[] opts = [
            Option("Smooth scroll time in msec (0=disabled):", 10,
                () => cfg.smoothscrollMsec.to!string,
                () {
                    promptNumber(disp, dispatch, "Enter smooth scroll time "~
                                                 "in msec, 0 to disable",
                                 0, 1000, (val) {
                                    cfg.smoothscrollMsec = val;
                                 }, cfg.smoothscrollMsec.to!string);
                }
            ),
            Option("Map layout style:", 9,
                () => cfg.mapStyle.to!string,
                () {
                    static immutable string[] labels = [
                        staticMap!(ident, EnumMembers!MapStyle)
                    ];
                    static immutable MapStyle[] vals = [
                        EnumMembers!MapStyle
                    ];

                    selectScreen(disp, dispatch, labels,
                        "Select map layout style:", [
                            SelectButton([keyEnter], "select", true, (i) {
                                cfg.mapStyle = vals[i];
                            }),
                            SelectButton(['q'], "cancel", true, null),
                        ], vals.countUntil(cfg.mapStyle).to!int);
                }
            ),
        ];

        SelectButton[] buttons = [
            SelectButton([keyEnter], "change", false, (i) {
                opts[i].edit();
            }),
            SelectButton(['q', '\x0F'], "return to game", true, null),
        ];

        descWidth = opts.map!(opt => opt.desc.displayLength)
                        .maxElement.to!int;

        selectScreen(disp, dispatch, opts, "Configure game options:",
                     buttons, 0);
    }

    PlayerAction getPlayerAction()
    {
        PlayerAction result;

        PlayerAction[dchar] keymap = [
            'i': PlayerAction(PlayerAction.Type.move, Dir.up),
            'm': PlayerAction(PlayerAction.Type.move, Dir.down),
            'h': PlayerAction(PlayerAction.Type.move, Dir.ana),
            'l': PlayerAction(PlayerAction.Type.move, Dir.kata),
            'o': PlayerAction(PlayerAction.Type.move, Dir.back),
            'n': PlayerAction(PlayerAction.Type.move, Dir.front),
            'j': PlayerAction(PlayerAction.Type.move, Dir.left),
            'k': PlayerAction(PlayerAction.Type.move, Dir.right),
            'p': PlayerAction(PlayerAction.Type.pass),
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
                    case ';': lookAtFloor();            break;
                    case '\t':
                        showInventory((InventoryItem item) {
                                result = PlayerAction(
                                        PlayerAction.Type.applyItem, item.id);
                                dispatch.pop();
                                gameFiber.call();
                            }, (InventoryItem item) {
                                result = PlayerAction(PlayerAction.Type.drop,
                                                      item.id, item.count);
                                dispatch.pop();
                                gameFiber.call();
                            }
                        );
                        break;
                    case 'd':
                        selectTarget("What do you want to drop?",
                            g.getInventory(),
                            (item) => promptDropCount(item, (toDrop) {
                                result = PlayerAction(PlayerAction.Type.drop,
                                                      toDrop.id, toDrop.count);
                                dispatch.pop();
                                gameFiber.call();
                            }),
                            "You're not carrying anything!"
                        );
                        break;
                    case 'q':
                        g.saveGame();
                        quit = true;
                        break;
                    case 'Q':
                        promptYesNo(disp, dispatch, "Really quit and "~
                                    "permanently delete this character?",
                                    (yes) {
                            if (yes)
                            {
                                quit = true;
                                quitScore = g.registerHiScore(Outcome.giveup);
                            }
                        });
                        break;
                    case '?':
                        showHelp();
                        break;
                    case '\x0c':        // ^L
                        disp.repaint(); // force repaint of entire screen
                        break;
                    case '\x0f':        // ^O
                        configOpts();
                        break;
                    case keyEnter: {
                        selectTarget("What do you want to apply?",
                            g.getApplyTargets(),
                            (item) {
                                result = PlayerAction(
                                    PlayerAction.Type.applyFloor, item.id);
                                dispatch.pop();
                                gameFiber.call();
                            },
                            "Nothing to apply here."
                        );
                        break;
                    }
                    case ',': {
                        selectTarget("What do you want to pick up?",
                            g.getPickupTargets(),
                            (item) {
                                result = PlayerAction(PlayerAction.Type.pickup,
                                                      item.id);
                                dispatch.pop();
                                gameFiber.call();
                            },
                            "Nothing to pick up here."
                        );
                        break;
                    }
                    default:
                        if (auto cmd = ch in keymap)
                        {
                            result = *cmd;
                            dispatch.pop();
                            gameFiber.call();
                        }
                        else
                        {
                            message("Unknown key: %s (press ? for help)"
                                    .format(ch.toPrintable));
                        }
                }
            }
        );

        dispatch.push(mainMode);
        Fiber.yield();

        assert(result.type != PlayerAction.Type.none);
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
            auto scrnPos = curview.renderingCoors(viewPos, cfg.mapStyle);
            mapview.moveTo(scrnPos[0], scrnPos[1]);
            mapview.renderCell(curview[viewPos], cfg.mapStyle);
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
            scrollDisp.renderMap(scrollview, cfg.mapStyle);
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
                    scrollDisp.renderMap(scrollview, cfg.mapStyle);
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

    void quitWithMsg(string msg, HiScore hs)
    {
        message(msg);
        quit = true;
        quitScore = hs;
    }

    /**
     * Create a subdisplay to be used as the canvas for pager().
     */
    auto pagerScreen()
    {
        auto width = min(80, disp.width - 6);
        auto padding = (disp.width - width) / 2;
        return subdisplay(&disp, region(vec(padding, 1),
                          vec(disp.width - padding, disp.height - 1)));
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

        pager(scrn, dispatch, lines, endPrompt, {
            gameFiber.call();
        });
        Fiber.yield();
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
        pager(scrn, dispatch, helpText[], "Press any key to return to game",
              {});
    }

    private void lookAtFloor()
    {
        auto objs = g.objectsOnFloor().array;
        if (objs.length == 0)
        {
            message("There's nothing of interest here.");
            return;
        }

        if (objs.length == 1)
        {
            message("There's %s here.".format(objs[0]));
            return;
        }

        static immutable heading = "You see here:";
        auto width = max(heading.displayLength + 2,
                         objs.map!(item => item.name.displayLength + 6)
                             .maxElement).to!int;
        auto height = 6 + objs.length.to!int;
        auto scrnX = (disp.width - width)/2;
        auto scrnY = (disp.height - height)/2;
        auto scrn = subdisplay(&disp, region(vec(scrnX, scrnY),
                                             vec(scrnX + width,
                                                 scrnY + height)));
        auto lookMode = Mode(
            () {
                scrn.hideCursor();
                scrn.color(Color.black, Color.white);

                scrn.moveTo(0, 0);
                scrn.clearToEos();

                scrn.moveTo(1, 1);
                scrn.writef("You see here:");

                foreach (i; 0 .. objs.length)
                {
                    scrn.moveTo(1, (3 + i).to!int);
                    renderItem(scrn, objs[i], Color.black, Color.white);
                }

                scrn.moveTo(1, height-2);
                scrn.color(Color.white, Color.blue);
                scrn.writef("[OK]");
                scrn.showCursor();
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

        dispatch.push(lookMode);
    }

    private void renderItem(S)(S scrn, InventoryItem item, Color fg, Color bg)
    {
        import tile : tiles;

        scrn.renderCell(tiles[item.tileId], cfg.mapStyle);
        scrn.color(fg, bg);
        scrn.writef(" %s", item);
        if (item.equipped)
            scrn.writef(" (equipped)");
        scrn.clearToEol();
    }

    private bool inventoryUi(InventoryItem[] inven, string promptStr,
                             SelectButton[] buttons, bool canSelect = true)
    {
        if (inven.length == 0)
            return false;

        auto self = this;
        struct Item
        {
            private InventoryItem item;
            size_t displayLength()
            {
                return 4 + item.name.displayLength + (item.equipped ? 11: 0);
            }
            void render(S)(S scrn, Color fg, Color bg)
            {
                self.renderItem(scrn, item, fg, bg);
            }
        }

        selectScreen(disp, dispatch, inven.map!(item => Item(item)), promptStr,
                     buttons, canSelect ? 0 : -1);
        return true;
    }

    private void promptDropCount(InventoryItem item,
                                 void delegate(InventoryItem) onDrop)
    {
        if (item.count == 1)
        {
            onDrop(item);
            return;
        }

        auto promptStr = format(
            "How many %s do you want to drop?", item.name);
        promptNumber(disp, dispatch, promptStr, 0, item.count, (count) {
            if (count > 0)
            {
                auto toDrop = item;
                toDrop.count = count;
                onDrop(toDrop);
            }
            else
                message("You decide against dropping anything.");
        }, item.count.to!string);
    }

    private void showInventory(void delegate(InventoryItem) onApply,
                               void delegate(InventoryItem) onDrop)
    {
        void delegate() onExit = null;

        auto inven = g.getInventory;
        if (!inventoryUi(inven, "You are carrying:",
            [
                SelectButton([keyEnter], "use/equip/unequip", true, (i) {
                    onApply(inven[i]);
                }),
                SelectButton(['d'],  "drop", true, (i) {
                    promptDropCount(inven[i], onDrop);
                }),
                SelectButton(['\t', 'q'], "done", true, null),
            ]))
        {
            message("You are not carrying anything right now.");
        }
    }

    private auto getCurView()
    {
        return viewport.curView(g.playerView).fmap!((pos, tileId) =>
            highlightAxialTiles(pos, tileId));
    }

    private void refreshMap()
    {
        auto curview = getCurView();
        mapview.renderMap(curview, cfg.mapStyle);

        disp.hideCursor();
        if (viewport.contains(g.playerPos))
        {
            auto cursorPos = renderingCoors(curview,
                                            g.playerPos - viewport.pos,
                                            cfg.mapStyle);
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
            statusview.writef("%s:", stat.label);
            final switch (stat.urgency)
            {
                case PlayerStatus.Urgency.none:
                    statusview.color(Color.DEFAULT, Color.DEFAULT);
                    break;

                case PlayerStatus.Urgency.warn:
                    statusview.color(Color.yellow, Color.DEFAULT);
                    break;

                case PlayerStatus.Urgency.critical:
                    statusview.color(Color.red | Bright, Color.DEFAULT);
                    break;
            }
            statusview.writef("%d", stat.curval);
            statusview.color(Color.DEFAULT, Color.DEFAULT);
            statusview.writef("/%d ", stat.maxval);
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

        msgBox.flush({
            refresh();
            input.getch();
        });

        term.clear();

        if (quitScore == HiScore.init)
            return "Be seeing you!";
        else
            return quitScore.to!string;
    }
}

// vim:set ai sw=4 ts=4 et:
