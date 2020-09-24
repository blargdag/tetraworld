/**
 * AI module.
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
module ai;

import std.algorithm;
import std.math;
import std.range;

import action;
import components;
import dir;
import fov;
import store_traits;
import vector;
import world;

/**
 * Tries to call the given move generator up to numTries times until a viable
 * move is found.
 *
 * Returns: true if a viable move was found, in which case `dir` contains the
 * viable move; false otherwise, in which case the contents of `dir` are
 * undefined.
 */
bool findViableMove(World w, ThingId agentId, Pos curPos, int numTries,
                    int[4] delegate() generator, out int[4] dir)
{
    while (numTries-- > 0)
    {
        dir = generator();
        if (canAgentMove(w, agentId, vec(dir)) &&
            (canMove(w, curPos, vec(dir)) ||
             canClimbLedge(w, curPos, vec(dir))))
        {
            return true;
        }
    }
    return false;
}

/**
 * AI decision-making routine.
 */
Action chooseAiAction(World w, ThingId agentId)
{
    auto agent = w.store.getObj(agentId);
    auto curPos = *w.store.get!Pos(agentId);

    // For now, chase player.
    auto r = w.store.getAll!Agent()
              .filter!(id => w.store.get!Agent(id).type == Agent.Type.player);
    if (!r.empty)
    {
        auto targetId = r.front;
        auto targetPos = *w.store.get!Pos(targetId);

        if (w.canSee(curPos, targetPos))
        {
            auto inven = w.store.get!Inventory(agentId);
            auto contents = inven ? inven.contents : [];
            auto weapons = contents
                .filter!(item => (item.type == Inventory.Item.Type.equipped ||
                                  item.type == Inventory.Item.Type.intrinsic)
                                  && w.store.get!Weapon(item.id) !is null)
                .map!(item => item.id);

            auto diff = targetPos - curPos;
            if (!weapons.empty && diff[].map!(x => abs(x)).sum == 1)
            {
                // Adjacent to player. Attack!
                import rndutil : pickOne;
                return (World w) => attack(w, agent, targetId, weapons.pickOne);
            }

            // If no weapons, flee from player instead of attack.
            if (weapons.empty)
                diff = -diff;

            int[4] dir;
            if (findViableMove(w, agentId, curPos, 6, () => chooseDir(diff),
                               dir))
                return (World w) => move(w, agent, vec(dir));
        }
        // Couldn't find a way to reach target, or can't see target, fallback
        // to random move.
    }

    // Nothing to do, just wander aimlessly.
    int[4] dir;
    if (findViableMove(w, agentId, curPos, 6, () => dir2vec(randomDir), dir))
        return (World w) => move(w, agent, vec(dir));

    // Can't even do that; give up.
    return (World w) => pass(w, agent);
}

// vim:set ai sw=4 ts=4 et:
