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

bool isViableMove(World w, Pos curPos, int[4] dir)
{
    if (dir == [0,0,0,0])
        return false;
    if (dir == [-1,0,0,0] && !w.locationHas!SupportsWeight(curPos))
        return false;
    return canMove(w, curPos, vec(dir));
}

bool findViableMove(World w, Pos curPos, int numTries,
                    int[4] delegate() generator, out int[4] dir)
{
    while (numTries-- > 0)
    {
        dir = generator();
        if (isViableMove(w, curPos, dir))
            return true;
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
        auto diff = targetPos - curPos;
        if (diff[].map!(x => abs(x)).sum == 1)
        {
            // Adjacent to player. Attack!
            return (World w) => attack(w, agent, targetId, invalidId/*FIXME*/);
        }
        else
        {
            int[4] dir;
            if (findViableMove(w, curPos, 6, () => chooseDir(diff), dir))
                return (World w) => move(w, agent, vec(dir));
            // Couldn't find a way to reach target, fallback to random move.
        }
    }

    // Nothing to do, just wander aimlessly.
    int[4] dir;
    if (findViableMove(w, curPos, 6, () => dir2vec(randomDir), dir))
        return (World w) => move(w, agent, vec(dir));

    // Can't even do that; give up.
    return (World w) => pass(w, agent);
}

// vim:set ai sw=4 ts=4 et:
