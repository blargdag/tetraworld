/**
 * Entity components
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
module components;

import store_traits;

@Indexed @Component
struct Pos
{
    import vector;
    Vec!(int,4) coors;
    alias coors this;

    this(int[4] _coors...) { coors = vec(_coors); }

    import loadsave;
    void load(L)(ref L loadfile)
    {
        coors[] = loadfile.parse!(int[])("coors")[];
    }
}

// vim:set ai sw=4 ts=4 et:
