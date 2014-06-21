/**
 * Tetraworld 4D map module
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
module map;

import display;
import rect;

/**
 * Checks if T is a 4D array of elements of type E, and furthermore has
 * dimensions that can be queried via opDollar.
 */
enum is4DArray(T,E) = is(typeof(T.init[0,0,0,0]) : E) &&
                      is(typeof(T.init.opDollar!0) : size_t) &&
                      is(typeof(T.init.opDollar!1) : size_t) &&
                      is(typeof(T.init.opDollar!2) : size_t) &&
                      is(typeof(T.init.opDollar!3) : size_t);

enum interColSpace = 0;
enum interRowSpace = 1;

/**
 * Renders a 4D map to the given grid-based display.
 *
 * Params:
 *  display = A grid-based output display satisfying isGridDisplay.
 *  map = An object which returns a printable character given a set of 4D
 *      coordinates.
 */
void renderMap(T, Map)(T display, Map map)
    if (isGridDisplay!T && is4DArray!(Map,dchar))
{
    auto wlen = map.opDollar!0;
    auto xlen = map.opDollar!1;
    auto ylen = map.opDollar!2;
    auto zlen = map.opDollar!3;

    foreach (w; 0 .. wlen)
    {
        auto rowy = w*(ylen + interRowSpace);
        foreach (x; 0 .. xlen)
        {
            auto colx = x*(ylen + zlen + interColSpace);
            foreach (y; 0 .. ylen)
            {
                auto outx = colx + (ylen - y - 1);
                auto outy = rowy + y;
                foreach (z; 0 .. zlen)
                {
                    display.moveTo(outx++, outy);
                    display.writef("%s", map[w,x,y,z]);
                }
            }
        }
    }
}

/**
 * Returns: The dimensions of the rendered image of a 4D map, that would be
 * rendered by renderMap.
 */
Dim renderSize(Map)(Map map)
    if (is4DArray!(Map,dchar))
{
    auto wlen = map.opDollar!0;
    auto xlen = map.opDollar!1;
    auto ylen = map.opDollar!2;
    auto zlen = map.opDollar!3;

    return Dim(xlen*(ylen + zlen + interColSpace),
               wlen*(ylen + interRowSpace));
}

unittest
{
    struct Map
    {
        enum opDollar(int n) = 3;
        dchar opIndex(int w, int x, int y, int z) { return '.'; }
    }
    auto map = Map();
    auto rsize = map.renderSize();
    assert(rsize == Dim(18, 12));

    struct TestDisplay
    {
        void moveTo(int x, int y)
        {
            // Check that rendered output is within stated bounds.
            assert(x >= 0 && x < rsize.width);
            assert(y >= 0 && y < rsize.height);
        }
        void writef(A...)(string fmt, A args) {}
        @property auto width() { return rsize.width; }
        @property auto height() { return rsize.height; }
    }
    auto disp = TestDisplay();

    // This will assert if output exceeds stated bounds.
    disp.renderMap(map);
}

// vim:set ai sw=4 ts=4 et:
