/**
 * Simple upload script for updating website files.
 *
 * Bash scripting sux. Why not do it in D?!
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

enum server = "eusebeia";
enum port = 62222;
enum destdir = "/var/www/tetraworld/";

enum files = [
    "tetraworld",
    "tetraworld.exe",
	"screenshots/2020-01-28a.gif",
    "www/index.html",
];

void main(string[] args)
{
    if (args.length >= 2 && args[1] == "--for-real")
    {
        writeln("Uploading for real this time!");
        auto rs = execute([
                "scp",
                "-CP" ~ port.to!string
            ] ~ files ~ [
                server ~ ":" ~ destdir
            ]
        );
        if (rs.status != 0)
            writefln("Upload failed: %s", rs.output);
    }
    else
    {
        writefln("Copying to local %s for testing.", destdir);
        mkdirRecurse(destdir);
        auto rs = execute([ "cp" ] ~ files ~ [ destdir ]);
        if (rs.status != 0)
            writefln("Upload failed: %s", rs.output);
    }
}

// vim: set ts=4 sw=4 et ai:
