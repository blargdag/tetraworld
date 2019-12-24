/**
 * n-dimensional BSP map generator.
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
module bsp;

import std.range.primitives;
import std.traits : ReturnType;

/**
 * A 4D rectangular region.
 */
struct Region
{
    int[4] min, max;

    long volume()
    {
        import std.algorithm : map, fold;
        import std.range : iota;
        return iota(4).map!(i => max[i] - min[i])
                      .fold!((a, b) => a*b)(1);
    }

    ///
    unittest
    {
        assert(Region([ 0, 0, 0, 0 ], [ 2, 3, 5, 7 ]).volume == 210);
        assert(Region([ 0, 0, 0, 7 ], [ 2, 3, 5, 7 ]).volume == 0);
        assert(Region([ 4, 3, 2, 1 ], [ 6, 6, 7, 8 ]).volume == 210);
    }

    int width(int dim)
        in (0 <= dim && dim < 4)
    {
        return max[dim] - min[dim];
    }

    int minWidth()
    {
        import std.algorithm : map, minElement;
        import std.range : iota;
        return iota(4).map!(i => max[i] - min[i]).minElement;
    }

    ///
    unittest
    {
        assert(Region([ 0, 0, 0, 0 ], [ 1, 5, 2, 3 ]).minWidth == 1);
        assert(Region([ -4, 0, 0, 0 ], [ 1, 5, 2, 3 ]).minWidth == 2);
    }

    int maxWidth()
    {
        import std.algorithm : map, maxElement;
        import std.range : iota;
        return iota(4).map!(i => max[i] - min[i]).maxElement;
    }

    ///
    unittest
    {
        assert(Region([ 0, 0, 0, 0 ], [ 1, 5, 2, 3 ]).maxWidth == 5);
        assert(Region([ 0, 4, 0, 0 ], [ 1, 5, 2, 3 ]).maxWidth == 3);
    }
}

/**
 * A BSP tree node.
 */
class BspNode
{
    int axis;
    int pivot;
    BspNode[2] children;

    bool isLeaf() const { return children[0] is null && children[1] is null; }
}

/**
 * Randomly picks a single element out of the given range with equal
 * probability for every element.
 *
 * Params:
 *  range = The range to pick an element from. Must be non-empty if defElem is
 *      not specified.
 *  defElem = (Optional) default element to return if the range is empty. If
 *      not specified, the range must not be empty.
 *
 * Complexity: O(n) where n is the length of the range.
 */
ElementType!R pickOne(R)(R range)
    if (isInputRange!R)
    in (!range.empty)
{
    ElementType!R result = range.front;
    range.popFront();
    size_t i = 2;
    while (!range.empty)
    {
        import std.random : uniform; 
        if (uniform(0, i++) == 0)
            result = range.front;
        range.popFront();
    }
    return result;
}

/// ditto
ElementType!R pickOne(R, E)(R range, E defElem)
    if (isInputRange!R && is(E : ElementType!R))
{
    if (range.empty)
        return defElem;
    return range.pickOne();
}

///
unittest
{
    assert([ 123 ].pickOne() == 123);
    assert((cast(int[]) []).pickOne(-1) == -1);
}

unittest
{
    int[5] counts;
    auto data = [ 0, 1, 2, 3, 4 ];
    foreach (_; 0 .. 50000)
    {
        counts[data.pickOne]++;
    }
    foreach (c; counts)
    {
        import std.math : round;
        assert(round((cast(float) c) / 10000) == 1.0);
    }
}

Region leftRegion()(Region r, int axis, int pivot)
{
    auto result = r;
    result.max[axis] = pivot;
    return result;
}

Region rightRegion()(Region r, int axis, int pivot)
{
    auto result = r;
    result.min[axis] = pivot;
    return result;
}

unittest
{
    auto r = Region([0, 0, 0, 0], [ 5, 5, 5, 5 ]);
    assert(leftRegion(r, 0, 3) == Region([ 0, 0, 0, 0 ], [ 3, 5, 5, 5 ]));
    assert(rightRegion(r, 0, 3) == Region([ 3, 0, 0, 0 ], [ 5, 5, 5, 5 ]));

    assert(leftRegion(r, 1, 3) == Region([ 0, 0, 0, 0 ], [ 5, 3, 5, 5 ]));
    assert(rightRegion(r, 1, 3) == Region([ 0, 3, 0, 0 ], [ 5, 5, 5, 5 ]));

    assert(leftRegion(r, 2, 4) == Region([ 0, 0, 0, 0 ], [ 5, 5, 4, 5 ]));
    assert(rightRegion(r, 2, 4) == Region([ 0, 0, 4, 0 ], [ 5, 5, 5, 5 ]));
}

unittest
{
    auto r = Region([2, 2, 2, 2], [ 5, 5, 5, 5 ]);
    assert(leftRegion(r, 0, 3) == Region([ 2, 2, 2, 2 ], [ 3, 5, 5, 5 ]));
    assert(rightRegion(r, 0, 3) == Region([ 3, 2, 2, 2 ], [ 5, 5, 5, 5 ]));
}

enum invalidAxis = -1;
enum invalidPivot = int.min;

/**
 * Generate a BSP partitioning of the given region with the given splitting
 * parameters.
 *
 * Params:
 *  canSplitRegion = A delegate that returns true if the given region can be
 *      further split, false otherwise.  Note that returning true does not
 *      guarantee that the region will actually be split; if no suitable
 *      splitting axis or pivot is found, it will not be split regardless.
 *  findSplitAxis = A delegate that returns a splitting axis for the given
 *      region. If no suitable axis is found, a return value of invalidAxis
 *      will force the region not to be split.
 *  findPivot = A delegate that computes a suitable pivot for splitting the
 *      given region along the given axis. A return value of invalidPivot
 *      indicates that no suitable pivot value can be found, and that the node
 *      should not be split after all.
 */
BspNode genBsp(Region region,
               bool delegate(Region r) canSplitRegion,
               int delegate(Region r) findSplitAxis,
               int delegate(Region r, int axis) findPivot)
{
    auto node = new BspNode();
    if (!canSplitRegion(region))
        return node;

    auto axis = findSplitAxis(region);
    if (axis == invalidAxis)
        return node;

    auto pivot = findPivot(region, axis);
    if (pivot == invalidPivot)
        return node;

    node.axis = axis;
    node.pivot = pivot;
    node.children[0] = genBsp(leftRegion(region, axis, pivot),
                              canSplitRegion, findSplitAxis, findPivot);
    node.children[1] = genBsp(rightRegion(region, axis, pivot),
                              canSplitRegion, findSplitAxis, findPivot);
    return node;
}

/**
 * Generate a BSP partitioning of the given region with the given minimum
 * region size.
 */
BspNode genBsp(Region region, int[4] minSize)
{
    import std.algorithm : filter;
    import std.random : uniform;
    import std.range : iota;

    return genBsp(region,
        (Region r) => true,
        (Region r) {
            auto axes = iota(4)
                .filter!(i => r.max[i] - r.min[i] >= 2*minSize[i] + 1);
            return axes.empty ? invalidAxis : axes.pickOne;
        },
        (Region r, int axis) => uniform(r.min[axis] + minSize[axis],
                                        r.max[axis] - minSize[axis])
    );
}

/**
 * Iterate over the rooms (leaf nodes) of the given BSP tree.
 *
 * Params:
 *  root = The root of the tree.
 *  region = The initial bounding region of the tree.
 *  dg = Delegate to invoke per room. The delegate should normally return 0; a
 *      non-zero return will abort the iteration and the value will be
 *      propagated to the return value of the entire iteration.
 */
int foreachRoom(BspNode root, Region region,
                int delegate(Region r, BspNode n) dg)
{
    if (root is null)
        return 0;

    if (root.isLeaf)
        return dg(region, root);

    int rc = foreachRoom(root.children[0],
                         leftRegion(region, root.axis, root.pivot),
                         dg);
    if (rc != 0) return rc;

    return foreachRoom(root.children[1],
                       rightRegion(region, root.axis, root.pivot),
                       dg);
}

unittest
{
    enum w = 24, h = 24;
    char[w*h] result;
    foreach (ref ch; result) { ch = '#'; }

    auto region = Region([ 0, 0, 0, 0 ], [ w, h, 0, 0 ]);
    auto tree = genBsp(region, [ 3, 3, 0, 0 ]);

    char fl = '!';
    tree.foreachRoom(region, (Region r, BspNode n) {
        foreach (j; r.min[1] .. r.max[1])
            foreach (i; r.min[0] .. r.max[0])
                result[i + j*w] = fl;
        fl++;
        return 0;
    });

    import std.stdio, std.range : chunks;
    //writefln("\n%(%-(%s%)\n%)", result[].chunks(w));
}

unittest
{
    enum w = 30, h = 24;
    static struct Screen
    {
        dchar[w*h] impl;
        static Screen opCall()
        {
            Screen result;
            foreach (ref ch; result.impl) { ch = '#'; }
            return result;
        }
        ref dchar opIndex(int i, int j)
            in (0 <= i && i < w)
            in (0 <= j && j < h)
        {
            return impl[i + w*j];
        }
        void dump()
        {
            import std.stdio, std.range : chunks;
            writefln("\n%(%-(%s%)\n%)", impl[].chunks(w));
        }
    }
    Screen result;

    void renderRoom(Region r, BspNode n)
    {
        foreach (j; r.min[1] .. r.max[1])
            foreach (i; r.min[0] .. r.max[0])
            {
                if (i == r.min[0] || i == r.max[0]-1)
                    result[i, j] = '│';
                else if (j == r.min[1] || j == r.max[1]-1)
                    result[i, j] = '─';
                else
                    result[i, j] = '.';
            }

        result[r.min[0], r.min[1]] = '┌';
        result[r.min[0], r.max[1]-1] = '└';
        result[r.max[0]-1, r.min[1]] = '┐';
        result[r.max[0]-1, r.max[1]-1] = '┘';
    }

    import std.algorithm : filter, clamp;
    import std.random : uniform;
    import std.range : iota;
    import gauss;

    auto region = Region([ 0, 0, 0, 0 ], [ w, h, 1, 1 ]);
    auto tree = genBsp(region,
        (Region r) => r.volume > 49 + uniform(0, 50),
        (Region r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                             .pickOne(invalidAxis),
        (Region r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
            invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
            //gaussian(r.max[axis] - r.min[axis], 4)
            //    .clamp(r.min[axis] + 3, r.max[axis] - 3)
    );

    int id = 0;
    tree.foreachRoom(region, (Region r, BspNode n) {
        renderRoom(r, n);

        import std.format : format;
        auto idstr = format("%d", id);
        foreach (i; 0 .. idstr.length)
        {
            if (i < r.max[0] - r.min[0] - 2)
                result[cast(int)(r.min[0] + i + 1), r.min[1]+1] = idstr[i];
        }
        id++;

        return 0;
    });

    result.dump();
}

// vim:set ai sw=4 ts=4 et:
