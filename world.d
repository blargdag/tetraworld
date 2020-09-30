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
                    if (pos[0] >= waterLevel)
                        result = water.id;
                    else
                        result = emptySpace.id;
                    return 1;
                }

                foreach (d; node.doors)
                {
                    if (pos[] == d.pos)
                    {
                        result = (pos[0] >= waterLevel) ? water.id
                                                        : doorway.id;
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
 * Event category.
 */
enum EventCat
{
    move    = 0x0100,
    itemAct = 0x0200,
    dmg     = 0x0300,
    mapChg  = 0x0400,
}

enum EventCatMask = 0xFF00;

/**
 * Event type.
 */
enum EventType
{
    // EventCat.move
    moveWalk        = 0x0101,
    moveJump        = 0x0102,
    moveClimb       = 0x0103,
    moveClimbLedge0 = 0x0104,
    moveClimbLedge1 = 0x0105,
    moveFall        = 0x0106,
    moveFallAside   = 0x0107,
    moveSink        = 0x0108,
    movePass        = 0x0109,

    // EventCat.itemAct
    itemPickup      = 0x0201,
    itemDrop        = 0x0202,
    itemUse         = 0x0203,
    itemEquip       = 0x0204,
    itemUnequip     = 0x0205,

    // EventCat.dmg
    dmgAttack       = 0x0301,
    dmgFallOn       = 0x0302,
    dmgKill         = 0x0303,
    dmgBlock        = 0x0304,

    // EventCat.mapChg
    mchgRevealPitTrap   = 0x0401,
    mchgTrigRockTrap    = 0x0402,
    mchgDoorOpen        = 0x0403,
    mchgDoorClose       = 0x0404,
    mchgMessage         = 0x0405,
}

/**
 * An in-game event.
 */
struct Event
{
    @property EventCat cat() { return cast(EventCat)(type & EventCatMask); }
    EventType type;
    Pos where, whereTo;
    ThingId subjId;
    ThingId objId;
    ThingId obliqueId;
    string msg;

    this(EventType _type, Pos _where, Pos _whereTo, ThingId _subjId,
         ThingId _objId = invalidId, ThingId _obliqueId = invalidId,
         string _msg = "")
    {
        type = _type;
        where = _where;
        whereTo = _whereTo;
        subjId = _subjId;
        objId = _objId;
        obliqueId = _obliqueId;
        msg = _msg;
    }

    this(EventType _type, Pos _where, ThingId _subjId,
         ThingId _objId = invalidId, ThingId _obliqueId = invalidId,
         string msg = "")
    {
        this(_type, _where, _where, _subjId, _objId, _obliqueId, msg);
    }

    this(EventType _type, Pos _where, ThingId _subjId, string msg)
    {
        this(_type, _where, _where, _subjId, invalidId, invalidId, msg);
    }
}

/**
 * Collection of events.
 */
struct Sensorium
{
    private void delegate(Event)[] listeners;

    /**
     * Register a listener for in-game Events.
     *
     * Note that listeners registered here are "raw" listeners; they will
     * receive *all* events unfiltered. It's up to the caller to filter events
     * accordingly.
     */
    void listen(void delegate(Event) cb)
    {
        listeners ~= cb;
    }

    /**
     * Add an event to the current timestamp.
     */
    void emit(Event ev)
    {
        foreach (cb; listeners)
            cb(ev);
    }
}

/**
 * The game world.
 */
class World
{
    GameMap map;
    Store store;

    @NoSave Sensorium events;
    @NoSave ulong triggerId; // TBD: does this need to be @NoSave??

    this()
    {
        registerTerrains(&store);
    }

    /**
     * Returns: An input range of all objects at the specified location,
     * including floor tiles.
     */
    auto getAllAt(Vec!(int,4) pos)
    {
        return store.getAllBy!Pos(Pos(pos))
                    .chain(only(map[pos]));
    }

    /**
     * Returns: true if one or more objects in the given location contains the
     * component Comp; false otherwise.
     */
    bool locationHas(Comp)(Vec!(int,4) pos)
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
