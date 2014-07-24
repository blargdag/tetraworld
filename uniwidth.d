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

struct CodeRange
{
    dchar start, end;

    bool canMerge(CodeRange cr)
    {
        return ((start >= cr.start && start < cr.end) ||
                (end >= cr.start && end < cr.end));
    }

    unittest
    {
        assert(CodeRange(1,11).canMerge(CodeRange(11,12)));
        assert(!CodeRange(1,10).canMerge(CodeRange(11,12)));
    }

    void merge(CodeRange cr)
    in { assert(canMerge(cr)); }
    body
    {
        start = min(start, cr.start);
        end = max(end, cr.end);
    }

    unittest
    {
        auto cr = CodeRange(10,20);
        cr.merge(CodeRange(20,30));
        assert(cr == CodeRange(10,30));
    }

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;
        sink.formattedWrite("%04X", start);
        if (end > start+1)
            sink.formattedWrite("..%04X", end-1);
    }
}

void main()
{
    auto reSingle = regex(`^([0-9A-F]+);(N|A|H|W|F|Na)\b`);
    auto reRange = regex(`^([0-9A-F]+)\.\.([0-9A-F]+);(N|A|H|W|F|Na)\b`);

    // For our purposes, we don't need to distinguish between explicit/implicit
    // narrowness, and ambiguous cases can just default to narrow. So we map
    // the original width to its equivalent using the following equivalence
    // table.
    string[string] equivs = [
        "Na" : "N",
        "N"  : "N",
        "H"  : "N",
        "A"  : "N",
        "W"  : "W",
        "F"  : "W"
    ];

    CodeRange[][string] widths;

    void addRange(CodeRange range, string width)
    {
        auto ranges = width in widths;
        if (ranges && ranges.length > 0 && (*ranges)[$-1].canMerge(range))
        {
            (*ranges)[$-1].merge(range);
        }
        else
            widths[width] ~= range;
    }

    foreach (line; File("ext/EastAsianWidth.txt", "r").byLine())
    {
        if (line.startsWith("#"))
            continue;

        if (auto m = line.match(reSingle))
        {
            auto width = equivs[m.captures[2]];
            dchar ch = cast(dchar) m.captures[1].to!int(16);
            addRange(CodeRange(ch, ch+1), width);
        }
        else if (auto m = line.match(reRange))
        {
            auto width = equivs[m.captures[3]];
            dchar start = cast(dchar) m.captures[1].to!int(16);
            dchar end = cast(dchar) m.captures[2].to!int(16) + 1;
            addRange(CodeRange(start, end), width);
        }
    }

    foreach (width; widths.byKey())
    {
        writeln("# ", width);
        foreach (range; widths[width])
        {
            writefln("%s;%s", range, width);
        }
        writeln();
    }
}

// vim:set ai sw=4 ts=4 et:
