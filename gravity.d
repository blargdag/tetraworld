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
    ThingId[] targets;

    private void enqueueNewTargets(World w)
    {
        auto app = appender(targets);
        w.store.getAllNew!Pos()
               .filter!(id => w.store.get!NoGravity(id) is null)
               .copy(app);
        targets = app.data;
        w.store.clearNew!Pos();
    }

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
     * Gravity system.
     */
    void run(World w)
    {
        enqueueNewTargets(w);
        ThingId[] newTargets;
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
                    auto obj = r.front;
                    auto objId = obj.id;

                    w.notify.fallOn(oldPos, t.id, objId);
                    if (w.store.get!Mortal(objId) !is null)
                    {
                        import damage;
                        w.injure(t.id, objId, invalidId /*FIXME*/, 1 /*FIXME*/);
                    }

                    if (w.store.getObj(objId) !is null)
                    {
                        // Throw object to random sideways direction, unless
                        // it's completely blocked in, in which case it stays
                        // put.
                        auto newPos = horizDirs
                            .map!(dir => Pos(floorPos + vec(dir2vec(dir))))
                            .filter!(pos => !w.locationHas!BlocksMovement(pos))
                            .pickOne(floorPos);

                        // If completely blocked on all sides, get stuck on
                        // top.
                        if (newPos == floorPos)
                            break;

                        rawMove(w, t, newPos, {
                            // FIXME: replace with something else, like being
                            // thrown to the side.
                            w.notify.fall(oldPos, t.id, newPos);
                        });
                    }
                }
                else
                {
                    rawMove(w, t, floorPos, {
                        w.notify.fall(oldPos, t.id, floorPos);
                    });
                }
            }
        }

        targets = newTargets;
    }
}

// vim:set ai sw=4 ts=4 et:
