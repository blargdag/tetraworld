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

import components;
import store_traits;
import world;

void injure(World w, ThingId inflictor, ThingId victim, ThingId weapon, int hp)
{
    auto m = w.store.get!Mortal(victim);
    if (m is null) // TBD: emit a message about target being impervious
        return;

    m.hp -= hp;
    if (m.hp <= 0)
    {
        w.notify.damage(DmgType.kill, *w.store.get!Pos(victim), inflictor,
                        victim, weapon);

        // TBD: drop corpses here
        // TBD: drop inventory items here
        w.store.destroyObj(victim);
    }
}

// vim:set ai sw=4 ts=4 et:
