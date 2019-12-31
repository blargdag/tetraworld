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

    /**
     * Returns: true if the region is empty.
     * NOTE: this is NOT the same as having zero volume; an empty Region is an
     * "invalid" Region that has negative volume, resulting from the
     * intersection of disjoint Regions.
     */
    bool empty()
    {
        foreach (i; 0 .. 4)
        {
            if (min[i] > max[i]) return true;
        }
        return false;
    }

    /**
     * Returns: true if the given point lies within this region; false
     * otherwise.
     */
    bool contains(int[4] point)
    {
        foreach (i; 0 .. 4)
        {
            if (point[i] < min[i] || point[i] >= max[i])
                return false;
        }
        return true;
    }

    unittest
    {
        auto r = Region([3,3,3,3], [6,6,6,6]);
        assert( r.contains([3,3,3,3]));
        assert( r.contains([5,5,5,5]));

        assert(!r.contains([0,0,0,0]));
        assert(!r.contains([6,6,6,6]));
        assert(!r.contains([7,7,7,7]));
    }

    /**
     * Returns: The volume of this region.
     */
    long volume() const
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

    bool intersects(Region r)
    {
        // Cases:
        // 1. |---|
        //          |---|   (no)
        //
        // 2. |---|
        //      |---|       (yes)
        //
        // 3. |----|
        //     |--|         (yes)
        //
        // 4.  |--|
        //    |----|        (yes)
        //
        // 5.   |---|
        //    |---|         (yes)
        //
        // 6.       |---|
        //    |---|         (no)
        foreach (i; 0 .. 4)
        {
            if (r.max[i] < this.min[i] || r.min[i] >= this.max[i])
                return 0;
        }
        return 1;
    }

    ///
    unittest
    {
        assert( Region([0,0,0,0], [2,2,2,2]).intersects(
                Region([1,1,1,1], [3,3,3,3])));
        assert(!Region([0,0,0,0], [1,1,1,1]).intersects(
                Region([2,2,2,2], [3,3,3,3])));
    }

    Region intersection(Region r)
    {
        Region result;
        foreach (i; 0 .. 4)
        {
            import std.algorithm : min, max;
            result.min[i] = max(this.min[i], r.min[i]);
            result.max[i] = min(this.max[i], r.max[i]);
        }
        return result;
    }

    ///
    unittest
    {
        auto r = Region([0,0,0,0], [5,5,5,5]).intersection(
                 Region([3,3,3,3], [7,7,7,7]));
        assert(r == Region([3,3,3,3], [5,5,5,5]));
        assert(!r.empty);

        assert(Region([0,0,0,0], [3,3,3,3]).intersection(
               Region([4,4,4,4], [5,5,5,5])).empty);
    }
}

struct Door
{
    int axis;
    int[4] pos;
}

/**
 * A BSP tree node.
 */
class BspNode
{
    int axis;
    int pivot;
    BspNode[2] children;
    Door[] doors;

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

version(unittest)
{
    struct Screen(int w, int h)
    {
        import std.format : format;
        dchar[w*h] impl;
        static Screen opCall()
        {
            Screen result;
            foreach (ref ch; result.impl) { ch = '#'; }
            return result;
        }
        ref dchar opIndex(int i, int j)
            in (0 <= i && i < w, format("(%d, %d)", i, j))
            in (0 <= j && j < h, format("(%d, %d)", i, j))
        {
            return impl[i + w*j];
        }
        void dump()
        {
            import std.stdio, std.range : chunks;
            writefln("\n%(%-(%s%)\n%)", impl[].chunks(w));
        }
    }

    void renderRoom(S)(ref S screen, Region r, BspNode n)
    {
        dstring walls = "│─.┌└┐┘"d;
        //dstring walls = "|-:,`.'"d;
        foreach (j; r.min[1] .. r.max[1])
            foreach (i; r.min[0] .. r.max[0])
            {
                if (i == r.min[0] || i == r.max[0]-1)
                    screen[i, j] = walls[0];
                else if (j == r.min[1] || j == r.max[1]-1)
                    screen[i, j] = walls[1];
                else
                    screen[i, j] = walls[2];
            }

        screen[r.min[0], r.min[1]] = walls[3];
        screen[r.min[0], r.max[1]-1] = walls[4];
        screen[r.max[0]-1, r.min[1]] = walls[5];
        screen[r.max[0]-1, r.max[1]-1] = walls[6];

        foreach (door; n.doors)
        {
            screen[door.pos[0], door.pos[1]] = door.axis ? '|' : '-';
        }
    }

    void dumpBsp(S)(ref S result, BspNode tree, Region region)
    {
        // Debug map dump 
        int id = 0;
        tree.foreachRoom(region, (Region r, BspNode n) {
            result.renderRoom(r, n);

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
 */
int foreachFiltRoom(BspNode root, Region region,
                    bool delegate(Region) filter,
                    int delegate(BspNode, Region) dg)
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
        auto rc = foreachFiltRoom(root.children[0], lr, filter, dg);
        if (rc != 0)
            return rc;
    }

    auto rr = rightRegion(region, root.axis, root.pivot);
    if (filter(rr))
        return foreachFiltRoom(root.children[1], rr, filter, dg);

    return 0;
}

/// ditto
int foreachFiltRoom(BspNode root, Region region, Region filter,
                            int delegate(BspNode, Region) dg)
{
    return foreachFiltRoom(root, region,
                                   (Region r) => r.intersects(filter), dg);
}

unittest
{
    auto root = new BspNode;
    root.axis = 0;
    root.pivot = 4;

    root.children[0] = new BspNode;
    root.children[0].axis = 1;
    root.children[0].pivot = 5;

    root.children[0].children[0] = new BspNode;
    root.children[0].children[1] = new BspNode;

    root.children[1] = new BspNode;
    root.children[1].axis = 1;
    root.children[1].pivot = 7;

    root.children[1].children[0] = new BspNode;
    root.children[1].children[0].axis = 1;
    root.children[1].children[0].pivot = 3;

    root.children[1].children[0].children[0] = new BspNode;

    root.children[1].children[0].children[1] = new BspNode;
    root.children[1].children[0].children[1].axis = 0;
    root.children[1].children[0].children[1].pivot = 8;

    root.children[1].children[0].children[1].children[0] = new BspNode;
    root.children[1].children[0].children[1].children[1] = new BspNode;

    root.children[1].children[1] = new BspNode;

    auto region = Region([0, 0, 0, 0], [12, 10, 1, 1]);
    auto filter = Region([3, 0, 0, 0], [4, 3, 1, 1]);

    //Screen!(12,10) scrn;
    //dumpBsp(scrn, root, region);

    Region[] regions;
    auto r = foreachFiltRoom(root, region, filter,
    (BspNode node, Region r)
    {
        regions ~= r;
        return 0;
    });

    assert(regions == [
        Region([0, 0, 0, 0], [4, 5, 1, 1]),
        Region([4, 0, 0, 0], [12, 3, 1, 1]),
        Region([4, 3, 0, 0], [8, 7, 1, 1]),
    ]);
}

unittest
{
    auto root = new BspNode;
    root.axis = 0;
    root.pivot = 5;

    root.children[0] = new BspNode;
    root.children[0].axis = 1;
    root.children[0].pivot = 5;

    root.children[0].children[0] = new BspNode;
    root.children[0].children[0].axis = 2;
    root.children[0].children[0].pivot = 5;

    root.children[0].children[0].children[0] = new BspNode;
    root.children[0].children[0].children[1] = new BspNode;

    root.children[0].children[1] = new BspNode;

    root.children[1] = new BspNode;
    root.children[1].axis = 2;
    root.children[1].pivot = 2;

    root.children[1].children[0] = new BspNode;

    root.children[1].children[1] = new BspNode;
    root.children[1].children[1].axis = 1;
    root.children[1].children[1].pivot = 2;

    root.children[1].children[1].children[0] = new BspNode;
    root.children[1].children[1].children[1] = new BspNode;

    auto region = Region([0, 0, 0, 0], [10, 10, 10, 1]);
    auto filter = Region([5, 2, 2, 0], [5, 5, 5, 1]);

    Region[] regions;
    auto r = foreachFiltRoom(root, region, filter,
    (BspNode node, Region r)
    {
        regions ~= r;
        return 0;
    });

    assert(regions == [
        Region([5, 2, 2, 0], [10, 10, 10, 1]),
    ]);
}

/**
 * Generate corridors based on BSP tree structure.
 */
void genCorridors(BspNode root, Region region)
{
    if (root.isLeaf) return;

    genCorridors(root.children[0], leftRegion(region, root.axis, root.pivot));
    genCorridors(root.children[1], rightRegion(region, root.axis, root.pivot));

    static struct LeftRoom
    {
        BspNode node;
        Region region;
    }

    LeftRoom[] leftRooms;
    root.children[0].foreachFiltRoom(region,
        (Region r) => r.max[root.axis] >= root.pivot,
        (BspNode node1, Region r1) {
            leftRooms ~= LeftRoom(node1, r1);
            return 0;
        });

    int ntries=0;
    while (ntries++ < 2*leftRooms.length)
    {
        auto leftRoom = leftRooms.pickOne;
        Region wallFilt = leftRoom.region;
        wallFilt.min[root.axis] = root.pivot;
        wallFilt.max[root.axis] = root.pivot;

        static struct RightRoom
        {
            BspNode node;
            Region region;
            int[4] basePos;
        }

        RightRoom[] rightRooms;
        root.children[1].foreachFiltRoom(region, wallFilt,
            (BspNode node2, Region r2) {
                auto ir = leftRoom.region.intersection(r2);

                int[4] basePos;
                foreach (i; 0 .. 4)
                {
                    import std.random : uniform;
                    if (ir.max[i] - ir.min[i] >= 3)
                        basePos[i] = uniform(ir.min[i]+1, ir.max[i]-1);
                    else
                    {
                        // Overlap is too small to place a door, skip.
//import std.stdio;writefln("left=%s right=%s TOO NARROW, SKIPPING", leftRoom.region, r2);
                        return 0;
                    }
                }

                rightRooms ~= RightRoom(node2, r2, basePos);
                return 0;
            });

        // If can't find a suitable door placement, try picking a different
        // left room.
        if (rightRooms.empty)
        {
//import std.stdio;writefln("left=%s NO MATCH, SKIPPING", leftRoom.region);
            continue;
        }

        auto rightRoom = rightRooms.pickOne;
        auto d = Door(root.axis);

        d.pos = rightRoom.basePos;
        d.pos[d.axis] = root.pivot-1;
        leftRoom.node.doors ~= d;

        d.pos = rightRoom.basePos;
        d.pos[d.axis] = root.pivot;
        rightRoom.node.doors ~= d;
        return;
    }

    // If we got here, it means we're in trouble.
    throw new Exception("No matching door placement found, give up");
}

unittest
{
    enum w = 48, h = 24;
    Screen!(w,h) result;

    import std.algorithm : filter, clamp;
    import std.random : uniform;
    import std.range : iota;
    import gauss;

    // Generate base BSP tree
    auto region = Region([ 0, 0, 0, 0 ], [ w, h, 3, 3 ]);
    auto tree = genBsp(region,
        (Region r) => r.width(0)*r.width(1) > 49 + uniform(0, 50),
        (Region r) => iota(4).filter!(i => r.max[i] - r.min[i] > 8)
                             .pickOne(invalidAxis),
        (Region r, int axis) => (r.max[axis] - r.min[axis] < 8) ?
            invalidPivot : uniform(r.min[axis]+4, r.max[axis]-3)
            //gaussian(r.max[axis] - r.min[axis], 4)
            //    .clamp(r.min[axis] + 3, r.max[axis] - 3)
    );

    // Generate connecting corridors
    genCorridors(tree, region);

    dumpBsp(result, tree, region);
}

// vim:set ai sw=4 ts=4 et:
