/**
 * Entity components
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
module components;

import loadsave;
import store_traits;

/**
 * Component of all objects that have a map position.
 */
@Indexed @Component @TrackNew
struct Pos
{
    import vector : Vec, vec;
    Vec!(int,4) coors;
    alias coors this;

    this(int[4] _coors...) { coors = vec(_coors); }

    import loadsave;
    void save(S)(ref S savefile)
    {
        savefile.put("coors", coors[]);
    }

    void load(L)(ref L loadfile)
    {
        coors[] = loadfile.parse!(int[])("coors")[];
    }
}

unittest
{
    import loadsave;
    import std.algorithm : splitter;
    import std.array : appender;

    auto pos = Pos([ 1, 2, 3, 4 ]);

    auto app = appender!string;
    auto sf = saveFile(app);
    sf.put("pos", pos);

    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto pos2 = lf.parse!Pos("pos");

    assert(pos2 == pos);
}

enum TileId : ushort
{
    blocked,

    space,
    wall,
    floorBare,
    floorGrassy,
    floorMuddy,
    water,
    doorway,
    ladder,
    ladderTop,

    player,
    creatureA,

    gold,
    portal,
    trapPit,
}

/**
 * Component of any object that has a ColorTile representation.
 *
 * .stackOrder is used for sorting which tile to show when there are multiple
 * items on a single position. Currently:
 *  <0 = background / floor tiles
 *  0 = items and other objects lying on the ground
 *  ≥1 = agents that can move around.
 */
@Component
struct Tiled
{
    enum Hint : ubyte { memorable, dynamic }
    TileId tileId;
    int stackOrder;
    Hint hint; // hints whether to save this TileId in map memory
}

/**
 * Component of an object that changes the appearance of empty space
 * immediately above it.
 */
@Component
struct TiledAbove
{
    TileId tileId;
    int stackOrder;
}

/**
 * Component of any object that has a name.
 */
@Component
struct Name
{
    // TBD: should make this i18n-able.
    string name;
}

enum UseEffect
{
    portal
}

/**
 * Component of any object that can be used or applied by the apply action.
 */
@Component
struct Usable
{
    UseEffect effect;
}

/**
 * Component to indicate an agent has stepped into an exit portal.
 */
@Component
struct UsePortal { }

/**
 * Inventory component
 */
@Component
struct Inventory
{
    ThingId[] contents;
}

/**
 * Component for objects that can be picked up.
 */
@Component
struct Pickable { }

enum Climbable : bool { no, yes }

/**
 * Component for objects that block movement into the same tile.
 */
@Component
struct BlocksMovement
{
    Climbable climbable;
}

/**
 * Component for objects that block visibility.
 */
@Component
struct BlocksView { }

/**
 * The type of weight support an object has.
 */
@BitFlags
enum SupportType
{
    within = 1 << 0,
    above  = 1 << 1,
    /+below = 1 << 2, /*for ropes!*/ +/
}

/**
 * Condition for an object to be supported by an object that has
 * SupportsWeight.
 */
enum SupportCond
{
    always,
    climbing,
    buoyant,
    /* notFalling // for fragile floors that break if you fall on it */
}

/**
 * Component for objects that (conditionally) support weight.
 *
 * Not to be confused with BlocksMovement, which is unconditional.
 */
@Component
struct SupportsWeight
{
    SupportType type;
    SupportCond cond;
}

/**
 * Component for objects that are not subject to gravity.
 */
@Component
struct NoGravity { }

/**
 * Component for objects that can climb ladders.
 */
@Component
struct Climbs { }

/**
 * Component for objects that don't sink in water.
 */
@Component
struct Swims { }

/**
 * Component attached by gravity system for objects that are sinking in water.
 */
@Component
struct Sinking { }

/**
 * Component for objects that negate weight support (e.g. pit traps).
 */
@Component
struct PitTrap { }

/**
 * Component for agent objects.
 */
@Component @TrackNew
struct Agent
{
    enum Type { ai, player, sinkAgent }
    Type type;
    // TBD: AI state goes here
}

/**
 * Component for objects that can be injured and killed.
 */
@Component
struct Mortal
{
    int maxhp;
    int hp; // FIXME: is there a better system than this lousy old thing?!
}

/**
 * Component for objects that emit a message when an agent touches them.
 */
@Component
struct Message
{
    string[] msgs;
}

// vim:set ai sw=4 ts=4 et:
