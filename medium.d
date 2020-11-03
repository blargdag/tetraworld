/**
 * Medium module.
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
module medium;

import std.algorithm;

import action;
import agent;
import components;
import store;
import store_traits;
import world;
import vector;

/**
 * Returns: Input range of Armor component of currently-active breathing
 * equipment.
 */
auto findBreathingEquip(World w, ThingId mortalId, Mortal* m)
{
    auto inven = w.store.get!Inventory(mortalId);
    return inven.contents
        .filter!(item => item.inEffect)
        .map!(item => w.store.get!Armor(item.id))
        .filter!(am => am !is null && (am.bonuses.canBreatheIn |
                                       m.curStats.canBreatheIn) != 0 &&
                       am.bonuses.maxair > 0);
}

private void applyMediumEffects(World w)
{
    foreach (mortalId; w.store.getAll!Mortal().dup)
    {
        auto m = w.store.get!Mortal(mortalId);
        auto pos = w.store.get!Pos(mortalId);
        if (pos is null || m is null ||
            m.curStats.canBreatheIn == Medium.init)
        {
            continue;
        }

        // Check for breathability. If current tile is not breathable, check
        // tile above (for air-breathers wading in water).
        ThingId mediumId;
        auto medium = w.getMediumAt(*pos, &mediumId);
        if ((m.curStats.canBreatheIn & medium) != 0 || 
            (medium == Medium.water &&
             (m.curStats.canBreatheIn & w.getMediumAt(*pos + vec(-1,0,0,0))) != 0))
        {
            if (m.curStats.air < m.curStats.maxair)
            {
                m.curStats.air = m.curStats.maxair;   // replenish air
                w.events.emit(Event(EventType.schgBreathReplenish, *pos,
                                    mortalId));
            }

            // Replenish breathing equipment.
            foreach (be; findBreathingEquip(w, mortalId, m))
            {
                be.bonuses.air = be.bonuses.maxair;
            }

            continue;
        }

        // Not in breathable medium. Check for presence of equipped breathing
        // equipment.
        auto beq = findBreathingEquip(w, mortalId, m);
        if (!beq.empty && beq.front.bonuses.air > 0)
        {
            beq.front.bonuses.air--;
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
        injure(w, mediumId, mortalId, DmgType.drown, 1, (dam) {
            w.events.emit(Event(EventType.dmgDrown, *pos, mortalId, mediumId));
        });
    }
}

/**
 * Register special agent that applies medium effects and other tile effects.
 */
void registerTileEffectAgent(Store* store, SysAgent* sysAgent)
{
    static Thing teAgent = Thing(tileEffectAgentId);

    AgentImpl agImpl;
    agImpl.chooseAction = (World w, ThingId agentId) {
        return (World w) {
            applyMediumEffects(w);
            return ActionResult(true, 10);
        };
    };

    sysAgent.registerAgentImpl(Agent.Type.tileEffectAgent, agImpl);
    store.registerSpecial(teAgent, Agent(Agent.type.tileEffectAgent));
}

// vim:set ai sw=4 ts=4 et:
