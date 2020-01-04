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
    auto newPos = oldPos.coors + displacement;

    if (w.map[newPos].ch == '/')
        return ActionResult(false, "Your way is blocked.");

    w.store.remove!Pos(subj);
    w.store.add!Pos(subj, Pos(newPos));

    return ActionResult(true);
}

// vim:set ai sw=4 ts=4 et:
