/**
 * Concrete displayable tiles.
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
module tile;

import arsd.terminal : Color;

import components : TileId;
import display;

struct Tile16
{
    dchar representation;
    ushort fg = Color.DEFAULT, bg = Color.DEFAULT;
}

Tile16[TileId.max+1] tiles = [
    TileId.wall:        Tile16('/'),
    TileId.floorBare:   Tile16('.'),
    TileId.floorGrassy: Tile16(':'),
    TileId.floorMuddy:  Tile16(';'),
    TileId.doorway:     Tile16('#'),

    TileId.player:      Tile16('&'),
    TileId.gold:        Tile16('$', Color.yellow),
    TileId.portal:      Tile16('@', Color.magenta),
];

// vim:set ai sw=4 ts=4 et:
