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

/**
 * Returns: The total interior volumes of the rooms in the given BSP tree.
 *
 * BUGS: This function is either misnamed, or wrongly implemented. It returns
 * the total interior *volume* of the map, not its *floor* area!
 */
int floorArea(MapNode node)
{
    return node.isLeaf ? node.interior.volume
                       : floorArea(node.left) + floorArea(node.right);
}

/**
 * Generate corridors based on BSP tree structure.
 */
void genCorridors(R)(MapNode root, R region)
    if (is(R == Region!(int,n), size_t n))
{
    if (root.isLeaf) return;

    genCorridors(root.left, leftRegion(region, root.axis, root.pivot));
    genCorridors(root.right, rightRegion(region, root.axis, root.pivot));

    static struct LeftRoom
    {
        MapNode node;
        R region;
    }

    LeftRoom[] leftRooms;
    root.left.foreachFiltRoom(region,
        (R r) => r.max[root.axis] >= root.pivot,
        (MapNode node1, R r1) {
            leftRooms ~= LeftRoom(node1, r1);
            return 0;
        });

    int ntries=0;
    while (ntries++ < 2*leftRooms.length)
    {
        import rndutil : pickOne;
        auto leftRoom = leftRooms.pickOne;
        R wallFilt = leftRoom.region;
        wallFilt.min[root.axis] = root.pivot;
        wallFilt.max[root.axis] = root.pivot;

        static struct RightRoom
        {
            MapNode node;
            R region;
            int[4] basePos;
        }

        RightRoom[] rightRooms;
        root.right.foreachFiltRoom(region, wallFilt,
            (MapNode node2, R r2) {
                auto ir = leftRoom.region.intersect(r2);

                int[4] basePos;
                foreach (i; 0 .. 4)
                {
                    import std.random : uniform;
                    if (ir.max[i] - ir.min[i] >= 3)
                        basePos[i] = uniform(ir.min[i]+1, ir.max[i]-1);
                    else
                    {
                        // Overlap is too small to place a door, skip.
//import std.stdio;writefln("left=%s right=%s TOO NARROW, SKIPPING", leftRoom.region, r2);
                        return 0;
                    }
                }

                rightRooms ~= RightRoom(node2, r2, basePos);
                return 0;
            });

        // If can't find a suitable door placement, try picking a different
        // left room.
        if (rightRooms.empty)
        {
//import std.stdio;writefln("left=%s NO MATCH, SKIPPING", leftRoom.region);
            continue;
        }

        auto rightRoom = rightRooms.pickOne;
        auto d = Door(root.axis);

        d.pos = rightRoom.basePos;
        d.pos[d.axis] = root.pivot;
        leftRoom.node.doors ~= d;

        //d.pos = rightRoom.basePos;
        //d.pos[d.axis] = root.pivot;
        rightRoom.node.doors ~= d;
        return;
    }

    // If we got here, it means we're in trouble.
    throw new Exception("No matching door placement found, give up");
}

/**
 * Insert additional doors to randomly-picked rooms outside of the BSP
 * connectivity structure, so that non-trivial topology is generated.
 *
 * Params:
 *  root = Root of BSP tree.
 *  region = Initial bounding region.
 *  count = Number of additional doors to insert.
 *  maxRetries = Maximum number of failures while looking for a room pair that
 *      can accomodate an extra door. This is to prevent infinite loops in case
 *      the given tree cannot accomodate another `count` doors.
 *  doorFilter = An optional delegate that accepts or rejects a door, and
 *      optionally marks it up in some way, e.g., with an .extra flag set, or
 *      some randomized door type. The delegate is passed the room nodes that
 *      it will connect. Returns: true if the door should be added, false
 *      otherwise. Note that returning false will count towards the number of
 *      failed attempts.
 *  pickAxis = An optional delegate that selects which axis to use for finding
 *      potential back-edges.
 *  allowMultiple = Whether or not to allow multiple doors on the same wall.
 *      Default: false.
 */
void genBackEdges(R)(MapNode root, R region, int count, int maxRetries = 15)
{
    import std.random : uniform;
    genBackEdges(root, region, count, maxRetries,
                 (in MapNode[2], ref Door) => true,
                 (MapNode node, R bounds) => uniform(0, 4),
                 false);
}

/// ditto
void genBackEdges(R)(MapNode root, R region, int count, int maxRetries,
                     bool delegate(in MapNode[2] node, ref Door) doorFilter,
                     int delegate(MapNode, R) pickAxis,
                     bool allowMultiple)
{
    import std.random : uniform;
    import rndutil : pickOne;
    do
    {
        static struct RightRoom
        {
            MapNode node;
            R region;
            int[4] basePos;
        }

        auto success = root.randomRoom(region, (MapNode node, R bounds) {
            // Randomly select a wall of the room.
            R wallFilt = bounds;
            auto axis = pickAxis(node, bounds);
            if (axis == invalidAxis)
                return false;
            wallFilt.min[axis] = wallFilt.max[axis]; 

            // Find an adjacent room that can be joined to this one via a door.
            RightRoom[] targets;
            root.foreachFiltRoom(region, wallFilt, (MapNode node2, R r2) {
                import std.algorithm : canFind, filter, fold;
                import std.range : iota;

                auto ir = bounds.intersect(r2);

                // Check that there isn't already a door between these two
                // rooms.
                if (!allowMultiple && node.doors.canFind!(d =>
                        iota(4).fold!((b,i) => b && ir.min[i] <= d.pos[i] &&
                                               d.pos[i] <= ir.max[i])(true)))
                    return 0;

                int[4] basePos;
                foreach (i; 0 .. 4)
                {
                    if (ir.max[i] - ir.min[i] >= 3)
                        basePos[i] = uniform(ir.min[i]+1, ir.max[i]-1);
                    else if (i == axis)
                        basePos[i] = ir.max[i];
                    else
                    {
                        // Overlap is too small to place a door, skip.
                        return 0;
                    }
                }

                // Avoid coincident doors
                if (node.doors.canFind!(d => d.pos == basePos))
                    return 0;

                targets ~= RightRoom(node2, r2, basePos);
                return 0;
            });

            if (targets.empty)
                return false; // couldn't match anything for this room

            auto rightRoom = targets.pickOne;

            auto d = Door(axis);
            d.pos = rightRoom.basePos;
            if (!doorFilter([node, rightRoom.node], d))
                return false;

            node.doors ~= d;
            rightRoom.node.doors ~= d;

            return true;
        });

        if (success)
            count--;
        else
            maxRetries--;
    } while (count > 0 && maxRetries > 0);
}

/**
 * Iterate over leaf nodes in the given BSP tree and assign room interiors with
 * random sizes.
 *
 * Prerequisites: Doors must have already been computed, since minimum room
 * interior regions are computed based on the position of doors.
 */
void resizeRooms(R)(MapNode root, R region)
    if (is(R == Region!(int,n), size_t n))
{
    foreachRoom(root, region, (R bounds, MapNode node) {
        import std.random : uniform;

        // Find minimum region room must cover in order for exits to connect.
        auto core = R(bounds.max, bounds.min);
        foreach (d; node.doors)
        {
            foreach (i; 0 .. 4)
            {
                if (i == d.axis)
                {
                    if (core.min[i] > d.pos[i])
                        core.min[i] = d.pos[i];
                    if (core.max[i] < d.pos[i])
                        core.max[i] = d.pos[i];
                }
                else
                {
                    if (core.min[i] > d.pos[i] - 1)
                        core.min[i] = d.pos[i] - 1;
                    if (core.max[i] < d.pos[i] + 1)
                        core.max[i] = d.pos[i] + 1;
                }
            }
        }

        // Expand minimum region to be at least 3 tiles wide in each direction.
        foreach (i; 0 .. 4)
        {
            if (bounds.length(i) < 3)
                continue;   // FIXME: should be an error

            while (core.length(i) < 3)
            {
                if (uniform(0, 2) == 0)
                {
                    if (bounds.min[i] < core.min[i])
                        core.min[i]--;
                }
                else
                {
                    if (core.max[i] < bounds.max[i])
                        core.max[i]++;
                }
            }
        }

        // Select random size between bounding region and minimum region.
        foreach (i; 0 .. 4)
        {
            node.interior.min[i] = uniform!"[]"(bounds.min[i], core.min[i]);
            node.interior.max[i] = uniform!"[]"(core.max[i], bounds.max[i]);
        }

        return 0;
    });
}

/**
 * Randomly assign room floors.
 */
void setRoomFloors(R)(MapNode root, R bounds)
    if (is(R == Region!(int,n), size_t n))
{
    foreachRoom(root, bounds, (R r, MapNode node) {
        import std.random : uniform;
        auto x = uniform(0, 100);
        node.style = (x < 50) ? FloorStyle.bare :
                     (x < 80) ? FloorStyle.grassy :
                                FloorStyle.muddy;
        return 0;
    });
}

unittest
{
    import testutil;
    enum w = 48, h = 24;
    auto result = TestScreen!(w,h)();

    import std.algorithm : filter, clamp;
    import std.random : uniform;
    import std.range : iota;
    import rndutil;

    // Generate base BSP tree
    auto bounds = region(vec(0, 0, 0, 0), vec(w-1, h-1, 3, 3));
    alias R = typeof(bounds);

    auto tree = genBsp!MapNode(bounds,
        (R r) => r.length(0)*r.length(1) > 49 + uniform(0, 50),
        (R r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                        .pickOne(invalidAxis),
        (R r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
            invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
            //gaussian(r.max[axis] - r.min[axis], 4)
            //    .clamp(r.min[axis] + 3, r.max[axis] - 3)
    );

    // Generate connecting corridors
    genCorridors(tree, bounds);
    genBackEdges!R(tree, bounds, 4, 15, (in MapNode[2] rooms, ref Door d) {
        d.type = Door.Type.extra;
        return true;
    }, (MapNode node, R region) => uniform(0, 2), false);
    resizeRooms(tree, bounds);
    setRoomFloors(tree, bounds);

    version(none)
    {
        dumpBsp(result, tree, bounds);
        assert(0);
    }
}

/**
 * Returns: A random room in the given BSP tree that's completely above the
 * water level.
 */
MapNode randomDryRoom(World w, out Region!(int,4) dryBounds)
    out(node; node !is null && node.isLeaf())
{
    auto dryRegion = w.map.bounds;
    dryRegion.max[0] = w.map.waterLevel - 1;

    MapNode dryRoom;
    int n = 0;
    foreachFiltRoom(w.map.tree, w.map.bounds, dryRegion,
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
    return dryRoom;
}

/**
 * Returns: A random floor location in the given BSP tree that's above the
 * water level.
 */
Vec!(int,4) randomDryPos(World w)
{
    Region!(int,4) dryBounds;
    auto dryRoom = randomDryRoom(w, dryBounds);
    return dryRoom.randomLocation(dryBounds);
}

/**
 * Generate pits and pit traps.
 */
void genPitTraps(World w)
{
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
                auto floorId = style2Terrain(rooms[1].style);
                w.store.createObj(Pos(d.pos), Name("pit trap"),
                    Tiled(TileId.wall, -1), *w.store.get!TiledAbove(floorId),
                    PitTrap(), NoGravity());
            }
            return true;
        },
        (MapNode node, Region!(int,4) bounds) => 0, // always pick vertical
        true,   // allow multiple pit traps on same wall as normal door
    );
}

/**
 * Map generation parameters.
 */
struct MapGenArgs
{
    int[4] dim;
}

/**
 * Generate new game world.
 */
World genNewGame(MapGenArgs args, out int[4] startPos)
{
    auto w = new World;
    w.map.bounds = region(vec(0, 0, 0, 0), vec(args.dim));

    alias R = Region!(int,4);
    w.map.tree = genBsp!MapNode(w.map.bounds,
        (R r) => r.volume > 24 + uniform(0, 80),
        (R r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                        .pickOne(invalidAxis),
        (R r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
            invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
    );
    genCorridors(w.map.tree, w.map.bounds);
    setRoomFloors(w.map.tree, w.map.bounds);

    // Add back edges, regular and pits/pit traps.
    genBackEdges(w.map.tree, w.map.bounds, uniform(3, 5), 15);
    genPitTraps(w);

    resizeRooms(w.map.tree, w.map.bounds);

    randomRoom(w.map.tree, w.map.bounds, (MapNode node, R r) {
        w.map.waterLevel = uniform(r.max[0], w.map.bounds.max[0]+1);
    });

    w.store.createObj(Pos(randomDryPos(w)), Tiled(TileId.portal),
                      Name("exit portal"), Usable(UseEffect.portal));

    Region!(int,4) startBounds;
    MapNode startRoom = randomDryRoom(w, startBounds);
    startPos = startRoom.randomLocation(startBounds);

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
                          BlocksMovement(), Agent(), Mortal(5,2), Climbs());
    }

    return w;
}

// Mapgen sanity tests.
unittest
{
    foreach (i; 0 .. 12)
    {
        int[4] startPos;
        MapGenArgs args;
        args.dim = [ 10, 10, 10, 10 ];
        auto w = genNewGame(args, startPos);

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
