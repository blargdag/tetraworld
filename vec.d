/**
 * Simple vector implementation.
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
module vec;

/**
 * Template for constructing an n-tuple of a given type T.
 */
template TypeVec(T, size_t n)
{
    import std.typecons : TypeTuple;
    alias tuple = TypeTuple;

    static if (n==0)
        alias TypeVec = tuple!();
    else
        alias TypeVec = tuple!(T, TypeVec!(T, n-1));
}

/**
 * Represents an n-dimensional vector of values.
 */
struct Vec(T, size_t n)
{
    /**
     * Retrieve this vector's contents as a tuple of n integers.
     */
    TypeVec!(T,n) expand;
    alias expand this;
}

///
unittest
{
    auto v3 = Vec!(int,3)(1,2,3);
    assert(v3[0] == 1 && v3[1] == 2 && v3[2] == 3);

    // Vector components can be individually passed to functions via .expand:
    void func(int x, int y, int z) { }
    func(v3.expand);
}

// vim:set ai sw=4 ts=4 et:
