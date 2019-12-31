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

/**
 * Returns: The dimensions of the given map as a Vec.
 */
Vec!(typeof(Map.init.opDollar!0),4) dimensions(Map)(Map map)
    if (is4DArray!Map)
{
    return vec(map.opDollar!0, map.opDollar!1, map.opDollar!2, map.opDollar!3);
}

unittest
{
    struct Map1(T)
    {
        enum opDollar(size_t i) = 3;
        T opIndex(int,int,int,int) { return T.init; }
    }
    static assert(is(ElementType!(Map1!int) == int));
    static assert(is(ElementType!(Map1!dchar) == dchar));

    assert(Map1!int.init.dimensions == vec(3,3,3,3));
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
 * Returns: The dimensions of the rendered image of a 4D map of the given
 * dimensions that would be rendered by renderMap, as a vector of width and
 * height, respectively.
 */
Vec!(int,2) renderSize(Vec!(int,4) dim)
{
    return vec(dim[1]*(dim[2] + dim[3] + interColSpace) - 1,
               dim[0]*(dim[2] + interRowSpace) - 1);
}

/// ditto
Vec!(int,2) renderSize(Map)(Map map)
    if (is4DArray!Map)
{
    return renderSize(map.dimensions);
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

            if (x > writtenArea.max[0]) writtenArea.max[0] = x+1;
            if (y > writtenArea.max[1]) writtenArea.max[1] = y+1;
        }
        void writef(A...)(string fmt, A args) {}
        @property auto width() { return rsize[0]; }
        @property auto height() { return rsize[1]; }
    }
    auto disp = TestDisplay();

    disp.renderMap(map); // This will assert if output exceeds stated bounds.
    assert(writtenArea.max == rsize);
}

/**
 * Converts 4D map coordinates to 2D rendering coordinates.
 * Params:
 *  map = 4D viewport used for rendering.
 *  coors = 4D coordinates relative to viewport.
 * Returns:
 *  2D coordinates where renderMap would draw a tile at the given 4D
 *  coordinates.
 */
Vec!(int,2) renderingCoors(Map)(Map map, Vec!(int,4) coors)
    if (is4DArray!Map)
{
    //auto wlen = map.opDollar!0;
    //auto xlen = map.opDollar!1;
    auto ylen = map.opDollar!2;
    auto zlen = map.opDollar!3;

    return vec(coors[1]*(ylen + zlen + interColSpace) +
               (ylen - coors[2] - 1) + coors[3],
               coors[0]*(ylen + interRowSpace) + coors[2]);
}

unittest
{
    struct Map
    {
        enum opDollar(int n) = 3;
        dchar opIndex(int w, int x, int y, int z) { return '.'; }
    }
    Map m;

    assert(m.renderingCoors(vec(0,0,0,0)) == vec(2,0));
    assert(m.renderingCoors(vec(1,1,1,1)) == vec(8,5));
    assert(m.renderingCoors(vec(2,2,2,2)) == vec(14,10));
    assert(m.renderingCoors(vec(1,0,0,0)) == vec(2,4));
    assert(m.renderingCoors(vec(0,1,0,0)) == vec(8,0));
    assert(m.renderingCoors(vec(0,0,1,0)) == vec(1,1));
    assert(m.renderingCoors(vec(0,0,0,1)) == vec(3,0));
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
    in (reg in region(vec(map.opDollar!0, map.opDollar!1, map.opDollar!2,
                          map.opDollar!3)))
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
    auto ref Elem opIndex(int[4] coors...)
    {
        version(D_NoBoundsChecks) {} else
        {
            import core.exception : RangeError;
            import std.exception : enforce;

            enforce((vec(coors) + reg.min) in reg, new RangeError);
        }

        return impl.opIndex(vec(coors) + reg.min);
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
        dchar opIndex(int[4] v...)
        {
            auto w = v[0];
            auto x = v[1];
            auto y = v[2];
            auto z = v[3];

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

enum minDisplaySize = renderSize(vec(3,3,3,3));

/**
 * Finds the optimal map dimensions whose rendering will fit within the given
 * target grid-based display.
 *
 * Note that the smallest viewport size is a 3x3x3x3 section of the map, which
 * requires a display size of at least minDisplaySize. An Exception will be
 * thrown if the display is smaller than this.
 *
 * Returns: The 4D dimensions as a Vec.
 */
Vec!(int,4) optimalViewportSize(int[2] dim)
out(r)
{
    auto rs = renderSize(r);
    assert(rs[0] > 0 && rs[0] <= dim[0] &&
           rs[1] > 0 && rs[1] <= dim[1]);
}
do
{
    import std.algorithm : min;
    static import std.math;

    static int sqrt(int x) { return cast(int)std.math.sqrt(cast(double)x); }

    immutable width = dim[0];
    immutable height = dim[1];

    if (width < minDisplaySize[0] || height < minDisplaySize[1])
    {
        import std.string : format;
        throw new Exception("%dx%d is too small to represent a 3x3x3x3 map"
                            .format(width, height));
    }

    // Find largest fitting regular hypercube in the given display.
    // Given a display size of W*H, we must satisfy:
    //
    //      (vtiles + htiles + interColSpace)*hplanes - 1 <= W  [1]
    //      (vtiles + interRowSpace)*vplanes - 1 <= H           [2]
    //
    // First we set all dimensions to be equal to n1, the unknown to be solved,
    // and try to maximize it. Substituting into [1], we have:
    //
    //      (n1 + n1 + interColSpace)*n1 - 1 <= W
    //
    // Solving for n1, we get:
    //
    //      n1a = (-interColSpace ± √(interColSpace^2 + 8*(W+1))) / 4
    //
    // Since n1 must be positive, we take the positive root.
    auto n1a = (-interColSpace + sqrt(interColSpace^^2 + 8*(width+1))) / 4;
    assert(n1a > 0.0);

    // Substituting into [2], we have:
    //
    //      (n1 + interRowSpace)*n1 - 1 <= H
    //      n1b = (-interRowSpace ± √(interRowSpace^2 + 4*(H+1))) / 2
    //
    // Since n1b must also be positive, we take the positive root.
    auto n1b = (-interRowSpace + sqrt(interRowSpace^^2 + 4*(height+1))) / 2;
    assert(n1b > 0.0);

    // The largest fitting hypercube, therefore, has edge length equal to the
    // minimum of n1a and n1b.
    auto n1 = cast(int)min(n1a, n1b);

    // Since we want to be able to center the rendered map on the player, the
    // hypercube must have odd edge length. So if it's even, we subtract 1.
    if (n1 % 2 == 0)
        n1--;

    // (This should already be assured by minDisplaySize, but just in case.)
    assert(n1 >= 3);

    // Now, a completely regular hypercube may not take maximum advantage of
    // the display size; so the next best choice is to have a regular cubic
    // base with irregular height.
    //
    // We do this by setting vplanes=n1 and the remaining 3 dimensions to be
    // n2, and try to maximize that. This is equivalent to maximizing vtiles in
    // [2], so we set vplanes=n1 and solve for vtiles:
    //
    //      (vtiles + interRowSpace)*n1 - 1 <= H
    //      vtiles <= (H+1)/n1 - interRowSpace
    //
    // We still have to obey [1], though, so we take the minimum of n1a and
    // vtiles. Again, we require n2 to be odd so that we can center the
    // viewport on the player, so we decrement n2 if it's even.
    auto vplanes = n1;
    auto n2 = min(n1a, (height+1)/n1 - interRowSpace);
    if (n2 % 2 == 0)
        n2--;
    assert(n2 >= 3);

    // Finally, we try to fill out as much horizontal space as we can while
    // maintaining a square configuration in at least 2 of the dimensions.
    // Since terminals generally have more horizontal space than vertical, we
    // choose to vary htiles by setting vtiles = hplanes = n2 and maximizing
    // htiles.
    //
    // So substituting n2 into [1], we have:
    //
    //      (n2 + htiles + interColSpace)*n2 - 1 <= W
    //      n2 + htiles + interColSpace <= (W+1)/n2
    //      htiles <= (W+1)/n2 - n2 - interColSpace
    auto htiles = (width+1)/n2 - n2 - interColSpace;

    // But we don't want htiles to be *too* disproportionate to the other
    // dimensions (i.e., we don't want an overly long hypercuboid), so we limit
    // it to at most 2*n2+1. And again, it must be an odd number so that the
    // viewport is centerable.
    auto n3 = min(2*n2 + 1, htiles);
    if (n3 % 2 == 0)
        n3--;
    assert(n3 >= 3);

    return vec(n1,n2,n2,n3);
}

unittest
{
    assert(optimalViewportSize(minDisplaySize) == vec(3,3,3,3));
    assert(optimalViewportSize([80, 24]) == vec(3,5,5,11));
}

// vim:set ai sw=4 ts=4 et:
