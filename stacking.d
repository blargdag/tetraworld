/**
 * Code for managing object stacks.
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
module stacking;

import components;
import store;
import store_traits;

/**
 * Returns: true if the two stacks can be merged, false otherwise.
 *
 * Criteria for stacking is (1) the objects to be stacked must have the
 * Stackable component, and (2) they must have exactly the same components
 * except possibly for Pos, and (3) all components must be identical except for
 * Pos and the count in the Stackable component.
 */
bool canStack(ref Store store, ThingId stack1, ThingId stack2)
{
    // Objects to be merged must be stackable.
    auto s1 = store.get!Stackable(stack1);
    auto s2 = store.get!Stackable(stack2);

    if (s1 is null || s2 is null)
        return false;

    // Objects must have an identical set of components.
    auto obj1 = store.getObj(stack1);
    auto obj2 = store.getObj(stack2);

    if (((obj1.systems ^ obj2.systems) & ~SysMask.pos) != 0)
        return false;

    // Every component must be identical, except for the Stackable component
    // which may differ in count.
    static foreach (i, T; AllComponents)
    {
        static if (is(T == Stackable))
        {
            // Compare any other fields of Stackable besides count (currently
            // none).
        }
        else static if (is(T == Pos))
        {
            // Ignore Pos, objects in different locations are allowed to stack
            // if they're otherwise identical.
        }
        else
        {
            if (obj1.systems & (1 << i))
            {
                auto comp1 = store.get!T(stack1);
                auto comp2 = store.get!T(stack2);

                assert(comp1 !is null && comp2 !is null);
                if (*comp1 != *comp2)
                    return false;
            }
        }
    }
    return true;
}

unittest
{
    Store store;

    auto a1 = store.createObj(Name("apple"), Stackable(1));
    auto a2 = store.createObj(Name("apple"), Stackable(1));
    auto a3 = store.createObj(Name("apple"), Stackable(2));
    auto a4 = store.createObj(Name("apple"), Stackable(2), QuestItem(1));
    auto o1 = store.createObj(Name("orange"), Stackable(1));
    auto o2 = store.createObj(Name("orange"), Stackable(1), Pos(1,2,3,4));

    assert( store.canStack(a1.id, a2.id));
    assert( store.canStack(a1.id, a3.id));
    assert(!store.canStack(a1.id, a4.id));
    assert(!store.canStack(a3.id, a4.id));

    assert(!store.canStack(a1.id, o1.id));
    assert( store.canStack(o1.id, o2.id));
}

// vim:set ai sw=4 ts=4 et:
