/**
 * Gravity module.
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
module gravity;

import std.algorithm;
import std.array;
import std.range;
import std.random;

import action;
import components;
import dir;
import rndutil;
import store;
import store_traits;
import world;
import vector;

/**
 * Gravity system.
 */
struct SysGravity
{
    private bool isSupported(World w, ThingId id, SupportsWeight* sw,
                             SupportType type)
    {
        if (sw is null || (sw.type & type) == 0)
            return false;

        final switch (sw.cond)
        {
            case SupportCond.always:
                return true;

            case SupportCond.climbing:
                if (w.store.get!Climbs(id) !is null)
                    return true;
                break;

            case SupportCond.buoyant:
                if (w.store.get!Swims(id) !is null)
                    return true;

                // Non-buoyant objects will sink, but only slowly, so simulate
                // this with random support.
                return (uniform(0, 10) < 4);
        }
        return false;
    }

    private bool willFall()(World w, ThingId id, out Pos oldPos,
                            out Pos floorPos)
    {
        // NOTE: race condition: a falling object may autopickup another
        // object and remove its Pos while we're still iterating, which
        // will cause posp to be null.
        auto posp = w.store.get!Pos(id);
        if (posp is null)
            return false;
        oldPos = *posp;

        // Check if something at current location is supporting this object.
        if (w.getAllAt(oldPos)
             .map!(id => w.store.get!SupportsWeight(id))
             .canFind!(sw => isSupported(w, id, sw, SupportType.within)))
        {
            return false;
        }

        // Check if something on the floor is supporting this object.
        floorPos = Pos(oldPos + vec(1,0,0,0));
        return !w.getAllAt(floorPos)
                 .map!(id => w.store.get!SupportsWeight(id))
                 .canFind!(sw => isSupported(w, id, sw, SupportType.above));
    }

    /**
     * Called when a falling object is on top of an object that blocks movement
     * but is unable to support weight.
     *
     * Returns: true if object should keep falling, false if object should stop
     * falling.
     */
    private bool fallOn(World w, Thing* t, Thing* obj, Pos oldPos,
                        Pos floorPos)
    {
        auto objId = obj.id;

        w.notify.fallOn(oldPos, t.id, objId);
        if (w.store.get!Mortal(objId) !is null)
        {
            import damage;
            w.injure(t.id, objId, invalidId /*FIXME*/, 1 /*FIXME*/);
        }

        if (w.store.getObj(objId) is null)
            return true; // obj has been destroyed; keep falling

        // Throw object to random sideways direction, unless it's completely
        // blocked in, in which case it stays put.
        auto newPos = horizDirs
            .map!(dir => Pos(floorPos + vec(dir2vec(dir))))
            .filter!(pos => !w.locationHas!BlocksMovement(pos) &&
                            !w.locationHas!BlocksMovement(Pos(pos +
                                                              vec(-1,0,0,0))))
            .pickOne(oldPos);

        // If completely blocked on all sides, get stuck on top.
        if (newPos == oldPos)
            return false;

        rawMove(w, t, newPos, {
            // FIXME: replace with something else, like being thrown to the
            // side.
            w.notify.fall(oldPos, t.id, newPos);
        });
        return true;
    }

    /**
     * Run main gravity system.
     */
    void run(World w)
    {
        auto targets = w.store.getAllNew!Pos()
                        .filter!(id => w.store.get!NoGravity(id) is null)
                        .array;
        foreach (t; targets.map!(id => w.store.getObj(id))
                           .filter!(t => t !is null))
        {
            Pos oldPos, floorPos;
            while (willFall(w, t.id, oldPos, floorPos))
            {
                // An object that blocks moves but is unable to support weight
                // will get damaged by the falling object, and throw the
                // falling object sideways. (Note that not supporting weight is
                // already implied by willFall().)
                auto r = w.store.getAllBy!Pos(floorPos)
                          .map!(id => w.store.getObj(id))
                          .filter!(t => t.systems & SysMask.blocksmovement);
                if (!r.empty)
                {
                    if (!fallOn(w, t, r.front, oldPos, floorPos))
                        break;
                }
                else
                {
                    rawMove(w, t, floorPos, {
                        w.notify.fall(oldPos, t.id, floorPos);
                    });
                }
            }
        }

        // We clear here rather than in enqueueTargets because objects that we
        // move around above should not be added back unless we explicitly put
        // them in newTargets.
        w.store.clearNew!Pos();
    }
}

unittest
{
    import gamemap;

    static void dump(World w)
    {
        import tile, std;
        writefln("%-(%-(%s%)\n%)",
            iota(4).map!(j =>
                iota(4).map!(i =>
                    tiles[w.store.get!Tiled(w.map[j,i,1,1]).tileId]
                    .representation)));
    }

    // Test map:
    //  0 ####
    //  1 #  #
    //  2 #  #
    //  3 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(0,0,0,0), vec(3,3,2,2));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(3,3,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = int.max;

    SysGravity grav;

    // Scenario 1:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #A #      2 #A@#
    //  3 ####      3 ####
    auto rock = w.store.createObj(Name("rock"), Pos(1,1,1,1));
    auto victim = w.store.createObj(Name("victim"), Pos(2,1,1,1),
                                    Mortal(2, 2), BlocksMovement());
    assert(!w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(2,2,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(*w.store.get!Mortal(victim.id) == Mortal(2, 1));

    // Scenario 2:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #A #      2 #@ #
    //  3 ####      3 ####
    w.store.remove!Pos(rock);
    w.store.add!Pos(rock, Pos(1,1,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(2,1,1,1));
    assert(w.store.getObj(victim.id) == null);

    // Scenario 3:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@##  ==> 1 #@##
    //  2 #A #      2 #A #
    //  3 ####      3 ####
    w.store.remove!Pos(rock);
    w.store.add!Pos(rock, Pos(1,1,1,1));
    victim = w.store.createObj(Name("victim"), Pos(2,1,1,1),
                               Mortal(3, 3), BlocksMovement());
    auto corner = w.store.createObj(Name("artificial wall"), Pos(1,2,1,1),
                                    BlocksMovement(), NoGravity());
    assert(w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(1,1,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(*w.store.get!Mortal(victim.id) == Mortal(3, 2));
    assert(*w.store.get!Pos(corner.id) == Pos(1,2,1,1));

    // Scenario 4:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #@ #
    //  2 #A##      2 #A##
    //  3 ####      3 ####
    w.store.remove!Pos(rock);
    w.store.add!Pos(rock, Pos(1,1,1,1));
    w.store.remove!Pos(corner);
    w.store.add!Pos(corner, Pos(2,2,1,1));
    assert(!w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(1,1,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(*w.store.get!Mortal(victim.id) == Mortal(3, 1));
    assert(*w.store.get!Pos(corner.id) == Pos(2,2,1,1));

    // Scenario 5:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #A##      2 #@##
    //  3 ####      3 ####
    w.store.remove!Pos(rock);
    w.store.add!Pos(rock, Pos(1,1,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(2,1,1,1));
    assert(w.store.getObj(victim.id) == null);
    assert(*w.store.get!Pos(corner.id) == Pos(2,2,1,1));
}

// vim:set ai sw=4 ts=4 et:
