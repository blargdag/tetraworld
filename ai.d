/**
 * AI module.
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
module ai;

import std.algorithm;
import std.math;
import std.range;

import action;
import components;
import dir;
import fov;
import store;
import store_traits;
import vector;
import world;

/**
 * Tries to call the given move generator up to numTries times until a viable
 * move is found.
 *
 * Returns: true if a viable move was found, in which case `dir` contains the
 * viable move; false otherwise, in which case the contents of `dir` are
 * undefined.
 */
bool findViableMove(World w, ThingId agentId, Pos curPos, int numTries,
                    int[4] delegate() generator, out int[4] dir)
{
    while (numTries-- > 0)
    {
        dir = generator();
        if (canAgentMove(w, agentId, vec(dir)) &&
            (canMove(w, curPos, vec(dir)) ||
             canClimbLedge(w, curPos, vec(dir))))
        {
            return true;
        }
    }
    return false;
}

/**
 * Low-level actions constituting steps toward reaching a goal.
 */
struct AiAction
{
    enum Type { attack, eat }

    Type type;
    int range;
    ThingId target;
    Pos targetPos;
}

static struct Target
{
    ThingId id;
    Pos pos;
    int dist;
}

/**
 * Returns: Nearest entity in the given ids to the given reference point.
 */
Target nearestTarget(R)(R ids, World w, Pos refPos, int maxRange,
                        bool delegate(ThingId,Pos) filter = null)
    if (isInputRange!R && is(ElementType!R == ThingId))
{
    Target result;
    result.dist = maxRange;
    foreach (id; ids)
    {
        auto pos = w.store.get!Pos(id);
        if (pos is null || !filter(id, *pos))
            continue;

        auto d = rectNorm(*pos - refPos);
        if (d < result.dist)
        {
            result.dist = d;
            result.id = id;
            result.pos = *pos;
        }
    }
    return result;
}

/**
 * Goal definition.
 */
class GoalDef
{
    abstract bool isActive(World w, ThingId agentId);
    abstract bool findTarget(World w, ThingId agentId, Pos agentPos,
                             int maxRange, out Target target);
    abstract AiAction[] makePlan(World w, Target target);
}

class EatGoal : GoalDef
{
    override bool isActive(World w, ThingId agentId)
    {
        auto m = w.store.get!Mortal(agentId);
        if (m is null || m.curStats.maxfood == 0)
            return false;

        return m.curStats.food <= m.curStats.maxfood / 4;
    }

    override bool findTarget(World w, ThingId agentId, Pos agentPos,
                             int maxRange, out Target target)
    {
        // FIXME: we really should use the BSP tree for indexing entities by
        // Pos, so that we can do proximity searches more efficiently!
        auto result = w.store.getAll!Edible()
                       .nearestTarget(w, agentPos, maxRange,
                                      (id, pos) => canSee(w, agentPos, pos));
        if (result.id == invalidId)
            return false;

        target = result;
        return true;
    }

    override AiAction[] makePlan(World w, Target target)
    {
        return [ AiAction(AiAction.Type.eat, 0, target.id, target.pos) ];
    }
}

class HuntGoal : GoalDef
{
    override bool isActive(World w, ThingId agentId)
    {
        return hasEquippedWeapon(w, agentId) != invalidId;
    }

    override bool findTarget(World w, ThingId agentId, Pos agentPos,
                             int maxRange, out Target target)
    {
        // FIXME: we really should use the BSP tree for indexing entities by
        // Pos, so that we can do proximity searches more efficiently!
        auto m = w.store.get!Mortal(agentId);
        auto agentFaction = (m is null) ? Faction.loner : m.faction;
        auto result = w.store.getAll!Mortal()
                       .filter!(id => id != agentId)
                       .filter!((id) {
                            auto m = w.store.get!Mortal(id);
                            return m.faction == Faction.loner ||
                                   m.faction != agentFaction;
                       })
                       .nearestTarget(w, agentPos, maxRange,
                                      (id, pos) => canSee(w, agentPos, pos));
        if (result.id == invalidId)
            return false;

        target = result;
        return true;
    }

    override AiAction[] makePlan(World w, Target target)
    {
        auto weaponRange = 1; // FIXME
        return [
            AiAction(AiAction.Type.attack, weaponRange, target.id, target.pos),
        ];
    }
}

GoalDef[Agent.Goal.Type.max] goalDefs;

static this()
{
    goalDefs[Agent.Goal.Type.eat] = new EatGoal();
    goalDefs[Agent.Goal.Type.hunt] = new HuntGoal();
    //goalDefs[Agent.Goal.Type.seekAir] = new SeekAirGoal();
}

/**
 * AI state and shared data.
 */
struct SysAi
{
    AiAction[][ThingId] plans;

    /**
     * AI decision-making routine.
     */
    Action chooseAiAction(World w, ThingId agentId)
    {
        auto subj = w.store.getObj(agentId);
        auto agentPos = w.store.get!Pos(agentId);
        if (agentPos is null)
            return (World w) => pass(w, subj);

        // Retrieve current plan. Make a new one if there isn't one.
        auto plan = plans.get(agentId, []);
        if (plan.empty)
            plan = planNewGoal(w, agentId, agentPos);
        scope(exit) plans[agentId] = plan;

        // Execute current plan.
        if (!plan.empty)
        {
            Action nextAct;
            if (executePlan(w, subj, *agentPos, plan, nextAct))
                return nextAct;

            // Plan failed, abort and make a new plan next turn.
            plan = [];
        }

        // Plan failed, or no plan. Make a random move, and make a new plan
        // next turn.
        int[4] dir;
        if (findViableMove(w, agentId, *agentPos, 6,
                           () => dir2vec(randomDir), dir))
            return (World w) => move(w, subj, vec(dir));

        // Can't even do that; give up.
        return (World w) => pass(w, subj);
    }

    private AiAction[] planNewGoal(World w, ThingId agentId, Pos* agentPos)
        in (agentPos !is null)
    {
        auto ag = w.store.get!Agent(agentId);
        assert(ag !is null);

        int minCost = int.max;
        Target bestTgt;
        GoalDef bestGoal;
        foreach (g; ag.goals)
        {
            auto gdef = goalDefs[g.type];
            if (gdef is null) continue; // TBD: temporary stop-gap
            if (!gdef.isActive(w, agentId))
                continue;

            Target tgt;
            if (!gdef.findTarget(w, agentId, *agentPos, g.mapRange, tgt))
                continue;

            auto cost = g.cost * tgt.dist;
            if (cost < minCost)
            {
                minCost = cost;
                bestTgt = tgt;
                bestGoal = gdef;
            }
        }

        if (bestTgt.id == invalidId)
            return [];  // couldn't find a suitable goal

        return bestGoal.makePlan(w, bestTgt);
    }

    private bool executePlan(World w, Thing* subj, Pos agentPos,
                             ref AiAction[] plan, out Action nextAct)
    {
        if (plan.empty)
            return false;

        auto aiAct = plan.front;

        // Track target. If it's within sight, update its tracked position.
        // Otherwise move towards its last-known location.
        auto p = w.store.get!Pos(aiAct.target);
        bool inSight;
        if (p !is null && canSee(w, agentPos, *p))
        {
            aiAct.targetPos = *p;
            inSight = true;
        }

        auto dist = rectNorm(agentPos - aiAct.targetPos);
        if (dist <= aiAct.range && inSight)
        {
            // Within range of target; run action.
            plan.popFront();

            final switch (aiAct.type)
            {
                case AiAction.Type.attack:
                    auto weaponId = hasEquippedWeapon(w, subj.id);
                    if (weaponId == invalidId)
                        return false;   // oops :-D

                    nextAct = (World w) => attack(w, subj, aiAct.target,
                                                  weaponId);
                    return true;

                case AiAction.Type.eat:
                    nextAct = (World w) => eat(w, subj, aiAct.target);
                    return true;
            }
        }
        else if (dist > 0)
        {
            // Out of range, or not in sight. Try to move towards it.

            // TBD: should do a pathfinding step here.

            int[4] dir;
            auto diff = aiAct.targetPos - agentPos;
            if (findViableMove(w, subj.id, agentPos, 6, () => chooseDir(diff),
                               dir))
            {
                nextAct = (World w) => move(w, subj, vec(dir));
                return true;
            }
        }

        // If we got here, it means either the target no longer exists, or we
        // cannot see it, or we couldn't find a viable move towards it. Give up
        // and plan a new course of action.
        return false;
    }
}

// vim:set ai sw=4 ts=4 et:
