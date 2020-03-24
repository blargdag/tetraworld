/**
 * Actions module.
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
module action;

import std.algorithm;
import components;
import store;
import store_traits;
import world;
import vector;

/**
 * An encapsulated game action.
 */
alias Action = ActionResult delegate(World w);

/**
 * Result of an action.
 */
struct ActionResult
{
    /**
     * Whether or not the action succeeded.
     */
    bool success;

    /**
     * How many ticks this action costed to perform. Note that this applies
     * even for failed actions; it must be non-zero to prevent dumb agents from
     * getting stuck in the turn queue.
     */
    ulong turnCost;

    invariant() { assert(turnCost > 0); }

    /**
     * If action failed, a failure message.
     */
    string failureMsg;
}

/**
 * A low-level movement routine that handles terrain exit/enter conditions,
 * autopickup, and other per-tile effects.
 *
 * Params:
 *  w = The World instance.
 *  subj = The agent being moved.
 *  newPos = The new position.
 *  notifyMove = A delegate for sending movement notifications after the
 *      movement but before any post-move effects are triggered.
 *
 * WARNING: this function DOES NOT CHECK for movement blockage, etc.. It
 * ASSUMES that the caller has already taken care of this.  It's meant to be a
 * low-level primitive for composing higher-level actions.
 */
void rawMove(World w, Thing* subj, Pos newPos, void delegate() notifyMove)
{
    w.store.remove!Pos(subj);
    w.store.add!Pos(subj, newPos);
    notifyMove();

    // Autopickup
    auto inven = w.store.get!Inventory(subj.id);
    if (inven != null)
    {
        // Note: need to .dup because otherwise we run into the bad ole
        // modify-while-iterating container issue.
        foreach (t; w.store.getAllBy!Pos(newPos).dup
                           .map!(id => w.store.getObj(id))
                           .filter!(t => w.store.get!Pickable(t.id) !is null))
        {
            w.store.remove!Pos(t);
            inven.contents ~= t.id;

            w.notify.itemAct(ItemActType.pickup, newPos, subj.id, t.id);
        }
    }

    // Triggers
    foreach (trigObj; w.store.getAllBy!Pos(newPos)
                    .map!(id => w.store.getObj(id)))
    {
        auto trig = w.store.get!Trigger(trigObj.id);
        if (trig is null || trig.type != Trigger.Type.onEnter)
            continue;

        auto groupId = Triggerable(trig.triggerId);
        foreach (t; w.store.getAllBy!Triggerable(groupId)
                     .map!(id => w.store.getObj(id)))
        {
            auto tga = w.store.get!Triggerable(t.id);
            assert(tga !is null);
            final switch (tga.effect)
            {
                case TriggerEffect.trapDoor:
                    w.store.remove!BlocksMovement(t);
                    w.store.remove!BlocksView(t);
                    w.store.remove!TiledAbove(t);
                    w.store.remove!Triggerable(t); // trigger only once(?)
                    w.store.add!Tiled(t, Tiled(TileId.trapPit));
                    w.notify.mapChange(MapChgType.revealPitTrap, newPos,
                                       subj.id, t.id);
                    break;

                case TriggerEffect.rockTrap:
                    auto pos = *w.store.get!Pos(t.id);
                    w.store.add!Tiled(trigObj, Tiled(TileId.trapRock));
                    w.store.createObj(pos, Name("rock"), Tiled(TileId.rock));
                    w.notify.mapChange(MapChgType.triggerRockTrap, pos,
                                       subj.id, t.id);
                    break;
            }
        }
    }

    // Emit any Messages
    foreach (msg; w.getAllAt(newPos)
                   .map!(id => w.store.get!Message(id))
                   .filter!(msg => msg !is null))
    {
        foreach (m; msg.msgs)
        {
            w.notify.message(newPos, subj.id, m);
        }
    }
}

/**
 * Iterates over the current supporters of the given agent's weight of the
 * given type(s) and invokes the given delegate.
 *
 * Params:
 *  w = The World object.
 *  agentId = The agent ID.
 *  type = The support types to check (can be multiple OR'd values).
 *  dg = The delegate to invoke per support. It is invoked with the supporting
 *      object's ID and SupportsWeight component. For conditional supporters,
 *      only objects whose conditions are currently satisfied by the agent are
 *      passed to the delegate. Normally, the delegate should return 0;
 *      returning a non-zero value short-circuits the iteration and propagates
 *      the value to the return value of this function.
 *
 * Returns: The first non-zero return value of dg, otherwise 0.
 */
int foreachSupport(World w, ThingId agentId, SupportType type,
                   int delegate(ThingId support, SupportsWeight* sw) dg)
{
    auto pos = *w.store.get!Pos(agentId);
    auto cm = w.store.get!CanMove(agentId);

    bool agentSupportedBy(SupportsWeight* sw)
    {
        final switch (sw.cond)
        {
            case SupportCond.always:
                return true;

            case SupportCond.climbing:
                if (cm !is null && (cm.types & CanMove.Type.climb))
                    return true;
                break;

            case SupportCond.buoyant:
                if (cm !is null && (cm.types & CanMove.Type.swim))
                    return true;
                break;
        }
        return false;
    }

    static struct Ent
    {
        ThingId id;
        SupportsWeight* sw;
    }

    if (type & SupportType.above)
    {
        auto floorPos = *w.store.get!Pos(agentId) + vec(1,0,0,0);
        foreach (e; w.getAllAt(floorPos)
                     .map!(id => Ent(id, w.store.get!SupportsWeight(id)))
                     .filter!(e => e.sw !is null &&
                                   (e.sw.type & SupportType.above) &&
                                   agentSupportedBy(e.sw)))
        {
            auto rc = dg(e.id, e.sw);
            if (rc)
                return rc;
        }
    }

    if (type & SupportType.within)
    {
        foreach (e; w.getAllAt(pos)
                     .map!(id => Ent(id, w.store.get!SupportsWeight(id)))
                     .filter!(e => e.sw !is null &&
                                   (e.sw.type & SupportType.within) &&
                                   agentSupportedBy(e.sw)))
        {
            auto rc = dg(e.id, e.sw);
            if (rc)
                return rc;
        }
    }

    return 0;
}

/**
 * Returns: true if the agent can move in the given direction, given the
 * current agent state; false otherwise.
 *
 * Note: This function does NOT check for obstacles, merely whether the agent
 * itself can move.
 */
bool canAgentMove(World w, ThingId agentId, Vec!(int,4) displacement)
{
    if (displacement.rectNorm != 1)
        return false; // TBD: check leaping ability

    auto p = w.store.get!Pos(agentId);
    if (p is null)
        return false;

    auto curPos = *p;
    auto cm = w.store.get!CanMove(agentId);
    if (cm is null)
        return false;

    // Vertical movement
    if (displacement == vec(1,0,0,0) || displacement == vec(-1,0,0,0))
    {
        // Check if on floor and can jump.
        if (foreachSupport(w, agentId, SupportType.above, (id, sw) {
                // Note: check for climbing is necessary for SupportType.above
                // because ladders do support from below, otherwise agent will
                // get stuck on the top of a ladder!
                if (sw.cond == SupportCond.climbing &&
                    (cm.types & CanMove.Type.climb))
                {
                    return 1;
                }
                if (sw.cond == SupportCond.always &&
                    (cm.types & CanMove.Type.jump))
                {
                    return 1;
                }
                return 0;
            }))
        {
            return true;
        }

        // Check if on ladder and can climb, or in water and can swim.
        if (foreachSupport(w, agentId, SupportType.within, (id, sw) {
                if (sw.cond == SupportCond.climbing &&
                    (cm.types & CanMove.Type.climb))
                {
                    return 1;
                }
                if (sw.cond == SupportCond.buoyant &&
                    (cm.types & CanMove.Type.swim))
                {
                    return 1;
                }
                return 0;
            }))
        {
            return true;
        }
    }
    else
    {
        // Horizontal movement: check if on floor and have walk/run ability, or
        // in water and can swim.
        if (foreachSupport(w, agentId, SupportType.above, (id, sw) {
                if ((sw.cond == SupportCond.always ||
                     sw.cond == SupportCond.climbing) &&
                    (cm.types & CanMove.Type.walk))
                {
                    return 1;
                }
                return 0;
            }))
        {
            return true;
        }
        if (foreachSupport(w, agentId, SupportType.within, (id, sw) {
                if (sw.cond == SupportCond.buoyant &&
                    (cm.types & CanMove.Type.swim))
                {
                    return 1;
                }
                return 0;
            }))
        {
            return true;
        }
    }

    return false;
}

unittest
{
    // Test environment:
    //   01234567
    // 0 ########
    // 1 #  #   #
    // 2 # _-_  #
    // 3 # =#=  #
    // 4 ####=~~#
    // 5 ####=~~#
    // 6 ########
    import gamemap;
    auto root = new MapNode;
    root.axis = 1;
    root.pivot = 4;

    root.left = new MapNode;
    root.left.interior = region(vec(1,1,0,0), vec(4,3,1,1));
    root.left.doors = [ Door(1, [3,2,0,0]) ];

    root.right = new MapNode;
    root.right.interior = region(vec(1,4,0,0), vec(6,7,1,1));
    root.right.doors = [ Door(1, [3,2,0,0]) ];

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(0,0,0,0), vec(8,7,2,2));
    w.map.waterLevel = 4;

    import terrain : createLadder;
    createLadder(&w.store, Pos(3,2,0,0));
    createLadder(&w.store, Pos(3,4,0,0));
    createLadder(&w.store, Pos(4,4,0,0));
    createLadder(&w.store, Pos(5,4,0,0));

    auto walker = w.store.createObj(Name("ходящий"),
                                    CanMove(CanMove.Type.walk));
    auto climber = w.store.createObj(Name("лазящий"),
                                     CanMove(CanMove.Type.climb));
    auto jumper = w.store.createObj(Name("прыгающий"),
                                    CanMove(CanMove.Type.jump));
    auto swimmer = w.store.createObj(Name("плавающий"),
                                    CanMove(CanMove.Type.swim));

    // Walker tests
    w.store.add!Pos(walker, Pos(3,1,0,0)); // on floor
    assert( canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    w.store.add!Pos(walker, Pos(3,2,0,0)); // bottom of ladder
    assert( canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    w.store.add!Pos(walker, Pos(2,2,0,0)); // top of ladder
    assert(!canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    w.store.add!Pos(walker, Pos(2,3,0,0)); // in doorway
    assert( canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    w.store.add!Pos(walker, Pos(4,5,0,0)); // floating in water
    assert(!canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    w.store.add!Pos(walker, Pos(5,5,0,0)); // on floor in water
    assert( canAgentMove(w, walker.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, walker.id, vec(1,0,0,0)));
    assert(!canAgentMove(w, walker.id, vec(-1,0,0,0)));

    // Climber tests
    w.store.add!Pos(climber, Pos(3,1,0,0)); // on floor
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, climber.id, vec(1,0,0,0)));

    w.store.add!Pos(climber, Pos(3,2,0,0)); // bottom of ladder
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert( canAgentMove(w, climber.id, vec(1,0,0,0)));

    w.store.add!Pos(climber, Pos(2,2,0,0)); // top of ladder
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert( canAgentMove(w, climber.id, vec(1,0,0,0)));

    w.store.add!Pos(climber, Pos(4,4,0,0)); // on ladder in water
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert( canAgentMove(w, climber.id, vec(1,0,0,0)));

    w.store.add!Pos(climber, Pos(5,4,0,0)); // bottom of ladder in water
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert( canAgentMove(w, climber.id, vec(1,0,0,0)));

    w.store.add!Pos(climber, Pos(4,5,0,0)); // in water
    assert(!canAgentMove(w, climber.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, climber.id, vec(1,0,0,0)));

    // Jumper tests
    w.store.add!Pos(jumper, Pos(3,1,0,0)); // on floor
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert( canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    w.store.add!Pos(jumper, Pos(2,1,0,0)); // in midair
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    w.store.add!Pos(jumper, Pos(3,2,0,0)); // bottom of ladder
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert( canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    w.store.add!Pos(jumper, Pos(2,2,0,0)); // top of ladder
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    w.store.add!Pos(jumper, Pos(5,5,0,0)); // on floor in water
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert( canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    w.store.add!Pos(jumper, Pos(4,5,0,0)); // in water
    assert(!canAgentMove(w, jumper.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, jumper.id, vec(-1,0,0,0)));

    // Swimmer tests
    w.store.add!Pos(swimmer, Pos(3,1,0,0)); // on floor
    assert(!canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(3,2,0,0)); // bottom of ladder
    assert(!canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(2,2,0,0)); // top of ladder
    assert(!canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(4,5,0,0)); // in water
    assert( canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert( canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(5,5,0,0)); // on floor in water
    assert( canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert( canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(4,4,0,0)); // on ladder in water
    assert( canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert( canAgentMove(w, swimmer.id, vec(-1,0,0,0)));

    w.store.add!Pos(swimmer, Pos(3,4,0,0)); // on ladder above water
    assert(!canAgentMove(w, swimmer.id, vec(0,1,0,0)));
    assert(!canAgentMove(w, swimmer.id, vec(-1,0,0,0)));
}

/**
 * Check if movement from the given location by the given displacement would be
 * blocked.
 */
bool canMove(World w, Vec!(int,4) pos, Vec!(int,4) displacement)
{
    auto newPos = Pos(pos + displacement);
    return !w.getAllAt(newPos)
             .canFind!(id => w.store.get!BlocksMovement(id) !is null);
}

/**
 * Check if moving in the given displacement from the given location qualifies
 * as a climb-ledge action.
 */
bool canClimbLedge(World w, Vec!(int,4) pos, Vec!(int,4) displacement)
{
    auto newPos = Pos(pos + displacement);

    // Only single-tile horizontal moves qualify for climb-ledges.
    if (displacement[0] != 0 || displacement.rectNorm != 1)
        return false;

    // Destination tile must block movement, but be climbable.
    if (!w.getAllAt(newPos)
          .canFind!((id) {
             auto bm = w.store.get!BlocksMovement(id);
             return bm !is null && bm.climbable == Climbable.yes;
          }))
        return false;

    // Tiles above current position and target position must not block
    // movement.
    return !w.getAllAt(Pos(pos + vec(-1,0,0,0)))
             .canFind!(id => w.store.get!BlocksMovement(id) !is null) &&
           !w.getAllAt(Pos(newPos + vec(-1,0,0,0)))
             .canFind!(id => w.store.get!BlocksMovement(id) !is null);
}

/**
 * Moves an object from its current location to a new location.
 */
ActionResult move(World w, Thing* subj, Vec!(int,4) displacement)
{
    auto oldPos = *w.store.get!Pos(subj.id);
    auto newPos = Pos(oldPos.coors + displacement);

    if (!canMove(w, oldPos, displacement))
    {
        if (canClimbLedge(w, oldPos, displacement))
        {
            auto medPos = Pos(oldPos + vec(-1,0,0,0));
            rawMove(w, subj, medPos, {
                w.notify.move(MoveType.climbLedge, oldPos, subj.id, medPos, 0);
            });

            newPos = Pos(newPos + vec(-1,0,0,0));
            rawMove(w, subj, newPos, {
                w.notify.move(MoveType.climbLedge, medPos, subj.id, newPos, 1);
            });

            return ActionResult(true, 15);
        }
        else
            return ActionResult(false, 10, "You bump into a wall!"); // FIXME
    }
    else
    {
        rawMove(w, subj, newPos, {
            // FIXME: differentiate between walk, jump, climb.
            if (displacement == vec(1,0,0,0) || displacement == vec(-1,0,0,0))
                w.notify.move(MoveType.climb, oldPos, subj.id, newPos, 0);
            else
                w.notify.move(MoveType.walk, oldPos, subj.id, newPos, 0);
        });
    }

    return ActionResult(true, 10);
}

/**
 * Pickup an object from the subject's location.
 */
ActionResult pickupItem(World w, Thing* subj, ThingId objId)
{
    auto subjPos = w.store.get!Pos(subj.id);
    auto objPos = w.store.get!Pos(objId);
    auto inven = w.store.get!Inventory(subj.id);

    if (inven is null)
        return ActionResult(false, 10, "You can't carry anything!");

    // TBD: pos check should be canReach(subj,obj).
    if (subjPos is null || objPos is null || *subjPos != *objPos)
        return ActionResult(false, 10, "You can't reach that object!");

    if (w.store.get!Pickable(objId) is null)
        return ActionResult(false, 10, "You can't pick that up!");

    auto obj = w.store.getObj(objId);
    w.store.remove!Pos(obj);
    inven.contents ~= objId;
    w.notify.itemAct(ItemActType.pickup, *subjPos, subj.id, objId);

    return ActionResult(true, 10);
}

/**
 * Use an item.
 */
ActionResult useItem(World w, Thing* subj, ThingId objId)
{
    auto u = w.store.get!Usable(objId);
    if (u is null)
        return ActionResult(false, 10, "Can't figure out how to use this "~
                                       "object.");

    final switch (u.effect)
    {
        case UseEffect.portal:
            // Experimental
            w.store.add!UsePortal(subj, UsePortal());
            return ActionResult(true, 10);
    }
}

/**
 * Pass a turn.
 */
ActionResult pass(World w, Thing* subj)
{
    auto pos = *w.store.get!Pos(subj.id);
    w.notify.pass(pos, subj.id);
    return ActionResult(true, 10);
}

/**
 * Attack a Mortal.
 *
 * BUGS: weaponId is currently unused.
 */
ActionResult attack(World w, Thing* subj, ThingId objId, ThingId weaponId)
{
    auto pos = w.store.get!Pos(subj.id);
    auto targetPos = w.store.get!Pos(objId);
    if (pos is null || targetPos is null)
        return ActionResult(false, 10, "You attack thin air!");

    /*if (!weapon.canReach(obj))*/
    if (rectNorm(*targetPos - *pos) > 1)
        return ActionResult(false, 10, "You're unable to reach that far!");

    // TBD: damage should be determined by weapon
    import damage;
    w.notify.damage(DmgType.attack, *pos, subj.id, objId, weaponId);
    w.injure(subj.id, objId, weaponId, 1 /*FIXME*/);

    return ActionResult(true, 10);
}

// vim:set ai sw=4 ts=4 et:
