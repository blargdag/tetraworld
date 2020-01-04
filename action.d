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
import world;
import vector;

struct ActionResult
{
    bool success;
    alias success this;

    string failureMsg;
}

/**
 * Moves an object from its current location to a new location.
 */
ActionResult move(World w, Thing* subj, Vec!(int,4) displacement)
{
    auto oldPos = w.store.get!Pos(subj.id);
    auto newPos = Pos(oldPos.coors + displacement);

    if (w.map[newPos].ch == '/')
        return ActionResult(false, "Your way is blocked.");

    w.store.remove!Pos(subj);
    w.store.add!Pos(subj, newPos);

    auto inven = w.store.get!Inventory(subj.id);
    if (inven != null)
    {
        foreach (t; w.store.getAllBy!Pos(newPos)
                           .map!(id => w.store.getObj(id))
                           .filter!(t => w.store.get!Pickable(t.id) !is null))
        {
            w.store.remove!Pos(t);
            inven.contents ~= t.id;
        }
    }

    return ActionResult(true);
}

/**
 * Activate an object on the floor.
 */
ActionResult applyFloor(World w, Thing* subj)
{
    import std.algorithm : map, filter;

    auto pos = *w.store.get!Pos(subj.id);
    auto r = w.store.getAllBy!Pos(pos)
                    .map!(id => w.store.get!Usable(id))
                    .filter!(u => u !is null);
    if (r.empty)
        return ActionResult(false, "Nothing to apply here.");

    final switch (r.front.effect)
    {
        case UseEffect.portal:
            // Experimental
            w.store.add!UsePortal(subj, UsePortal());
            return ActionResult(true);
    }
}

// vim:set ai sw=4 ts=4 et:
