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

struct Region
{
    int[4] min, max;
}

/**
 * A BSP tree node.
 */
struct BspNode
{
    int axis;
    int pivot;
    BspNode*[2] children;

    bool isLeaf() const { return children[0] is null && children[1] is null; }
}

/**
 * Randomly picks a single element out of the given range with equal
 * probability for every element.
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

///
unittest
{
    assert([ 123 ].pickOne() == 123);
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

Region leftRegion(Region r, int axis, int pivot)
{
    auto result = r;
    result.max[axis] = pivot;
    return result;
}

Region rightRegion(Region r, int axis, int pivot)
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

/**
 * Generate a BSP partitioning of the given region with the given minimum
 * region size.
 */
BspNode* genBsp(Region region, int[4] minSize)
{
    import std.algorithm : filter;
    import std.random : uniform;
    import std.range : iota;

    auto node = new BspNode();

    auto availIdx = iota(4)
        .filter!(i => region.max[i] - region.min[i] >= 2*minSize[i] + 1);
    if (availIdx.empty)
        return node;

    auto axis = availIdx.pickOne;
    auto pivot = uniform(region.min[axis] + minSize[axis],
                         region.max[axis] - minSize[axis]);

    node.axis = axis;
    node.pivot = pivot;
    node.children[0] = genBsp(leftRegion(region, axis, pivot), minSize);
    node.children[1] = genBsp(rightRegion(region, axis, pivot), minSize);
    return node;
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
int foreachRoom(const(BspNode)* root, Region region,
                int delegate(Region r) dg)
{
    if (root is null)
        return 0;

    if (root.isLeaf)
        return dg(region);

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

    char fl = '0';
    tree.foreachRoom(region, (Region r) {
        foreach (j; r.min[1] .. r.max[1])
            foreach (i; r.min[0] .. r.max[0])
                result[i + j*w] = fl;
        fl++;
        return 0;
    });

    import std.stdio, std.range : chunks;
    writefln("%(%-(%s%)\n%)", result[].chunks(w));
}

// vim:set ai sw=4 ts=4 et:
