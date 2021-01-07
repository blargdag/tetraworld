/**
 * Yet another 4D world.
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
module tetraworld;

import std.conv : to;
import std.getopt;
import std.range;
import std.stdio;

import game;
import hiscore;
import ui;

/**
 * Main program.
 */
int main(string[] args)
{
    enum Action { play, playTest, showHiScores }
    Action act = Action.play;
    TextUiConfig uiConfig;
    bool testLevel;

    auto optInfo = getopt(args,
        std.getopt.config.caseSensitive,
        "smoothscroll|S",
            "Set smooth scroll total time in msec (0 to disable).",
            &uiConfig.smoothscrollMsec,
        "hiscore|H",
            "Display high score.",
            { act = Action.showHiScores; },
        "record|R",
            "Record session in specified playterm transcript.",
            &uiConfig.tscriptFile,
        "test|T",
            "(Debug version only) Play test level instead of main game.",
            { act = Action.playTest; },
    );

    if (optInfo.helpWanted)
    {
        defaultGetoptPrinter("Tetraworld V3.0", optInfo.options);
        return 1;
    }

    if (act == Action.showHiScores)
    {
        int n = (args.length >= 2) ? args[1].to!int : 5;
        printHiScores((const(char)[] s) { stdout.write(s); },
                      loadHiScores().take(n));
        return 0;
    }

    Game game;

    import std.file : exists;
    if (saveFileName.exists)
        game = Game.loadGame();
    else
    {
        if (act == Action.playTest)
        {
            debug
            {
                game = Game.testLevel();
            }
            else
            {
                stderr.writeln("Test level only available in debug builds");
                return 1;
            }
        }
        else
            game = Game.newGame();
    }

    auto ui = new TextUi(uiConfig);
    try
    {
        auto quitMsg = ui.play(game);
        writeln(quitMsg);

        version(Windows)
        {
            import core.thread : Thread;
            import core.time : dur;
            Thread.sleep(dur!"seconds"(3));
        }
        return 0;
    }
    catch (Exception e)
    {
        // Emergency save when things go wrong.
        game.saveGame();
        writefln("Error: %s", e.msg);
        return 2;
    }
}

// vim:set ai sw=4 ts=4 et:
