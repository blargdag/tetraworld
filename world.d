/**
 * World model.
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
module world;

import std.algorithm;
import std.math;
import std.random : uniform;
import std.range;

import bsp;
import components;
import gamemap;
import loadsave;
import store;
import store_traits;
import terrain;
import vector;

/**
 * Map representation.
 */
struct GameMap
{
    private MapNode tree;
    private alias R = Region!(int,4);
    private R bounds;

    this(int[4] _dim)
    {
        bounds.min = vec(0, 0, 0, 0);
        bounds.max = _dim;

        import rndutil : pickOne;
        tree = genBsp!MapNode(bounds,
            (R r) => r.volume > 24 + uniform(0, 80),
            (R r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                            .pickOne(invalidAxis),
            (R r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
                invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
        );
        genCorridors(tree, bounds);
        resizeRooms(tree, bounds);
        setRoomFloors(tree, bounds);
    }

    @property int opDollar(int i)() { return bounds.max[i]; }

    ThingId opIndex(int[4] pos...)
    {
        import std.math : abs;

        // FIXME: should be a more efficient way to do this
        auto result = blockBare.id;
        foreachFiltRoom(tree, bounds, (R r) => r.contains(vec(pos)),
            (MapNode node, R r) {
                auto rr = node.interior;
                if (iota(4).fold!((b, i) => b && rr.min[i] < pos[i] &&
                                            pos[i] < rr.max[i])(true))
                {
                    // Generate ladders to doors.
                    foreach (d; node.doors.filter!(d => d.type ==
                                                        Door.Type.normal))
                    {
                        // Horizontal doors: add step ladders if too high.
                        import std.math : abs;
                        if (d.axis != 0 && rr.max[0] - d.pos[0] > 2 &&
                            pos[0] > d.pos[0] &&
                            abs(pos[d.axis] - d.pos[d.axis]) == 1 &&
                            iota(1,4).filter!(i => i != d.axis)
                                .fold!((b, i) => b && pos[i] == d.pos[i])
                                      (true))
                        {
                            result = ladder.id;
                            return 1;
                        }

                        // Vertical shafts: add ladder all the way up.
                        if (d.axis == 0 && pos[0] > d.pos[0] &&
                            iota(1,4).fold!((b, i) => b && pos[i] == d.pos[i])
                                           (true))
                        {
                            result = ladder.id;
                            return 1;
                        }
                    }

                    result = emptySpace.id;
                    return 1;
                }

                foreach (d; node.doors)
                {
                    if (pos[] == d.pos && (d.type != Door.Type.trapdoor))
                    {
                        // Normal vertical exits should have ladders that reach
                        // up to the top (in the floor).
                        result = (d.axis == 0 && d.type == Door.Type.normal) ?
                                 ladder.id : doorway.id;
                        return 1;
                    }
                }

                final switch (node.style)
                {
                    case FloorStyle.bare:
                        result = blockBare.id;
                        break;

                    case FloorStyle.grassy:
                        result = blockGrassy.id;
                        break;

                    case FloorStyle.muddy:
                        result = blockMuddy.id;
                        break;
                }
                return 1;
            }
        );
        return result;
    }

    Vec!(int,4) randomLocation()
    {
        return .randomLocation(tree, bounds);
    }
}
static assert(is4DArray!GameMap && is(CellType!GameMap == ThingId));

enum void delegate(Args) doNothing(Args...) = (Args args) {};

/**
 * Set of hooks for external code to react to in-game events.
 */
struct EventWatcher
{
    /**
     * An agent climbs a ledge.
     */
    void delegate(Pos pos, ThingId subj, Pos newPos, int seq) climbLedge =
        doNothing!(Pos, ThingId, Pos, int);

    /**
     * An agent or object moves (not necessarily on their own accord).
     */
    void delegate(Pos pos, ThingId subj, Pos newPos) move =
        doNothing!(Pos, ThingId, Pos);

    /**
     * An object falls down.
     */
    void delegate(Pos pos, ThingId subj, Pos newPos) fall =
        doNothing!(Pos, ThingId, Pos);

    /**
     * An object falls on top of another, possibly causing damage.
     */
    void delegate(Pos pos, ThingId subj, ThingId obj) fallOn =
        doNothing!(Pos, ThingId, ThingId);

    /**
     * An agent picks up an object.
     */
    void delegate(Pos pos, ThingId subj, ThingId obj) pickup =
        doNothing!(Pos, ThingId, ThingId);

    /**
     * An agent triggers an exit portal.
     */
    void delegate(Pos pos, ThingId subj, ThingId portal) usePortal =
        doNothing!(Pos, ThingId, ThingId);

    /**
     * An agent passes a turn.
     */
    void delegate(Pos pos, ThingId subj) pass = doNothing!(Pos, ThingId);

    /**
     * An agent attacks something.
     */
    void delegate(Pos pos, ThingId subj, ThingId obj, ThingId weapon) attack =
        doNothing!(Pos, ThingId, ThingId, ThingId);

    /**
     * A mortal is killed by something.
     */
    void delegate(Pos pos, ThingId killer, ThingId victim) kill =
        doNothing!(Pos, ThingId, ThingId);
}

class World
{
    GameMap map;
    Store store;
    @NoSave EventWatcher notify;

    this()
    {
        registerTerrains(&store);
    }

    /**
     * Returns: An input range of all objects at the specified location,
     * including floor tiles.
     */
    auto getAllAt(Pos pos)
    {
        return store.getAllBy!Pos(Pos(pos))
                    .chain(only(map[pos]));
    }

    /**
     * Returns: true if one or more objects in the given location contains the
     * component Comp; false otherwise.
     */
    bool locationHas(Comp)(Pos pos)
    {
        return !getAllAt(pos).filter!(id => store.get!Comp(id) !is null)
                             .empty;
    }
}

// FIXME: this should go into its own mapgen module.
World genNewGame(int[4] dim)
{
    import components;
    import rndutil;

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

    w.store.createObj(Pos(randomLocation(w.map.tree, w.map.bounds)),
                      Tiled(TileId.portal), Name("exit portal"),
                      Usable(UseEffect.portal));

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

// Door placement checks.
unittest
{
    foreach (i; 0 .. 12)
    {
        auto w = genNewGame([ 10, 10, 10, 10 ]);
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
    }
}

// vim:set ai sw=4 ts=4 et:
