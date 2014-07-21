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
    /// The dimension of this vector.
    enum dim = n;

    /**
     * Retrieve this vector's contents as a tuple of n integers.
     */
    TypeVec!(T,n) byComponent;
    alias byComponent this;

    /**
     * Per-element unary operations.
     */
    Vec opUnary(string op)()
        if (is(typeof((T t) => mixin(op ~ "t"))))
    {
        Vec result;
        foreach (i, ref x; result.byComponent)
        {
            x = mixin(op ~ "this[i]");
        }
        return result;
    }

    /**
     * Per-element binary operations.
     */
    Vec opBinary(string op, U)(Vec!(U,n) v)
        if (is(typeof(mixin("T.init" ~ op ~ "U.init"))))
    {
        Vec result;
        foreach (i, ref x; result.byComponent)
        {
            x = mixin("this[i]" ~ op ~ "v[i]");
        }
        return result;
    }

    /// ditto
    Vec opBinary(string op, U)(U y)
        if (isScalar!U &&
            is(typeof(mixin("T.init" ~ op ~ "U.init"))))
    {
        Vec result;
        foreach (i, ref x; result.byComponent)
        {
            x = mixin("this[i]" ~ op ~ "y");
        }
        return result;
    }

    /// ditto
    Vec opBinaryRight(string op, U)(U y)
        if (isScalar!U &&
            is(typeof(mixin("U.init" ~ op ~ "T.init"))))
    {
        Vec result;
        foreach (i, ref x; result.byComponent)
        {
            x = mixin("y" ~ op ~ "this[i]");
        }
        return result;
    }

    /**
     * Per-element assignment operators.
     */
    void opOpAssign(string op, U)(Vec!(U,n) v)
        if (is(typeof({ T t; mixin("t " ~ op ~ "= U.init;"); })))
    {
        foreach (i, ref x; byComponent)
        {
            mixin("x " ~ op ~ "= v[i];");
        }
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
    static if (is(typeof([args]) : U[], U))
        return Vec!(U, args.length)(args);
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

    // Vector components can be individually passed to functions via
    // .byComponent:
    void func(int x, int y, int z) { }
    func(v1.byComponent);

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
    auto v = Vec!(int,3)(1,2,3);
    auto w = Vec!(int,3)(4,5,6);
    v += w;
    assert(v == vec(5,7,9));
}

/**
 * Represents an n-dimensional cubic subregion of an n-dimensional cube, or
 * equivalently, the upper and lower bounds of the n components of an
 * n-dimensional vector.
 */
struct Region(T, size_t n)
    if (is(typeof(T.init < T.init)))
{
    import std.typecons : staticIota;

    /**
     * The bounds of the n-dimensional cube.
     *
     * The lowerbound is inclusive, whereas the upperbound is exclusive; hence,
     * when any element of lowerBound is equal to the corresponding element of
     * upperBound, the region is empty.
     */
    Vec!(T,n) lowerBound;
    Vec!(T,n) upperBound; /// ditto

    /**
     * Constructor.
     *
     * The single-argument case defaults the lowerBound to (T.init, T.init,
     * ...).
     */
    this(Vec!(T,n) _upperBound)
    {
        upperBound = _upperBound;
    }

    /// ditto
    this(Vec!(T,n) _lowerBound, Vec!(T,n) _upperBound)
    {
        lowerBound = _lowerBound;
        upperBound = _upperBound;
    }

    /**
     * Returns: false if every element of lowerBound is strictly less than the
     * corresponding element of upperBound; true otherwise.
     */
    @property bool empty()
    {
        foreach (i; staticIota!(0, n))
            if (lowerBound[i] >= upperBound[i])
                return true;
        return false;
    }
}

/// ditto
auto region(T, size_t n)(Vec!(T,n) upperBound)
{
    return Region!(T,n)(upperBound);
}

/// ditto
auto region(T, size_t n)(Vec!(T,n) lowerBound, Vec!(T,n) upperBound)
{
    return Region!(T,n)(lowerBound, upperBound);
}

unittest
{
    Region!(int,4) r0;
    assert(r0.empty);

    auto r1 = region(vec(2,2,2,2));
    assert(r1.lowerBound == vec(0,0,0,0) && r1.upperBound == vec(2,2,2,2));
    assert(!r1.empty);

    auto r2 = region(vec(1,1,1,1), vec(2,2,2,2));
    assert(r2.lowerBound == vec(1,1,1,1) && r2.upperBound == vec(2,2,2,2));
    assert(!r2.empty);

    assert(region(vec(1,1,1,1), vec(0,0,0,0)).empty);
    assert(region(vec(1,1,1,1), vec(1,1,1,0)).empty);
    assert(region(vec(1,1,1,1), vec(2,2,2,1)).empty);
    assert(region(vec(1,1,1,1), vec(2,1,2,2)).empty);
    assert(region(vec(1,1,1,1), vec(2,0,2,2)).empty);
}

// vim:set ai sw=4 ts=4 et:
