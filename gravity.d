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

import agent;
import action;
import components;
import dir;
import rndutil;
import store;
import store_traits;
import world;
import vector;

Thing gravity = Thing(gravityId);

/**
 * Register special gravity-related objects.
 */
void registerGravityObjs(Store* store, SysAgent* sysAgent, SysGravity* sysGravity)
{
    // Agent for sinking objects.
    AgentImpl sinkImpl;
    sinkImpl.chooseAction = (World w, ThingId agentId) {
        sysGravity.sinkObjects(w);
        return (World w) => ActionResult(true, 10);
    };
    sysAgent.registerAgentImpl(Agent.Type.sinkAgent, sinkImpl);

    store.registerSpecial(gravity, Weapon(DmgType.fallOn),
                          Agent(Agent.type.sinkAgent));
}

enum FallType
{
    // NOTE: this is ordered in such a way that when multiple objects
    // provide different kinds of support, min(FallType) gives the
    // resulting overall effect.
    none = 0,
    rest = 1,
    sink = 2,
    fall = 3,
}

private FallType checkSupport(World w, ThingId id, bool alreadyFalling,
                              SupportsWeight* sw, SupportType type)
{
    if (sw is null || (sw.type & type) == 0)
        return FallType.fall;

    auto cm = w.store.get!CanMove(id);

    final switch (sw.cond)
    {
        case SupportCond.always:
            return FallType.rest;

        case SupportCond.permanent:
            return FallType.none;

        case SupportCond.climbing:
            if (!alreadyFalling && cm !is null &&
                (cm.types & CanMove.Type.climb))
            {
                return FallType.rest;
            }
            break;

        case SupportCond.buoyant:
            if (cm !is null && (cm.types & CanMove.Type.swim))
                return FallType.rest;

            // Non-buoyant objects will sink, but only slowly.
            return FallType.sink;
    }
    return FallType.fall;
}

private FallType computeFallTypeImpl(World w, ThingId id, bool alreadyFalling,
                                     Pos oldPos, Pos floorPos)
{
    // Check if something at current location is supporting this object.
    auto ft = w.getAllAt(oldPos)
               .map!(swid => checkSupport(w, id, alreadyFalling,
                                          w.store.get!SupportsWeight(swid),
                                          SupportType.within))
               .minElement;
    if (ft <= FallType.rest)
        return ft;

    // Check if something on the floor is supporting this object.
    ft = min(ft,
        w.getAllAt(floorPos)
         .map!(swid => checkSupport(w, id, alreadyFalling,
                                    w.store.get!SupportsWeight(swid),
                                    SupportType.above))
         .minElement);
    return ft;
}

private FallType computeFallType(World w, ThingId id, bool alreadyFalling,
                                 out Pos oldPos, out Pos floorPos)
{
    // NOTE: race condition: a falling object may autopickup another object and
    // remove its Pos while we're still iterating, which will cause posp to be
    // null.
    auto posp = w.store.get!Pos(id);
    if (posp is null)
        return FallType.none;

    oldPos = *posp;
    floorPos = Pos(oldPos + vec(1,0,0,0));

    return computeFallTypeImpl(w, id, alreadyFalling, oldPos, floorPos);
}

/**
 * Returns: Whether given entity still fall or sink, if it were to be placed at
 * the given position.
 */
FallType computeFallType(World w, ThingId id, Pos pos)
{
    Pos floorPos = Pos(pos + vec(1,0,0,0));
    return computeFallTypeImpl(w, id, false, pos, floorPos);
}

/**
 * Gravity system.
 */
struct SysGravity
{
    // List of objects that are sinking or could potentially be falling.
    //
    // NOTE: do NOT remove objects that have merely come to rest, as their
    // support may change; only remove them if the support is permanent (part
    // of unchanging terrain).
    //
    // NOTE: FallType.rest is interpreted as having come to rest the previous
    // iteration, and fallOn will be suppressed until the fall state changes
    // again. This is to prevent multiple over-invocations of fallOn when we
    // get called from the agent system multiple times per turn.
    private FallType[ThingId] trackedObjs;

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

        w.events.emit(Event(EventType.dmgFallOn, oldPos, t.id, objId,
                            gravityId));
        if (w.store.get!Mortal(objId) !is null)
        {
            import damage;
            w.injure(t.id, objId, DmgType.fallOn, 1 /*FIXME*/);
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
            w.events.emit(Event(EventType.moveFallAside, oldPos, newPos,
                                t.id));
        });
        return true;
    }

    private void runOnce(World w, Thing* t, FallType prevType)
    {
        Pos oldPos, floorPos;
        FallType type = computeFallType(w, t.id, false, oldPos, floorPos);
        EventType etype = EventType.moveFall;
        OUTER: while (type > FallType.rest)
        {
            final switch (type)
            {
                case FallType.none:
                case FallType.rest:
                    assert(0);

                case FallType.sink:
                    // Sinking is done by the sinking agent; here we just mark
                    // the object as sinking and the agent will pick it up
                    // later.
                    break OUTER;

                case FallType.fall:
                    // An object that blocks moves but is unable to support
                    // weight will get damaged by the falling object, and throw
                    // the falling object sideways. (Note that not supporting
                    // weight is already implied by FallType.fall.)
                    auto r = w.store.getAllBy!Pos(floorPos)
                              .map!(id => w.store.getObj(id))
                              .filter!(t => t.systems &
                                            SysMask.blocksmovement);
                    if (!r.empty)
                    {
                        // Note: if prevType == rest, that means we already
                        // triggered fallOn the last time round; don't trigger
                        // it again until the blocking object moves away.
                        type = FallType.rest;
                        if (prevType == FallType.rest ||
                            !fallOn(w, t, r.front, oldPos, floorPos))
                        {
                            break OUTER;
                        }
                    }
                    else
                    {
                        rawMove(w, t, floorPos, {
                            w.events.emit(Event(etype, oldPos, floorPos,
                                                t.id));
                        });
                        prevType = type;
                        etype = EventType.moveFall2;
                    }
                    break;
            }
            type = computeFallType(w, t.id, true, oldPos, floorPos);
        }

        if (type == FallType.none)
        {
            trackedObjs.remove(t.id);
        }
        else
        {
            // Keep track of object fall state.
            trackedObjs[t.id] = type;
        }
    }

    /**
     * Run main gravity system.
     */
    void run(World w)
    {
        // Returns: true if new targets were added; false otherwise.
        bool mergeNewTargets(bool first)
        {
            bool result = false;
            foreach (id; w.store.getAllNew!Pos()
                          .filter!((id) {
                                auto wgt = w.store.get!Weight(id);
                                return (wgt !is null) ? wgt.value > 0 : false;
                          }))
            {
                // If object received new Pos since last call to .run,
                // unconditionally overwrite its state to .init. Within the
                // same .run call, however, retain previous state so that we
                // don't trigger fallOn too many times.
                if (first || id !in trackedObjs)
                    trackedObjs[id] = FallType.init;
                result = true;
            }

            // We clear now so that any newly-spawned objects or objects that
            // got moved due to gravity-initiated triggers will be noticed in
            // the next iteration.
            w.store.clearNew!Pos();

            return result;
        }

        mergeNewTargets(true);
        do
        {
            foreach (id; trackedObjs.byKeyValue
                                    .filter!(kv => kv.value != FallType.sink)
                                    .map!(kv => kv.key)
                                    .array)
            {
                auto t = w.store.getObj(id);
                if (t is null)
                {
                    trackedObjs.remove(id);
                    continue;
                }

                runOnce(w, t, trackedObjs.get(id, FallType.init));
            }
        } while (mergeNewTargets(false));
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
        // Note: need to copy Thing* into array because rawMove() can
        // potentially destroy / remove objects.
        foreach (obj; trackedObjs.byKeyValue
                                 .filter!(kv => kv.value == FallType.sink)
                                 .map!(kv => w.store.getObj(kv.key))
                                 .filter!(t => t !is null)
                                 .array)
        {
            Pos oldPos, floorPos;
            auto type = computeFallType(w, obj.id, false, oldPos, floorPos);
            final switch (type)
            {
                case FallType.none:
                    // Object resting on permanent surface; untrack it.
                    trackedObjs.remove(obj.id);
                    break;

                case FallType.rest:
                    // Object resting on support; nothing left to do but don't
                    // untrack it just yet (support may shift).
                    trackedObjs[obj.id] = type;
                    break;

                case FallType.fall:
                    // Object may have left the water since the last call to
                    // sinkObjects. So update the state now.
                    trackedObjs[obj.id] = type;
                    continue;

                case FallType.sink:
                    rawMove(w, obj, floorPos, {
                        w.events.emit(Event(EventType.moveSink, oldPos,
                                            floorPos, obj.id));
                    });
                    break;
            }
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
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(3,3,2,2));
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
    auto rock = w.store.createObj(Name("rock"), Pos(1,1,1,1), Weight(10));
    auto victim = w.store.createObj(Name("victim"), Pos(2,1,1,1), Weight(100),
                                    Mortal(Stats(2,2)), BlocksMovement());
    assert(!w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(2,2,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats == Stats(2, 1));

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
    victim = w.store.createObj(Name("victim"), Pos(2,1,1,1), Weight(100),
                               Mortal(Stats(3,3)), BlocksMovement());
    auto corner = w.store.createObj(Name("artificial wall"), Pos(1,2,1,1),
                                    BlocksMovement());
    assert(w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(1,1,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats == Stats(3, 2));
    assert(*w.store.get!Pos(corner.id) == Pos(1,2,1,1));

    // Scenario 4:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #@ #
    //  2 #A##      2 #A##
    //  3 ####      3 ####
    grav = grav.init;
    w.store.remove!Pos(rock);
    w.store.add!Pos(rock, Pos(1,1,1,1));
    w.store.remove!Pos(corner);
    w.store.add!Pos(corner, Pos(2,2,1,1));
    assert(!w.locationHas!BlocksMovement(Pos(1,2,1,1)));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(1,1,1,1));
    assert(*w.store.get!Pos(victim.id) == Pos(2,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats == Stats(3, 1));
    assert(*w.store.get!Pos(corner.id) == Pos(2,2,1,1));

    // Scenario 5:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #A##      2 #@##
    //  3 ####      3 ####
    grav = grav.init;
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
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));
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
    w.map.waterLevel = 3;
    assert(w.map[2,1,1,1] == emptySpace.id);
    assert(w.map[3,1,1,1] == water.id);
    auto rock = w.store.createObj(Name("rock"), Pos(1,1,1,1), Weight(10));
    grav.run(w);

    assert(*w.store.get!Pos(rock.id) == Pos(3,1,1,1));

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
    assert(*w.store.get!Pos(rock.id) == Pos(4,1,1,1));

    // Optimization test
    assert(!canFind(grav.trackedObjs.byKey, rock.id));
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
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));

    import mapgen : addLadders;
    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(1,1,1,1), vec(6,4,3,3));
    w.map.waterLevel = int.max;
    addLadders(w, w.map.tree, w.map.bounds);

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
    auto rock = w.store.createObj(Name("rock"), Pos(2,1,1,1), Weight(10));
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
    auto guy = w.store.createObj(Name("guy"), Pos(2,1,1,1), Weight(100),
                                 CanMove(CanMove.Type.climb));
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
    w.map.waterLevel = 3;
    grav.run(w);

    assert(*w.store.get!Pos(guy.id) == Pos(3,1,1,1));
}

// Test for gravity-triggered spawns of objects that must subsequently fall
// down.
unittest
{
    import gamemap, terrain;

    // Test map:
    //    0123
    //  0 ####
    //  1 #? #  ? = spawn location
    //  2 #  #
    //  3 #  #
    //  4 #T #  T = trigger
    //  5 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(1,1,1,1), vec(6,4,3,3));
    w.map.waterLevel = int.max;

    SysGravity grav;
    auto trigger = w.store.createObj(Pos(4,1,1,1), Name("trap"),
                                     Trigger(Trigger.Type.onWeight,
                                             w.triggerId, 10));
    auto rocktrap = w.store.createObj(Pos(1,1,1,1),
                                      Triggerable(w.triggerId,
                                                  TriggerEffect.rockTrap));
    w.triggerId++;

    auto rock = w.store.createObj(Name("big rock"), Weight(50), Pos(1,1,1,1));
    grav.run(w);

    // No rock should be left hanging.
    assert(w.store.getAllBy!Pos(Pos(1,1,1,1)) == [ rocktrap.id ]);

    // Should be exactly two rocks on the floor.
    auto objs = w.store.getAllBy!Pos(Pos(4,1,1,1));
    assert(objs.length == 3);
    auto names = objs.map!(id => w.store.get!Name(id).name)
                     .array;
    names.sort();
    assert(names == [ "big rock", "rock", "trap" ]);
}

unittest
{
    import gamemap, terrain;

    // Test map:
    //    0123
    //  0 ####
    //  1 #? #  ? = spawn location
    //  2 #  #
    //  3 #~~#
    //  4 #T~#  T = trigger
    //  5 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = region(vec(1,1,1,1), vec(6,4,3,3));
    w.map.waterLevel = 3;

    SysGravity grav;

    auto trigger = w.store.createObj(Pos(4,1,1,1), Name("trap"),
                                     Trigger(Trigger.Type.onWeight,
                                             w.triggerId, 10));
    auto rocktrap = w.store.createObj(Pos(1,1,1,1),
                                      Triggerable(w.triggerId,
                                                  TriggerEffect.rockTrap));
    w.triggerId++;

    // Test #1: test sinking mechanic.
    auto rock = w.store.createObj(Name("big rock"), Weight(50), Pos(1,1,1,1));
    grav.run(w);
    assert(*w.store.get!Pos(rock.id) == Pos(3,1,1,1));

    grav.sinkObjects(w);
    assert(*w.store.get!Pos(rock.id) == Pos(4,1,1,1));

    // Find rock spawned by rock trap.
    auto r = w.getAllAt(vec(1,1,1,1))
              .map!(id => w.store.getObj(id))
              .filter!(t => (t.systems & SysMask.name) &&
                            w.store.get!Name(t.id).name == "rock");
    assert(!r.empty);
    auto newrock = r.front;
    r.popFront();
    assert(r.empty);

    // Test #2: test sink mechanics of spawned rock.
    grav.run(w);
    assert(*w.store.get!Pos(newrock.id) == Pos(3,1,1,1));

    grav.sinkObjects(w);
    assert(*w.store.get!Pos(newrock.id) == Pos(4,1,1,1));
}

// Test falling of resting objects when support is displaced.
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
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(6,4,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = int.max;

    SysGravity grav;

    // Scenario 1 (null case):
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #@ #
    //  2 #= #      2 #= #
    //  3 #  #      3 #  #
    //  4 #  #      4 #  #
    //  5 ####      5 ####
    auto fatso = w.store.createObj(Name("fatso"), Pos(1,1,1,1), Weight(100));
    auto platform = w.store.createObj(Name("platform"), Pos(2,1,1,1),
        SupportsWeight(SupportType.above, SupportCond.always));

    grav.run(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(1,1,1,1));
    assert((fatso.id in grav.trackedObjs) !is null);

    // Scenario 2:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 # =#      2 # =#
    //  3 #  #      3 #  #
    //  4 #  #      4 #@ #
    //  5 ####      5 ####
    w.store.remove!Pos(platform);
    w.store.add!Pos(platform, Pos(2,2,1,1));
    grav.run(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(4,1,1,1));

    // Scenario 3:
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@~#  ==> 1 #~~#
    //  2 #~~#      2 #@~#
    //  3 #=~#      3 #=~#
    //  4 #~~#      4 #~~#
    //  5 ####      5 ####
    w.store.remove!Pos(fatso);
    w.store.add!Pos(fatso, Pos(1,1,1,1));
    w.store.remove!Pos(platform);
    w.store.add!Pos(platform, Pos(3,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(2,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);

    // Platform should prevent sinking
    assert(*w.store.get!Pos(fatso.id) == Pos(2,1,1,1));

    // Scenario 4:
    //    0123        0123        0123
    //  0 ####      0 ####      0 #### 
    //  1 #~~#  ==> 1 #~~#  ==> 1 #~~# 
    //  2 #@~#      2 #~~#      2 #~~# 
    //  3 #~=#      3 #@=#      3 #~=# 
    //  4 #~~#      4 #~~#      4 #@~# 
    //  5 ####      5 ####      5 #### 
    w.store.remove!Pos(platform);
    w.store.add!Pos(platform, Pos(3,2,1,1));
    w.map.waterLevel = 0;

    grav.run(w);
    grav.sinkObjects(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(3,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(4,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);

    // Should have come to permanent rest
    assert(*w.store.get!Pos(fatso.id) == Pos(4,1,1,1));
    assert((fatso.id in grav.trackedObjs) is null);

    // Scenario 5 (frequency of fallOn):
    //    0123        0123
    //  0 ####      0 ####
    //  1 #@ #  ==> 1 #  #
    //  2 #  #      2 #  #
    //  3 #  #      3 #@ #
    //  4 #&##      4 #&##
    //  5 ####      5 ####
    w.store.remove!Pos(fatso);
    w.store.add!Pos(fatso, Pos(1,1,1,1));
    w.store.destroyObj(platform.id);
    auto victim = w.store.createObj(Name("бедняжка"), Pos(4,1,1,1),
                                    Mortal(Stats(5,5)), BlocksMovement());
    auto blocker = w.store.createObj(Name("wall"), Pos(4,2,1,1),
                                     BlocksMovement());
    w.map.waterLevel = int.max;

    grav.run(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(3,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats.hp == 4);

    // Once we've come to rest, further invocations should not trigger fallOn
    // anymore.
    grav.run(w);

    assert(*w.store.get!Pos(fatso.id) == Pos(3,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats.hp == 4);
}

// Float-in-midair bug
unittest
{
    import gamemap, terrain;

    // Test map:
    //  0 ####
    //  1 #  #
    //  2 #J #
    //  3 #=~#
    //  4 #=~#
    //  5 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,2,2,2));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(6,3,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = 3;

    SysGravity grav;

    // Ladders
    createLadder(&w.store, Pos(3,1,1,1));
    createLadder(&w.store, Pos(4,1,1,1));

    auto jumper = w.store.createObj(Name("прыгун"), Pos(2,1,1,1), Weight(10),
        CanMove(CanMove.Type.walk | CanMove.Type.climb | CanMove.Type.jump));

    // Initial state sanity test
    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(jumper.id) == Pos(2,1,1,1));

    // Should be at rest
    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(jumper.id) == Pos(2,1,1,1));

    // Test jumping and falling into water.
    w.store.remove!Pos(jumper);
    w.store.add!Pos(jumper, Pos(1,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(jumper.id) == Pos(3,1,1,1));

    // Check fall status after landing in water
    assert(jumper.id in grav.trackedObjs &&
           grav.trackedObjs[jumper.id] == FallType.rest);

    // Move up
    w.store.remove!Pos(jumper);
    w.store.add!Pos(jumper, Pos(2,1,1,1));

    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(jumper.id) == Pos(2,1,1,1));
    assert(jumper.id !in grav.trackedObjs ||
           grav.trackedObjs[jumper.id] != FallType.sink);

    // Jump
    w.store.remove!Pos(jumper);
    w.store.add!Pos(jumper, Pos(1,1,1,1));

    // Should be falling again
    grav.sinkObjects(w);
    assert(jumper.id in grav.trackedObjs &&
           grav.trackedObjs[jumper.id] != FallType.sink);

    grav.run(w);
    assert(*w.store.get!Pos(jumper.id) == Pos(3,1,1,1));

    // Check fall status after landing in water the second time.
    assert(jumper.id in grav.trackedObjs &&
           grav.trackedObjs[jumper.id] == FallType.sink);

    grav.sinkObjects(w);
    assert(jumper.id in grav.trackedObjs &&
           grav.trackedObjs[jumper.id] == FallType.rest);
}

// Walk on enemy bug.
unittest
{
    import gamemap, terrain;

    // Test map:
    //    0123
    //  0 ####
    //  1 #  #
    //  2 #_ #
    //  3 #@ #
    //  4 #=A#
    //  5 ####
    MapNode root = new MapNode;
    root.interior = Region!(int,4)(vec(1,1,1,1), vec(5,3,2,2));
    auto bounds = Region!(int,4)(vec(0,0,0,0), vec(6,3,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = bounds;
    w.map.waterLevel = int.max;

    SysGravity grav;

    // Ladders
    createLadder(&w.store, Pos(3,1,1,1));
    createLadder(&w.store, Pos(4,1,1,1));

    auto walker = w.store.createObj(Name("топчущий"), Pos(3,1,1,1), Weight(10),
        CanMove(CanMove.Type.walk | CanMove.Type.climb | CanMove.Type.jump));
    auto victim = w.store.createObj(Name("жертва"), Pos(4,2,1,1), Weight(10),
        Mortal(Stats(3,3)), BlocksMovement());

    // Initial state sanity test
    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(walker.id) == Pos(3,1,1,1));

    // Should be at rest
    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(walker.id) == Pos(3,1,1,1));

    // Walk onto victim
    w.store.remove!Pos(walker);
    w.store.add!Pos(walker, Pos(3,2,1,1));

    grav.run(w);
    grav.sinkObjects(w);
    assert(*w.store.get!Pos(walker.id) == Pos(4,1,1,1));
    assert(w.store.get!Mortal(victim.id).curStats.hp == 2);
}

// vim:set ai sw=4 ts=4 et:
