/**
 * Functions to generate discrete random numbers with Gaussian distribution.
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
module gauss;

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

// vim: set ts=4 sw=4 et ai:
