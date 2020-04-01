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
import fov;
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
    apply, pickup, drop, pass,
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
     * Prompt the user to select an inventory item to perform an action on.
     * Returns: invalidId if the user cancels the action.
     *
     * FIXME: should include count too.
     */
    InventoryItem pickInventoryObj(string whatPrompt, string countPromptFmt);

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
 * Inventory item.
 */
struct InventoryItem
{
    ThingId id;
    string name;
    int count;
}

/**
 * Game simulation.
 */
class Game
{
    private GameUi ui;
    private World w;
    private SysAgent sysAgent;
    private SysGravity sysGravity;

    private Thing* player;
    private MapMemory plMapMemory;
    private Vec!(int,4) lastPlPos;
    private int storyNode;
    private bool quit;

    /**
     * Returns: The player's current position.
     */
    Vec!(int,4) playerPos()
    {
        auto posp = w ? w.store.get!Pos(player.id) : null;
        if (posp !is null)
            lastPlPos = posp.coors;
        return lastPlPos;
    }

    /**
     * Returns: The player's world view (a filtered version of World based on
     * what the player knows / can perceive).
     */
    WorldView playerView()
    {
        return WorldView(w, plMapMemory, playerPos);
    }

    /**
     * Returns: The player's current statuses.
     */
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

    /**
     * Returns: Items currently in the player's inventory.
     */
    InventoryItem[] getInventory()
    {
        auto inven = w.store.get!Inventory(player.id);
        if (inven is null)
            return [];

        return inven.contents
                    .map!((id) {
                        auto stk = w.store.get!Stackable(id);
                        return InventoryItem(id, w.store.get!Name(id).name,
                                             stk ? stk.count : 1);
                    })
                    .array;
    }

    private int numGold()
    {
        auto inv = w.store.get!Inventory(player.id);
        return inv.contents
                  .filter!((id) {
                      auto qi = w.store.get!QuestItem(id);
                      return qi !is null && qi.questId == 1;
                  })
                  .map!(id => w.store.get!Stackable(id))
                  .map!(stk => (stk is null) ? 1 : stk.count)
                  .sum
                  .to!int;
    }

    private int maxGold()
    {
        return w.store.getAll!QuestItem
                      .filter!(id => w.store.get!QuestItem(id).questId == 1)
                      .map!(id => w.store.get!Stackable(id))
                      .map!(stk => (stk is null) ? 1 : stk.count)
                      .sum
                      .to!int;
    }

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("story", storyNode);
        sf.put("world", w);
        sf.put("agent", sysAgent);
        sf.put("gravity", sysGravity);
        sf.put("memory", plMapMemory);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.storyNode = lf.parse!int("story");
        game.w = lf.parse!World("world");
        game.sysAgent = lf.parse!SysAgent("agent");
        game.sysGravity = lf.parse!SysGravity("gravity");
        game.plMapMemory = lf.parse!MapMemory("memory");

        game.player = game.w.store.getObj(playerId);
        if (game.player is null)
            throw new Exception("Save file is corrupt!");

        // Permadeath. :-D
        import std.file : remove;
        remove(saveFileName);

        return game;
    }

    static Game newGame() { return new Game; }

    debug static Game testLevel()
    {
        int[4] startPos;
        auto g = new Game;
        g.w = genTestLevel(startPos);
        g.setupLevel();
        rawMove(g.w, g.player, Pos(startPos), {});
        return g;
    }

    private Action movePlayer(int[4] displacement, ref string errmsg)
    {
        auto pos = playerPos;
        if (!canMove(w, pos, vec(displacement)) &&
            !canClimbLedge(w, pos, vec(displacement)))
        {
            errmsg = "Your way is blocked.";
            return null;
        }

        auto v = vec(displacement);
        return (World w) => move(w, player, v);
    }

    private Action pickupObj(ref string errmsg)
    {
        auto pos = *w.store.get!Pos(player.id);
        auto r = w.store.getAllBy!Pos(pos)
                        .filter!(id => w.store.get!Pickable(id) !is null);
        if (r.empty)
        {
            errmsg = "Nothing here to pick up.";
            return null;
        }

        // TBD: if more than one object, present player a choice.
        return (World w) => pickupItem(w, player, r.front);
    }

    private Action dropObj(ref string errmsg)
    {
        auto item = ui.pickInventoryObj("What do you want to drop?",
                                        "How many %s do you want to drop?");
        if (item.id == invalidId || item.count == 0)
        {
            errmsg = (getInventory().length == 0) ?
                     "You have nothing to drop." :
                     "You decide against dropping anything.";
            return null;
        }
        return (World w) => dropItem(w, player, item.id, item.count);
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

    private void setupLevel()
    {
        // Player memory needs to cover outer walls to avoid strange artifacts
        // like un-rememberable walls.
        plMapMemory = MapMemory(region(w.map.bounds.min,
                                       w.map.bounds.max + vec(1,1,1,1)));

        player = w.store.createObj(
            Tiled(TileId.player, 1, Tiled.Hint.dynamic), Name("you"),
            Agent(Agent.Type.player), Inventory(), Weight(1000),
            BlocksMovement(), Mortal(5,5),
            CanMove(CanMove.Type.walk | CanMove.Type.climb |
                    CanMove.Type.jump | CanMove.Type.swim)
        );
    }

    private void startStory()
    {
        ui.infoScreen(storyNodes[storyNode].infoScreen, "[Proceed]");

        int[4] startPos;
        w = storyNodes[storyNode].genMap(startPos);
        sysAgent = SysAgent.init;
        sysGravity = SysGravity.init;
        setupLevel();

        setupEventWatchers();
        setupAgentImpls();

        // Move player to starting position.
        rawMove(w, player, Pos(startPos), {});
        ui.moveViewport(playerPos);
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
                ui.message("You activate the exit portal!");
                ui.message("You collected %d out of %d gold.", ngold, maxgold);

                storyNode++;
                if (storyNode < storyNodes.length)
                {
                    startStory();
                }
                else
                {
                    quit = true;
                    ui.quitWithMsg("Congratulations, you have finished the "~
                                   "game!");
                }
            }
        }
    }

    void setupEventWatchers()
    {
        w.notify.move = (MoveType type, Pos pos, ThingId subj, Pos newPos,
                         int seq)
        {
            if (subj == player.id)
            {
                final switch (type)
                {
                    case MoveType.walk:
                    case MoveType.jump:
                    case MoveType.climb:
                    case MoveType.sink:
                        ui.moveViewport(newPos);
                        break;

                    case MoveType.climbLedge:
                        if (seq == 0)
                            ui.message("You climb up the ledge.");
                        goto case MoveType.walk;

                    case MoveType.fall:
                        ui.moveViewport(newPos);
                        ui.message("You fall!");
                        break;

                    case MoveType.fallAside:
                        ui.moveViewport(newPos);
                        ui.message("The impact sends you rolling to the side!");
                        break;
                }
            }
            else if (canSee(w, playerPos, pos) || canSee(w, playerPos, newPos))
            {
                if (type == MoveType.sink)
                    ui.message("%s sinks in the water.",
                               w.store.get!Name(subj).name.asCapitalized);
                ui.updateMap(pos, newPos);
            }
        };
        w.notify.itemAct = (ItemActType type, Pos pos, ThingId subj,
                            ThingId obj)
        {
            if (subj == player.id)
            {
                auto name = w.store.get!Name(obj);
                final switch (type)
                {
                    case ItemActType.pickup:
                        if (name !is null)
                            ui.message("You pick up the " ~ name.name ~ ".");
                        break;

                    case ItemActType.drop:
                        if (name !is null)
                            ui.message("You drop the " ~ name.name ~ ".");
                        break;

                    case ItemActType.use:
                        assert(0); // TBD
                }
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
        w.notify.damage = (DmgType type, Pos pos, ThingId subj, ThingId obj,
                           ThingId weapon)
        {
            auto subjName = w.store.get!Name(subj).name;
            auto objName = (obj == player.id) ? "you" :
                           w.store.get!Name(obj).name;
            final switch (type)
            {
                case DmgType.attack:
                    ui.message("%s hits %s!", subjName.asCapitalized, objName);
                    break;

                case DmgType.fallOn:
                    if (subj == player.id)
                    {
                        ui.moveViewport(pos);
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
                    break;

                case DmgType.kill:
                    ui.message("%s killed %s!", subjName.asCapitalized,
                               objName);
                    if (obj == player.id)
                    {
                        quit = true;
                        ui.quitWithMsg("YOU HAVE DIED.");
                    }
                    break;
            }
        };
        w.notify.mapChange = (MapChgType type, Pos pos, ThingId subj,
                              ThingId obj)
        {
            auto subjName = w.store.get!Name(subj);
            final switch (type)
            {
                case MapChgType.revealPitTrap:
                    if (subjName)
                        ui.message("A trap door opens up under %s!",
                                   w.store.get!Name(subj).name);
                    else
                        ui.message("A trap door opens up!");
                    break;

                case MapChgType.triggerRockTrap:
                    if (subjName)
                        ui.message("A trap door opens up above %s and a rock "~
                                   "falls out!", w.store.get!Name(subj).name);
                    else
                        ui.message("A trap door opens in the ceiling and a "~
                                   "rock falls out!");
                    break;
            }
        };
        w.notify.message = (Pos pos, ThingId subj, string msg)
        {
            if (subj != player.id)
                return;
            ui.message(msg);
        };
    }

    auto objectsOnFloor()
    {
        import std.format : format;
        return w.store.getAllBy!Pos(Pos(playerPos))
                .filter!(id => id != player.id)
                .map!(id => w.store.getObj(id))
                .filter!(t => (t.systems & SysMask.name) != 0 &&
                              (t.systems & SysMask.tiled) != 0)
                .map!((Thing* t) {
                    auto tiled = w.store.get!Tiled(t.id);
                    auto nm = w.store.get!Name(t.id);
                    auto stk = w.store.get!Stackable(t.id);
                    if (stk is null || stk.count == 1)
                        return format("a %s", nm.name);
                    return format("%d %s", stk.count, nm.name);
                });
    }

    private void observeSurroundings()
    {
        auto objs = objectsOnFloor().array;
        if (objs.empty)
            return;

        if (objs.length == 1)
            ui.message("You see %s here.", objs[0]);
        else if (objs.length == 2)
            ui.message("You see %s and %s here.", objs[0], objs[1]);
        else
            ui.message("There's a pile of things here.");
    }

    private Action processPlayer()
    {
        observeSurroundings();

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
                case pickup: act = pickupObj(errmsg);             break;
                case drop:  act = dropObj(errmsg);                break;
                case apply: act = applyFloorObj(errmsg);          break;
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

        if (w is null)
        {
            startStory();
        }
        else
        {
            setupEventWatchers();
            setupAgentImpls();

            ui.moveViewport(playerPos);
            ui.message("Welcome back!");

            // FIXME: shouldn't this be in the UI code instead??
            ui.message("Press '?' for help.");
        }

        while (!quit)
        {
            sysGravity.run(w);
            if (!sysAgent.run(w))
                quit = true;
            portalSystem();
        }
    }
}

struct StoryNode
{
    string[] infoScreen;
    World function(ref int[4] startPos) genMap;
}

StoryNode[] storyNodes = [
    StoryNode([
        "Welcome to Tetraworld Corp.!",

        "You have been hired as a 4D Treasure Hunter by our Field Operations "~
        "Department to explore 4D space and retrieve any treasure you find.",

        "As an initial orientation, you have been teleported to a training "~
        "area consisting of a single tunnel in 4D space. Your task is to "~
        "familiarize yourself with your 4D view, and to learn 4D movement by "~
        "following this tunnel to the far end where you will find an exit "~
        "portal.",

        "The exit portal will return you to Tetraworld Corp., where you will "~
        "receive your first assignment.",

        "Good luck!",
    ], (ref int[4] startPos) {
        return genTutorialLevel(startPos);
    }),

    StoryNode([
        "Excellent job!",

        "Now that you have learned how to move around in 4D space, you will "~
        "begin to learn how to perform your duties as a treasure hunter.",

        "Your next assigned area is one of the smaller cave systems that "~
        "Tetraworld Corp. has discovered in the course of its pioneering 4D "~
        "exploration.  This is a simple area with a number of caves that "~
        "have a branching structure.  You will need to explore the area "~
        "and retrieve all the gold ore. This assignment will also acquiant "~
        "you with navigating a non-linear maze in 4D.",

        "Once you have collected all the gold ore, locate the exit portal "~
        "and return."
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 9, 9, 9, 9 ];
        args.goldPct = 1.8;
        return genBspLevel(args, startPos);
    }),

    StoryNode([
        "Excellent!",

        "Now that you have learned the basics of 4D treasure-hunting, it is "~
        "time for your first non-trivial assignment.",

	    "Your task is to collect gold ore located in the ore mines. The area "~
        "you will be responsible for is highly branching, and may require "~
        "extra effort on your part to find all the ore that has been "~
        "detected there.  Furthermore, the caves may loop, so careful "~
        "thoroughness on your part will be required to ensure the successful "~
        "completion of your assignment.",

        "Good luck!"
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 10, 10, 10, 10 ];
        args.nBackEdges = ValRange(3, 5);
        args.goldPct = 1.8;
        return genBspLevel(args, startPos);
    }),

    StoryNode([
        "Outstanding!",

        "The next area is similar to the previous one, and is also located "~
        "in the ore mines. It is slightly larger and more complex, and, "~
        "unfortunately, is also located in a more unstable zone, and there "~
        "may be environmental hazards, such as hidden pits and flooded areas.",

        "In particular, we advise you to avoid by all means any native "~
        "creatures that you might encounter, as they are likely to be "~
        "hostile, and your 4D environmental suit is not equipped for combat "~
        "and will not survive extensive damage.",

        "We trust in the timely and competent completion of this assignment. "~
        "Good luck!",
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 12, 12, 12, 12 ];
        args.nBackEdges = ValRange(3, 5);
        args.nPitTraps = ValRange(8, 12);
        args.nRockTraps = ValRange(1, 4);
        args.goldPct = 1.0;
        args.waterLevel = ValRange(9, 15);
        args.nMonstersA = ValRange(2, 5);
        return genBspLevel(args, startPos);
    }),

    StoryNode([
        "We are very pleased with your continuing performance.",

        "The next area is a large one, and quite complex and potentially "~
        "hazardous. You will probably have to take notes to keep track of "~
        "where you are. But we are confident that this will present no "~
        "problem to your current skills. Again, collect all the gold and "~
        "bring them to the exit portal.  You know the protocol.",

        "Good luck!",
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 15, 15, 15, 15 ];
        args.nBackEdges = ValRange(5, 8);
        args.nPitTraps = ValRange(12, 18);
        args.nRockTraps = ValRange(6, 15);
        args.goldPct = 1.0;
        args.waterLevel = ValRange(10, 15);
        args.nMonstersA = ValRange(4, 6);
        return genBspLevel(args, startPos);
    }),

    StoryNode([
        "Exceptional!",

        "Clearly, you are more than capable of tackling the next area, "~
        "which is even larger and more complex. As usual, find all the "~
        "gold and bring them to the exit portal.",

        "Keep up the good work!",
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 20, 20, 20, 20 ];
        args.nBackEdges = ValRange(10, 15);
        args.nPitTraps = ValRange(20, 25);
        args.nRockTraps = ValRange(20, 25);
        args.goldPct = 1.0;
        args.waterLevel = ValRange(10, 20);
        args.nMonstersA = ValRange(6, 8);
        return genBspLevel(args, startPos);
    }),

    StoryNode([
        "Something is wrong.",

        "As you step out of the portal, expecting to be back in Tetraworld "~
        "Corp, you find yourself instead in a strange new location, with no "~
        "indication as to what happened.  With a sudden loud, sizzling "~
        "noise, the portal behind you vibrates violently and then explodes "~
        "with a deafening pop.",

        "When you recover from the shock, there is no trace left of the "~
        "portal, nor any indication of any instructions or communications "~
        "from Tetraworld Corp.  It seems that you are now stranded in an "~
        "unknown 4D location, and you have to somehow find a way to survive "~
        "long enough to find out what happened, and, hopefully, find a way "~
        "out of here.",

        "As you take your first steps forward, you hear faint echoes of "~
        "unfriendly noises wafting from the distance.  This area seems even "~
        "vaster than the one you have just been to, and fraught with new, "~
        "unknown dangers. You will have to use every wit at your disposal to "~
        "survive in this unfriendly terrain.",

        "You brace yourself and prepare for the worst."
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.dim = [ 32, 32, 32, 32 ];
        args.nBackEdges = ValRange(200, 300);
        args.nPitTraps = ValRange(200, 300);
        args.nRockTraps = ValRange(200, 300);
        args.goldPct = 0.2;
        args.waterLevel = ValRange(16, 32);
        args.nMonstersA = ValRange(15, 30);
        return genBspLevel(args, startPos);
    }),
];

// vim:set ai sw=4 ts=4 et:
