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
import std.random : uniform;
import std.range;

import bsp;
import map;
import store;
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

    ColorTile opIndex(int[4] pos...)
    {
        import std.math : abs;
        import arsd.terminal : Color;

        auto fg = Color.DEFAULT;
        auto bg = Color.DEFAULT;

        // FIXME: should be a more efficient way to do this
        auto result = ColorTile('/', fg, bg);
        foreachFiltRoom(tree, bounds, (R r) => r.contains(vec(pos)),
            (MapNode node, R r) {
                auto rr = node.interior;
                if (iota(4).fold!((b, i) => b && rr.min[i] < pos[i] &&
                                            pos[i] < rr.max[i])(true))
                {
                    result.ch = node.style;
                    return 1;
                }

                foreach (d; node.doors)
                {
                    if (pos[] == d.pos)
                    {
                        result.ch = '#';
                        return 1;
                    }
                }

                result.ch = '/';
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
static assert(is4DArray!GameMap && is(CellType!GameMap == ColorTile));

class World
{
    GameMap map;
    Store store;
}

// FIXME: this should go into its own mapgen module.
World newGame(int[4] dim)
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
    resizeRooms(w.map.tree, w.map.bounds);
    setRoomFloors(w.map.tree, w.map.bounds);

    import arsd.terminal : Color;
    import components;
    w.store.createObj(Pos(randomLocation(w.map.tree, w.map.bounds)),
                      Tiled(ColorTile('@', Color.DEFAULT, Color.DEFAULT)));

    return w;
}

// vim:set ai sw=4 ts=4 et:
