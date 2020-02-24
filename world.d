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
                if (node.interior.contains(vec(pos)))
                {
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
                        result = (pos[0] > waterLevel) ? water.id : doorway.id;
                        return 1;
                    }
                }

                result = style2Terrain(node.style);
                return 1;
            }
        );
        return result;
    }

    unittest
    {
        GameMap map;
        map.tree = new MapNode();
        map.tree.interior = region(vec(1,1,1,1), vec(2,2,2,2));
        map.bounds = region(vec(0,0,0,0), vec(3,3,3,3));
        map.waterLevel = int.max;

        assert(map[0,0,0,0] == blockBare.id);
        assert(map[1,1,1,1] == emptySpace.id);
        assert(map[2,2,2,2] == blockBare.id);
        assert(map[3,3,3,3] == blockBare.id);
    }
}
static assert(is4DArray!GameMap && is(CellType!GameMap == ThingId));

enum void delegate(Args) doNothing(Args...) = (Args args) {};

/**
 * Type of movement event.
 */
enum MoveType
{
    walk, jump, climb, climbLedge, fall, fallAside, sink,
}

/**
 * Type of item interaction event.
 */
enum ItemActType
{
    pickup, drop, use,
}

/**
 * Type of damage event.
 */
enum DmgType
{
    attack, fallOn, kill,
}

/**
 * Set of hooks for external code to react to in-game events.
 */
struct EventWatcher
{
    /**
     * An agent moves.
     */
    void delegate(MoveType type, Pos oldPos, ThingId subj, Pos newPos, int seq)
        move = doNothing!(MoveType, Pos, ThingId, Pos, int);

    /**
     * An agent interacts with an object.
     */
    void delegate(ItemActType type, Pos pos, ThingId subj, ThingId obj)
        itemAct = doNothing!(ItemActType, Pos, ThingId, ThingId);

    /**
     * An agent passes a turn.
     */
    void delegate(Pos pos, ThingId subj) pass = doNothing!(Pos, ThingId);

    /**
     * An object damages another object.
     */
    void delegate(DmgType type, Pos pos, ThingId subj, ThingId obj,
                  ThingId weapon) damage =
        doNothing!(DmgType, Pos, ThingId, ThingId, ThingId);

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

    void load(L)(ref L loadfile)
        if (isLoadFile!L)
    {
        map = loadfile.parse!GameMap("map");

        // This needs to be done explicitly because we need to copy over
        // registered terrains from World's initial state.
        if (!loadfile.checkAndEnterBlock("store"))
            throw new Exception("Missing 'store' block");

        store.load(loadfile);

        if (!loadfile.checkAndLeaveBlock())
            throw new Exception("'store' block not closed");
    }
}

// vim:set ai sw=4 ts=4 et:
