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
import std.container.binaryheap;
import std.stdio;

import action;
import components;
import loadsave;
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
        message(format(fmt.args));
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
}

/**
 * An entry in the turn queue.
 */
private struct QueueEntry
{
    ulong nextTurn;
    ThingId id;

    int opCmp(ref const QueueEntry b)
    {
        // Sort not just by .nextTurn, but also by ID to ensure stable priority
        // sorting (relative order of agents with same .nextTurn is stable
        // rather than changing randomly between turns).
        return nextTurn < b.nextTurn ? 1 :
               nextTurn > b.nextTurn ? -1 :
               id < b.id ? 1 :
               id > b.id ? -1 : 0;
    }
}

unittest
{
    auto a1 = QueueEntry(10, 101);
    auto a2 = QueueEntry(10, 102);
    auto a3 = QueueEntry(15, 103);

    assert(a1 == a1);
    assert(a2 == a2);
    assert(a3 == a3);

    assert(a1 > a2);
    assert(a1 > a3);
    assert(a2 > a3);
}

/**
 * An Agent's implementation.
 */
struct AgentImpl
{
    /**
     * A delegate representing the Agent's decision function. It examines the
     * World state and returns an Action representing the Agent's chosen course
     * of action.
     */
    Action delegate(World w, ThingId agentId) chooseAction;

    /**
     * A delegate that notifies the Agent of an action failure. 
     */
    void delegate(World w, ThingId agentId, ActionResult result)
        notifyFailure;
}

/**
 * System for managing turn-based timing for agents.
 */
struct SysAgent
{
    private alias TurnQueue = BinaryHeap!(QueueEntry[]);
    private TurnQueue turnQueue;
    private bool inited;

    private AgentImpl[Agent.Type.max + 1] agentImpls;

    private void setup()
    {
        if (inited) return;
        turnQueue = TurnQueue([]);
        inited = true;
    }

    /**
     * Register an agent implementation.
     *
     * Params:
     *  type = The Agent type.
     *  impl = The implementation of the Agent's decision routine and failure
     *      notification routine.
     */
    void registerAgentImpl(Agent.Type type, AgentImpl impl)
        in (impl.chooseAction !is null)
    {
        agentImpls[type] = impl;
    }

    /**
     * Current turn number.
     */
    ulong curTick()
    {
        setup();
        return (turnQueue.empty) ? 1 : turnQueue.front.nextTurn;
    }

    /**
     * Collect entities with newly-added Agent components from the Store and
     * enqueue them for processing.
     */
    private void enqueueNewAgents(World w)
    {
        foreach (id; w.store.getAllNew!Agent)
        {
            auto ag = w.store.get!Agent(id);
            if (ag is null) continue;

            auto nextTurn = curTick();
            turnQueue.insert(QueueEntry(nextTurn, id));
        }

        w.store.clearNew!Agent();
    }

    /**
     * Run a single iteration of this system.
     *
     * Returns: false if there are no agents to run, true otherwise.
     */
    bool run(World w)
    {
        setup();
        enqueueNewAgents(w);

        if (turnQueue.empty)
            return false; // nothing to do

        auto ent = turnQueue.front;
        auto id = ent.id;
        auto thisTick = ent.nextTurn;

        auto agt = w.store.get!Agent(id);
        if (agt is null)
            return true; // Agent was unregistered since last update, ignore.

        // Run agent logic and execute agent's action.
        auto type = agt.type;
        Action action = agentImpls[type].chooseAction(w, id);
        assert(action !is null);

        ActionResult result = action(w);
        if (!result.success)
        {
            if (agentImpls[type].notifyFailure !is null)
                agentImpls[type].notifyFailure(w, id, result);

            assert(result.turnCost > 0);
        }

        // NOTE: this MUST NOT be done before the Agent's Action is executed,
        // because if it's the player Agent, the player might trigger a game
        // save, but at that point the player Agent is no longer in the queue
        // so the next time the game starts up it will get stuck in an infinite
        // loop.
        turnQueue.popFront();

        // Reschedule agent in queue unless it was deregistered during its
        // action code. (We have to refetch it from the store because it may
        // have changed.)
        agt = w.store.get!Agent(id);
        if (agt !is null)
        {
            auto nextTurn = thisTick + result.turnCost;
            turnQueue.insert(QueueEntry(nextTurn, id));
        }

        return true;
    }

    /**
     * Save the current agent state into the destination file.
     */
    void save(S)(S savefile)
        if (isSaveFile!S)
    {
        savefile.put("turnQueue", turnQueue.dup);
    }

    /**
     * Load the agent subsystem state from the given file.
     */
    void load(L)(ref L loadfile)
        if (isLoadFile!L)
    {
        auto turns = loadfile.parse!(QueueEntry[])("turnQueue");

        size_t turn;
        foreach (ent; turns)
        {
// FIXME: TBD
//            auto id = ent.id;
//            auto t = store.getObj(id);
//            if (t is null) continue;
//
//            auto ag = store.get!Agent(id);
//            if (ag is null || t is null)
//                throw new LoadException("Invalid turn data");

            // Verify ascending order
            if (ent.nextTurn < turn)
                throw new LoadException("Turn data corrupted");

            turn = ent.nextTurn;
        }

        turnQueue.acquire(turns);
        inited = true;
    }
}

/**
 * Gravity system.
 */
void gravitySystem(World w)
{
    bool willFall()(ThingId id, out Pos oldPos, out Pos floorPos)
    {
        // NOTE: race condition: a falling object may autopickup another
        // object and remove its Pos while we're still iterating, which
        // will cause posp to be null.
        auto posp = w.store.get!Pos(id);
        if (posp is null)
            return false;

        oldPos = *posp;
        floorPos = Pos(oldPos + vec(1,0,0,0));

        return w.store.get!SupportsWeight(w.map[floorPos]) is null ||
               w.locationHas!PitTrap(floorPos);
    }

    foreach (t; w.store.getAllNew!Pos().dup
                       .filter!(id => w.store.get!NoGravity(id) is null)
                       .map!(id => w.store.getObj(id)))
    {
        Pos oldPos, floorPos;
        while (willFall(t.id, oldPos, floorPos))
        {
            rawMove(w, t, floorPos, {
                w.notify.fall(oldPos, t.id, floorPos);
            });
        }
    }

    w.store.clearNew!Pos();
}

/**
 * Game simulation.
 */
class Game
{
    private GameUi ui;
    /*private*/ World w; // FIXME
    private SysAgent sysAgent;

    private Thing* player;
    private bool quit;

    /**
     * Returns: The player's current position.
     */
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

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("world", w);
        sf.put("agent", sysAgent);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.w = lf.parse!World("world");
        game.sysAgent = lf.parse!SysAgent("agent");

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
            Tiled(TileId.player, 1), Name("You"), Agent(Agent.Type.player),
            Inventory(), BlocksMovement()
        );
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
        return (World w) {
            auto result = move(w, player, v);

            // TBD: this is a hack that should be replaced by a System,
            // probably.
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

            return result;
        };
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
                import std.format : format;
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

                // Reveal any pit traps that the player may have fallen
                // through.
                auto r = w.getAllAt(newPos)
                          .filter!(id => w.store.get!PitTrap(id) !is null)
                          .map!(id => w.store.getObj(id));
                if (!r.empty)
                {
                    w.store.add!Tiled(r.front, Tiled(TileId.trapPit));
                    ui.message("You fall through a hidden pit!");

                    // FIXME: hack to reveal blank space just above pit instead
                    // of floor tile.
                    w.store.createObj(Pos(pos), Name("pit"),
                                      Tiled(TileId.space), NoGravity());
                }
                else
                    ui.message("You fall!");
            }
            else
                ui.updateMap(pos, newPos);
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
                ui.message("You pause for a moment.");
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
        aiImpl.chooseAction = (World w, ThingId agentId)
        {
            return (World w) {
                // For now, just move randomly.
                import dir;
                auto t = w.store.getObj(agentId);
                return move(w, t, vec(dir2vec(randomDir)));
            };
        };
        sysAgent.registerAgentImpl(Agent.Type.ai, aiImpl);
    }

    void run(GameUi _ui)
    {
        ui = _ui;
        setupEventWatchers();
        setupAgentImpls();

        while (!quit)
        {
            gravitySystem(w);
            if (!sysAgent.run(w))
                quit = true;
            portalSystem();
        }
    }
}

// vim:set ai sw=4 ts=4 et:
