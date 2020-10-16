/**
 * Simple utility for building a BSP tree given a set of rectangular regions.
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
import std;
import vector;

class Node
{
    Node left, right;
    int axis, pivot;
    Region!(int,4) interior;
}

/**
 * Find pivot that most evenly divides the given values into two halves.
 *
 * Prerequisites: values must be sorted, otherwise the return value is
 * meaningless.
 */
auto findPivotIdx(R)(R values)
    if (isRandomAccessRange!R && hasLength!R)
    in (!values.empty)
{
    const midx = values.length / 2;
    const median = values[midx];
    foreach (stride; 0 .. midx)
    {
        assert(midx >= stride && midx + stride < values.length);
        if (values[midx - stride] != median)
            return midx - stride + 1;
        if (values[midx + stride] != median)
            return midx + stride;
    }
    return 0;
}

unittest
{
    assert(findPivotIdx([ 0, 0, 0, 0, 1, 1, 1, 1 ]) == 4);
    assert(findPivotIdx([ 0, 0, 0, 1, 1, 1, 1, 1 ]) == 3);
    assert(findPivotIdx([ 0, 0, 0, 0, 0, 1, 1, 1 ]) == 5);
    assert(findPivotIdx([ 0, 0, 0, 0, 0, 0, 0, 1 ]) == 7);
    assert(findPivotIdx([ 0, 0, 0, 0, 0, 0, 0, 0 ]) == 0);

    assert(findPivotIdx([ 0, 1, 2, 3, 4, 5, 6, 7 ]) == 4);
    assert(findPivotIdx([ 0, 1, 2, 2, 2, 5, 5, 7 ]) == 5);
    assert(findPivotIdx([ 0, 1, 2, 3, 3, 3, 5, 7 ]) == 3);

    assert(findPivotIdx([ 0, 1, 2, 3, 4, 5, 6 ]) == 3);
    assert(findPivotIdx([ 0, 1, 2, 3, 3, 5, 6 ]) == 3);
    assert(findPivotIdx([ 0, 1, 2, 2, 4, 5, 6 ]) == 4);
}

size_t numSplits()(Region!(int,4)[] boxes, int axis, int pivot)
{
    return boxes.count!(box => box.min[axis] < pivot && box.max[axis] > pivot);
}

unittest
{
    auto boxes = [
        region(vec(0,0,0,0), vec(3,1,5,1)),
        region(vec(0,0,1,1), vec(5,2,5,2)),
        region(vec(1,0,2,2), vec(2,3,5,3)),
        region(vec(2,0,3,3), vec(3,4,5,4)),
        region(vec(2,0,4,4), vec(4,5,5,5)),
    ];

    assert(boxes.numSplits(0, 0) == 0);
    assert(boxes.numSplits(0, 1) == 2);
    assert(boxes.numSplits(0, 2) == 2);
    assert(boxes.numSplits(0, 3) == 2);
    assert(boxes.numSplits(0, 4) == 1);
    assert(boxes.numSplits(0, 5) == 0);

    assert(boxes.numSplits(1, 0) == 0);
    assert(boxes.numSplits(1, 1) == 4);
    assert(boxes.numSplits(1, 2) == 3);
    assert(boxes.numSplits(1, 3) == 2);
    assert(boxes.numSplits(1, 4) == 1);
    assert(boxes.numSplits(1, 5) == 0);

    assert(boxes.numSplits(2, 0) == 0);
    assert(boxes.numSplits(2, 1) == 1);
    assert(boxes.numSplits(2, 2) == 2);
    assert(boxes.numSplits(2, 3) == 3);
    assert(boxes.numSplits(2, 4) == 4);
    assert(boxes.numSplits(2, 5) == 0);

    assert(boxes.numSplits(3, 0) == 0);
    assert(boxes.numSplits(3, 1) == 0);
    assert(boxes.numSplits(3, 2) == 0);
    assert(boxes.numSplits(3, 3) == 0);
    assert(boxes.numSplits(3, 4) == 0);
    assert(boxes.numSplits(3, 5) == 0);
}

void findAxisPivot(Region!(int,4)[] boxes, out int axis, out int pivot)
{
    size_t minMetric = size_t.max;
    foreach (d; 0 .. 4)
    {
        boxes.sort!((a,b) => a.min[d] < b.min[d]);

        const idealIdx = boxes.length / 2;
        auto idx = findPivotIdx(boxes.map!(box => box.min[d]));
        auto dIdx = (idx < idealIdx) ? idealIdx - idx : idx - idealIdx;

        auto curPivot = boxes[idx].min[d];
        auto nSplits = boxes.numSplits(d, curPivot);

        auto metric = dIdx*dIdx + nSplits*nSplits;
        if (metric < minMetric)
        {
            minMetric = metric;
            axis = d;
            pivot = curPivot;
        }
    }
}

unittest
{
    auto data = [
        region(vec(0,0,0,0), vec(2,5,1,1)),
        region(vec(2,0,0,0), vec(4,5,1,1)),
        region(vec(4,0,0,0), vec(6,2,1,1)),
        region(vec(4,2,0,0), vec(6,4,1,1)),
    ];

    int axis, pivot;
    findAxisPivot(data, axis, pivot);
    assert(axis == 0 && pivot == 4);
}

Node buildBsp(Region!(int,4)[] boxes)
{
    if (boxes.length == 0)
        return null;

    auto node = new Node;
    if (boxes.length == 1)
    {
        node.interior = boxes[0];
        return node;
    }

    // Find "best" pivot
    findAxisPivot(boxes, node.axis, node.pivot);

    // TBD: distribute nodes among child nodes, splitting as necessary

    return node;
}

template Re(string strRegex)
{
    struct Impl
    {
        static Regex!char re;
        static this()
        {
            re = regex(strRegex);
        }
    }
    Regex!char Re() { return Impl.re; }
}

Region!(int,4) parseRegion(const(char)[] input)
{
    auto m = input.matchFirst(
        Re!`\((\d+),(\d+),(\d+),(\d+)\)x\((\d+),(\d+),(\d+),(\d+)\)`);
    enforce(!m.empty);

    return region(vec(m[1].to!int, m[2].to!int, m[3].to!int, m[4].to!int),
                  vec(m[5].to!int, m[6].to!int, m[7].to!int, m[8].to!int));
}

unittest
{
    assert(parseRegion("(1,2,3,4)x(5,6,7,8)") == region(vec(1,2,3,4),
                                                        vec(5,6,7,8)));
}

void main()
{
}

// vim:set ai sw=4 ts=4 et:
