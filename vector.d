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
module vector;

/**
 * Checks if a given type is a scalar type or an instance of Vec!(T,n).
 */
enum isScalar(T) = !is(T : Vec!(U,n), U, size_t n);
static assert(isScalar!int);
static assert(!isScalar!(Vec!(int,2)));

/**
 * Represents an n-dimensional vector of values.
 */
struct Vec(T, size_t n)
{
    T[n] impl;
    alias impl this;

    /**
     * Compares two vectors.
     */
    bool opEquals()(auto ref const Vec v) const
    {
        foreach (i; 0 .. n)
        {
            if (impl[i] != v[i])
                return false;
        }
        return true;
    }

    /**
     * Per-element unary operations.
     */
    Vec opUnary(string op)()
        if (is(typeof((T t) => mixin(op ~ "t"))))
    {
        Vec result;
        foreach (i, ref x; result.impl)
            x = mixin(op ~ "this[i]");
        return result;
    }

    /**
     * Per-element binary operations.
     */
    Vec opBinary(string op, U)(Vec!(U,n) v)
        if (is(typeof(mixin("T.init" ~ op ~ "U.init"))))
    {
        Vec result;
        foreach (i, ref x; result.impl)
            x = mixin("this[i]" ~ op ~ "v[i]");
        return result;
    }

    /// ditto
    Vec opBinary(string op, U)(U y)
        if (isScalar!U &&
            is(typeof(mixin("T.init" ~ op ~ "U.init"))))
    {
        Vec result;
        foreach (i, ref x; result.impl)
            x = mixin("this[i]" ~ op ~ "y");
        return result;
    }

    /// ditto
    Vec opBinaryRight(string op, U)(U y)
        if (isScalar!U &&
            is(typeof(mixin("U.init" ~ op ~ "T.init"))))
    {
        Vec result;
        foreach (i, ref x; result.impl)
            x = mixin("y" ~ op ~ "this[i]");
        return result;
    }

    /**
     * Per-element assignment operators.
     */
    void opOpAssign(string op, U)(Vec!(U,n) v)
        if (is(typeof({ T t; mixin("t " ~ op ~ "= U.init;"); })))
    {
        foreach (i, ref x; impl)
            mixin("x " ~ op ~ "= v[i];");
    }
}

/**
 * Convenience function for creating vectors.
 * Returns: Vec!(U,n) instance where n = args.length, and U is the common type
 * of the elements given in args. A compile-time error results if the arguments
 * have no common type.
 */
auto vec(T...)(T args)
{
    static if (args.length == 1 && is(T[0] == U[n], U, size_t n))
        return Vec!(U, n)(args);
    else static if (is(typeof([args]) : U[], U))
        return Vec!(U, args.length)([ args ]);
    else
        static assert(false, "No common type for " ~ T.stringof);
}

///
unittest
{
    // Basic vector construction
    auto v1 = vec(1,2,3);
    static assert(is(typeof(v1) == Vec!(int,3)));
    assert(v1[0] == 1 && v1[1] == 2 && v1[2] == 3);

    // Vector comparison
    auto v2 = vec(1,2,3);
    assert(v1 == v2);

    // Unary operations
    assert(-v1 == vec(-1, -2, -3));
    assert(++v2 == vec(2,3,4));
    assert(v2 == vec(2,3,4));
    assert(v2-- == vec(2,3,4));
    assert(v2 == vec(1,2,3));

    // Binary vector operations
    auto v3 = vec(2,3,1);
    assert(v1 + v3 == vec(3,5,4));

    auto v4 = vec(1.1, 2.2, 3.3);
    static assert(is(typeof(v4) == Vec!(double,3)));
    assert(v4 + v1 == vec(2.1, 4.2, 6.3));

    // Binary operations with scalars
    assert(vec(1,2,3)*2 == vec(2,4,6));
    assert(vec(4,2,6)/2 == vec(2,1,3));
    assert(3*vec(1,2,3) == vec(3,6,9));

    // Non-numeric vectors
    auto sv1 = vec("a", "b");
    static assert(is(typeof(sv1) == Vec!(string,2)));
    assert(sv1 ~ vec("c", "d") == vec("ac", "bd"));
    assert(sv1 ~ "post" == vec("apost", "bpost"));
    assert("pre" ~ sv1 == vec("prea", "preb"));
}

unittest
{
    // Test opOpAssign.
    auto v = vec(1,2,3);
    auto w = vec(4,5,6);
    v += w;
    assert(v == vec(5,7,9));
}

unittest
{
    int[4] z = [ 1, 2, 3, 4 ];
    auto v = vec(z);
    static assert(is(typeof(v) == Vec!(int,4)));
    assert(v == vec(1, 2, 3, 4));
}

/**
 * Represents an n-dimensional cubic subregion of an n-dimensional cube, or
 * equivalently, the upper and lower bounds of the n components of an
 * n-dimensional vector.
 */
struct Region(T, size_t _n)
    if (is(typeof(T.init < T.init)))
{
    import std.traits : CommonType;

    /**
     * The dimensionality of this region.
     */
    enum n = _n;

    /**
     * The bounds of the n-dimensional cube.
     *
     * The lowerbound is inclusive, whereas the upperbound is exclusive; hence,
     * when any element of min is equal to the corresponding element of max,
     * the region is empty.
     */
    Vec!(T,n) min;
    Vec!(T,n) max; /// ditto

    /**
     * Constructor.
     *
     * The single-argument case defaults the min to (T.init, T.init, ...).
     */
    this(Vec!(T,n) _upperBound)
    {
        max = _upperBound;
    }

    /// ditto
    this(Vec!(T,n) _lowerBound, Vec!(T,n) _upperBound)
    {
        min = _lowerBound;
        max = _upperBound;
    }

    /**
     * Returns: The length of the Region along the i'th dimension.
     */
    @property auto length()(uint i)
        if (is(typeof(T.init - T.init)))
    {
        return max[i] - min[i];
    }

    /**
     * Returns: Vector of the lengths of this Region along each dimension of
     * type Vec!(U,n), where U is the type of the difference between two
     * instances of T.
     */
    @property auto lengths()()
        if (is(typeof(T.init - T.init)))
    {
        alias U = typeof(T.init - T.init);

        Vec!(U,n) result;
        foreach (i; 0 .. cast(uint) n)
            result[i] = length(i);
        return result;
    }

    static if (is(typeof(T.init*T.init*T.init)))
    {
        /**
         * Returns: The volume of this region.
         */
        auto volume()() const
        {
            import std.algorithm : map, fold;
            import std.range : iota;
            return iota(4).map!(i => max[i] - min[i])
                          .fold!((a, b) => a*b)(1);
        }

        ///
        unittest
        {
            assert(region(vec(0, 0, 0, 0), vec(2, 3, 5, 7)).volume == 210);
            assert(region(vec(0, 0, 0, 7), vec(2, 3, 5, 7)).volume == 0);
            assert(region(vec(4, 3, 2, 1), vec(6, 6, 7, 8)).volume == 210);
        }
    }

    /**
     * Returns: false if every element of min is strictly less than the
     * corresponding element of max; true otherwise.
     */
    @property bool empty()
    {
        static foreach (i; 0 .. n)
            if (min[i] >= max[i])
                return true;
        return false;
    }

    /**
     * Returns: true if the given vector lies within the region; false
     * otherwise. Lying within means each component c of the vector satisfies l
     * <= c < h, where l and h are the corresponding components from min and
     * max, respectively.
     */
    bool contains(U)(Vec!(U,n) v)
        if (is(typeof(T.init < U.init)))
    {
        static foreach (i; 0 .. n)
        {
            if (v[i] < min[i] || v[i] >= max[i])
                return false;
        }
        return true;
    }

    /**
     * Returns: true if this region lies within the given region r. Lying
     * within means all of the bounds in the given region is either the same,
     * or a narrowing of the corresponding bounds in this region. Empty regions
     * never contain anything, but are contained by all non-empty regions.
     */
    bool contains(U)(Region!(U,n) r)
        if (is(typeof(T.init < U.init)))
    {
        static foreach (i; 0 .. n)
        {
            // Empty regions never contain anything
            if (min[i] >= max[i])
                return false;

            // Empty regions are always contained in non-empty regions.
            assert(min[i] < max[i]);
            if (r.min[i] < r.max[i] && (r.min[i] < min[i] || r.max[i] > max[i]))
                return false;
        }
        return true;
    }

    /**
     * Returns: true if this region intersects with the given region.
     */
    bool intersects(U)(Region!(U,n) r)
        if (is(typeof(T.init < U.init)) && is(CommonType!(T,U)))
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
        foreach (i; 0 .. n)
        {
            if (r.max[i] < this.min[i] || r.min[i] >= this.max[i])
                return 0;
        }
        return 1;
    }

    ///
    unittest
    {
        assert( region(vec(0,0,0,0), vec(2,2,2,2)).intersects(
                region(vec(1,1,1,1), vec(3,3,3,3))));
        assert(!region(vec(0,0,0,0), vec(1,1,1,1)).intersects(
                region(vec(2,2,2,2), vec(3,3,3,3))));
    }

    /**
     * Computes intersection of two regions.
     */
    Region!(CommonType!(T,U),n) intersect(U)(Region!(U,n) r)
        if (is(typeof(T.init < U.init)) && is(CommonType!(T,U)))
    {
        Region!(CommonType!(T,U),n) result;
        static foreach (i; 0 .. n)
        {
            import std.algorithm : max, min;
            result.min[i] = max(this.min[i], r.min[i]);
            result.max[i] = min(this.max[i], r.max[i]);
        }
        return result;
    }

    /**
     * Returns: A region of the specified dimensions centered on this region.
     */
    Region centeredRegion(Vec!(T,n) size)
    {
        auto lb = min + (max - min - size)/2;
        return Region(lb, lb + size);
    }
}

/// ditto
auto region(T, size_t n)(Vec!(T,n) max)
{
    return Region!(T,n)(max);
}

/// ditto
auto region(T, size_t n)(Vec!(T,n) min, Vec!(T,n) max)
{
    return Region!(T,n)(min, max);
}

unittest
{
    Region!(int,4) r0;
    assert(r0.empty);

    // Test ctors & .empty
    auto r1 = region(vec(2,2,2,2));
    assert(r1.min == vec(0,0,0,0) && r1.max == vec(2,2,2,2));
    assert(!r1.empty);

    auto r2 = region(vec(1,1,1,1), vec(2,2,2,2));
    assert(r2.min == vec(1,1,1,1) && r2.max == vec(2,2,2,2));
    assert(!r2.empty);

    // Test .empty
    assert(region(vec(1,1,1,1), vec(0,0,0,0)).empty);
    assert(region(vec(1,1,1,1), vec(1,1,1,0)).empty);
    assert(region(vec(1,1,1,1), vec(2,2,2,1)).empty);
    assert(region(vec(1,1,1,1), vec(2,1,2,2)).empty);
    assert(region(vec(1,1,1,1), vec(2,0,2,2)).empty);

    // Test vector containment
    assert(r2.contains(vec(1,1,1,1)));
    assert(!r2.contains(vec(1,1,1,0)));
    assert(!r2.contains(vec(1,1,1,2)));
    assert(!r2.contains(vec(1,1,0,1)));
    assert(!r2.contains(vec(1,1,2,1)));

    // Test region containment
    assert(r2.contains(r2));   // reflexivity
    assert(region(vec(0,0,0,0), vec(2,2,2,2)).contains(r2));
    assert(region(vec(1,0,1,1), vec(2,2,2,2)).contains(r2));
    assert(region(vec(1,1,1,1), vec(3,3,3,3)).contains(r2));
    assert(region(vec(1,1,1,1), vec(3,2,2,2)).contains(r2));

    // Empty regions containment
    assert(region(vec(-1,-1), vec(2,2)).contains(region(vec(0,0))));
    assert(region(vec(1,1), vec(2,2)).contains(region(vec(0,0))));
    assert(!region(vec(0,0)).contains(region(vec(0,0))));
    assert(!region(vec(0,0)).contains(region(vec(-1,-1), vec(1,1))));
}

unittest
{
    // Region intersections
    auto r1 = region(vec(1,1,1), vec(4,3,3));
    auto r2 = region(vec(2,0,0), vec(3,4,3));
    assert(r1.intersect(r2) == region(vec(2,1,1), vec(3,3,3)));

    // Disjoint regions
    auto r3 = region(vec(1,1,1));
    assert(r1.intersect(r3).empty);

    // Intersection with empty region
    auto r4 = region(vec(2,0,0), vec(2,4,4));
    assert(r1.intersect(r4).empty);
}

unittest
{
    auto r = region(vec(0,0,0,0), vec(5,5,5,5)).intersect(
             region(vec(3,3,3,3), vec(7,7,7,7)));
    assert(r == region(vec(3,3,3,3), vec(5,5,5,5)));
    assert(!r.empty);

    assert(region(vec(0,0,0,0), vec(3,3,3,3)).intersect(
           region(vec(4,4,4,4), vec(5,5,5,5))).empty);
}

unittest
{
    // Test centeredRegion
    auto r1 = region(vec(0, 0), vec(5, 5));
    auto r2 = region(vec(1, 1), vec(4, 4));
    assert(r1.centeredRegion(vec(3,3)) == r2);
    assert(r2.centeredRegion(vec(5,5)) == r1);
}

unittest
{
    // Test .lengths
    auto r = region(vec(0,1,2,3), vec(8,7,6,5));
    assert(r.lengths == vec(8,6,4,2));
}

// vim:set ai sw=4 ts=4 et:
