/**
 * Agent module.
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
module agent;

import std.container.binaryheap;

import action;
import components;
import loadsave;
import store;
import store_traits;
import world;

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

        Agent* agt;
        while (!turnQueue.empty &&
               (agt = w.store.get!Agent(turnQueue.front.id)) is null)
        {
            // Agent was unregistered since last update, ignore.
            turnQueue.popFront;
        }

        if (turnQueue.empty)
            return false; // nothing to do

        // Run agent logic and execute agent's action.
        auto ent = turnQueue.front;
        auto thisTick = ent.nextTurn;
        auto id = ent.id;
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

// vim:set ai sw=4 ts=4 et:
