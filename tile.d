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
    dchar isometric, straight;
    ushort fg = Color.DEFAULT, bg = Color.DEFAULT;

    this(dchar _iso, dchar _straight, Color _fg = Color.DEFAULT,
         Color _bg = Color.DEFAULT)
    {
        isometric = _iso;
        straight = _straight;
        fg = _fg;
        bg = _bg;
    }

    this(dchar _iso, Color _fg = Color.DEFAULT, Color _bg = Color.DEFAULT)
    {
        this(_iso, _iso, _fg, _bg);
    }
}

Tile16[TileId.max+1] tiles = [
    TileId.blocked:         Tile16('#', '\u2591'),
    TileId.unknown:         Tile16('?'),
    TileId.space:           Tile16(' '),
    TileId.wall:            Tile16('/', '#'),
    TileId.floorBare:       Tile16('.'),
    TileId.floorGrassy:     Tile16(':'),
    TileId.floorMuddy:      Tile16(';'),
    TileId.water:           Tile16('~', Color.blue),
    TileId.doorway:         Tile16('-'),
    TileId.lockedDoor:      Tile16('+', Color.magenta),
    TileId.unlockedDoor:    Tile16('-', Color.magenta),
    TileId.ladder:          Tile16('='),
    TileId.ladderTop:       Tile16('_'),

    TileId.lever1:       Tile16('\\', Color.magenta),
    TileId.lever2:       Tile16('|', Color.magenta),

    TileId.player:      Tile16('&'),
    TileId.creatureA:   Tile16('A', Color.red),
    TileId.creatureB:   Tile16('B', Color.red),
    TileId.creatureC:   Tile16('C', Color.red),

    TileId.gold:        Tile16('$', Color.yellow),
    TileId.rock:        Tile16('*'),
    TileId.scuba1:      Tile16('['),
    TileId.scuba2:      Tile16('[', Color.magenta),

    TileId.vegetation1: Tile16('%', Color.green),
    TileId.vegetation2: Tile16('%'),
    TileId.crabShell:   Tile16('['),
    TileId.portal:      Tile16('@', Color.magenta),
    TileId.trapPit:     Tile16('^', Color.red),
    TileId.trapRock:    Tile16('^', Color.red),
];

// vim:set ai sw=4 ts=4 et:
