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

import store_traits;

/**
 * Component of all objects that have a map position.
 */
@Indexed @Component
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

enum TileId
{
    space,
    wall,
    floorBare,
    floorGrassy,
    floorMuddy,
    doorway,

    player,
    gold,
    portal,
}

/**
 * Component of any object that has a ColorTile representation.
 */
@Component
struct Tiled
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

/**
 * Component for objects that blocks movement.
 */
@Component
struct BlocksMovement { }

// vim:set ai sw=4 ts=4 et:
