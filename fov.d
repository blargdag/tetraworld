/**
 * Field-of-vision module
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
module fov;

import std.algorithm;
import std.range;

import components;
import loadsave;
import vector;
import world;

/**
 * An agent's memory of the map.
 */
struct MapMemory
{
    private TileId[] impl;
    private Region!(int,4) reg;
    private Vec!(int,4) dim;

    this(Region!(int,4) bounds)
    {
        reg = bounds;
        impl.length = reg.volume;
        dim = reg.max - reg.min;
    }

    TileId opIndex(int[4] pos...)
    {
        if (reg.contains(vec(pos)))
        {
            auto off = vec(pos) - reg.min;
            return impl[off[0] + dim[0]*(off[1] + dim[1]*(off[2] +
                                                          dim[2]*off[3]))];
        }
        else
            return TileId.blocked;
    }

    void opIndexAssign(TileId tile, int[4] pos...)
    {
        if (!reg.contains(vec(pos)))
            return; // no-op
        auto off = vec(pos) - reg.min;
        impl[off[0] + dim[0]*(off[1] + dim[1]*(off[2] + dim[2]*off[3]))] =
            tile;
    }

    void save(S)(ref S savefile)
        if (isSaveFile!S)
    {
        savefile.put("reg", reg);

        import std.base64 : Base64;
        import std.zlib : compress;
        savefile.put("data", Base64.encode(compress(impl)));
    }

    void load(L)(ref L loadfile)
        if (isLoadFile!L)
    {
        reg = loadfile.parse!(Region!(int,4))("reg");
        dim = reg.max - reg.min;

        import std.base64 : Base64;
        import std.zlib : uncompress;
        auto len = reg.volume;
        auto rawdata = loadfile.parse!string("data");
        auto data = cast(TileId[]) uncompress(Base64.decode(rawdata), len);
        if (data.length != len)
            throw new LoadException("Map memory data corrupted");

        impl = data;
    }
}

/**
 * Returns: true if the target tile is visible from the given reference
 * position.
 */
bool canSee(World w, Vec!(int,4) eyePos, Vec!(int,4) targetPos)
{
    import std.math : abs;

    auto diff = targetPos - eyePos;
    auto basis = diff[].map!(x => abs(x)).maxElement;
    auto accum = diff;

    foreach (_; 1 .. basis)
    {
        if (w.locationHas!BlocksView(Pos(eyePos + accum/basis)))
            return false;   // hit an obstacle
        accum += diff;
    }
    return true;
}

unittest
{
    // Test map:
    //    0123456
    //  0 #######
    //  1 #     #
    //  2 #######
    import gamemap;
    auto root = new RoomNode;
    root.isRoom.interior = region(vec(1,1,1,1), vec(2,6,3,3));

    auto w = new World;
    w.map.tree = root;
    w.map.bounds = root.interior;
    w.map.waterLevel = int.max;

    assert( canSee(w, vec(1,0,1,1), vec(1,0,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,1,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,2,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,3,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,4,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,5,1,1)));
    assert( canSee(w, vec(1,0,1,1), vec(1,6,1,1)));
    assert(!canSee(w, vec(1,0,1,1), vec(1,7,1,1)));
    assert(!canSee(w, vec(1,0,1,1), vec(1,8,1,1)));

    assert( canSee(w, vec(1,1,1,1), vec(1,1,1,1)));
    assert( canSee(w, vec(1,1,1,1), vec(1,2,1,1)));
    assert( canSee(w, vec(1,1,1,1), vec(1,3,1,1)));
    assert( canSee(w, vec(1,1,1,1), vec(1,4,1,1)));
    assert( canSee(w, vec(1,1,1,1), vec(1,5,1,1)));
    assert( canSee(w, vec(1,1,1,1), vec(1,6,1,1)));
    assert(!canSee(w, vec(1,1,1,1), vec(1,7,1,1)));
    assert(!canSee(w, vec(1,1,1,1), vec(1,8,1,1)));
}

/**
 * The game world filtered through the eyes (and other senses, including
 * knowledge) of an Agent.
 */
struct WorldView
{
    private World w;
    private MapMemory mem;
    private Vec!(int,4) refPos;

    this(World _w, MapMemory memory, Vec!(int,4) _refPos)
    {
        w = _w;
        mem = memory;
        refPos = _refPos;
    }

    /**
     * Returns: Tile at the given position, or TileId.blocked if it's not
     * visible to the subject for whatever reason.
     */
    TileId opIndex(int[4] pos...)
    {
        // This is because the leftmost walls in a map are implicit (they are
        // at the -1 coordinate), but we need to remember them, so we offset
        // the real coordinates in order to map the leftmost walls to
        // coordinate 0 in the memory.
        auto mempos = vec(pos) + vec(1,1,1,1);

        if (!canSee(w, refPos, vec(pos)))
            return mem[mempos];

        auto result = opIndexImpl(pos);
        mem[mempos] = result[1];
        return result[0];
    }

    private TileId terrainTile(int[4] pos)
    {
        import terrain : emptySpace;
        auto terrainId = w.map[pos];
        if (terrainId == emptySpace.id)
        {
            // Empty space: check if tile below has TiledAbove; if so, render
            // that instead.
            auto ta = w.getAllAt(Pos(vec(pos) + vec(1,0,0,0)))
                       .map!(id => w.store.get!TiledAbove(id))
                       .filter!(ta => ta !is null);
            if (!ta.empty)
                return ta.front.tileId;
        }

        return w.store.get!Tiled(terrainId).tileId;
    }

    /**
     * Returns: The top TileId and the TileId to be stored in map memory.
     * Usually identical, except when the top TileId has Hint.dynamic
     * (indicating an object that frequently moves and therefore should not be
     * saved in map memory).
     */
    private TileId[2] opIndexImpl(int[4] pos)
    {
        TileId[2] result;
        auto r = w.store.getAllBy!Pos(Pos(pos))
                        .map!(id => w.store.get!Tiled(id))
                        .filter!(tilep => tilep !is null)
                        .map!(tilep => *tilep);
        if (r.empty)
        {
            result[0] = result[1] = terrainTile(pos);
            return result;
        }

        result[0] = r.save
                     .maxElement!(tile => tile.stackOrder)
                     .tileId;
        auto s = r.filter!(tile => tile.hint != Tiled.Hint.dynamic);
        result[1] = (!s.empty) ? s.maxElement!(tile => tile.stackOrder).tileId
                               : terrainTile(pos);

        return result;
    }

    @property int opDollar(int i)() { return w.map.opDollar!i; }

    import gamemap;
    static assert(is4DArray!(typeof(this)));
}

// vim:set ai sw=4 ts=4 et:
