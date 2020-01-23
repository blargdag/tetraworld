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

import std.algorithm;
import std.conv;
import std.math;
import std.random;
import std.range;

/**
 * Abstract 4D axial direction.
 */
enum Dir
{
    self, left, right, front, back, ana, kata, up, down
}

/**
 * Returns: A random direction that isn't Dir.self.
 */
Dir randomDir()
{
    Dir d;

    do
    {
        d = uniform!Dir;
    } while (d == Dir.self);

    return d;
}

/**
 * Convert an abstract direction to a concrete vector in that direction.
 */
int[4] dir2vec(Dir dir) pure
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
string dir2str(Dir dir) pure
{
    return dir.to!string;
}

unittest
{
    assert(Dir.up.dir2str == "up");
    assert(Dir.down.dir2str == "down");
    assert(Dir.ana.dir2str == "ana");
    assert(Dir.kata.dir2str == "kata");
}

/**
 * Choose a cardinal direction to move that heads towards the given goal, with
 * the likelihood of each direction scaled by the relative magnitude of the
 * corresponding coordinate in the goal coordinates.
 */
int[4] chooseDir(int[4] goal)
    out(v; v[].map!(x => abs(x)).sum == 1)
{
    auto sum = goal[].map!(x => abs(x)).sum;
    auto pick = uniform(0, sum);
    auto acc = 0;
    foreach (i; 0 .. 4)
    {
        acc += abs(goal[i]);
        if (pick < acc)
        {
            int[4] result;
            result[i] = (goal[i] < 0) ? -1 : 1;
            return result;
        }
    }
    assert(0);
}

///
unittest
{
    assert(chooseDir([10, 0, 0, 0]) == [1,0,0,0]);
    assert(chooseDir([-10, 0, 0, 0]) == [-1,0,0,0]);
    assert(chooseDir([0, 0, 10, 0]) == [0,0,1,0]);
    assert(chooseDir([0, -5, 0, 0]) == [0,-1,0,0]);
    assert(chooseDir([0, 0, 0, -7]) == [0,0,0,-1]);

    void testDistrib(int[4] vec)
    {
        enum ntrials = 200;
        enum tolerance = 1.0;

        double[4] counts = [0,0,0,0];
        auto csum = vec[].map!(x => abs(x)).sum;
        foreach (_; 0 .. ntrials)
        {
            auto v = chooseDir(vec);
            auto idx = v[].countUntil!(e => e == 1 || e == -1);
            assert(idx != -1);
            counts[idx] += v[idx];
        }
        foreach (i; 0 .. 4)
        {
            import std.format : format;
            assert(abs(counts[i]*csum/ntrials - vec[i]) < tolerance,
                   format("v=%s n=%d tol=%f counts=%s normalized=%s", vec,
                          ntrials, tolerance, counts,
                          counts[].map!(c => c*csum/ntrials)));
        }
    }

    //foreach (_; 0 .. 50)
    {
        testDistrib([ 1, 0, 0, -5 ]);
        testDistrib([ 1, 2, 3, 4 ]);
        testDistrib([ -10, 1, -1, 1 ]);
        testDistrib([ -10, 1, 12, 1 ]);
    }
}

// vim:set ai sw=4 ts=4 et:
