/**
 * Materials module.
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
module materials;

import action;
import agent;
import components;
import store;
import store_traits;
import world;
import vector;

private void applyMaterialEffects(World w)
{
    foreach (mortalId; w.store.getAll!Mortal().dup)
    {
        auto m = w.store.get!Mortal(mortalId);
        auto pos = w.store.get!Pos(mortalId);
        if (pos is null || m is null ||
            m.curStats.canBreatheIn == Material.init)
        {
            continue;
        }

        // Check for breathability. If current tile is not breathable, check
        // tile above (for air-breathers wading in water).
        ThingId materialId;
        auto material = w.getMaterialAt(*pos, &materialId);
        if ((m.curStats.canBreatheIn & material) != 0 || 
            (material == Material.water &&
             (m.curStats.canBreatheIn & w.getMaterialAt(*pos + vec(-1,0,0,0))) != 0))
        {
            if (m.curStats.air < m.curStats.maxair)
            {
                m.curStats.air = m.curStats.maxair;   // replenish air
                w.events.emit(Event(EventType.schgBreathReplenish, *pos,
                                    mortalId));
            }
            continue;
        }

        // Can't breathe. Drain air supply.
        m.curStats.air--;
        if (m.curStats.air > 0)
        {
            w.events.emit(Event(EventType.schgBreathHold, *pos,
                                mortalId));
            continue;
        }

        // Out of air. Begin drowning.
        import damage : injure;
        injure(w, materialId, mortalId, DmgType.drown, 1, (dam) {
            w.events.emit(Event(EventType.dmgDrown, *pos,
                                mortalId, materialId));
        });
    }
}

/**
 * Register special agent that applies material effects and other tile effects.
 */
void registerTileEffectAgent(Store* store, SysAgent* sysAgent)
{
    static Thing teAgent = Thing(tileEffectAgentId);

    AgentImpl agImpl;
    agImpl.chooseAction = (World w, ThingId agentId) {
        return (World w) {
            applyMaterialEffects(w);
            return ActionResult(true, 10);
        };
    };

    sysAgent.registerAgentImpl(Agent.Type.tileEffectAgent, agImpl);
    store.registerSpecial(teAgent, Agent(Agent.type.tileEffectAgent));
}

// vim:set ai sw=4 ts=4 et:
