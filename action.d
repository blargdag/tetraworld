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

            w.notify.pickup(newPos, subj.id, t.id);
        }
    }
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
bool canClimb(World w, Vec!(int,4) pos, Vec!(int,4) displacement)
{
    // Note that BlocksMovement is not sufficient for climbability; the target
    // tile must also have SupportsWeight. This is to prevent the player from
    // climbing on top of creatures. :-D
    auto newPos = Pos(pos + displacement);
    return displacement != vec(1,0,0,0) &&
           w.getAllAt(newPos)
            .canFind!(id => w.store.get!SupportsWeight(id) !is null) &&
           !w.getAllAt(Pos(pos + vec(-1,0,0,0)))
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
        if (canClimb(w, oldPos, displacement))
        {
            auto medPos = Pos(oldPos + vec(-1,0,0,0));
            rawMove(w, subj, medPos, {
                w.notify.climbLedge(oldPos, subj.id, medPos, 0);
            });

            newPos = Pos(newPos + vec(-1,0,0,0));
            rawMove(w, subj, newPos, {
                w.notify.climbLedge(medPos, subj.id, newPos, 1);
            });

            return ActionResult(true, 15);
        }
        else
            return ActionResult(false, 10, "You bump into a wall!"); // FIXME
    }
    else
    {
        rawMove(w, subj, newPos, {
            w.notify.move(oldPos, subj.id, newPos);
        });
    }

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
    w.store.add!Injury(w.store.getObj(objId), Injury(subj.id, weaponId, 1));
    w.notify.attack(*pos, subj.id, objId, weaponId);

    return ActionResult(true, 10);
}

// vim:set ai sw=4 ts=4 et:
