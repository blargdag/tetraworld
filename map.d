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
import vector;

/**
 * Checks if T is a 4D array of elements, and furthermore has dimensions that
 * can be queried via opDollar.
 */
enum is4DArray(T) = is(typeof(T.init[0,0,0,0])) &&
                    is(typeof(T.init.opDollar!0) : int) &&
                    is(typeof(T.init.opDollar!1) : int) &&
                    is(typeof(T.init.opDollar!2) : int) &&
                    is(typeof(T.init.opDollar!3) : int);

/**
 * Returns: The element type of the given 4D array.
 */
template ElementType(T)
    if (is4DArray!T)
{
    alias ElementType = typeof(T.init[0,0,0,0]);
}

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
    if (isGridDisplay!T && is4DArray!Map && is(ElementType!Map == dchar))
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
 * Returns: The dimensions of the rendered image of a 4D map that would be
 * rendered by renderMap, as a vector of width and height, respectively.
 */
Vec!(int,2) renderSize(Map)(Map map)
    if (is4DArray!Map && is(ElementType!Map == dchar))
{
    auto wlen = map.opDollar!0;
    auto xlen = map.opDollar!1;
    auto ylen = map.opDollar!2;
    auto zlen = map.opDollar!3;

    return vec(xlen*(ylen + zlen + interColSpace) - 1,
               wlen*(ylen + interRowSpace) - 1);
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
    assert(rsize == vec(17, 11));

    Region!(int,2) writtenArea;

    struct TestDisplay
    {
        void moveTo(int x, int y)
        {
            // Check that rendered output is within stated bounds.
            assert(x >= 0 && x < rsize[0]);
            assert(y >= 0 && y < rsize[1]);

            if (x > writtenArea.upperBound[0]) writtenArea.upperBound[0] = x+1;
            if (y > writtenArea.upperBound[1]) writtenArea.upperBound[1] = y+1;
        }
        void writef(A...)(string fmt, A args) {}
        @property auto width() { return rsize[0]; }
        @property auto height() { return rsize[1]; }
    }
    auto disp = TestDisplay();

    disp.renderMap(map); // This will assert if output exceeds stated bounds.
    assert(writtenArea.upperBound == rsize);
}

/**
 * An adaptor that represents a rectangular subset of a 4D array.
 */
struct SubMap(Map)
    if (is4DArray!Map)
{
    alias Elem = ElementType!Map;

    private Map impl;
    Region!(int,4) reg;

    /// Constructor.
    this(Map map, Region!(int,4) _reg)
    in
    {
        assert(reg in region(vec(map.opDollar!0, map.opDollar!1,
                                 map.opDollar!2, map.opDollar!3)));
    }
    body
    {
        impl = map;
        reg = _reg;
    }

    /// Array dimensions.
    @property int opDollar(size_t n)()
        if (n < 4)
    {
        return reg.length!n;
    }

    /// Array dereference
    auto ref Elem opIndex(TypeVec!(int, 4) coors)
    {
        version(D_NoBoundsChecks) {} else
        {
            import core.exception : RangeError;
            import std.exception : enforce;

            enforce((vec(coors) + reg.lowerBound) in reg, new RangeError);
        }

        return impl.opIndex((vec(coors) + reg.lowerBound).byComponent);
    }

    static assert(is4DArray!(typeof(this)));
}

/**
 * Constructs a submap of the given 4D map, with the specified dimensions.
 */
auto submap(Map)(Map map, Region!(int,4) reg)
    if (is4DArray!Map)
{
    return SubMap!Map(map, reg);
}

unittest
{
    import core.exception : RangeError;
    import std.exception : assertThrown;

    struct Map
    {
        enum opDollar(int n) = 5;
        dchar opIndex(int w, int x, int y, int z)
        {
            if (w*x*y*z == 0 || w==4 || x==4 || y==4 || z==4)
                return '/';
            else
                return '.';
        }
    }
    auto map = Map();
    auto submap = map.submap(region(vec(1,1,1,1), vec(4,4,4,4)));

    assertThrown!RangeError(submap[-1,-1,-1,-1]);
    assertThrown!RangeError(submap[3,3,3,3]);

    assert(submap[0,0,0,0] == '.');
    assert(submap[2,2,2,2] == '.');
}

// vim:set ai sw=4 ts=4 et:
