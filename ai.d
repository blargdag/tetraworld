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
import std.random;
import std.range;

import action;
import components;
import dir;
import fov;
import medium;
import store;
import store_traits;
import vector;
import world;

/**
 * Predict the final resting position of the given agent if it were to move in
 * the given direction from the given location.
 *
 * The main purpose of this is to evaluate whether a move would end up in an
 * undesirable place, like an unbreathable medium.
 *
 * Prerequisites: The caller must have determined beforehand that the agent can
 * actually move in the given direction. No checks to that end are made; this
 * function assumes that the move is valid.
 */
Pos predictDest(World w, ThingId agentId, Pos curPos, Vec!(int,4) dir)
{
    auto pos = Pos(curPos + dir);
    if (w.locationHas!BlocksMovement(pos) &&
        !w.locationHas!BlocksMovement(pos + vec(-1,0,0,0)) &&
        !w.locationHas!BlocksMovement(curPos + vec(-1,0,0,0)))
    {
        // Climb-ledge.
        return Pos(pos + vec(-1,0,0,0));
    }

    import gravity : FallType, computeFallType;
    while (computeFallType(w, agentId, pos) >= FallType.sink)
    {
        pos = pos + vec(1,0,0,0);
    }

    return pos;
}

unittest
{
    import gamemap, terrain;

    // Test map:
    //    01234
    //  0 #####
    //  1 #   #
    //  2 ##@ #
    //  3 #~#~#
    //  4 #~~~#
    //  5 #####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,4,2,2));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(6,5,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = 3;

    w.store.createObj(Name("block"), Pos(2,1,1,1), BlocksMovement(),
                      SupportsWeight(SupportType.above));
    w.store.createObj(Name("block"), Pos(3,2,1,1), BlocksMovement(),
                      SupportsWeight(SupportType.above));

    auto creature = w.store.createObj(Name("ехидна"), Pos(2,2,1,1),
        CanMove(CanMove.Type.walk | CanMove.Type.climb | CanMove.Type.swim));

    assert(predictDest(w, creature.id, Pos(2,2,1,1), vec(-1,0,0,0)) ==
           Pos(2,2,1,1));
    assert(predictDest(w, creature.id, Pos(2,2,1,1), vec(0,-1,0,0)) ==
           Pos(1,1,1,1));
    assert(predictDest(w, creature.id, Pos(2,2,1,1), vec(0,1,0,0)) ==
           Pos(3,3,1,1));

    w.map.waterLevel = 4;
    assert(predictDest(w, creature.id, Pos(2,2,1,1), vec(0,1,0,0)) ==
           Pos(4,3,1,1));
}

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
            // Check phobias. Currently, just unbreathable mediums.
            auto destPos = predictDest(w, agentId, curPos, vec(dir));
            if (canBreatheIn(w, agentId, curPos))
            {
                // Currently in good medium. Try to stay there.
                if (canSee(w, curPos, destPos))
                    return canBreatheIn(w, agentId, destPos);

                // Can't see where we'll end up; randomly choose to take a
                // risk, or not.
                // FIXME: this should be configurable per agent.
                if (uniform(0, 2) == 0)
                    return true;
            }
            else
            {
                // Currently in bad medium; just keep moving and hope we get
                // out.
                return true;
            }
        }
    }
    return false;
}

private struct Target
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
 * Invokes a delegate with coordinates of points in the 16-cell of the given
 * radius, in order of increasing Manhattan distance from the given origin.
 *
 * Params:
 *  origin = The center of the 16-cell.
 *  radius = The out-radius of the 16-cell.
 *  cb = Delegate to invoke. Should return non-zero to terminate the iteration
 *      immediately, 0 to continue. Any non-zero return value is propagated to
 *      the return value of this function.
 */
int diamondOnion(Vec!(int,4) origin, int radius,
                 int delegate(Vec!(int,4) pos, int dist) cb)
{
    foreach (r; 0 .. radius+1)
    {
        foreach (i; -r .. r+1)
        {
            auto r0 = r - abs(i);
            foreach (j; -r0 .. r0 + 1)
            {
                auto r1 = r0 - abs(j);
                foreach (k; -r1 .. r1 + 1)
                {
                    auto r2 = r1 - abs(k);
                    auto l = -r2;
                    assert(i.abs + j.abs + k.abs + l.abs == r);

                    auto pos = Pos(origin + vec(i,j,k,l));
                    auto ret = cb(pos, r);
                    if (ret != 0)
                        return ret;

                    if (l != 0)
                    {
                        pos = Pos(origin + vec(i,j,k,-l));
                        ret = cb(pos, r);
                        if (ret != 0)
                            return ret;
                    }
                }
            }
        }
    }
    return 0;
}

unittest
{
    int n;
    int curRad;
    diamondOnion(vec(0,0,0,0), 1, (Vec!(int,4) pos, int dist) {
        n++;
        assert(dist == curRad || dist == curRad+1);
        curRad = dist;
        return 0;
    });
    assert(n == 9);

    n = 0;
    curRad = 0;
    diamondOnion(vec(0,0,0,0), 2, (Vec!(int,4) pos, int dist) {
        n++;
        assert(dist == curRad || dist == curRad+1);
        curRad = dist;
        return 0;
    });
    assert(n == 41);

    n = 0;
    curRad = 0;
    diamondOnion(vec(0,0,0,0), 3, (Vec!(int,4) pos, int dist) {
        n++;
        assert(dist == curRad || dist == curRad+1);
        curRad = dist;
        return 0;
    });
    assert(n == 129);
}

/**
 * Low-level actions constituting steps toward reaching a goal.
 */
struct Plan
{
    enum Act { none, attack, eat }

    Agent.Goal.Type type;
    Act act;
    int range;
    ThingId target;
    Pos targetPos;
}

/**
 * Goal definition.
 */
class GoalDef
{
    immutable Agent.Goal.Type type;
    this(Agent.Goal.Type _type) { type = _type; }

    abstract bool isActive(World w, ThingId agentId);
    abstract bool findTarget(World w, ThingId agentId, Pos agentPos,
                             int maxRange, out Target target);
    abstract Plan makePlan(World w, Target target);
}

class EatGoal : GoalDef
{
    this() { super(Agent.Goal.Type.eat); }
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

    override Plan makePlan(World w, Target target)
    {
        return Plan(Agent.Goal.Type.eat, Plan.Act.eat, 0, target.id,
                        target.pos);
    }
}

class HuntGoal : GoalDef
{
    this() { super(Agent.Goal.Type.hunt); }
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

    override Plan makePlan(World w, Target target)
    {
        auto weaponRange = 1; // FIXME
        return Plan(Agent.Goal.Type.hunt, Plan.Act.attack, weaponRange,
                        target.id, target.pos);
    }
}

class SeekAirGoal : GoalDef
{
    this() { super(Agent.Goal.Type.seekAir); }
    override bool isActive(World w, ThingId agentId)
    {
        auto pos = w.store.get!Pos(agentId);
        auto m = w.store.get!Mortal(agentId);
        ThingId dummy;

        // Active when agent is in a non-breathable medium.
        return pos !is null && m !is null && !canBreatheIn(w, m, *pos, dummy);
    }

    override bool findTarget(World w, ThingId agentId, Pos agentPos,
                             int maxRange, out Target target)
    {
        auto m = w.store.get!Mortal(agentId);
        assert(m !is null);

        // FIXME: probably needs optimization: this call scans O(n^3)
        // surrounding tiles to find a breathable one. :-/
        bool result;
        diamondOnion(agentPos, maxRange, (pos, dist) {
            ThingId airTile;
            if (w.getMediumAt(pos, &airTile) & m.curStats.canBreatheIn)
            {
                target = Target(airTile, Pos(pos), dist);
                result = true;
                return 1;
            }
            return 0;
        });
        return result;
    }

    override Plan makePlan(World w, Target target)
    {
        return Plan(Agent.Goal.Type.seekAir, Plan.Act.none, 0,
                        target.id, target.pos);
    }
}

GoalDef[Agent.Goal.Type.max+1] goalDefs;

static this()
{
    goalDefs[Agent.Goal.Type.eat] = new EatGoal();
    goalDefs[Agent.Goal.Type.hunt] = new HuntGoal();
    goalDefs[Agent.Goal.Type.seekAir] = new SeekAirGoal();
}

/**
 * AI state and shared data.
 */
struct SysAi
{
    private static struct Goal
    {
        GoalDef def;
        Target target;
        int cost;
    }

    private Goal findBestGoal(World w, ThingId agentId, Pos agentPos)
    {
        auto ag = w.store.get!Agent(agentId);
        Goal bestGoal;

        bestGoal.cost = int.max;
        foreach (g; ag.goals)
        {
            auto gdef = goalDefs[g.type];
            if (gdef is null) continue; // TBD: temporary stop-gap
            if (!gdef.isActive(w, agentId))
                continue;

            Target tgt;
            if (!gdef.findTarget(w, agentId, agentPos, g.mapRange, tgt))
                continue;

            auto cost = g.cost * tgt.dist;
            if (cost < bestGoal.cost)
            {
                bestGoal.cost = cost;
                bestGoal.target = tgt;
                bestGoal.def = gdef;
            }
        }

        return bestGoal;
    }

    /**
     * AI decision-making routine.
     */
    Action chooseAiAction(World w, ThingId agentId)
    {
        auto subj = w.store.getObj(agentId);
        auto agentPos = w.store.get!Pos(agentId);
        if (agentPos is null)
            return (World w) => pass(w, subj);

        // Retrieve current plan. Make a new one if there isn't one, or if
        // another goal has become more important.
        auto bestGoal = findBestGoal(w, agentId, *agentPos);
        if (bestGoal.def !is null)
        {
            auto plan = bestGoal.def.makePlan(w, bestGoal.target);

            Action nextAct;
            if (executePlan(w, subj, *agentPos, plan, nextAct))
                return nextAct;
        }

        // Plan failed, or no plan. Make a random move.
        int[4] dir;
        if (findViableMove(w, agentId, *agentPos, 6,
                           () => dir2vec(randomDir), dir))
            return (World w) => move(w, subj, vec(dir));

        // Can't even do that; give up.
        return (World w) => pass(w, subj);
    }

    private bool executePlan(World w, Thing* subj, Pos agentPos,
                             Plan plan, out Action nextAct)
    {
        // Track target. If it's within sight, update its tracked position.
        // Otherwise move towards its last-known location.
        auto p = w.store.get!Pos(plan.target);
        bool inSight;
        if (p !is null && canSee(w, agentPos, *p))
        {
            plan.targetPos = *p;
            inSight = true;
        }

        auto dist = rectNorm(agentPos - plan.targetPos);
        if (dist <= plan.range && inSight)
        {
            // Within range of target; run action.
            final switch (plan.act)
            {
                case Plan.Act.none:
                    // The whole point of the goal was to get to the target
                    // position (or within some range of it); since that's
                    // accomplished, it's time to move on to the next goal.
                    return false;

                case Plan.Act.attack:
                    auto weaponId = hasEquippedWeapon(w, subj.id);
                    if (weaponId == invalidId)
                        return false;   // oops :-D

                    nextAct = (World w) => attack(w, subj, plan.target,
                                                  weaponId);
                    return true;

                case Plan.Act.eat:
                    nextAct = (World w) => eat(w, subj, plan.target);
                    return true;
            }
        }
        else if (dist > 0)
        {
            // Out of range, or not in sight. Try to move towards it.

            // TBD: should do a pathfinding step here.

            int[4] dir;
            auto diff = plan.targetPos - agentPos;
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
