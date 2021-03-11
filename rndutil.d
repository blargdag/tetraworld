/**
 * Various RNG-related functions.
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
module rndutil;

import std.range.primitives;

/**
 * Use the Box-Muller transform to return a random point with the given mean
 * position drawn from a Gaussian distribution with the given deviation.
 */
int[2] gaussianPoint(int[2] mean, int deviation)
{
    import std.math : cos, log, sin, sqrt, PI;
    import std.random : uniform01;

    auto u = uniform01();
    auto v = uniform01();
    auto x0 = sqrt(-2.0*log(u)) * cos(2.0*PI*v);
    auto y0 = sqrt(-2.0*log(u)) * sin(2.0*PI*v);

    int[2] result;
    result[0] = mean[0] + cast(int)(deviation * x0);
    result[1] = mean[1] + cast(int)(deviation * y0);
    return result;
}

/**
 * Convenient shorthand for discarding a sample from gaussianPoint and
 * returning the other.
 */
int gaussian(int mean, int deviation)
{
    int[2] meanv = [ mean, 0 ];
    return gaussianPoint(meanv, deviation)[0];
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
    import std.traits : Unqual;

    Unqual!(ElementType!R) result = range.front;
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

// vim: set ts=4 sw=4 et ai:
