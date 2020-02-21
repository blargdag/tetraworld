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
    private enum FallType
    {
        // NOTE: this is ordered in such a way that when multiple objects
        // provide different kinds of support, min(FallType) gives the
        // resulting overall effect.
        none = 0,
        sink = 1,
        fall = 2,
    }

    private FallType checkSupport(World w, ThingId id, bool alreadyFalling,
                                  SupportsWeight* sw, SupportType type)
    {
        if (sw is null || (sw.type & type) == 0)
            return FallType.fall;

        final switch (sw.cond)
        {
            case SupportCond.always:
                return FallType.none;

            case SupportCond.climbing:
                if (!alreadyFalling && w.store.get!Climbs(id) !is null)
                    return FallType.none;
                break;

            case SupportCond.buoyant:
                if (w.store.get!Swims(id) !is null)
                    return FallType.none;

                // Non-buoyant objects will sink, but only slowly.
                return FallType.sink;
        }
        return FallType.fall;
    }

    private FallType computeFallType(World w, ThingId id, bool alreadyFalling,
                                     out Pos oldPos, out Pos floorPos)
    {
        // NOTE: race condition: a falling object may autopickup another
        // object and remove its Pos while we're still iterating, which
        // will cause posp to be null.
        auto posp = w.store.get!Pos(id);
        if (posp is null)
            return FallType.none;
        oldPos = *posp;

        // Check if something at current location is supporting this object.
        auto ft = w.getAllAt(oldPos)
                   .map!(swid => checkSupport(w, id, alreadyFalling,
                                            w.store.get!SupportsWeight(swid),
                                            SupportType.within))
                   .minElement;
        if (ft != FallType.fall)
            return ft;

        // Check if something on the floor is supporting this object.
        floorPos = Pos(oldPos + vec(1,0,0,0));
        ft = w.getAllAt(floorPos)
              .map!(swid => checkSupport(w, id, alreadyFalling,
                                       w.store.get!SupportsWeight(swid),
                                       SupportType.above))
              .minElement;
        return ft;
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

        w.notify.damage(DmgType.fallOn, oldPos, t.id, objId, invalidId);
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
            w.notify.move(MoveType.fallAside, oldPos, t.id, newPos, 0);
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
            FallType type = computeFallType(w, t.id, false, oldPos, floorPos);
            OUTER: while (type != FallType.none)
            {
                final switch (type)
                {
                    case FallType.none:
                        assert(0);

                    case FallType.sink:
                        // Sinking is done by the sinking agent; here we just
                        // mark the object has sinking and the agent will pick
                        // it up later.
                        w.store.add!Sinking(t, Sinking());
                        break OUTER;

                    case FallType.fall:
                        // An object that blocks moves but is unable to support
                        // weight will get damaged by the falling object, and
                        // throw the falling object sideways. (Note that not
                        // supporting weight is already implied by willFall().)
                        auto r = w.store.getAllBy!Pos(floorPos)
                                  .map!(id => w.store.getObj(id))
                                  .filter!(t => t.systems &
                                                SysMask.blocksmovement);
                        if (!r.empty)
                        {
                            if (!fallOn(w, t, r.front, oldPos, floorPos))
                                break OUTER;
                        }
                        else
                        {
                            rawMove(w, t, floorPos, {
                                w.notify.move(MoveType.fall, oldPos, t.id,
                                              floorPos, 0);
                            });
                        }
                        break;
                }
                type = computeFallType(w, t.id, true, oldPos, floorPos);
            }
        }

        // We clear here rather than in enqueueTargets because objects that we
        // move around above should not be added back unless we explicitly put
        // them in newTargets.
        w.store.clearNew!Pos();
    }

    /**
     * Run slow-sinking agent for objects that are slowly sinking in water.
     *
     * Note: We cannot do this in run() because this needs to be keyed to the
     * agent system's tick time (run() may get called multiple times per turn,
     * which would produce strange sinking acceleration the more agents there
     * are).
     */
    void sinkObjects(World w)
    {
        Thing*[] objsAtRest;

        // Note: need to copy Thing* into array because rawMove() can
        // potentially destroy / remove objects.
        foreach (obj; w.store.getAll!Sinking()
                       .map!(id => w.store.getObj(id))
                       .filter!(t => t !is null)
                       .array)
        {
            auto posp = w.store.get!Pos(obj.id);
            if (posp is null)   // sidestep race conditions
                continue;

            auto oldPos = *posp;
            auto floorPos = Pos(oldPos + vec(1,0,0,0));

            if (w.locationHas!BlocksMovement(floorPos) ||
                w.getAllAt(floorPos)
                 .map!(id => checkSupport(w, obj.id, false,
                                          w.store.get!SupportsWeight(id),
                                          SupportType.above))
                 .minElement == FallType.none)
            {
                // Object has come to rest on something; stop sinking.
                objsAtRest ~= obj;
            }
            else
            {
                rawMove(w, obj, floorPos, {
                    w.notify.move(MoveType.sink, oldPos, obj.id, floorPos, 0);
                });
            }
        }

        // Remove Sinking component from objects that have come to rest.
        foreach (obj; objsAtRest)
        {
            w.store.remove!Sinking(obj);
        }
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
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(4,4,3,3));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(4,4,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = int.max;

    //dump(w);

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

unittest
{
    import gamemap, terrain;

    // Test map:
    //  0 ####
    //  1 #  #
    //  2 #  #
    //  3 #  #
    //  4 #  #
    //  5 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(6,4,3,3));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(6,4,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;

    SysGravity grav;

    // Scenario 1:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #  #      2 #  #
    //  3 #~~#      3 #@~#
    //  4 #~~#      4 #~~#
    //  5 ####      5 ####
    w.map.waterLevel = 2;
    assert(w.map[2,1,1,1] == emptySpace.id);
    assert(w.map[3,1,1,1] == water.id);
    auto rock = w.store.createObj(Name("rock"), Pos(1,1,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(3,1,1,1));
    assert(w.store.get!Sinking(rock.id) !is null);

    // Scenario 2:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #  #  ==> 1 #  #
    //  2 #  #      2 #  #
    //  3 #@~#      3 #~~#
    //  4 #~~#      4 #@~#
    //  5 ####      5 ####
    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(rock.id) == Pos(4,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);
    assert(w.store.get!Sinking(rock.id) is null);
}

// Test for ladders not holding weight when you're already falling.
unittest
{
    import gamemap, terrain;

    static void dump()(World w)
    {
        import tile, std;
        writefln("%-(%-(%s%)\n%)",
            iota(6).map!(j =>
                iota(4).map!(i =>
                    tiles[w.store.get!Tiled(w.map[j,i,1,1]).tileId]
                    .representation)));
    }

    // Test map:
    //  0 ####
    //  1 #  #
    //  2 |_ #
    //  3 #= #
    //  4 #= #
    //  5 ####
    MapNode root = new MapNode;
    root.doors ~= Door(1, [2,0,1,1], Door.Type.normal);
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(6,4,3,3));

    import mapgen : addLadders;
    auto w = new World;
    w.map.tree = root;
    w.map.bounds = root.interior;
    w.map.waterLevel = int.max;
    addLadders(w);

    //dump(w);

    SysGravity grav;

    // Scenario 1: (ladders do not hold things that can't climb)
    //    0123        0123
    //  0 ####      0 ####
    //  1 #  #  ==> 1 #  #
    //  2 |$ #      2 |_ #
    //  3 #= #      3 #= #
    //  4 #= #      4 #$ #
    //  5 ####      5 ####
    auto rock = w.store.createObj(Name("rock"), Pos(2,1,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(4,1,1,1));

    // Scenario 2: (ladders hold things that can climb)
    //    0123        0123
    //  0 ####      0 ####
    //  1 #  #  ==> 1 #  #
    //  2 |@ #      2 |@ #
    //  3 #= #      3 #= #
    //  4 #= #      4 #= #
    //  5 ####      5 ####
    w.store.destroyObj(rock.id);
    auto guy = w.store.createObj(Name("guy"), Pos(2,1,1,1), Climbs());
    grav.run(w);

    assert(*w.store.get!Pos(guy.id) == Pos(2,1,1,1));

    // Scenario 3: (ladders don't hold climbers that are already falling)
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 |_ #      2 |_ #
    //  3 #= #      3 #= #
    //  4 #= #      4 #@ #
    //  5 ####      5 ####
    w.store.remove!Pos(guy);
    w.store.add!Pos(guy, Pos(1,1,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(guy.id) == Pos(4,1,1,1));

    // Scenario 4: (water breaks fall)
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 |_ #      2 |_ #
    //  3 #=~#      3 #@~#
    //  4 #=~#      4 #=~#
    //  5 ####      5 ####
    w.store.remove!Pos(guy);
    w.store.add!Pos(guy, Pos(1,1,1,1));
    w.map.waterLevel = 2;
    grav.run(w);

    assert(*w.store.get!Pos(guy.id) == Pos(3,1,1,1));
}

// vim:set ai sw=4 ts=4 et:
