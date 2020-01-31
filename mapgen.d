/**
 * Map generation module.
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
module mapgen;

import std.algorithm;
import std.math : abs;
import std.random : uniform;
import std.range;

import bsp;
import components;
import gamemap;
import rndutil;
import vector;
import world;

// FIXME: this should go into its own mapgen module.
World genNewGame(int[4] dim, out int[4] startPos)
{
    auto w = new World;
    w.map.bounds = region(vec(0, 0, 0, 0), vec(dim));

    alias R = Region!(int,4);
    w.map.tree = genBsp!MapNode(w.map.bounds,
        (R r) => r.volume > 24 + uniform(0, 80),
        (R r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                        .pickOne(invalidAxis),
        (R r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
            invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
    );
    genCorridors(w.map.tree, w.map.bounds);

    // Regular back edges.
    genBackEdges(w.map.tree, w.map.bounds, uniform(3, 5), 15);

    // Pit traps.
    genBackEdges(w.map.tree, w.map.bounds, uniform(8, 12), 20,
        (in MapNode[2] rooms, ref Door d) {
            assert(d.axis == 0);

            bool nextToExisting;
            foreach (rm; rooms)
            {
                foreach (dd; rm.doors)
                {
                    if (dd.type == Door.Type.normal &&
                        iota(4).map!(i => abs(d.pos[i] - dd.pos[i])).sum == 1)
                    {
                        nextToExisting = true;
                    }

                    if (dd.axis != 0 &&
                        iota(1, 4).map!(i => abs(d.pos[i] - dd.pos[i]))
                                  .sum == 1)
                    {
                        // Don't place where a ladder would be placed.
                        return false;
                    }
                }
            }

            if (!nextToExisting && uniform(0, 100) < 30)
            {
                // Non-hidden open pit.
                d.type = Door.Type.extra;
            }
            else
            {
                d.type = Door.Type.trapdoor;
                w.store.createObj(Pos(d.pos), Name("pit trap"),
                    Tiled(TileId.wall), PitTrap(), NoGravity());
            }
            return true;
        },
        (MapNode node, Region!(int,4) bounds) => 0, // always pick vertical
        true,   // allow multiple pit traps on same wall as normal door
    );

    resizeRooms(w.map.tree, w.map.bounds);
    setRoomFloors(w.map.tree, w.map.bounds);

    randomRoom(w.map.tree, w.map.bounds, (MapNode node, R r) {
        w.map.waterLevel = uniform(r.max[0], w.map.bounds.max[0]+1);
    });

    Vec!(int,4) randomDryPos(MapNode node, Region!(int,4) bounds)
    {
        auto dryRegion = bounds;
        dryRegion.max[0] = w.map.waterLevel - 1;

        MapNode dryRoom;
        Region!(int,4) dryBounds;
        int n = 0;
        foreachFiltRoom(node, bounds, dryRegion,
            (MapNode node, Region!(int,4) r) {
                if (r.max[0] > w.map.waterLevel)
                    return 0; // reject partially-submerged rooms

                if (n == 0 || uniform(0, n) == 0)
                {
                    dryRoom = node;
                    dryBounds = r;
                }
                n++;
                return 0;
            }
        );
        assert(dryRoom !is null);
        return dryRoom.randomLocation(dryBounds);
    }

    w.store.createObj(Pos(randomDryPos(w.map.tree, w.map.bounds)),
                      Tiled(TileId.portal), Name("exit portal"),
                      Usable(UseEffect.portal));

    startPos = randomDryPos(w.map.tree, w.map.bounds);

    int floorArea(MapNode node)
    {
        return node.isLeaf ? node.interior.volume
                           : floorArea(node.left) + floorArea(node.right);
    }

    enum goldPct = 0.2;
    auto ngold = cast(int)(floorArea(w.map.tree) * goldPct / 100);

    foreach (i; 0 .. ngold)
    {
        w.store.createObj(Pos(randomLocation(w.map.tree, w.map.bounds)),
                          Tiled(TileId.gold), Name("gold"), Pickable());
    }

    foreach (i; 0 .. uniform(4, 6))
    {
        w.store.createObj(Pos(randomLocation(w.map.tree, w.map.bounds)),
                          Tiled(TileId.creatureA, 1), Name("conical creature"),
                          BlocksMovement(), Agent(), Mortal(5,2));
    }

    return w;
}

// Mapgen sanity tests.
unittest
{
    foreach (i; 0 .. 12)
    {
        int[4] startPos;
        auto w = genNewGame([ 10, 10, 10, 10 ], startPos);

        // Door placement checks.
        foreachRoom(w.map.tree, w.map.bounds,
            (Region!(int,4) region, MapNode node) {
                foreach (i; 0 .. node.doors.length-1)
                {
                    auto d1 = node.doors[i];
                    auto pos1 = d1.pos;
                    foreach (j; i+1 .. node.doors.length)
                    {
                        auto d2 = node.doors[j];
                        auto pos2 = d2.pos;

                        // No coincident doors.
                        assert(pos1 != pos2);

                        // Only trapdoors/pits are allowed to be adjacent to
                        // another door.
                        if (iota(4).map!(i => abs(pos1[i] - pos2[i])).sum == 1)
                        {
                            assert(d1.type != Door.Type.normal ||
                                   d2.type != Door.Type.normal);
                        }
                    }

                    // Trapdoors & pits not allowed where ladders would be
                    // placed.
                    if (d1.type != Door.Type.normal)
                    {
                        foreach (j; 0 .. node.doors.length)
                        {
                            auto d2 = node.doors[j];
                            auto pos2 = d2.pos;

                            if (i == j || d2.axis == 0)
                                continue;

                            assert(iota(1,4).map!(i => abs(pos1[i] - pos2[i]))
                                            .sum != 1);
                        }
                    }
                }
                return 0;
            }
        );

        // Water level tests.
        import std.format : format;
        assert(startPos[0] < w.map.waterLevel,
               format("startPos %s below water level %d", startPos,
                      w.map.waterLevel));
        foreach (pos; w.store.getAll!Usable()
                       .filter!(id => w.store.get!Usable(id).effect ==
                                      UseEffect.portal)
                       .map!(id => w.store.get!Pos(id))
                       .filter!(posp => posp !is null)
                       .map!(posp => *posp))
        {
            assert(pos[0] < w.map.waterLevel,
                   format("Portal %s below water level %d", pos,
                          w.map.waterLevel));
        }
    }
}

// vim:set ai sw=4 ts=4 et:
