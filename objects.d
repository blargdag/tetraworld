/**
 * Standard object creation functions.
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
module objects;

import components;
import store;
import vector;

Thing* createRockTrapTrig(Store* store, Vec!(int,4) trigPos, ulong triggerId)
{
    return store.createObj(Pos(trigPos),
                           Trigger(Trigger.Type.onWeight, triggerId, 500));
}

Thing* createRockTrap(Store* store, Vec!(int,4) ceilingPos, ulong triggerId)
{
    return store.createObj(Pos(ceilingPos),
                           Triggerable(triggerId, TriggerEffect.rockTrap));
}

Thing* createPortal(Store* store, Vec!(int,4) pos, string dest="")
{
    return store.createObj(Pos(pos), Tiled(TileId.portal), Name("exit portal"),
                           Usable(UseEffect.portal, "activate"), Weight(1));
}

// vim:set ai sw=4 ts=4 et:
