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
 * Returns: true if dir passes the following checks:
 * - It's not zero (not staying still);
 * - If it's moving up, the current position can support weight so that the
 *   agent will not immediately fall down again;
 * - There are no (known) obstacles that block movement in that direction.
 */
bool isViableMove(World w, ThingId agentId, Pos curPos, int[4] dir)
{
    auto cm = w.store.get!CanMove(agentId);
    if (cm is null)
        return false;

    if (dir == [0,0,0,0])
        return false;

    if (dir == [-1,0,0,0] && ((cm.types & CanMove.Type.jump) == 0 ||
                              !w.locationHas!SupportsWeight(curPos)))
        return false;

    if ((cm.types & CanMove.Type.climb) && canClimb(w, curPos, vec(dir)))
        return true;

    if (!(cm.types & CanMove.Type.walk))
        return false;

    return canMove(w, curPos, vec(dir));
}

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
        if (isViableMove(w, agentId, curPos, dir))
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

        if (w.canSee(curPos, targetPos))
        {
            auto diff = targetPos - curPos;
            if (diff[].map!(x => abs(x)).sum == 1)
            {
                // Adjacent to player. Attack!
                return (World w) => attack(w, agent, targetId,
                                           invalidId/*FIXME*/);
            }
            else
            {
                int[4] dir;
                if (findViableMove(w, agentId, curPos, 6,
                                   () => chooseDir(diff), dir))
                    return (World w) => move(w, agent, vec(dir));
            }
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
