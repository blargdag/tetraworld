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
import std.range;
import std.regex;
import std.stdio;

struct CodeRange
{
    dchar start, end;

    bool overlaps(CodeRange cr)
    {
        return ((start >= cr.start && start < cr.end) ||
                (end >= cr.start && end < cr.end));
    }

    unittest
    {
        assert(CodeRange(1,11).overlaps(CodeRange(11,12)));
        assert(!CodeRange(1,10).overlaps(CodeRange(11,12)));
    }

    void merge(CodeRange cr)
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

struct Entry
{
    CodeRange range;
    string width;

    void toString(scope void delegate(const(char)[]) sink)
    {
        import std.format : formattedWrite;
        sink.formattedWrite("%s;%s", range, width);
    }
}

/**
 * Returns: An input range of Entry objects.
 */
auto parse(R)(R input)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
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

    auto reEmpty = regex(`^\s*$`);
    auto reSingle = regex(`^([0-9A-F]+);(N|A|H|W|F|Na)\b`);
    auto reRange = regex(`^([0-9A-F]+)\.\.([0-9A-F]+);(N|A|H|W|F|Na)\b`);

    struct Result
    {
        R     range;
        Entry front;
        bool  empty;

        this(R _range)
        {
            range = _range;
            next(); // get things started
        }

        void next()
        {
            while (!range.empty)
            {
                auto line = range.front;

                if (auto m = line.match(reSingle))
                {
                    auto width = equivs[m.captures[2]];
                    dchar ch = cast(dchar) m.captures[1].to!int(16);
                    front = Entry(CodeRange(ch, ch+1), width);
                    empty = false;
                    return;
                }
                else if (auto m = line.match(reRange))
                {
                    auto width = equivs[m.captures[3]];
                    dchar start = cast(dchar) m.captures[1].to!int(16);
                    dchar end = cast(dchar) m.captures[2].to!int(16) + 1;
                    front = Entry(CodeRange(start, end), width);
                    empty = false;
                    return;
                }
                else if (!line.startsWith("#") && !line.match(reEmpty))
                {
                    import std.string : format;
                    throw new Exception("Couldn't parse line:\n%s"
                                        .format(line));
                }

                range.popFront();
            }
            empty = true;
        }

        void popFront()
        {
            range.popFront();
            next();
        }
    }
    static assert(isInputRange!Result);

    return Result(input);
}

void outputByWidthType(R)(R input)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
    CodeRange[][string] widths;
    string lastWidth;

    void addRange(Entry entry)
    {
        auto range = entry.range;
        auto width = entry.width;
        auto ranges = width in widths;
        if (ranges && ranges.length > 0 && width == lastWidth)
        {
            (*ranges)[$-1].merge(range);
        }
        else
            widths[width] ~= range;

        lastWidth = width;
    }

    foreach (entry; input.parse())
    {
         addRange(entry);
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

/**
 * Returns: An input range of Entry objects.
 */
auto mergeConsecutive(R)(R input)
    if (isInputRange!R && is(ElementType!R : Entry))
{
    struct Result
    {
        R     range;
        bool  empty;
        Entry front;

        this(R _range)
        {
            range = _range;
            next();
        }

        void next()
        {
            while (!range.empty)
            {
                auto e = range.front;
                if (front.width != e.width)
                {
                    if (front.width != "")
                    {
                        empty = false;
                        front = e;
                        return;
                    }
                    front = e;
                }
                else
                    front.range.merge(e.range);

                range.popFront();
            }
            empty = (front.width == "");
        }

        void popFront()
        {
            if (range.empty)
                empty = true; // on last element
            else
                next();
        }
    }

    return Result(input);
}

void outputByCodePoint(R)(R input)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
    writefln("%(%s\n%)", input.parse().mergeConsecutive());
}

void tally(R)(R input)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
    int totalW, totalN;

    foreach (e; input.parse().mergeConsecutive())
    {
        if (e.width=="W")
            totalW += (e.range.end - e.range.start);
        else if (e.width=="N")
            totalN += (e.range.end - e.range.start);
        else
            assert(0);
    }
    writefln("Tally: W=%d N=%d\n", totalW, totalN);
}

void genRecogCode(R)(R input)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
    import std.uni;

    CodepointSet wideChars;
    foreach (e; input.parse().mergeConsecutive())
    {
        if (e.width=="W")
            wideChars.add(e.range.start, e.range.end);
    }

    writeln(wideChars.toSourceCode("isWide"));
}

void main()
{
    auto input = File("ext/EastAsianWidth.txt", "r").byLine();
    
    //outputByWidthType(input);
    //outputByCodePoint(input);
    //tally(input);
    genRecogCode(input);
}

// vim:set ai sw=4 ts=4 et:
