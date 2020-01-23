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
    auto t = w.store.getObj(agentId);
    auto curPos = *w.store.get!Pos(agentId);

    // For now, chase player.
    auto r = w.store.getAll!Agent()
              .filter!(id => w.store.get!Agent(id).type == Agent.Type.player);
    if (r.empty)
    {
        // Nothing to do, just wander aimlessly.
        return (World w) => move(w, t, vec(dir2vec(randomDir)));
    }

    auto targetId = r.front;
    auto targetPos = *w.store.get!Pos(targetId);
    auto dir = chooseDir(targetPos - curPos);
    return (World w) => move(w, t, vec(dir));
}

// vim:set ai sw=4 ts=4 et:
