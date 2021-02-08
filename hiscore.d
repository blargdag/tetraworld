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
import std.conv : to;
import std.datetime;
import std.file : exists;
import std.format;
import std.range;
import std.stdio;

import loadsave;

enum hiscoreFile = ".tetra.hiscores";
enum hiscoreLockFile = ".tetra.hiscores.lock";

enum hiscoreFileVer = 1000;

enum Outcome { giveup, dead, win }

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

    inout(DateTime) toDateTime() inout { return cast(DateTime) impl; }

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
    @NoSave int rank;
    TimeStamp timestamp;
    string name;
    Outcome outcome;
    int levels;
    long turns;
    string desc;
    string lastLocation;

    void toStringImpl(W)(W sink, size_t rankWidth, size_t nameWidth) const
        if (isOutputRange!(W, char))
    {
        auto dt = timestamp.toDateTime;
        sink.formattedWrite("#%-*d   %-*s   %04d-%02d-%02d %02d:%02d:%02d\n",
                            rankWidth, rank, nameWidth, name,
                            dt.year, dt.month, dt.day, dt.hour, dt.minute,
                            dt.second);

        auto loc = (lastLocation.length > 0) ? lastLocation :
                    format("level %d", levels);
        final switch (outcome)
        {
            case Outcome.dead:
                sink.formattedWrite("\tDied in %s after %d turns.\n",
                                    loc, turns);
                break;

            case Outcome.giveup:
                sink.formattedWrite("\tGave up in %s after %d turns.\n",
                                    loc, turns);
                break;

            case Outcome.win:
                sink.formattedWrite("\tEmerged victorious from %s after %d "~
                                    "turns.\n", loc, turns);
                break;
        }

        sink.formattedWrite("\t%s\n", desc);
        sink.formattedWrite("\n");
    }

    void toString(W)(W sink) const
        if (isOutputRange!(W, char))
    {
        toStringImpl(sink, 0, 0);
    }
}

/**
 * Orders the given HiScores by rank.
 */
int cmpByRank(const HiScore a, const HiScore b)
{
    return (a.outcome > b.outcome) ? -1 :
           (a.outcome < b.outcome) ? 1 :
           (a.levels > b.levels) ? -1 :
           (a.levels < b.levels) ? 1 :
           (a.turns < b.turns) ? -1 :
           (a.turns > b.turns) ? 1 :
           a.timestamp.impl.opCmp(b.timestamp.impl);
}

/// ditto
bool orderByRank(const HiScore a, const HiScore b)
{
    return cmpByRank(a, b) < 0;
}

private HiScore[] loadHiScoresImpl()
{
    if (!hiscoreFile.exists)
        return [];

    auto lf = loadFile(File(hiscoreFile, "rb").byLine);
    auto ver = lf.parse!int("version");
    // FIXME: check version and run upgrade code here
    if (ver != hiscoreFileVer)
        throw new Exception("Incompatible high score file version");
        // FIXME: incompatible version should just reset to blank at worst, not
        // error out!

    auto scores = lf.parse!(HiScore[])("hiscores");
    sort!orderByRank(scores);
    return scores;
}

private HiScore[] assignRanks(HiScore[] scores)
{
    foreach (i, ref hs; scores)
    {
        hs.rank = 1 + i.to!int;
    }
    return scores;
}

/**
 * Loads the current high score file.
 */
HiScore[] loadHiScores()
{
    auto lockf = File(hiscoreLockFile, "w+");
    lockf.lock();
    scope(exit) lockf.unlock();

    return loadHiScoresImpl().assignRanks;
}

/**
 * Appends the given score to the high score file.
 */
HiScore addHiScore(HiScore score)
{
    auto lockf = File(hiscoreLockFile, "w+");
    lockf.lock();
    scope(exit) lockf.unlock();

    auto scores = loadHiScoresImpl();
    auto rank = 1 + scores.assumeSorted!orderByRank.lowerBound(score).length;
    score.rank = rank.to!int;
    scores ~= score;
    sort!orderByRank(scores);

    auto sf = File(hiscoreFile, "wb").lockingTextWriter.saveFile;
    sf.put("version", hiscoreFileVer);
    sf.put("hiscores", scores);

    return score;
}

/**
 * Format given hiscores into the given sink.
 */
void printHiScores(W)(W sink, HiScore[] scores)
    if (isOutputRange!(W, char))
{
    auto rankWidth = format("%d", scores.length + 1).length;
    auto nameWidth = scores.map!(hs => hs.name.length)
                           .maxElement(0)
                           .max(4);

    foreach (i, hs; scores)
    {
        hs.toStringImpl(sink, rankWidth, nameWidth);
    }
}

unittest
{
    auto data = [
        HiScore(1, TimeStamp("2020-10-16T14:21:21.0391709"), "JSWalker",
                Outcome.dead, 4, 501,
                "Eaten by a ravenous glomiferous worm.",
                "Swamp Mines"),
        HiScore(2, TimeStamp("2020-11-11T09:51:05.7083912"), "tetra",
                Outcome.dead, 9, 6501,
                "Dissolved in acid.",
                "Abandoned Factory"),
        HiScore(3, TimeStamp("2020-12-05T19:29:47.8518203"), "newb",
                Outcome.dead, 3, 342,
                "Disintegrated from direct exposure to 4D space."),
    ];
    auto app = appender!string;

    printHiScores(app, data);

    assert(app.data ==
        "#1   JSWalker   2020-10-16 14:21:21\n"~
        "\tDied in Swamp Mines after 501 turns.\n"~
        "\tEaten by a ravenous glomiferous worm.\n"~
        "\n"~
        "#2   tetra      2020-11-11 09:51:05\n"~
        "\tDied in Abandoned Factory after 6501 turns.\n"~
        "\tDissolved in acid.\n"~
        "\n"~
        "#3   newb       2020-12-05 19:29:47\n"~
        "\tDied in level 3 after 342 turns.\n"~
        "\tDisintegrated from direct exposure to 4D space.\n"~
        "\n"
    );
}

// vim:set ai sw=4 ts=4 et:
