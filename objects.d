/**
 * Standard object creation functions.
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
module objects;

import components;
import store;
import vector;

Thing* createRockTrapTrig(Store* store, Vec!(int,4) trigPos, ulong triggerId)
{
    return store.createObj(Pos(trigPos),
                           Trigger(Trigger.Type.onWeight, triggerId, 500));
}

Thing* createRockTrap(Store* store, Vec!(int,4) ceilingPos, ulong triggerId)
{
    return store.createObj(Pos(ceilingPos),
                           Triggerable(triggerId, TriggerEffect.rockTrap));
}

Thing* createPortal(Store* store, Vec!(int,4) pos, string dest="")
{
    return store.createObj(Pos(pos), Tiled(TileId.portal), Name("exit portal"),
                           Usable(UseEffect.portal, "activate"), Weight(1));
}

Thing* createCrabShell(Store* store, Vec!(int,4) pos)
{
    return store.createObj(Pos(pos), Name("hard hemiglomic shell"), Weight(5),
                           Armor(DmgType.fallOn), Tiled(TileId.crabShell),
                           Pickable());
}

Thing* createRock(Store* store, Vec!(int,4) pos)
{
    return store.createObj(Pos(pos), Tiled(TileId.rock), Name("rock"),
                           Pickable(), Stackable(1), Weight(50));
}

Thing* createDenseVeg(Store* store, Vec!(int,4) pos)
{
    return store.createObj(Pos(pos), Tiled(TileId.vegetation2, -1),
                           Weight(100), BlocksView(),
                           Name("dense vegetation"));
}

Thing* createVeg(Store* store, Vec!(int,4) pos)
{
    return store.createObj(Pos(pos), Tiled(TileId.vegetation1, -1),
                           Weight(100), Name("vegetation"));
}

Thing* createGold(Store* store, Vec!(int,4) pos)
{
    return store.createObj(Pos(pos), Tiled(TileId.gold), Name("gold"),
                           Pickable(), QuestItem(1), Stackable(1), Weight(1));
}

Thing* createMonsterA(Store* store, Vec!(int,4) pos)
{
    auto tentacles = store.createObj(Name("tentacles"),
                                     Weapon(DmgType.blunt, 1));
    return store.createObj(Pos(pos), Name("conical creature"), Weight(1000),
        Tiled(TileId.creatureA, 1, Tiled.Hint.dynamic), BlocksMovement(),
        Agent(), Mortal(5,5, Material.air,5,5),
        CanMove(CanMove.Type.walk | CanMove.Type.climb),
        Inventory([
            Inventory.Item(tentacles.id, Inventory.Item.Type.intrinsic),
        ]));
}

Thing* createShell(Comp...)(Store* store, Comp comps)
{
    return store.createObj(Name("hard hemiglomic shell"), Weight(5),
                           Armor(DmgType.fallOn), Tiled(TileId.crabShell),
                           Pickable(), comps);
}

Thing* createMonsterB(Store* store, Vec!(int,4) pos)
{
    auto claws = store.createObj(Name("claws"),
                                 Weapon(DmgType.pierce, 2, "pinches"));
    auto shell = createShell(store);

    return store.createObj(Pos(pos), Name("shelled creature"),
        Weight(1200), BlocksMovement(), Agent(Agent.Type.ai, 20),
        CanMove(CanMove.Type.walk), Mortal(3,3, Material.air | Material.water),
        Tiled(TileId.creatureC, 1, Tiled.Hint.dynamic),
        Inventory([
            Inventory.Item(claws.id, Inventory.Item.Type.intrinsic),
            Inventory.Item(shell.id, Inventory.Item.Type.equipped),
        ]));
}

// vim:set ai sw=4 ts=4 et:
