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
import vector;

/**
 * A BSP tree node.
 */
class BspNode(Derived)
{
    int axis;
    int pivot;
    Derived left, right;

    final bool isLeaf() const { return left is null && right is null; }
}

/**
 * Plain BSP node with no additional data. Mainly just for testing purposes.
 */
class Node : BspNode!Node { }

/**
 * Returns: The subregion to the "left" of the given region along the given
 * axis and splitting pivot.
 */
R leftRegion(R)(R r, int axis, int pivot)
    in (axis < r.n)
{
    auto result = r;
    result.max[axis] = pivot;
    return result;
}

/**
 * Returns: The subregion to the "right" of the given region along the given
 * axis and splitting pivot.
 */
R rightRegion(R)(R r, int axis, int pivot)
    in (axis < r.n)
{
    auto result = r;
    result.min[axis] = pivot;
    return result;
}

unittest
{
    auto r = region(vec(0, 0, 0, 0), vec(5, 5, 5, 5));
    assert(leftRegion(r, 0, 3) == region(vec(0, 0, 0, 0), vec(3, 5, 5, 5)));
    assert(rightRegion(r, 0, 3) == region(vec(3, 0, 0, 0), vec(5, 5, 5, 5)));

    assert(leftRegion(r, 1, 3) == region(vec(0, 0, 0, 0), vec(5, 3, 5, 5)));
    assert(rightRegion(r, 1, 3) == region(vec(0, 3, 0, 0), vec(5, 5, 5, 5)));

    assert(leftRegion(r, 2, 4) == region(vec(0, 0, 0, 0), vec(5, 5, 4, 5)));
    assert(rightRegion(r, 2, 4) == region(vec(0, 0, 4, 0), vec(5, 5, 5, 5)));
}

unittest
{
    auto r = region(vec(2, 2, 2, 2), vec(5, 5, 5, 5));
    assert(leftRegion(r, 0, 3) == region(vec(2, 2, 2, 2), vec(3, 5, 5, 5)));
    assert(rightRegion(r, 0, 3) == region(vec(3, 2, 2, 2), vec(5, 5, 5, 5)));
}

enum invalidAxis = -1;
enum invalidPivot = int.min;

/**
 * Generate a BSP partitioning of the given region with the given splitting
 * parameters.
 *
 * Params:
 *  Node = The node type to use for internal nodes.
 *  Leaf = The node type to use for leaf nodes.
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
Node genBsp(Node, Leaf=Node, R)
           (R region,
            bool delegate(R r) canSplitRegion,
            int delegate(R r) findSplitAxis,
            int delegate(R r, int axis) findPivot)
    if (is(Node : BspNode!D, D) && is(R == Region!(int,n), size_t n))
{
    Leaf newLeaf()
    {
        static if (is(typeof(new Leaf(region)) : Leaf))
            return new Leaf(region);
        else
            return new Leaf;
    }

    if (!canSplitRegion(region))
        return newLeaf();

    auto axis = findSplitAxis(region);
    if (axis == invalidAxis)
        return newLeaf();

    auto pivot = findPivot(region, axis);
    if (pivot == invalidPivot)
        return newLeaf();

    auto node = new Node();
    node.axis = axis;
    node.pivot = pivot;
    node.left = genBsp!(Node, Leaf)(leftRegion(region, axis, pivot),
                                    canSplitRegion, findSplitAxis, findPivot);
    node.right = genBsp!(Node, Leaf)(rightRegion(region, axis, pivot),
                                     canSplitRegion, findSplitAxis, findPivot);
    return node;
}

/**
 * Generate a BSP partitioning of the given region with the given minimum
 * region size.
 */
Node genBsp(Node,R)(R region, int[4] minSize)
    if (is(Node : BspNode!D, D) && is(R == Region!(int,n), size_t n))
{
    import std.algorithm : filter;
    import std.random : uniform;
    import std.range : iota;
    import rndutil : pickOne;

    return genBsp!Node(region,
        (R r) => true,
        (R r) {
            auto axes = iota(4)
                .filter!(i => r.max[i] - r.min[i] >= 2*minSize[i] + 1);
            return axes.empty ? invalidAxis : axes.pickOne;
        },
        (R r, int axis) => uniform(r.min[axis] + minSize[axis],
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
int foreachRoom(Node,R)(Node root, R region, int delegate(R r, Node n) dg)
    if (is(Node : BspNode!D, D) && is(R == Region!(int,n), size_t n))
{
    if (root is null)
        return 0;

    if (root.isLeaf)
        return dg(region, root);

    int rc = foreachRoom(root.left, leftRegion(region, root.axis, root.pivot),
                         dg);
    if (rc != 0) return rc;

    return foreachRoom(root.right, rightRegion(region, root.axis, root.pivot),
                       dg);
}

unittest
{
    enum w = 24, h = 24;
    char[w*h] result;
    foreach (ref ch; result) { ch = '#'; }

    auto reg = region(vec(0, 0, 0, 0), vec(w, h, 0, 0));
    auto tree = genBsp!Node(reg, [ 3, 3, 0, 0 ]);

    char fl = '!';
    tree.foreachRoom(reg, (Region!(int,4) r, Node n) {
        foreach (j; r.min[1] .. r.max[1])
            foreach (i; r.min[0] .. r.max[0])
                result[i + j*w] = fl;
        fl++;
        return 0;
    });

    import std.stdio, std.range : chunks;
    //writefln("\n%(%-(%s%)\n%)", result[].chunks(w));
}

/**
 * Invokes the given delegate on every child node that passes the specified
 * region filter and whose parent nodes also pass the filter.
 *
 * Params:
 *  root = Root of the BSP tree.
 *  region = Initial bounding region for the BSP tree.
 *  filter = A delegate that returns true if the given region passes the
 *      filter, or a Region with which child nodes must intersect. Note that
 *      the filter delegate must also pass the regions of ancestor nodes if
 *      descendent nodes are to be accepted, since subtrees are pruned early
 *      based on the filter applied to ancestor nodes. (This requirement is
 *      automatically met if a Region is passed as filter.)
 *  dg = Delegate to invoke per leaf node that passes the filter. Should
 *      normally return 0; returning non-zero aborts the search.
 *
 * Returns: 0 if the iteration was completed, or the non-zero value returned by
 * dg if iteration was stopped before the end.
 */
int foreachFiltRoom(Node,R)(Node root, R region,
                            bool delegate(R) filter, int delegate(Node, R) dg)
    if (is(R == Region!(int,n), size_t n))
{
    if (root.isLeaf)
    {
        if (filter(region))
            return dg(root, region);
        else return 0;
    }

    auto lr = leftRegion(region, root.axis, root.pivot);
    if (filter(lr))
    {
        auto rc = foreachFiltRoom(root.left, lr, filter, dg);
        if (rc != 0)
            return rc;
    }

    auto rr = rightRegion(region, root.axis, root.pivot);
    if (filter(rr))
        return foreachFiltRoom(root.right, rr, filter, dg);

    return 0;
}

/// ditto
int foreachFiltRoom(Node,R)(Node root, R region, R filter,
                            int delegate(Node, R) dg)
    if (is(R == Region!(int,n), size_t n))
{
    return foreachFiltRoom(root, region, (R r) => r.intersects(filter), dg);
}

unittest
{
    auto root = new Node;
    root.axis = 0;
    root.pivot = 4;

    root.left = new Node;
    root.left.axis = 1;
    root.left.pivot = 5;

    root.left.left = new Node;
    root.left.right = new Node;

    root.right = new Node;
    root.right.axis = 1;
    root.right.pivot = 7;

    root.right.left = new Node;
    root.right.left.axis = 1;
    root.right.left.pivot = 3;

    root.right.left.left = new Node;

    root.right.left.right = new Node;
    root.right.left.right.axis = 0;
    root.right.left.right.pivot = 8;

    root.right.left.right.left = new Node;
    root.right.left.right.right = new Node;

    root.right.right = new Node;

    auto bounds = region(vec(0, 0, 0, 0), vec(12, 10, 1, 1));
    auto filter = region(vec(3, 0, 0, 0), vec(4, 3, 1, 1));

    //import testutil;
    //TestScreen!(12,10) scrn;
    //dumpBsp(scrn, root, bounds);

    Region!(int,4)[] regions;
    auto r = foreachFiltRoom(root, bounds, filter,
        (Node node, Region!(int,4) r)
        {
            regions ~= r;
            return 0;
        }
    );

    assert(regions == [
        region(vec(0, 0, 0, 0), vec(4, 5, 1, 1)),
        region(vec(4, 0, 0, 0), vec(12, 3, 1, 1)),
        region(vec(4, 3, 0, 0), vec(8, 7, 1, 1)),
    ]);
}

unittest
{
    auto root = new Node;
    root.axis = 0;
    root.pivot = 5;

    root.left = new Node;
    root.left.axis = 1;
    root.left.pivot = 5;

    root.left.left = new Node;
    root.left.left.axis = 2;
    root.left.left.pivot = 5;

    root.left.left.left = new Node;
    root.left.left.right = new Node;

    root.left.right = new Node;

    root.right = new Node;
    root.right.axis = 2;
    root.right.pivot = 2;

    root.right.left = new Node;

    root.right.right = new Node;
    root.right.right.axis = 1;
    root.right.right.pivot = 2;

    root.right.right.left = new Node;
    root.right.right.right = new Node;

    auto bounds = region(vec(0, 0, 0, 0), vec(10, 10, 10, 1));
    auto filter = region(vec(5, 2, 2, 0), vec(5, 5, 5, 1));

    Region!(int,4)[] regions;
    auto r = foreachFiltRoom(root, bounds, filter,
        (Node node, Region!(int,4) r)
        {
            regions ~= r;
            return 0;
        }
    );

    assert(regions == [
        region(vec(5, 2, 2, 0), vec(10, 10, 10, 1)),
    ]);
}

// vim:set ai sw=4 ts=4 et:
