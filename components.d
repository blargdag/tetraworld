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
    unknown,

    space,
    wall,
    floorBare,
    floorGrassy,
    floorMuddy,
    water,
    doorway,
    lockedDoor,
    unlockedDoor,
    ladder,
    ladderTop,

    lever1,
    lever2,

    player,
    creatureA,
    creatureC,

    gold,
    rock,
    scuba1,
    scuba2,

    vegetation1,
    vegetation2,
    crabShell,
    portal,
    trapPit,
    trapRock,
}

/**
 * Component of any object that has a ColorTile representation.
 *
 * .stackOrder is used for sorting which tile to show when there are multiple
 * items on a single position. Currently:
 *  <0 = background / floor tiles
 *  0 = items and other objects lying on the ground
 *  1 = quest items and other highly-visible items
 *  ≥2 = agents that can move around.
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
    portal, trigger
}

/**
 * Component of any object that can be used or applied by the apply action.
 */
@Component
struct Usable
{
    UseEffect effect;
    string useVerb;
    ulong triggerId;
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
    static struct Item
    {
        ThingId id;
        enum Type { carrying, equipped, intrinsic }
        Type type;

        bool inEffect()
        {
            return type == Type.equipped || type == Type.intrinsic;
        }
    }
    Item[] contents;
    bool autopickup; // TBD: should have some kind of object type preference here
}

/**
 * Component for objects that can be picked up.
 */
@Component
struct Pickable { }

/**
 * Component for quest items.
 */
@Component
struct QuestItem
{
    int questId;
}

/**
 * Component for items that can be stacked.
 */
@Component
struct Stackable
{
    int count;
}

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
    permanent,  // for terrains that never change
    climbing,
    buoyant,
    /* notFalling // for fragile floors that break if you fall on it */
}

/**
 * Component for objects that (conditionally) support weight.
 */
@Component
struct SupportsWeight
{
    SupportType type;
    SupportCond cond;
}

/**
 * Component for objects that are subject to gravity.
 */
@Component
struct Weight
{
    int value = 1;
}

/**
 * Components for objects that can move on their own accord.
 */
@Component
struct CanMove
{
    @BitFlags
    enum Type
    {
        walk    = 1 << 0,
        climb   = 1 << 1,
        jump    = 1 << 2,
        swim    = 1 << 3,
    }

    Type types;
}

/**
 * Component for objects that trigger other objects.
 */
@Component
struct Trigger
{
    enum Type { onEnter, onWeight }
    Type type;
    ulong triggerId;
    int minWeight;
}

/**
 * The effect when an object is triggered.
 */
enum TriggerEffect
{
    trapDoor, rockTrap, toggleDoor, removeMsg,
}

/**
 * Component for objects that can be triggered.
 */
@Component @Indexed
struct Triggerable
{
    ulong triggerId;
    TriggerEffect effect;

    size_t toHash() const @safe pure nothrow { return triggerId; }
    bool opEquals(ref const Triggerable a) const @safe pure nothrow
    {
        return triggerId == a.triggerId;
    }
}

/**
 * Component for agent objects.
 */
@Component @TrackNew
struct Agent
{
    enum Type { ai, player, sinkAgent, tileEffectAgent }
    Type type;
    int ticksPerTurn = 10;

    static struct Goal
    {
        enum Type { eat, hunt, seekAir }

        Type type;
        int mapRange;
        int cost;
    }
    Goal[] goals;
}

/**
 * Component of objects that act as a medium for other objects.
 */
@Component @BitFlags
enum Medium
{
    none    = 0,

    // NOTE: the following is ordered such that if there are multiple mediums
    // m[] in one location, the effective mediums will be m.max().
    air     = 1 << 0,
    water   = 1 << 1,
    rock    = 1 << 2,
}

/**
 * Stats block.
 */
struct Stats
{
    int maxhp;
    int hp; // FIXME: is there a better system than this lousy old thing?!

    Medium canBreatheIn;
    int maxair, air;

    //TBD: food type
    int maxfood, food;
}

/**
 * Creature AI will not target other members of its own faction, except the
 * 'loner' faction, which is always targetable.
 */
enum Faction
{
    loner,
    crawlers,
    swimmers,
}

/**
 * Component for objects that can be injured and killed.
 */
@Component
struct Mortal
{
    Stats baseStats;
    Stats curStats;

    Faction faction;

    this(Stats _baseStats, Faction _faction = Faction.init)
    {
        baseStats = curStats = _baseStats;
        faction = _faction;
    }
}

/**
 * Component for objects that emit a message when an agent touches them.
 */
@Component
struct Message
{
    string[] msgs;
}

@BitFlags
enum DmgType
{
    none = 0,

    blunt = 1 << 0,
    bite = 1 << 1,
    pierce = 1 << 2,
    fallOn = 1 << 3,
    drown =  1 << 4,
}

/**
 * Component for objects that can be worn.
 */
@Component
struct Armor
{
    DmgType protection;
    //int durability;

    Stats bonuses;
}

/**
 * Component of objects that can be used as weapons.
 */
@Component
struct Weapon
{
    DmgType dmgType;
    int dmg;
    string attackVerb = "hits";
}

@Component
struct Edible
{
    // TBD: food type
    int nutrition;
}

// vim:set ai sw=4 ts=4 et:
