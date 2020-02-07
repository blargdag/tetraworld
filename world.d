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
    private alias R = Region!(int,4);

    MapNode tree;
    R bounds;

    int waterLevel;

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

                    if (pos[0] > waterLevel)
                        result = water.id;
                    else
                        result = emptySpace.id;
                    return 1;
                }

                foreach (d; node.doors)
                {
                    if (pos[] == d.pos)
                    {
                        // Normal vertical exits should have ladders that reach
                        // up to the top (in the floor).
                        result = (d.axis == 0 && d.type == Door.Type.normal) ?
                                 ladder.id :
                                 (pos[0] > waterLevel) ? water.id : doorway.id;
                        return 1;
                    }
                }

                result = style2Terrain(node.style);
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

    /**
     * A message is emitted by a Message object.
     */
    void delegate(Pos pos, ThingId subj, string msg) message =
        doNothing!(Pos, ThingId, string);
}

/**
 * The game world.
 */
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

// vim:set ai sw=4 ts=4 et:
