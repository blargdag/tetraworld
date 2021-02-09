/**
 * Data files and directory paths.
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
module config;

import std.path;
import std.process;

/**
 * Returns: The path to the data directory where game files are stored.
 *
 * BUGS: Currently this is just a user-local directory where we store all our
 * stuff. Eventually we should split per-user config and global data (e.g.
 * hiscore files) in their respective locations per OS conventions.
 */
string gameDataDir()
{
    string path;
    version(Posix)
    {
        path = buildPath(environment["HOME"], ".tetraworld");
    }
    else version(Windows)
    {
        path = buildPath(environment["APPDATA"], "tetraworld");
    }
    else static assert(0, "Unknown OS, please add datadir path");

    import std.file : mkdirRecurse;
    mkdirRecurse(path);

    return path;
}

// vim:set ai sw=4 ts=4 et:
