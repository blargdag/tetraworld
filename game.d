/**
 * Game simulation module.
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
module game;

import std.algorithm;
import std.array;
import std.conv : to;
import std.random : uniform;
import std.stdio;
import std.uni : asCapitalized;

import action;
import agent;
import ai;
import components;
import dir;
import gravity;
import loadsave;
import mapgen;
import rndutil;
import store;
import store_traits;
import vector;
import world;

/**
 * Default savegame filename.
 *
 * TBD: this really should be replaced with a playground directory system like
 * in nethack.
 */
enum saveFileName = ".tetra.save";

/**
 * Logical player input action.
 */
enum PlayerAction
{
    none, up, down, left, right, front, back, ana, kata,
    apply, pass,
}

/**
 * Generic UI API.
 */
interface GameUi
{
    /**
     * Add a message to the message log.
     */
    void message(string msg);

    /// ditto
    final void message(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        message(format(fmt, args));
    }

    /**
     * Read player action from user input.
     */
    PlayerAction getPlayerAction();

    /**
     * Notify UI that a map change has occurred.
     *
     * Params:
     *  where = List of affected locations to update.
     */
    void updateMap(Pos[] where...);

    /**
     * Notify that the map should be moved and recentered on a new position.
     * The map will be re-rendered.
     *
     * If multiple refreshes occur back-to-back without an intervening input
     * event, a small pause will be added for animation effect.
     */
    void moveViewport(Vec!(int,4) center);

    /**
     * Signal end of game with an exit message.
     */
    void quitWithMsg(string msg);

    /// ditto
    final void quitWithMsg(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        quitWithMsg(format(fmt, args));
    }

    /**
     * Display some info for the user and wait for keypress.
     */
    void infoScreen(const(string)[] paragraphs, string endPrompt = "[End]");
}

/**
 * Player status.
 */
struct PlayerStatus
{
    string label;
    int curval;
    int maxval;
}

/**
 * Game simulation.
 */
class Game
{
    private GameUi ui;
    /*private*/ World w; // FIXME
    private SysAgent sysAgent;
    private SysGravity sysGravity;

    private Thing* player;
    private Vec!(int,4) lastPlPos;
    private bool isNewGame;
    private bool quit;

    /**
     * Returns: The player's current position.
     */
    Vec!(int,4) playerPos()
    {
        auto posp = w.store.get!Pos(player.id);
        if (posp !is null)
            lastPlPos = posp.coors;
        return lastPlPos;
    }

    PlayerStatus[] getStatuses()
    {
        PlayerStatus[] result;
        if (w.store.get!Inventory(player.id) !is null)
            result ~= PlayerStatus("$", numGold(), maxGold());

        auto m = w.store.get!Mortal(player.id);
        if (m !is null)
            result ~= PlayerStatus("hp", m.hp, m.maxhp);

        return result;
    }

    private int numGold()
    {
        auto inv = w.store.get!Inventory(player.id);
        return inv.contents
                  .map!(id => w.store.get!Tiled(id))
                  .filter!(tp => tp !is null && tp.tileId == TileId.gold)
                  .count
                  .to!int;
    }

    private int maxGold()
    {
        return w.store.getAll!Tiled
                      .map!(id => w.store.get!Tiled(id))
                      .filter!(tp => tp.tileId == TileId.gold)
                      .count
                      .to!int;
    }

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("world", w);
        sf.put("agent", sysAgent);
        sf.put("gravity", sysGravity);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.w = lf.parse!World("world");
        game.sysAgent = lf.parse!SysAgent("agent");
        game.sysGravity = lf.parse!SysGravity("gravity");

        game.player = game.w.store.getObj(playerId);
        if (game.player is null)
            throw new Exception("Save file is corrupt!");

        game.isNewGame = false;

        // Permadeath. :-D
        import std.file : remove;
        remove(saveFileName);

        return game;
    }

    static Game newGame()
    {
        auto g = new Game;
        int[4] startPos;
        MapGenArgs args;
        args.dim = [ 12, 12, 12, 12 ];
        //g.w = genBspLevel(args, startPos);
        g.w = genTutorialLevel(startPos);

        g.player = g.w.store.createObj(
            Pos(startPos), Tiled(TileId.player, 1), Name("you"),
            Agent(Agent.Type.player), Inventory(), BlocksMovement(), Climbs(),
            Swims(), Mortal(5,5)
        );

        g.isNewGame = true;
        return g;
    }

    private Action movePlayer(int[4] displacement, ref string errmsg)
    {
        auto pos = playerPos;
        if (!canMove(w, pos, vec(displacement)) &&
            !canClimb(w, pos, vec(displacement)))
        {
            errmsg = "Your way is blocked.";
            return null;
        }

        auto v = vec(displacement);
        return (World w) => move(w, player, v);
    }

    private Action applyFloorObj(ref string errmsg)
    {
        auto pos = *w.store.get!Pos(player.id);
        auto r = w.store.getAllBy!Pos(pos)
                        .filter!(id => w.store.get!Usable(id) !is null);
        if (r.empty)
        {
            errmsg = "Nothing to apply here.";
            return null;
        }

        return (World w) => useItem(w, player, r.front);
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
                ui.message("You activate the exit portal!");
                ui.quitWithMsg("Congratulations! You collected %d out of %d "~
                               "gold.", ngold, maxgold);
            }
        }
    }

    void setupEventWatchers()
    {
        w.notify.move = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
                ui.moveViewport(newPos);
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.climbLedge = (Pos pos, ThingId subj, Pos newPos, int seq)
        {
            if (subj == player.id)
            {
                if (seq == 0)
                    ui.message("You climb up the ledge.");
                ui.moveViewport(newPos);
            }
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.fall = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
            {
                ui.moveViewport(newPos);

                // FIXME: this really should be done elsewhere!!!
                // Reveal any pit traps that the player may have fallen
                // through.
                auto r = w.getAllAt(newPos)
                          .filter!(id => w.store.get!PitTrap(id) !is null)
                          .map!(id => w.store.getObj(id));
                if (!r.empty)
                {
                    if (r.front.systems & SysMask.tiledabove)
                    {
                        ui.message("You fall through a hidden pit!");
                        w.store.remove!TiledAbove(r.front);
                    }
                    w.store.add!Tiled(r.front, Tiled(TileId.trapPit));
                }
                else
                    ui.message("You fall!");
            }
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.fallOn = (Pos pos, ThingId subj, ThingId obj)
        {
            if (subj == player.id)
            {
                ui.moveViewport(pos);
                // FIXME: reveal pit traps here? Though if we move that
                // elsewhere, this ought to be already taken care of.
                ui.message("You fall on top of %s!",
                           w.store.get!Name(obj).name);
            }
            else
            {
                ui.updateMap(pos);
                ui.message("%s falls on top of %s!",
                           w.store.get!Name(subj).name.asCapitalized,
                           w.store.get!Name(obj).name);
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
            else
                ui.updateMap(pos);
        };
        w.notify.pass = (Pos pos, ThingId subj)
        {
            if (subj == player.id)
            {
                ui.message("You pause for a moment.");
                ui.moveViewport(pos);
            }
        };
        w.notify.attack = (Pos pos, ThingId subj, ThingId obj, ThingId weapon)
        {
            auto subjName = w.store.get!Name(subj).name;
            auto objName = (obj == player.id) ? "you" :
                           w.store.get!Name(obj).name;
            ui.message("%s hits %s!", subjName.asCapitalized, objName);
        };
        w.notify.kill = (Pos pos, ThingId killer, ThingId victim)
        {
            auto subjName = w.store.get!Name(killer).name;
            auto objName = (victim == player.id) ? "you" :
                           w.store.get!Name(victim).name;
            ui.message("%s killed %s!", subjName.asCapitalized, objName);
            if (victim == player.id)
            {
                quit = true;
                ui.quitWithMsg("YOU HAVE DIED.");
            }
        };
        w.notify.message = (Pos pos, ThingId subj, string msg)
        {
            if (subj != player.id)
                return;
            ui.message(msg);
        };
    }

    Action processPlayer()
    {
        Action act;
        string errmsg;
        while (act is null)
        {
            final switch (ui.getPlayerAction()) with(PlayerAction)
            {
                case up:    act = movePlayer([-1,0,0,0], errmsg); break;
                case down:  act = movePlayer([1,0,0,0],  errmsg); break;
                case ana:   act = movePlayer([0,-1,0,0], errmsg); break;
                case kata:  act = movePlayer([0,1,0,0],  errmsg); break;
                case back:  act = movePlayer([0,0,-1,0], errmsg); break;
                case front: act = movePlayer([0,0,1,0],  errmsg); break;
                case left:  act = movePlayer([0,0,0,-1], errmsg); break;
                case right: act = movePlayer([0,0,0,1],  errmsg); break;
                case apply: act = applyFloorObj(errmsg); break;
                case pass:  act = (World w) => .pass(w, player);  break;
                case none:  assert(0, "Internal error");
            }

            if (act is null)
                ui.message(errmsg); // FIXME: should be ui.echo
        }
        return act;
    }

    void setupAgentImpls()
    {
        AgentImpl playerImpl;
        playerImpl.chooseAction = (World w, ThingId agentId)
        {
            return processPlayer();
        };
        playerImpl.notifyFailure = (World w, ThingId agentId,
                                    ActionResult result)
        {
            ui.message(result.failureMsg);
        };
        sysAgent.registerAgentImpl(Agent.Type.player, playerImpl);

        AgentImpl aiImpl;
        aiImpl.chooseAction = (w, agentId) => chooseAiAction(w, agentId);
        sysAgent.registerAgentImpl(Agent.Type.ai, aiImpl);

        // Gravity system proxy for sinking objects over time.
        AgentImpl sinkImpl;
        sinkImpl.chooseAction = (World w, ThingId agentId) {
            sysGravity.sinkObjects(w);
            return (World w) => ActionResult(true, 10);
        };
        sysAgent.registerAgentImpl(Agent.Type.sinkAgent, sinkImpl);
        auto sinkAgent = new Thing(257); // FIXME: need master list of special IDs
        w.store.registerSpecial(*sinkAgent, Agent(Agent.type.sinkAgent));
    }

    void run(GameUi _ui)
    {
        ui = _ui;
        setupEventWatchers();
        setupAgentImpls();

        if (isNewGame)
        {
            ui.infoScreen(textStory001, "[Go forth!]");
            //ui.infoScreen(textGeneralIntro, "[Go forth!]");
            ui.message("Welcome to Tetraworld!");
        }
        else
        {
            ui.message("Welcome back!");

            // FIXME: shouldn't this be in the UI code instead??
            ui.message("Press '?' for help.");
        }

        // Hack to trigger autopickup / Messages at initial position.
        rawMove(w, player, Pos(playerPos), {});

        while (!quit)
        {
            sysGravity.run(w);
            if (!sysAgent.run(w))
                quit = true;
            portalSystem();
        }
    }
}

// Temporary placeholder until we get alternative mapgens ready.
private static immutable textGeneralIntro = [
    "Welcome to Tetraworld Corp.!",

    "You have been hired as a 4D Treasure Hunter by our Field Operations "~
    "Department to explore 4D space and retrieve any treasure you find.",

    "You have been assigned to one of our mining areas, and your task is to "~
    "locate and retrieve all of the gold ores therein, and bring them to the "~
    "exit portal.  The exit portal will return you to Tetraworld Corp., "~
    "where you will receive your next assignment.",

    "Beware that there may be hazards awaiting therein, such as hidden pits "~
    "and flooded areas.  In particular, we advise you to avoid by all means "~
    "any native creatures that you might encounter, as they are likely to be "~
    "hostile, and your 4D environmental suit is not equipped for combat and "~
    "will not survive extensive damage.",

    "We trust in the timely and competent completion of this assignment. "~
    "Good luck!",
];

private static immutable textStory001 = [
    "Welcome to Tetraworld Corp.!",

    "You have been hired as a 4D Treasure Hunter by our Field Operations "~
    "Department to explore 4D space and retrieve any treasure you find.",

    "As an initial orientation, you have been teleported to a training area "~
    "consisting of a single tunnel in 4D space. Your task is to familiarize "~
    "yourself with your 4D view, and to learn 4D movement by following this "~
    "tunnel to the far end where you will find an exit portal.",

    "The exit portal will return you to Tetraworld Corp., where you will "~
    "receive your first assignment.",

    "Good luck!",
];

// vim:set ai sw=4 ts=4 et:
