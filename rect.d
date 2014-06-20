/**
 * Module dealing with rectangles and operations on them.
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

module rect;

/**
 * Represents a rectangular area.
 */
struct Rectangle
{
    int x, y, width, height;

    /**
     * Returns: true if this rectangle does not have positive area.
     */
    @property bool empty() { return width <= 0 && height <= 0; }

    unittest
    {
        auto r1 = Rectangle.init;
        assert(r1.empty);

        auto r2 = Rectangle(0, 0, 1, 1);
        assert(!r2.empty);
    }

    /**
     * Returns: A rectangle of the specified dimensions centered in this
     * rectangle.
     * Params:
     *  ctrWidth = Width of centered rectangle.
     *  ctrHeight = Height of centered rectangle.
     */
    Rectangle centerRect(int ctrWidth, int ctrHeight)
    {
        return Rectangle(x + (width - ctrWidth)/2, y + (height - ctrHeight)/2,
                         ctrWidth, ctrHeight);
    }

    unittest
    {
        auto r1 = Rectangle(0, 0, 5, 5);
        auto r2 = Rectangle(1, 1, 3, 3);
        assert(r1.centerRect(3,3) == r2);
        assert(r2.centerRect(5,5) == r1);
    }
}

// vim:set ai sw=4 ts=4 et:
