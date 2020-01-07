/**
 * 4D direction handling.
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
module dir;

/**
 * Abstract 4D axial direction.
 */
enum Dir
{
    self, left, right, front, back, ana, kata, up, down
}

/**
 * Convert an abstract direction to a concrete vector in that direction.
 */
int[4] dir2vec(Dir dir)
{
    final switch (dir)
    {
        case Dir.self:  return [  0,  0,  0,  0 ];
        case Dir.left:  return [  0,  0,  0, -1 ];
        case Dir.right: return [  0,  0,  0,  1 ];
        case Dir.front: return [  0,  0, -1,  0 ];
        case Dir.back:  return [  0,  0,  1,  0 ];
        case Dir.ana:   return [  0, -1,  0,  0 ];
        case Dir.kata:  return [  0,  1,  0,  0 ];
        case Dir.up:    return [ -1,  0,  0,  0 ];
        case Dir.down:  return [  1,  0,  0,  0 ];
    }
    assert(0);
}

unittest
{
    assert(Dir.self.dir2vec == [ 0, 0, 0, 0 ]);
    assert(Dir.up.dir2vec == [ -1, 0, 0, 0 ]);
    assert(Dir.down.dir2vec == [ 1, 0, 0, 0 ]);
}

/**
 * Returns: String name of the given direction.
 */
string dir2str(Dir dir)
{
    import std.conv : to;
    return dir.to!string;
}

unittest
{
    assert(Dir.up.dir2str == "up");
    assert(Dir.down.dir2str == "down");
    assert(Dir.ana.dir2str == "ana");
    assert(Dir.kata.dir2str == "kata");
}

// vim:set ai sw=4 ts=4 et:
