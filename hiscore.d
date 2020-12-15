/**
 * Module dealing with player death and log of past games.
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
module hiscore;

import std.algorithm;
import std.array;
import std.datetime;
import std.file : exists;
import std.format;
import std.range;
import std.stdio;

import loadsave;

enum hiscoreFile = ".tetra.hiscores";
enum Outcome { dead, giveup, win }

/**
 * Wrapper around sys.datetime.SysTime to integrate it nicely into our
 * load/save system.
 */
@TreatAsString
struct TimeStamp
{
    SysTime impl;

    this(string isoExtString)
    {
        impl = SysTime.fromISOExtString(isoExtString);
    }

    this(SysTime time)
    {
        impl = time;
    }

    void toString(R)(R sink)
        if (isOutputRange!(R, char))
    {
        put(sink, impl.toISOExtString);
    }

    unittest
    {
        TimeStamp ts;
        auto app = appender!string;
        ts.toString(app);
    }

    unittest
    {
        TimeStamp ts;
        ts.impl = SysTime(DateTime(2020, 12, 15, 9, 48, 40), UTC());
        auto app = appender!string;
        auto sf = saveFile(app);
        sf.put("timestamp", ts);

        auto saved = app.data;
        auto lf = loadFile(saved.splitter("\n"));
        auto ts2 = lf.parse!TimeStamp("timestamp");
        assert(ts == ts2);
    }
}

/**
 * An entry in the high score board.
 */
struct HiScore
{
    TimeStamp timestamp;
    int rank; // TBD
    string name;
    ulong turns;
    Outcome outcome;
    string desc;

    void toString(W)(W sink)
        if (isOutputRange!(W, char))
    {
        string status;
        final switch (outcome)
        {
            case Outcome.dead:      status = "Dead";    break;
            case Outcome.giveup:    status = "Gave up"; break;
            case Outcome.win:       status = "WON";     break;
        }

        sink.formattedWrite("%s | %s in %d turns | %s",
                            name, status, turns, desc);
    }
}

/**
 * Loads the current high score file.
 */
HiScore[] loadHiScores()
{
    if (!hiscoreFile.exists)
        return [];

    auto lf = loadFile(File(hiscoreFile, "rb").byLine);
    return lf.parse!(HiScore[])("hiscores");
}

/**
 * Appends the given score to the high score file.
 *
 * BUGS: currently, does not protect against concurrent accesses.
 */
void addHiScore(HiScore score)
{
    auto scores = loadHiScores();
    scores ~= score;
    auto sf = File(hiscoreFile, "ab").lockingTextWriter.saveFile;
    sf.put("hiscores", scores);
}

// vim:set ai sw=4 ts=4 et:
