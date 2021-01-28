/**
 * Entity/component storage
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
module store;

import std.meta : allSatisfy, ApplyRight, staticMap;
import std.traits : hasUDA, getUDAs, getSymbolsByUDA;

import components;
import loadsave;
import store_traits;

/**
 * List of all Components.
 */
alias AllComponents = getSymbolsByUDA!(components, Component);
static assert(AllComponents.length <= 32, "Need to expand systems width");

private string genSysMask()
{
    string code;
    code ~= "@BitFlags\n";
    code ~= "enum SysMask : uint\n";
    code ~= "{\n";
    code ~= "    none = 0,\n";

    static foreach (i, T; AllComponents)
    {
        import std.conv : text;
        import std.uni : toLower;

        code ~= text("    ", T.stringof.toLower, " = 1 << ", i, ",\n");
    }

    code ~= "}\n";
    return code;
}

/**
 * Entity systems mask.
 *
 * Each bit set in the mask means that the Thing's ID has been registered in
 * the corresponding entity system. Usually this means that system also stores
 * some additional associated data keyed by the Thing's ID, although some
 * subsystems are implicit and don't store additional data separately.
 */
mixin(genSysMask);

struct Thing
{
    ThingId id;
    SysMask systems;
}

private alias StorageOf(T) = T[ThingId];
private template IndexOf(T)
{
    static if (hasUDA!(T, Indexed))
    {
        alias IndexOf = ThingId[][T];
    }
    else
        alias IndexOf = void[0];
}
private template NewListOf(T)
{
    static if (hasUDA!(T, TrackNew))
        alias NewListOf = ThingId[];
    else
        alias NewListOf = void[0];
}

private alias Storage = staticMap!(StorageOf, AllComponents);
private alias Indices = staticMap!(IndexOf, AllComponents);
private alias NewLists = staticMap!(NewListOf, AllComponents);

/**
 * Entity/component storage.
 */
struct Store
{
    /**
     * Universal table of game objects indexed by ID.
     */
    private Thing*[ThingId] things;

    /**
     * Universal highest assigned ID.
     */
    private ThingId curId = specialMaxId;

    private Storage pods;
    private Indices indices;
    private NewLists newlists;

    // Generate storage access methods
    static foreach (i, T; AllComponents)
    {
        /**
         * Add component T to a Thing.
         */
        void add(U : T)(Thing* t, U comp)
            in (t !is null)
        {
            t.systems |= 1 << i; // FIXME
            pods[i][t.id] = comp;

            static if (hasUDA!(T, Indexed))
            {
                indices[i][comp] ~= t.id;
            }

            static if (hasUDA!(T, TrackNew))
            {
                newlists[i] ~= t.id;
            }
        }

        /**
         * Remove component T from a Thing.
         */
        void remove(U : T)(Thing* t)
            in (t !is null)
        {
            t.systems &= ~(1 << i); // FIXME

            static if (hasUDA!(T, Indexed))
            {
                // Update index
                import std.algorithm : countUntil, remove;

                auto p = t.id in pods[i];
                if (p is null)
                    return;

                auto comp = *p;
                auto list = indices[i][comp];
                auto idx = list.countUntil(t.id);
                if (idx < list.length)
                    indices[i][comp] = list.remove(idx);
            }

            pods[i].remove(t.id);
        }

        /**
         * Look up component T by ThingId.
         */
        inout(T)* get(U : T)(ThingId id) inout
        {
            return id in pods[i];
        }

        /**
         * Returns: A list of all ThingId's that contain the given component.
         */
        ThingId[] getAll(U : T)() const
        {
            return pods[i].keys;
        }

        /**
         * Look up list of ThingId's by component.
         */
        static if (hasUDA!(T, Indexed))
        {
            inout(ThingId)[] getAllBy(U : T)(T t) inout
            {
                auto p = t in indices[i];
                return (p is null) ? [] : *p;
            }
        }

        /**
         * Access to lists of entities with newly added components.
         */
        static if (hasUDA!(T, TrackNew))
        {
            ThingId[] getAllNew(U : T)() { return newlists[i]; }
            void clearNew(U : T)() { newlists[i] = []; }
        }
    }

    /**
     * Allocate and return a new game object with a newly-assigned, unique ID.
     * The new ID will always be non-zero.
     *
     * Note that IDs are never reused, and therefore guaranteed to be unique.
     */
    Thing* createObj(Components...)(Components components)
    {
        curId++;
        auto t = new Thing(curId);
        things[curId] = t;

        foreach (comp; components)
        {
            alias Comp = typeof(comp);
            add!Comp(t, comp);
        }

        return t;
    }

    unittest
    {
        import vector : vec;
        Store store;
        auto obj = store.createObj(Pos(vec(1,2,3,4)));
    }

    /**
     * Register a terrain object.
     */
    void registerTerrain(Components...)(ref Thing ter, Components components)
        in(ter.id <= terrainMaxId)
        in(ter.id !in things)
    {
        things[ter.id] = &ter;

        foreach (comp; components)
        {
            alias Comp = typeof(comp);
            add!Comp(&ter, comp);
        }
    }

    /**
     * Register special non-physical object that has a ThingId and can interact
     * with other in-game objects.
     */
    void registerSpecial(Components...)(ref Thing obj, Components components)
        in (obj.id >= terrainMaxId && obj.id < specialMaxId)
        in (obj.id !in things)
    {
        things[obj.id] = &obj;

        foreach (comp; components)
        {
            alias Comp = typeof(comp);
            add!Comp(&obj, comp);
        }
    }

    /**
     * Look up a game object by ID.
     */
    inout(Thing)* getObj(ThingId id) inout
    {
        auto p = id in things;
        return (p is null) ? null : *p;
    }

    /**
     * Dispose of the object with the given ID. Once disposed, its ID will
     * always return null.
     */
    void destroyObj(ThingId id)
        in (id >= specialMaxId)
    {
        auto t = getObj(id);

        // Cleanup
        static foreach (i, T; AllComponents)
        {
            if (t.systems & (1 << i))
                remove!T(t);
        }

        things.remove(id);
    }

    private void saveThings(S)(S savefile)
        if (isSaveFile!S)
    {
        savefile.push("things");
        savefile.put("curId", curId);
        foreach (id; things.byKey)
        {
            if (id < specialMaxId) continue;
            savefile.put("thing", *things[id]);
        }
        savefile.pop();
    }

    /**
     * Save storage state to the given save file.
     */
    void save(S)(ref S savefile)
        if (isSaveFile!S)
    {
        saveThings(savefile);   // this must come first

        static foreach (i, T; AllComponents)
        {
            import std.conv : to;
            import std.uni : toLower;

            savefile.push(T.stringof.toLower);
            foreach (p; pods[i].byKeyValue)
            {
                // Don't save components of special IDs, since those are
                // re-created upon reloading.
                if (p.key < specialMaxId) continue;
                savefile.put(p.key.to!string, p.value);
            }
            savefile.pop();

            // (Note: no need to save indices; the component data itself is
            // already sufficient for us to rebuild the indices after loading.)

            static if (hasUDA!(T, TrackNew))
            {{
                enum newlistName = T.stringof.toLower ~ "New";
                savefile.put(newlistName, newlists[i]);
            }}
        }
    }

    void loadThings(L)(ref L loadfile)
        if (isLoadFile!L)
    {
        if (!loadfile.checkAndEnterBlock("things"))
            throw new LoadException("Missing 'things' block");

        curId = loadfile.parse!ThingId("curId");

        Thing*[ThingId] newThings;
        while (!loadfile.checkAndLeaveBlock())
        {
            if (loadfile.empty)
                throw new LoadException("Unexpected EOF in things block");

            auto t = new Thing;
            *t = loadfile.parse!Thing("thing");
            newThings[t.id] = t;
        }

        // Copy specials (non-saved Things) from old Thing registry.
        import std.algorithm : filter;
        foreach (id; things.byKey.filter!(id => id < specialMaxId))
        {
            newThings[id] = things[id];
        }
        things = newThings;
    }

    /**
     * Rebuild index from freshly-loaded data.
     */
    private void rebuildIdx(int i, T, L)(ref L loadfile)
        if (isLoadFile!L)
    {
        foreach (p; pods[i].byKeyValue)
        {
            indices[i][p.value] ~= p.key;
        }
    }

    private void loadTable(int i, T, L)(ref L loadfile)
        if (isLoadFile!L)
    {
        import std.algorithm : filter;
        import std.uni : toLower;

        auto newdata = loadfile.parse!(StorageOf!T)(T.stringof.toLower);

        // Merge special entries from old table to new table.
        foreach (id; pods[i].byKey.filter!(id => id < specialMaxId))
        {
            newdata[id] = pods[i][id];
        }
        pods[i] = newdata;

        static if (hasUDA!(T, Indexed))
        {
            rebuildIdx!(i, T)(loadfile);
        }

        static if (hasUDA!(T, TrackNew))
        {
            enum newlistName = T.stringof.toLower ~ "New";
            newlists[i] = loadfile.parse!(ThingId[])(newlistName);
        }
    }

    /**
     * Load storage state from the given save file.
     */
    void load(L)(ref L loadfile)
        if (isLoadFile!L)
    {
        loadThings(loadfile);

        foreach (i, T; AllComponents)
        {
            loadTable!(i, T)(loadfile);
        }
    }

    /**
     * Export a single entity and its dependencies into a second Store.
     */
    Thing* exportObj()(ThingId id, Store *destStore)
    {
        ThingId[ThingId] dependents;

        // Fix up ThingId references by replacing with IDs in the new store,
        // copying the referent object if necessary.
        void copyRefs(T)(T src, ref T target)
        {
            import std.traits : FieldNameTuple, hasUDA;
            static if (is(T == struct))
            {
                static foreach (field; FieldNameTuple!T)
                {
                    static if (hasUDA!(__traits(getMember, src, field),
                                       DupOnExport))
                    {
                        ThingId subId = __traits(getMember, src, field);
                        auto p = subId in dependents;
                        if (p is null)
                        {
                            auto subobj = exportObj(subId, destStore);
                            __traits(getMember, target, field) = subobj.id;
                            dependents[subId] = subobj.id;
                        }
                        else
                            __traits(getMember, target, field) = *p;
                    }
                    else
                    {
                        copyRefs(__traits(getMember, src, field),
                                 __traits(getMember, target, field));
                    }
                }
            }
            else static if (is(T == U[], U))
            {
                foreach (i; 0 .. src.length)
                {
                    copyRefs(src[i], target[i]);
                }
            }
            // FIXME: currently we just ignore other field types.
        }

        auto obj = getObj(id);
        if (obj is null) return null;

        // Create target object
        auto destObj = destStore.createObj();

        // Copy components
        foreach (i, T; AllComponents)
        {
            auto p = get!T(obj.id);
            if (p !is null)
            {
                destStore.add!T(destObj, *p);

                // Recursively copy ThingId referents
                copyRefs(*p, *destStore.get!T(destObj.id));
            }
        }

        return destObj;
    }
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "pos {",
        " 100 {",
        "  coors [ 1 0 0 1 ]",
        " }",
        " 200 {",
        "  coors [ 2 3 1 2 ]",
        " }",
        " 300 {",
        "  coors [ 1 0 0 1 ]",
        " }",
        " 400 {",
        "  coors [ 2 3 1 2 ]",
        " }",
        " 500 {",
        "  coors [ 1 0 0 1 ]",
        " }",
        "}",
        "posNew [  ]"
    ]);

    Store store;

    foreach (i, T; AllComponents)
    {
        static if (is(T == Pos))
            store.loadTable!(i, T)(lf);
    }

    static auto sorted(ThingId[] ids)
    {
        import std.algorithm : sort;
        auto result = ids.dup;
        sort(result);
        return result;
    }

    assert(sorted(store.getAllBy!Pos(Pos(0, 0, 0, 0))) == []);
    assert(sorted(store.getAllBy!Pos(Pos(1, 0, 0, 1))) == [ 100, 300, 500 ]);
    assert(sorted(store.getAllBy!Pos(Pos(2, 0, 0, 2))) == [ ]);

    assert(sorted(store.getAllBy!Pos(Pos(0, 3, 1, 2))) == [ ]);
    assert(sorted(store.getAllBy!Pos(Pos(1, 3, 1, 2))) == [ ]);
    assert(sorted(store.getAllBy!Pos(Pos(2, 3, 1, 2))) == [ 200, 400 ]);
}

unittest
{
    Store s;
    auto t = s.createObj();
    foreach (T; AllComponents)
    {
        s.add!T(t, T.init);
        auto comp = s.get!T(t.id);
        static if (hasUDA!(T, Indexed))
        {
            ThingId[] list = s.getAllBy!T(T.init);
        }
        s.remove!T(t);
    }
}

unittest
{
    Store s;
    auto t = s.createObj!Pos(Pos(1, 2, 3, 4));
    auto pos = *s.get!Pos(t.id);
    assert(pos == Pos(1, 2, 3, 4));
}

// Test export of entities between stores.
unittest
{
    Store s1, s2;
    auto obj = s1.createObj(Name("some guy"), Agent(Agent.Type.player),
        Tiled(TileId.player, 2, Tiled.Hint.dynamic),
        Inventory([
            Inventory.Item(s1.createObj(Name("pocket lint")).id),
            Inventory.Item(s1.createObj(Name("pebbles"), Stackable(3)).id)
        ]),
        Mortal(Stats(5, 5, Medium.air))
    );

    s2.createObj(Name("red herring")); // just to bump the current ID

    auto dobj = s1.exportObj(obj.id, &s2);
    assert(*s2.get!Name(dobj.id) == Name("some guy"));
    assert(*s2.get!Agent(dobj.id) == Agent(Agent.Type.player));
    assert(*s2.get!Tiled(dobj.id) == Tiled(TileId.player, 2, Tiled.Hint.dynamic));
    assert(*s2.get!Mortal(dobj.id) == Mortal(Stats(5, 5, Medium.air)));

    auto inv = s2.get!Inventory(dobj.id);
    assert(inv !is null && inv.contents.length == 2);
    auto lint = s2.getObj(inv.contents[0].id);
    assert(*s2.get!Name(lint.id) == Name("pocket lint"));
    auto pebbles = s2.getObj(inv.contents[1].id);
    assert(*s2.get!Name(pebbles.id) == Name("pebbles"));
    assert(*s2.get!Stackable(pebbles.id) == Stackable(3));
}

// vim: set ts=4 sw=4 et ai:
