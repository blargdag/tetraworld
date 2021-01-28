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
import std.typecons : tuple;

import action;
import agent;
import components;
import store;
import store_traits;
import world;
import vector;

/**
 * Returns: true if the given Mortal can breathe at the given location, false
 * otherwise.
 */
bool canBreatheIn(World w, Mortal* m, Pos pos, out ThingId mediumId)
{
    if (m is null || m.curStats.canBreatheIn == Medium.none)
        return true;    // this Mortal doesn't need to breathe

    auto medium = w.getMediumAt(pos, &mediumId);
    if ((m.curStats.canBreatheIn & medium) != 0)
        return true;    // Can breathe in current tile

    if (medium == Medium.water &&
        (m.curStats.canBreatheIn & w.getMediumAt(pos + vec(-1,0,0,0))) != 0)
    {
        return true;    // Wading in water with air above.
    }

    return false;
}

/// ditto
bool canBreatheIn(World w, ThingId mortalId, Pos pos)
{
    ThingId dummy;
    auto m = w.store.get!Mortal(mortalId);
    return canBreatheIn(w, m, pos, dummy);
}

unittest
{
    import gamemap, objects;

    auto root = new RoomNode;
    root.isRoom.interior = region(vec(1,1,1,1), vec(10,4,4,4));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(1,1,1,1), vec(10,4,4,4));
    w.map.waterLevel = 8;

    auto monA = createMonsterA(&w.store, Pos(8,2,2,2));

    assert( canBreatheIn(w, monA.id, Pos(7,2,2,2)));
    assert( canBreatheIn(w, monA.id, Pos(8,2,2,2)));
    assert(!canBreatheIn(w, monA.id, Pos(9,2,2,2)));
}

/**
 * Returns: Input range of Armor component of currently-active breathing
 * equipment.
 */
auto findBreathingEquip(World w, ThingId mortalId, Mortal* m)
{
    auto inven = w.store.get!Inventory(mortalId);
    return (inven ? inven.contents : [])
        .filter!(item => item.inEffect)
        .map!(item => tuple(item.id, w.store.get!Armor(item.id)))
        .filter!(t => t[1] !is null && (t[1].bonuses.canBreatheIn |
                                        m.curStats.canBreatheIn) != 0 &&
                      t[1].bonuses.maxair > 0);
}

private void applyMediumEffects(World w)
{
    void replenishBreathEquip(ThingId mortalId, Mortal* m, Pos pos)
    {
        foreach (p; findBreathingEquip(w, mortalId, m))
        {
            auto id = p[0];
            auto be = p[1];
            if (be.bonuses.air < be.bonuses.maxair)
            {
                be.bonuses.air = be.bonuses.maxair;
                w.events.emit(Event(EventType.itemReplenish, pos, mortalId,
                                    id));
            }
        }
    }

    foreach (mortalId; w.store.getAll!Mortal().dup)
    {
        auto pos = w.store.get!Pos(mortalId);
        if (pos is null)
            continue;

        auto m = w.store.get!Mortal(mortalId);
        ThingId mediumId;
        if (canBreatheIn(w, m, *pos, mediumId))
        {
            if (m.curStats.air < m.curStats.maxair)
            {
                m.curStats.air = m.curStats.maxair;   // replenish air
                w.events.emit(Event(EventType.schgBreathReplenish, *pos,
                                    mortalId));
            }

            replenishBreathEquip(mortalId, m, *pos);
            continue;
        }

        // Not in breathable medium. Check for presence of equipped breathing
        // equipment.
        auto beq = findBreathingEquip(w, mortalId, m);
        if (!beq.empty && beq.front[1].bonuses.air > 0)
        {
            beq.front[1].bonuses.air--;
            continue;
        }

        // Can't breathe. Drain air supply.
        m.curStats.air--;
        if (m.curStats.air > 0)
        {
            w.events.emit(Event(EventType.schgBreathHold, *pos, mortalId));
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
