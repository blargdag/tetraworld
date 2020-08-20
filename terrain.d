/**
 * Terrain definitions.
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
module terrain;

import components;
import store;
import store_traits;

Thing emptySpace = Thing(1);
Thing doorway = Thing(2);
Thing lockedDoor = Thing(3);
Thing blockBare = Thing(10);
Thing blockGrassy = Thing(11);
Thing blockMuddy = Thing(12);
Thing water = Thing(20);

Thing* createLadder(Store* store, Pos pos)
{
    return store.createObj(Pos(pos), Tiled(TileId.ladder, -1), Name("ladder"),
        TiledAbove(TileId.ladderTop, -1),
        SupportsWeight(SupportType.above | SupportType.within,
                       SupportCond.climbing));
}

void registerTerrains(Store* store)
{
    store.registerTerrain(emptySpace, Tiled(TileId.space, -2),
                          Name("Thin air"));
    store.registerTerrain(doorway, Tiled(TileId.doorway, -2), Name("door"));
    store.registerTerrain(lockedDoor, Tiled(TileId.lockedDoor, -2),
                          BlocksMovement(), Name("locked door"));

    store.registerTerrain(blockBare, Tiled(TileId.wall, -2), Name("wall"),
                          TiledAbove(TileId.floorBare, -1),
                          BlocksMovement(Climbable.yes), BlocksView(),
                          SupportsWeight(SupportType.above |
                                         SupportType.within));

    store.registerTerrain(blockGrassy, Tiled(TileId.wall, -2), Name("wall"),
                          TiledAbove(TileId.floorGrassy, -1),
                          BlocksMovement(Climbable.yes), BlocksView(),
                          SupportsWeight(SupportType.above |
                                         SupportType.within));

    store.registerTerrain(blockMuddy, Tiled(TileId.wall, -2), Name("wall"),
                          TiledAbove(TileId.floorMuddy, -1),
                          BlocksMovement(Climbable.yes), BlocksView(),
                          SupportsWeight(SupportType.above |
                                         SupportType.within));

    store.registerTerrain(water, Tiled(TileId.water, -2),
                          SupportsWeight(SupportType.within,
                                         SupportCond.buoyant),
                          Name("water"));
}

unittest
{
    Store store;
    registerTerrains(&store);

    // Yeah, this started out as a very simple idea, but exploded into one
    // fiendish mess!  It's great that it's *possible* to do this; it's not so
    // great that *this* is what it takes to do it!!
    static foreach (name; __traits(allMembers, mixin(__MODULE__)))
    {
        static if (is(typeof(__traits(getMember, mixin(__MODULE__), name)) ==
                      Thing))
        {
            assert(store.getObj(__traits(getMember, mixin(__MODULE__),
                                         name).id) ==
                   &__traits(getMember, mixin(__MODULE__), name));
        }
    }
}

// vim:set ai sw=4 ts=4 et:
