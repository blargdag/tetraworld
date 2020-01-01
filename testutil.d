/**
 * Various unittesting tools.
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
module testutil;

version(unittest):

struct TestScreen(int w, int h)
{
    import std.format : format;
    dchar[w*h] impl;
    static TestScreen opCall()
    {
        TestScreen result;
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

// vim:set ai sw=4 ts=4 et:
