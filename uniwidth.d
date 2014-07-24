/**
 * Simple program to parse EastAsianWidth.txt to extract some useful info.
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

import std.algorithm;
import std.conv;
import std.regex;
import std.stdio;

struct CodeRangeWidth
{
    dchar start, end;
    string width;

    bool canMerge(CodeRangeWidth crw)
    {
        return width == crw.width &&
               ((start >= crw.start && start < crw.end) ||
                (end >= crw.start && end < crw.end));
    }

    CodeRangeWidth merge(CodeRangeWidth crw)
    in { assert(canMerge(crw)); }
    body
    {
        return CodeRangeWidth(min(start, crw.start), max(end, crw.end), width);
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;

        sink.formattedWrite("%04x", start);
        if (end > start+1)
            sink.formattedWrite("..%04x", end);
        sink.formattedWrite(";%s", width);
    }
}

void main()
{
    auto reSingle = regex(`^([0-9A-F]+);(N|A|H|W|F|Na)\b`);
    auto reRange = regex(`^([0-9A-F]+)\.\.([0-9A-F]+);(N|A|H|W|F|Na)\b`);

    foreach (line; File("ext/EastAsianWidth.txt", "r").byLine())
    {
        if (line.startsWith("#"))
            continue;

        if (auto m = line.match(reSingle))
        {
            auto width = m.captures[2].idup;
            dchar ch = cast(dchar) m.captures[1].to!int(16);
            auto crw = CodeRangeWidth(ch, ch+1, width);
            writeln(crw);
        }
        else if (auto m = line.match(reRange))
        {
            auto width = m.captures[3].idup;
            dchar start = cast(dchar) m.captures[1].to!int(16);
            dchar end = cast(dchar) m.captures[2].to!int(16) + 1;
            auto crw = CodeRangeWidth(start, end, width);
            writeln(crw);
        }
    }
}

// vim:set ai sw=4 ts=4 et:
