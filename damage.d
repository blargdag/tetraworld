/**
 * Damage system.
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
module damage;

import std.algorithm;

import components;
import store_traits;
import world;
import vector;

private int calcEffectiveDmg(World w, ThingId inflictor, ThingId victim,
                             ref DmgType dmgType, int baseDmg)
{
    import std.algorithm : max;

    if (auto inven = w.store.get!Inventory(victim))
    {
        auto equipped = inven.contents
            .filter!(item => item.inEffect)
            .map!(item => item.id);

        foreach (armorId; equipped)
        {
            auto wb = w.store.get!Armor(armorId);
            if (wb is null)
                continue;

            if ((dmgType & wb.protection) != 0)
            {
                // TBD: amount of damage reduction should be calculated from
                // equipment stats
                baseDmg = max(0, baseDmg-1);
                w.events.emit(Event(EventType.dmgBlock,
                                    *w.store.get!Pos(victim), victim,
                                    invalidId /*FIXME: weaponId*/,
                                    armorId));
                dmgType &= ~wb.protection;
            }
        }
    }
    return baseDmg;
}

/**
 * Inflict injury on the specified victim with the given damage type and base
 * damage value.
 *
 * Params:
 *  w = The World object.
 *  inflictor = The attacker.
 *  victim = The victim.
 *  dmgType = The kind of damage to apply.
 *  dam = The base damage value. This will be reduced by any armor the victim is
 *      wearing that confers protection against the specified damage type.
 *  notifyInjure = An optional delegate to invoke when the effective damage is
 *      non-zero. Intended for emitting damage messages that are suppressed if
 *      damage is zero.
 */
void injure(World w, ThingId inflictor, ThingId victim, DmgType dmgType,
            int dam, void delegate(int dam) notifyInjure = null)
{
    auto m = w.store.get!Mortal(victim);
    if (m is null) // TBD: emit a message about target being impervious
        return;

    dam = calcEffectiveDmg(w, inflictor, victim, dmgType, dam);
    if (dam > 0 && notifyInjure !is null)
        notifyInjure(dam);

    m.curStats.hp -= dam;
    if (m.curStats.hp <= 0)
    {
        auto pos = w.store.get!Pos(victim);
        w.events.emit(Event(EventType.dmgKill, *pos, inflictor, victim,
                            invalidId /*FIXME: weaponId */, dmgType));

        // TBD: drop corpses here

        // Drop inventory items & destroy intrinsics
        auto inven = w.store.get!Inventory(victim);
        if (inven !is null)
        {
            foreach (item; inven.contents)
            {
                final switch (item.type)
                {
                    case Inventory.Item.Type.carrying:
                    case Inventory.Item.Type.equipped:
                        auto obj = w.store.getObj(item.id);
                        w.store.add!Pos(obj, *pos);
                        break;

                    case Inventory.Item.Type.intrinsic:
                        w.store.destroyObj(item.id);
                        break;
                }
            }
        }

        w.store.destroyObj(victim);
    }
}

unittest
{
    import gamemap;
    import vector;

    auto root = new RoomNode;
    root.interior = region(vec(1,1,1,1), vec(3,3,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(0,0,0,0), vec(4,4,4,4));
    w.map.waterLevel = 5;

    auto club = w.store.createObj(Name("большой дуб"),
                                  Weapon(DmgType.blunt, 5));
    auto attacker = w.store.createObj(Name("разбойник"), Pos(2,1,1,1),
        Inventory([
            Inventory.Item(club.id, Inventory.Item.Type.equipped)
        ]));
    auto coin = w.store.createObj(Name("монетка"));
    auto coat = w.store.createObj(Name("палто"), Armor());
    auto fear = w.store.createObj(Name("страх"));
    auto victim = w.store.createObj(Name("бедняжка"), Pos(2,1,1,2),
        Mortal(Stats(1,1)),
        Inventory([
            Inventory.Item(coin.id, Inventory.Item.Type.carrying),
            Inventory.Item(coat.id, Inventory.Item.Type.equipped),
            Inventory.Item(fear.id, Inventory.Item.Type.intrinsic),
        ]));

    bool killed;
    w.events.listen((Event ev) {
        if (ev.type == EventType.dmgKill)
        {
            assert(ev.where == Pos(2,1,1,2));
            assert(ev.subjId == attacker.id);
            assert(ev.objId == victim.id);
            //assert(weapon == club.id); // TBD
            killed = true;
        }
    });

    assert(w.store.get!Pos(coin.id) is null);
    assert(w.store.get!Pos(coat.id) is null);
    assert(w.store.get!Pos(fear.id) is null);

    injure(w, attacker.id, victim.id, DmgType.blunt, 5);

    assert(killed);
    assert(w.store.getObj(victim.id) is null);
    assert(*w.store.get!Pos(coin.id) == Pos(2,1,1,2));
    assert(*w.store.get!Pos(coat.id) == Pos(2,1,1,2));
    assert(w.store.getObj(fear.id) is null);
}

// vim:set ai sw=4 ts=4 et:
