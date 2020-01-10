/**
 * Game simulation module.
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
module game;

import std.algorithm;
import std.stdio;

import action;
import components;
import loadsave;
import store;
import store_traits;
import vector;
import world;

/**
 * Logical player input action.
 */
enum PlayerAction
{
    none, up, down, left, right, front, back, ana, kata, apply,
}

/**
 * Generic UI API.
 */
interface GameUi
{
    /**
     * Add a message to the message log.
     */
    void message(string msg);

    /// ditto
    final void message(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        message(format(fmt.args));
    }

    /**
     * Read player action from user input.
     */
    PlayerAction getPlayerAction();

    /**
     * Notify UI that a map change has occurred.
     *
     * Params:
     *  where = List of affected locations to update.
     */
    void updateMap(Pos[] where...);

    /**
     * Notify that the map should be moved and recentered on a new position.
     * The map will be re-rendered.
     *
     * If multiple refreshes occur back-to-back without an intervening input
     * event, a small pause will be added for animation effect.
     */
    void moveViewport(Vec!(int,4) center);

    /**
     * Signal end of game with an exit message.
     */
    void quitWithMsg(string msg);

    /// ditto
    final void quitWithMsg(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        import std.format : format;
        quitWithMsg(format(fmt, args));
    }
}

enum saveFileName = ".tetra.save";

/**
 * Game simulation.
 */
class Game
{
    private GameUi ui;
    /*private*/ World w; // FIXME
    private Thing* player;
    private bool quit;

    Vec!(int,4) playerPos()
    {
        return w.store.get!Pos(player.id).coors;
    }

    auto numGold()
    {
        auto inv = w.store.get!Inventory(player.id);
        return inv.contents
                  .map!(id => w.store.get!Tiled(id))
                  .filter!(tp => tp !is null && tp.tileId == TileId.gold)
                  .count;
    }

    auto maxGold()
    {
        return w.store.getAll!Tiled
                      .map!(id => w.store.get!Tiled(id))
                      .filter!(tp => tp.tileId == TileId.gold)
                      .count;
    }

    private void doAction(alias act, Args...)(Args args)
    {
        ActionResult res = act(args);
        if (!res)
        {
            ui.message(res.failureMsg);
        }
    }

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("world", w);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.w = lf.parse!World("world");

        game.player = game.w.store.getObj(playerId);
        if (game.player is null)
            throw new Exception("Save file is corrupt!");

        // Permadeath. :-D
        import std.file : remove;
        remove(saveFileName);

        return game;
    }

    static Game newGame()
    {
        auto g = new Game;
        g.w = genNewGame([ 12, 12, 12, 12 ]);
        //game.w = newGame([ 9, 9, 9, 9 ]);
        g.player = g.w.store.createObj(
            Pos(g.w.map.randomLocation()),
            Tiled(TileId.player, 1),
            Name("You"),
            Inventory()
        );
        return g;
    }

    private void movePlayer(int[4] displacement)
    {
        doAction!move(w, player, vec(displacement));

        // TBD: this is a hack that should be replaced by a System, probably.
        {
            if (!w.store.getAllBy!Pos(Pos(playerPos))
                        .map!(id => w.store.get!Tiled(id))
                        .filter!(tp => tp !is null &&
                                 tp.tileId == TileId.portal)
                        .empty)
            {
                ui.message("You see the exit portal here.");
            }
        }
    }

    private void applyFloorObj()
    {
        doAction!applyFloor(w, player);
    }

    private void portalSystem()
    {
        if (w.store.get!UsePortal(player.id) !is null)
        {
            w.store.remove!UsePortal(player);

            auto ngold = numGold();
            auto maxgold = maxGold();

            if (ngold < maxgold)
            {
                ui.message("The exit portal is here, but you haven't found "~
                           "all the gold yet.");
            }
            else
            {
                quit = true;
                import std.format : format;
                ui.quitWithMsg("Congratulations! You collected %d out of %d "~
                               "gold.", ngold, maxgold);
            }
        }
    }

    private void gravitySystem()
    {
        bool somethingFell;
        do
        {
            somethingFell = false;
            foreach (t; w.store.getAll!Pos()
                               .map!(id => w.store.getObj(id)))
            {
                auto pos = *w.store.get!Pos(t.id);
                auto floorPos = pos + vec(1,0,0,0);

                // Gravity pulls downwards as long as there is no support
                // underneath.
                if (w.store.get!SupportsWeight(w.map[floorPos]) is null)
                {
                    w.store.remove!Pos(t);
                    w.store.add!Pos(t, Pos(floorPos));
                    w.notify.fall(pos, t.id, Pos(floorPos));
                    somethingFell = true;
                }
            }
        } while (somethingFell);
    }

    void setupEventWatchers()
    {
        w.notify.move = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
                ui.moveViewport(newPos);
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.climbLedge = (Pos pos, ThingId subj, Pos newPos, int seq)
        {
            if (subj == player.id)
            {
                if (seq == 0)
                    ui.message("You climb up the ledge.");
                ui.moveViewport(newPos);
            }
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.fall = (Pos pos, ThingId subj, Pos newPos)
        {
            if (subj == player.id)
            {
                ui.moveViewport(newPos);
                ui.message("You fall!");
            }
            else
                ui.updateMap(pos, newPos);
        };
        w.notify.pickup = (Pos pos, ThingId subj, ThingId obj)
        {
            if (subj == player.id)
            {
                auto name = w.store.get!Name(obj);
                if (name !is null)
                    ui.message("You pick up the " ~ name.name ~ ".");
            }
            else
                ui.updateMap(pos);
        };
    }

    void run(GameUi _ui)
    {
        ui = _ui;
        setupEventWatchers();
        while (!quit)
        {
            gravitySystem();

            // handle player input
            final switch (ui.getPlayerAction()) with(PlayerAction)
            {
                case up:    movePlayer([-1,0,0,0]); break;
                case down:  movePlayer([1,0,0,0]);  break;
                case ana:   movePlayer([0,-1,0,0]); break;
                case kata:  movePlayer([0,1,0,0]);  break;
                case back:  movePlayer([0,0,-1,0]); break;
                case front: movePlayer([0,0,1,0]);  break;
                case left:  movePlayer([0,0,0,-1]); break;
                case right: movePlayer([0,0,0,1]);  break;
                case apply: applyFloorObj();        break;
                case none:  assert(0, "Internal error");
            }

            portalSystem();
        }
    }
}

// vim:set ai sw=4 ts=4 et:
