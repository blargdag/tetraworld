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

import std.stdio;

import game;
import ui;

/**
 * Main program.
 */
int main()
{
    Game game;
    string welcomeMsg;

    import std.file : exists;
    if (saveFileName.exists)
    {
        game = Game.loadGame();
        welcomeMsg = "Welcome back!";
    }
    else
    {
        game = Game.newGame();
        welcomeMsg = "Welcome to Tetraworld!";
    }

    auto ui = new TextUi;
    try
    {
        auto quitMsg = ui.play(game, welcomeMsg);
        writeln(quitMsg);
        return 0;
    }
    catch (Exception e)
    {
        // Emergency save when things go wrong.
        game.saveGame();
        writefln("Error: %s", e.msg);
        return 1;
    }
}

// vim:set ai sw=4 ts=4 et:
