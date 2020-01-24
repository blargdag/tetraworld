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
import store_traits;
import vector;
import world;

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
        auto diff = targetPos - curPos;
        if (diff[].map!(x => abs(x)).sum == 1)
        {
            // Adjacent to player. Attack!
            return (World w) => attack(w, agent, targetId, invalidId/*FIXME*/);
        }
        else
        {
            foreach (_; 0 .. 6)
            {
                auto dir = chooseDir(targetPos - curPos);
                if (canMove(w, curPos, vec(dir)))
                    return (World w) => move(w, agent, vec(dir));
            }
            // Couldn't find a way to reach target, fallback to random move.
        }
    }

    // Nothing to do, just wander aimlessly.
    return (World w) => move(w, agent, vec(dir2vec(randomDir)));
}

// vim:set ai sw=4 ts=4 et:
