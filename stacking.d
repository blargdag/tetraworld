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
    auto obj1 = store.getObj(stack1);
    auto obj2 = store.getObj(stack2);

    // Objects to be merged must be stackable.
    if ((obj1.systems & SysMask.stackable) == 0 ||
        (obj2.systems & SysMask.stackable) == 0)
    {
        return false;
    }

    // Objects must have an identical set of components.
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

/**
 * Merge stack1 to stack2.
 *
 * Returns: true if the merge succeeded; false otherwise. Note that if true is
 * returned, stack1 will NO LONGER BE VALID (it will be destroyed from the
 * store).
 */
bool stackObjs(ref Store store, ThingId stack1, ThingId stack2)
{
    if (!canStack(store, stack1, stack2))
        return false;

    store.get!Stackable(stack2).count += store.get!Stackable(stack1).count;
    store.destroyObj(stack1);
    return true;
}

unittest
{
    Store store;

    auto a1 = store.createObj(Name("apple"), Stackable(1));
    auto a2 = store.createObj(Name("apple"), Stackable(1));
    auto a3 = store.createObj(Name("apple"), Stackable(3));
    auto a4 = store.createObj(Name("apple"), Stackable(1), QuestItem(1));

    assert(store.stackObjs(a1.id, a2.id));
    assert(store.get!Stackable(a2.id).count == 2);
    assert(store.getObj(a1.id) is null);

    assert(store.stackObjs(a2.id, a3.id));
    assert(store.get!Stackable(a3.id).count == 5);
    assert(store.getObj(a2.id) is null);

    assert(!store.stackObjs(a3.id, a4.id));
    assert(store.get!Stackable(a3.id).count == 5);
    assert(store.get!Stackable(a4.id).count == 1);
}

/**
 * Splits `count` items off the given stack and returns it as a new object.
 *
 * Returns: The current stack, if the requested number of objects is identical
 * to its current count; null if the given object is not a stack, or its count
 * is less than the requested number of items; otherwise a new object
 * representing a stack of the requested number of items. All components from
 * the old stack are copied over to the new stack, and the two stacks will be
 * identical except possibly for the count in their Stackable component.
 */
Thing* splitStack(ref Store store, ThingId oldStack, int count)
{
    auto stk = store.get!Stackable(oldStack);
    if (stk is null || stk.count < count)
        return null;

    if (stk.count == count)
        return store.getObj(oldStack);

    assert(stk.count > count);
    auto result = store.createObj();
    static foreach (i, T; AllComponents)
    {{
        // Copy components of old stack over.
        auto p = store.get!T(oldStack);
        if (p !is null)
        {
            auto comp = *p;
            static if (is(T == Stackable))
            {
                comp.count = count;
            }
            store.add!T(result, comp);
        }
    }}

    stk.count -= count;
    return result;
}

unittest
{
    Store store;
    auto s1 = store.createObj(Name("apple"), Stackable(10));

    auto s2 = store.splitStack(s1.id, 11);
    assert(s2 is null && store.get!Stackable(s1.id).count == 10);

    auto s3 = store.splitStack(s1.id, 10);
    assert(s3 is s1);

    auto s4 = store.splitStack(s1.id, 6);
    assert(*store.get!Name(s4.id) == Name("apple"));
    assert(store.get!Stackable(s4.id).count == 6);
    assert(store.get!Stackable(s1.id).count == 4);
}

/**
 * Merge the given item stack to the given target array.
 *
 * If the array contains a mergeable object that can merge with the given
 * stack, the stack is merged into the target (and becomes invalidated);
 * otherwise, it's appended to the end of the array.
 *
 * WARNING: The input stack will become invalidated if it was merged, so the
 * caller should not depend on it still being a valid object after calling this
 * function!
 */
void mergeToArray(ref Store store, ThingId stack, ref ThingId[] target)
{
    bool merged = false;
    foreach (i; 0 .. target.length)
    {
        // Merge into existing item if it's mergeable.
        import stacking;
        if (store.stackObjs(stack, target[i]))
        {
            merged = true;
            break;
        }
    }

    // Not mergeable; add it as a separate item.
    if (!merged)
        target ~= stack;
}

// vim:set ai sw=4 ts=4 et:
