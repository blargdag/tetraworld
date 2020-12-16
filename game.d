/**
 * Game simulation module.
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
module game;

import std.algorithm;
import std.array;
import std.conv : to;
import std.format : format, formattedWrite;
import std.random : uniform;
import std.range.primitives;
import std.stdio;
import std.uni : asCapitalized;

import action;
import agent;
import ai;
import components;
import dir;
import fov;
import gravity;
import hiscore;
import loadsave;
import mapgen;
import medium;
import rndutil;
import store;
import store_traits;
import vector;
import world;

/**
 * Default savegame filename.
 *
 * TBD: this really should be replaced with a playground directory system like
 * in nethack.
 */
enum saveFileName = ".tetra.save";

/**
 * Logical player input action.
 */
struct PlayerAction
{
    enum Type
    {
        none, move, applyFloor, applyItem, pickup, drop, pass,
    }

    Type type;
    union
    {
        Dir dir;
        ThingId objId;
    }
    int objCount;

    this(Type _type, Dir _dir)
    {
        type = _type;
        dir = _dir;
    }

    this(Type _type, ThingId _objId = invalidId, int _objCount = 0)
    {
        type = _type;
        objId = _objId;
        objCount = _objCount;
    }
}

/**
 * Generic UI API.
 */
interface GameUi
{
    /**
     * Add a message to the message log.
     */
    void message(string msg);

    /// ditto
    final void message(Args...)(string fmt, Args args)
        if (Args.length >= 1)
    {
        message(format(fmt, args));
    }

    /**
     * Read player action from user input.
     */
    PlayerAction getPlayerAction();

    /**
     * Notify UI that a map change has occurred.
     *
     * Params:
     *  where = List of affected locations to update.
     */
    void updateMap(Pos[] where...);

    /**
     * Notify that the map should be moved and recentered on a new position.
     * The map will be re-rendered.
     *
     * If multiple refreshes occur back-to-back without an intervening input
     * event, a small pause will be added for animation effect.
     */
    void moveViewport(Vec!(int,4) center);

    /**
     * Signal end of game with an exit message.
     */
    void quitWithMsg(string msg, HiScore hs);

    /**
     * Display some info for the user and wait for keypress.
     */
    void infoScreen(const(string)[] paragraphs, string endPrompt = "[End]");
}

/**
 * Player status.
 */
struct PlayerStatus
{
    string label;
    int curval;
    int maxval;

    enum Urgency { none, warn, critical }
    Urgency urgency;
}

/**
 * Inventory item.
 */
struct InventoryItem
{
    ThingId id;
    TileId tileId;
    string name;
    int count;
    bool equipped;

    void toString(W)(W sink)
    {
        if (count == 1)
            put(sink, "a ");
        else
            sink.formattedWrite("%d ", count);
        put(sink, name);
    }

    unittest
    {
        import std.array : appender;
        auto app = appender!string;
        auto item = InventoryItem(1, TileId.unknown, "thingie", 1);
        item.toString(app);
        assert(app.data == "a thingie");
    }
}

// TBD: move this to a more appropriate place
static bool canHear(World w, int hearRadius, Vec!(int,4) hearer,
                    Vec!(int,4) soundSrc)
{
    import std.algorithm : map, fold;
    import std.range : iota;

    // TBD: modulate hearing by world geometry.
    auto radSqr = hearRadius * hearRadius;
    return iota(4).map!(i => hearer[i] - soundSrc[i])
                  .map!(x => x*x)
                  .sum <= radSqr;
}

unittest
{
    auto w = new World;
    // TBD: test geometry
    assert( canHear(w, 20, vec(0,0,0,0), vec(10,10,10,10)));
    assert(!canHear(w, 20, vec(0,0,0,0), vec(11,11,11,11)));
}

/**
 * Game simulation.
 */
class Game
{
    private GameUi ui;
    private World w;
    private SysAgent sysAgent;
    private SysGravity sysGravity;
    private SysAi sysAi;

    private Thing* player;
    private MapMemory plMapMemory;
    private Vec!(int,4) lastPlPos, lastObservePos;
    private int storyNode;
    private bool quit;

    private int nTurns;

    /**
     * Returns: The player's current position.
     */
    Vec!(int,4) playerPos()
    {
        auto posp = w ? w.store.get!Pos(player.id) : null;
        if (posp !is null)
            lastPlPos = posp.coors;
        return lastPlPos;
    }

    /**
     * Returns: The player's world view (a filtered version of World based on
     * what the player knows / can perceive).
     */
    WorldView playerView()
    {
        return WorldView(w, plMapMemory, playerPos);
    }

    /**
     * Returns: The player's current statuses.
     */
    PlayerStatus[] getStatuses()
    {
        static PlayerStatus.Urgency urgency(int val, int max)
        {
            return (val <= max / 4) ? PlayerStatus.Urgency.critical :
                   (val <= max / 2) ? PlayerStatus.Urgency.warn :
                   PlayerStatus.Urgency.none;
        }

        PlayerStatus[] result;
        if (w.store.get!Inventory(player.id) !is null)
            result ~= PlayerStatus("$", numGold(), maxGold());

        auto m = w.store.get!Mortal(player.id);
        if (m !is null)
        {
            auto st = m.curStats;
            result ~= PlayerStatus("hp", st.hp, st.maxhp,
                                   urgency(st.hp, st.maxhp));
            result ~= PlayerStatus("air", st.air, st.maxair,
                                   urgency(st.air, st.maxair));
        }

        foreach (p; findBreathingEquip(w, player.id, m))
        {
            auto id = p[0];
            auto be = p[1];
            result ~= PlayerStatus("scuba", be.bonuses.air, be.bonuses.maxair,
                                   urgency(be.bonuses.air, be.bonuses.maxair));
        }

        return result;
    }

    /**
     * Returns: Items currently in the player's inventory.
     */
    InventoryItem[] getInventory(bool delegate(Inventory.Item) filt = null)
    {
        auto inven = w.store.get!Inventory(player.id);
        if (inven is null)
            return [];

        return inven.contents
                    .filter!(item => item.type == Inventory.Item.Type.carrying ||
                                     item.type == Inventory.Item.Type.equipped)
                    .filter!(item => filt ? filt(item) : true)
                    .map!((item) {
                        auto id = item.id;
                        auto tl = w.store.get!Tiled(id);
                        auto nm = w.store.get!Name(id);
                        auto stk = w.store.get!Stackable(id);
                        return InventoryItem(id, tl ? tl.tileId :
                                                      TileId.unknown,
                                             nm ? nm.name : "???",
                                             stk ? stk.count : 1,
                                             item.type == Inventory.Item.Type.equipped);
                    })
                    .array;
    }

    auto toInventoryItem(ThingId id)
    {
        auto tiled = w.store.get!Tiled(id);
        auto nm = w.store.get!Name(id);
        auto stk = w.store.get!Stackable(id);
        return InventoryItem(id, tiled ? tiled.tileId : TileId.unknown,
                             nm ? nm.name : "???",
                             stk ? stk.count : 1);
    }

    private int numGold()
    {
        auto inv = w.store.get!Inventory(player.id);
        return inv.contents
                  .map!(item => item.id)
                  .filter!((id) {
                      auto qi = w.store.get!QuestItem(id);
                      return qi !is null && qi.questId == 1;
                  })
                  .map!(id => w.store.get!Stackable(id))
                  .map!(stk => (stk is null) ? 1 : stk.count)
                  .sum
                  .to!int;
    }

    private int maxGold()
    {
        return w.store.getAll!QuestItem
                      .filter!(id => w.store.get!QuestItem(id).questId == 1)
                      .map!(id => w.store.get!Stackable(id))
                      .map!(stk => (stk is null) ? 1 : stk.count)
                      .sum
                      .to!int;
    }

    void saveGame()
    {
        auto sf = File(saveFileName, "wb").lockingTextWriter.saveFile;
        sf.put("player", player.id);
        sf.put("story", storyNode);
        sf.put("turns", nTurns);
        sf.put("world", w);
        sf.put("agent", sysAgent);
        sf.put("gravity", sysGravity);
        sf.put("ai", sysAi);
        sf.put("memory", plMapMemory);
    }

    static Game loadGame()
    {
        auto lf = File(saveFileName, "r").byLine.loadFile;
        ThingId playerId = lf.parse!ThingId("player");

        auto game = new Game;
        game.storyNode = lf.parse!int("story");
        game.nTurns = lf.parse!int("turns");
        game.w = lf.parse!World("world");
        game.sysAgent = lf.parse!SysAgent("agent");
        game.sysGravity = lf.parse!SysGravity("gravity");
        game.sysAi = lf.parse!SysAi("ai");
        game.plMapMemory = lf.parse!MapMemory("memory");

        game.player = game.w.store.getObj(playerId);
        if (game.player is null)
            throw new Exception("Save file is corrupt!");

        // Permadeath. :-D
        import std.file : remove;
        remove(saveFileName);

        return game;
    }

    static Game newGame() { return new Game; }

    debug static Game testLevel()
    {
        int[4] startPos;
        auto g = new Game;
        g.w = genTestLevel(startPos);
        g.setupLevel();
        rawMove(g.w, g.player, Pos(startPos), {});
        return g;
    }

    private Action movePlayer(int[4] displacement, ref string errmsg)
    {
        auto pos = playerPos;
        if (!canMove(w, pos, vec(displacement)) &&
            !canClimbLedge(w, pos, vec(displacement)))
        {
            if (auto weapon = hasEquippedWeapon(w, player.id))
            {
                if (auto target = canAttack(w, player.id, vec(displacement), weapon))
                {
                    return (World w) => attack(w, player, target, weapon);
                }
            }
            errmsg = "Your way is blocked.";
            return null;
        }

        auto v = vec(displacement);
        return (World w) => move(w, player, v);
    }

    private Action pickupObj(ThingId targetId, ref string errmsg)
    {
        return (World w) => pickupItem(w, player, targetId);
    }

    private Action dropObj(ThingId objId, int count, ref string errmsg)
    {
        return (World w) => dropItem(w, player, objId, count);
    }

    private Action applyObj(ThingId targetId, ref string errmsg)
    {
        auto r = getInventory(item => item.id == targetId);
        if (r.empty)
        {
            errmsg = "You're not carrying that!";
            return null;
        }

        auto item = r.front;
        auto obj = w.store.getObj(item.id);
        if (obj.systems & (SysMask.armor | SysMask.weapon))
        {
            if (item.equipped)
                return (World w) => unequip(w, player, item.id);
            else
                return (World w) => equip(w, player, item.id);
        }
        else
        {
            // TBD: invoke use action for usable items
        }

        errmsg = "You can't apply that!";
        return null;
    }

    private Action applyFloorObj(ThingId targetId, ref string errmsg)
    {
        // Check use prerequisites.
        // FIXME: need a more general prerequisites model here.
        auto u = w.store.get!Usable(targetId);
        if (u is null)
        {
            errmsg = "You can't apply that!";
            return null;
        }

        if (u.effect == UseEffect.portal)
        {
            auto ngold = numGold();
            auto maxgold = maxGold();
            if (ngold < maxgold)
            {
                errmsg = "The exit portal is here, but you haven't found "~
                         "all the gold yet.";
                return null;
            }
        }

        return (World w) => useItem(w, player, targetId);
    }

    private void setupLevel()
    {
        // Player memory needs to cover outer walls to avoid strange artifacts
        // like un-rememberable walls.
        plMapMemory = MapMemory(region(w.map.bounds.min,
                                       w.map.bounds.max + vec(1,1,1,1)));

        Stats stats;
        stats.maxhp = stats.hp = 5;
        stats.canBreatheIn = Medium.air;
        stats.maxair = stats.air = 8;

        player = w.store.createObj(
            Tiled(TileId.player, 2, Tiled.Hint.dynamic), Name("you"),
            Agent(Agent.Type.player), Inventory([], true), Weight(1000),
            BlocksMovement(), Mortal(stats, Faction.loner),
            CanMove(CanMove.Type.walk | CanMove.Type.climb |
                    CanMove.Type.jump | CanMove.Type.swim)
        );
    }

    private void startStory()
    {
        ui.infoScreen(storyNodes[storyNode].infoScreen, "[Proceed]");

        int[4] startPos;
        w = storyNodes[storyNode].genMap(startPos);
        sysAgent = SysAgent.init;
        sysGravity = SysGravity.init;
        sysAi = SysAi.init;
        setupLevel();

        setupAgentImpls();
        sysGravity.run(w);

        // Move player to starting position.
        rawMove(w, player, Pos(startPos), {});
        sysGravity.run(w);
        ui.moveViewport(playerPos);

        setupEventWatchers();
    }

    private void portalSystem()
    {
        if (w.store.get!UsePortal(player.id) !is null)
        {
            w.store.remove!UsePortal(player);

            auto ngold = numGold();
            auto maxgold = maxGold();

            ui.message("You collected %d out of %d gold.", ngold, maxgold);

            storyNode++;
            if (storyNode < storyNodes.length)
            {
                startStory();
            }
            else
            {
                quit = true;
                ui.quitWithMsg("Congratulations, you have finished the game!",
                    registerHiScore(Outcome.win, "Won the game"));
            }
        }
    }

    HiScore registerHiScore(Outcome outcome, string desc = "")
    {
        import std.datetime.systime : Clock, SysTime;
        import std.process : environment;

        HiScore hs;
        hs.timestamp = TimeStamp(Clock.currTime);
        hs.name = environment.get("USER", "anonymous");
        hs.levels = storyNode;
        hs.turns = nTurns;
        hs.outcome = outcome;
        if (hs.outcome == Outcome.giveup)
        {
            hs.desc = (storyNode == 0) ?  "Chickened out the first day on "~
                                          "the job." :
                      (storyNode < 6) ? "Walked out on the job." :
                      "Escaped in terror from 4D space.";
        }
        else
            hs.desc = desc;

        addHiScore(hs);
        return hs;
    }

    private HiScore genDeathScore(Event ev)
        in (ev.type == EventType.dmgKill && ev.objId == player.id)
    {
        auto subjName = w.store.get!Name(ev.subjId).name;
        string desc;

        // TBD: add more funny messages depending on contextual information.
        import terrain : water;
        int waterDepth = (playerPos[0] - w.map.waterLevel + 1)*5;
        if (ev.subjId == water.id)
        {
            if (waterDepth > 0)
                desc = format("Drowned under %d feet of water.", waterDepth);
            else
                desc = format("Impressively drowned while above water.");
        }
        else
        {
            if (ev.dmgType & DmgType.fallOn)
                desc = format("Killed by a falling %s.", subjName);
            else if (waterDepth > 0)
                desc = format("Killed by %s while %d feet under water.",
                              subjName, waterDepth);
            else
                desc = format("Killed by %s.", subjName);
        }

        return registerHiScore(Outcome.dead, desc);
    }

    private string fmtVisibleEvent(Event ev)
    {
        if (ev.cat == EventCat.move)
        {
            auto isPlayer = (ev.subjId == player.id);
            bool canSeeWhere = canSee(w, playerPos, ev.where);
            bool canSeeWhereTo = canSee(w, playerPos, ev.whereTo);
            bool moveIntoView = !canSeeWhere && canSeeWhereTo;
            bool moveOutOfView = canSeeWhere && !canSeeWhereTo;

            string subjName = "you";
            if (!isPlayer)
            {
                auto nameObj = w.store.get!Name(ev.subjId);
                if (nameObj is null)
                    return "";
                subjName = nameObj.name;
            }
            string verb; // TBD: replace this with lang module

            switch (ev.type)
            {
                case EventType.moveWalk:
                case EventType.moveJump:
                case EventType.moveClimb:
                case EventType.moveClimbLedge1:
                    return "";

                case EventType.moveSink:
                    verb = isPlayer ? "sink" : "sinks";
                    return format("%s %s in the water.",
                                  subjName.asCapitalized, verb);

                case EventType.moveClimbLedge0:
                    verb = isPlayer ? "climb up" : "climbs up";
                    return format("%s %s the ledge.",
                                  subjName.asCapitalized, verb);

                case EventType.moveFall:
                    verb = isPlayer ? "fall" : "falls";
                    return (isPlayer || moveIntoView || moveOutOfView) ?
                            format("%s %s!", subjName.asCapitalized, verb) :
                            "";

                case EventType.moveFall2:
                    // Suppress consecutive fall messages unless it conveys new
                    // information.
                    return (!isPlayer && (moveIntoView || moveOutOfView)) ?
                            format("%s falls!", subjName.asCapitalized) : "";

                case EventType.moveFallAside:
                    return format("The impact sends %s rolling to the side!",
                                  subjName);

                case EventType.movePass:
                    // Pause messages are too noisy for NPCs, just show it only
                    // when it's the player himself.
                    //verb = isPlayer ? "pause" : "pauses";
                    //return format("%s %s for a moment.", subjName.asCapitalized, verb);
                    return isPlayer ? "You pause for a moment." : "";

                default:
                    assert(0, "Unhandled event type: %s".format(ev.type));
            }
            assert(0);
        }
        else if (ev.cat == EventCat.itemAct)
        {
            auto isPlayer = (ev.subjId == player.id);
            auto subjName = isPlayer ? "you" :
                            w.store.get!Name(ev.subjId).name;
            auto objName = w.store.get!Name(ev.objId);
            string verb; // TBD: replace this with lang module

            switch (ev.type)
            {
                case EventType.itemPickup:
                    verb = isPlayer ? "pick up" : "picks up";
                    break;

                case EventType.itemDrop:
                    verb = isPlayer ? "drop" : "drops";
                    break;

                case EventType.itemUse:
                    verb = (ev.msg != "") ? ev.msg :
                           isPlayer ? "activate" : "activates";
                    break;

                case EventType.itemEquip:
                    verb = (ev.msg != "") ? ev.msg :
                           isPlayer ? "equip" : "equips";
                    break;

                case EventType.itemUnequip:
                    verb = isPlayer ? "unequip" : "unequips";
                    break;

                case EventType.itemEat:
                    verb = isPlayer ? "eat" : "eats";
                    break;

                case EventType.itemReplenish:
                    return isPlayer ? format("You refill your %s.",
                                             objName.name) : "";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
            if (objName !is null)
                return format("%s %s the %s.", subjName.asCapitalized, verb,
                              objName.name);

            return "";
        }
        else if (ev.cat == EventCat.dmg)
        {
            auto isPlayer = (ev.subjId == player.id);
            auto subjName = w.store.get!Name(ev.subjId).name;
            auto objName = (ev.objId == player.id) ? "you" :
                           (ev.objId == invalidId) ? "" :
                           w.store.get!Name(ev.objId).name;
            auto possName = isPlayer ? "your" : "its";
            auto wpnName = w.store.get!Name(ev.obliqueId);
            string verb;

            switch (ev.type)
            {
                case EventType.dmgAttack:
                    auto wpn = w.store.get!Weapon(ev.obliqueId);
                    if (wpnName !is null)
                        return format("%s %s %s with %s %s!",
                                      subjName.asCapitalized, wpn.attackVerb,
                                      objName, possName, wpnName.name);
                    else
                        return format("%s %s %s!", subjName.asCapitalized,
                                      wpn.attackVerb, objName);
                    break;

                case EventType.dmgFallOn:
                    verb = isPlayer ? "fall" : "falls";
                    return format("%s %s on top of %s!",
                                  subjName.asCapitalized, verb, objName);

                case EventType.dmgKill:
                    import terrain : water;
                    if (ev.subjId == water.id)
                        return format("%s drowned!", objName.asCapitalized);
                    else
                        return format("%s killed %s!", subjName.asCapitalized,
                                      objName);

                case EventType.dmgBlock:
                    auto subjPoss = (ev.subjId == player.id) ? "your" :
                                    w.store.get!Name(ev.subjId).name ~ "'s";
                    auto armorName = w.store.get!Name(ev.obliqueId).name;
                    auto pronoun = (ev.subjId == player.id) ? "you" : "it";
                    return format("%s %s shields %s from the blow!",
                                  subjPoss.asCapitalized, armorName, pronoun);

                case EventType.dmgDrown:
                    return isPlayer ? "You're drowning!"
                                    : format("%s is drowning!",
                                             subjName.asCapitalized);

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
            assert(0);
        }
        else if (ev.cat == EventCat.mapChg)
        {
            auto isPlayer = (ev.subjId == player.id);
            auto subjName_ = w.store.get!Name(ev.subjId);
            string subjName = isPlayer ? "you" :
                              subjName_ ? subjName_.name : "";

            switch (ev.type)
            {
                case EventType.mchgRevealPitTrap:
                    if (subjName.length > 0)
                        return format("A trap door opens up under %s!",
                                      subjName);
                    else
                        return "A trap door opens up!";

                case EventType.mchgTrigRockTrap:
                    if (subjName.length > 0)
                        return format("A trap door opens up above %s and a "~
                                      "rock falls out!", subjName);
                    else
                        return "A trap door opens in the ceiling and a rock "~
                               "falls out!";
                    break;

                case EventType.mchgDoorOpen:
                    return "The door swings open!";

                case EventType.mchgDoorClose:
                    return "The door swings shut!";

                case EventType.mchgMessage:
                    return (isPlayer) ? ev.msg : "";

                case EventType.mchgSplashIn:
                    return isPlayer ? "Splash!" :
                            format("%s falls into the water with a splash!",
                                   subjName.asCapitalized);

                case EventType.mchgSplashOut:
                    return isPlayer ? "Splash!" :
                            format("%s splashes out of the water.",
                                   subjName.asCapitalized);

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
        }
        else if (ev.cat == EventCat.statChg)
        {
            auto isPlayer = (ev.subjId == player.id);
            auto subjName_ = w.store.get!Name(ev.subjId);
            string subjName = isPlayer ? "you" :
                              subjName_ ? subjName_.name : "";

            switch (ev.type)
            {
                case EventType.schgBreathHold:
                    return (isPlayer) ? "You hold your breath." : "";

                case EventType.schgBreathReplenish:
                    if (isPlayer)
                        return "You draw in a gulp of air!";
                    else
                        return format("%s gasps for air!",
                                      subjName.asCapitalized);

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
        }
        assert(0);
    }

    private string fmtAudibleEvent(Event ev)
    {
        if (ev.cat == EventCat.move)
        {
            switch (ev.type)
            {
                case EventType.moveWalk:
                case EventType.moveJump:
                case EventType.moveClimb:
                case EventType.moveClimbLedge1:
                case EventType.moveClimbLedge0:
                case EventType.moveFall:
                case EventType.moveFall2:
                case EventType.movePass:
                    return "";

                case EventType.moveSink:
                    return "You hear the sound of water.";

                case EventType.moveFallAside:
                    return "You hear a bump!";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
            assert(0);
        }
        else if (ev.cat == EventCat.itemAct)
        {
            switch (ev.type)
            {
                case EventType.itemPickup:
                case EventType.itemDrop:
                case EventType.itemUse:
                case EventType.itemEquip:
                case EventType.itemUnequip:
                case EventType.itemEat:
                case EventType.itemReplenish:
                    return "";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
            assert(0);
        }
        else if (ev.cat == EventCat.dmg)
        {
            switch (ev.type)
            {
                case EventType.dmgAttack:
                case EventType.dmgFallOn:
                    return "You hear some noises.";

                case EventType.dmgKill:
                    return "You hear a groan!";

                case EventType.dmgBlock:
                    return "";

                case EventType.dmgDrown:
                    return "You hear bubbles in water.";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
            assert(0);
        }
        else if (ev.cat == EventCat.mapChg)
        {
            switch (ev.type)
            {
                case EventType.mchgRevealPitTrap:
                case EventType.mchgTrigRockTrap:
                    return "You hear a creaking sound.";

                case EventType.mchgDoorOpen:
                    return "You hear a door open in the distance!";

                case EventType.mchgDoorClose:
                    return "You hear a door shut in the distance!";

                case EventType.mchgSplashIn:
                case EventType.mchgSplashOut:
                    return "You hear a splash.";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
        }
        else if (ev.cat == EventCat.statChg)
        {
            switch (ev.type)
            {
                case EventType.schgBreathHold:
                    return "";

                case EventType.schgBreathReplenish:
                    return "You hear gasping.";

                default:
                    assert(0, "Unhandled event type: %s"
                              .format(ev.type));
            }
        }
        assert(0);
    }

    private void setupEventWatchers()
    {
        w.events.listen((Event ev) {
            bool involvesPlayer = (ev.objId == player.id);
            bool seenByPlayer = canSee(w, playerPos, ev.where) || (
                                    ev.where != ev.whereTo &&
                                    canSee(w, playerPos, ev.whereTo));

            enum plHearRad = 20; // TBD: should be agent-dependent

            string msg;
            if (involvesPlayer || seenByPlayer)
                msg = fmtVisibleEvent(ev);
            else if (canHear(w, plHearRad, playerPos, ev.where) ||
                     canHear(w, plHearRad, playerPos, ev.whereTo))
                msg = fmtAudibleEvent(ev);

            if (msg.length > 0)
                ui.message(msg);

            // NOTE: the UI will insert animation pauses if ui.updateMap is
            // called more than once per UI main loop iteration. Too many calls
            // to it will cause jerkiness; so it should only be called for
            // important events for which we want an animation pause (e.g.,
            // monster movement, objects that fall on you, etc).
            if (ev.cat == EventCat.move)
            {
                if (ev.subjId == player.id)
                    ui.moveViewport(ev.whereTo);
                else
                    ui.updateMap(ev.where, ev.whereTo);
            }
            else if (ev.type == EventType.dmgFallOn)
                ui.updateMap(ev.where, ev.whereTo);

            if (ev.type == EventType.dmgKill && ev.objId == player.id)
            {
                quit = true;
                ui.quitWithMsg("YOU HAVE DIED.", genDeathScore(ev));
            }
        });
    }

    InventoryItem[] getApplyTargets()
    {
        return w.store.getAllBy!Pos(Pos(playerPos))
                      .filter!(id => w.store.get!Usable(id) !is null)
                      .map!(id => toInventoryItem(id))
                      .array;
    }

    InventoryItem[] getPickupTargets()
    {
        return w.store.getAllBy!Pos(Pos(playerPos))
                .filter!(id => w.store.get!Pickable(id) !is null)
                .map!(id => toInventoryItem(id))
                .array;
    }

    auto objectsOnFloor()
    {
        return w.store.getAllBy!Pos(Pos(playerPos))
                .filter!(id => id != player.id)
                .map!(id => w.store.getObj(id))
                .filter!(t => (t.systems & SysMask.name) != 0 &&
                              (t.systems & SysMask.tiled) != 0)
                .map!((Thing* t) => toInventoryItem(t.id));
    }

    private void observeSurroundings()
    {
        auto objs = objectsOnFloor().array;
        if (objs.empty)
            return;

        if (objs.length == 1)
            ui.message("You see %s here.", objs[0]);
        else if (objs.length == 2)
            ui.message("You see %s and %s here.", objs[0], objs[1]);
        else
            ui.message("There's a pile of things here.");
    }

    private Action processPlayer()
    {
        if (playerPos != lastObservePos)
        {
            observeSurroundings();
            lastObservePos = playerPos;
        }

        Action act;
        string errmsg;
        while (act is null)
        {
            auto pAct = ui.getPlayerAction();
            final switch (pAct.type) with(PlayerAction.Type)
            {
                case move:
                    act = movePlayer(dir2vec(pAct.dir), errmsg);
                    break;
                case pickup:
                    act = pickupObj(pAct.objId, errmsg);
                    break;
                case drop:
                    act = dropObj(pAct.objId, pAct.objCount, errmsg);
                    break;
                case applyItem:
                    act = applyObj(pAct.objId, errmsg);
                    break;
                case applyFloor:
                    act = applyFloorObj(pAct.objId, errmsg);
                    break;
                case pass:
                    act = (World w) => .pass(w, player);
                    break;
                case none:
                    assert(0, "Internal error");
            }

            if (act is null)
                ui.message(errmsg); // FIXME: should be ui.echo
        }

        if (act !is null)
            nTurns++;

        return act;
    }

    private void setupAgentImpls()
    {
        AgentImpl playerImpl;
        playerImpl.chooseAction = (World w, ThingId agentId)
        {
            return processPlayer();
        };
        playerImpl.notifyFailure = (World w, ThingId agentId,
                                    ActionResult result)
        {
            ui.message(result.failureMsg);
        };
        sysAgent.registerAgentImpl(Agent.Type.player, playerImpl);

        AgentImpl aiImpl;
        aiImpl.chooseAction = (w, agentId) => sysAi.chooseAiAction(w, agentId);
        sysAgent.registerAgentImpl(Agent.Type.ai, aiImpl);

        // Gravity system proxy for sinking objects over time.
        registerGravityObjs(&w.store, &sysAgent, &sysGravity);

        // Background agent that applies tile effects per turn.
        registerTileEffectAgent(&w.store, &sysAgent);
    }

    void run(GameUi _ui)
    {
        ui = _ui;

        if (w is null)
        {
            startStory();
        }
        else
        {
            setupEventWatchers();
            setupAgentImpls();

            ui.moveViewport(playerPos);
            ui.message("Welcome back!");

            // FIXME: shouldn't this be in the UI code instead??
            ui.message("Press '?' for help.");
        }

        while (!quit)
        {
            if (!sysAgent.run(w))
                quit = true;
            portalSystem();
            sysGravity.run(w);
        }
    }
}

struct StoryNode
{
    string[] infoScreen;
    World function(ref int[4] startPos) genMap;
}

StoryNode[] storyNodes = [
    StoryNode([
        "Welcome to Tetraworld Corp.!",

        "You have been hired as a 4D Treasure Hunter by our Field Operations "~
        "Department to explore 4D space and retrieve any treasure you find.",

        "As an initial orientation, you have been teleported to a training "~
        "area consisting of a single tunnel in 4D space. Your task is to "~
        "familiarize yourself with your 4D view, and to learn 4D movement by "~
        "following this tunnel to the far end where you will find an exit "~
        "portal.",

        "The exit portal will return you to Tetraworld Corp., where you will "~
        "receive your first assignment.",

        "Good luck!",
    ], (ref int[4] startPos) {
        return genTutorialLevel(startPos);
    }),

    StoryNode([
        "Excellent job!",

        "Now that you have learned how to move around in 4D space, you will "~
        "begin to learn how to perform your duties as a treasure hunter.",

        "Your next assigned area is one of the smaller cave systems that "~
        "Tetraworld Corp. has discovered in the course of its pioneering 4D "~
        "exploration.  This is a simple area with a number of caves that "~
        "have a branching structure.  You will need to explore the area "~
        "and retrieve all the gold ore. This assignment will also acquiant "~
        "you with navigating a non-linear maze in 4D.",

        "Once you have collected all the gold ore, locate the exit portal "~
        "and return."
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.tree.minNodeDim = 3;
        args.goldPct = 3.0;
        args.rockPct = 1.0;
        return genBspLevel(region(vec(7,7,7,7)), args, startPos);
    }),

    StoryNode([
        "Excellent!",

        "Now that you have learned the basics of 4D treasure-hunting, it is "~
        "time for your first non-trivial assignment.",

	    "Your task is to collect gold ore located in the ore mines. The area "~
        "you will be responsible for is highly branching, and may require "~
        "extra effort on your part to find all the ore that has been "~
        "detected there.  Furthermore, the caves may loop, so careful "~
        "thoroughness on your part will be required to ensure the successful "~
        "completion of your assignment.",

        "Good luck!"
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.nBackEdges = ValRange(3, 5);
        args.goldPct = 1.8;
        return genBspLevel(region(vec(8,8,8,8)), args, startPos);
    }),

    StoryNode([
        "Outstanding!",

        "The next area is similar to the previous one, and is also located "~
        "in the ore mines. It is slightly larger and more complex, and, "~
        "unfortunately, is also located in a more unstable zone, and there "~
        "may be environmental hazards, such as hidden pits and falling rocks.",

        "In particular, we advise you to avoid by all means any native "~
        "creatures that you might encounter, as they are likely to be "~
        "hostile, and your 4D environmental suit is not equipped for combat "~
        "and will not survive extensive damage.",

        "We trust in the timely and competent completion of this assignment. "~
        "Good luck!",
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.nBackEdges = ValRange(3, 5);
        args.nPitTraps = ValRange(8, 12);
        args.nRockTraps = ValRange(1, 4);
        args.goldPct = 1.0;
        args.nMonstersA = ValRange(2, 5);
        return genBspLevel(region(vec(9,9,9,9)), args, startPos);
    }),

    StoryNode([
        "We are very pleased with your continuing performance.",

        "The next area is a large one, and quite complex and hazardous. "~
        "You will probably have to take notes to keep track of your "~
        "location.  Furthermore, according to our records, it is likely to "~
        "be partially submerged. Therefore, great care must be taken when "~
        "traversing this hostile terrain.",

        "But we are confident that this will present no problem to your "~
        "current skills. Collect all the gold ores and bring them to the "~
        "exit portal.  You know the protocol.",

        "Good luck!",
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.nBackEdges = ValRange(5, 8);
        args.nPitTraps = ValRange(12, 18);
        args.nRockTraps = ValRange(6, 12);
        args.goldPct = 1.0;
        args.waterLevel = ValRange(5, 8);
        args.nMonstersA = ValRange(4, 6);
        args.nMonstersC = ValRange(0, 3);
        args.nScubas = ValRange(1, 2); // FIXME: for testing only
        return genBspLevel(region(vec(10,10,10,10)), args, startPos);
    }),

    StoryNode([
        "Exceptional!",

        "We have a special mission for you.  One of our remote storage "~
        "facilities has been badly damaged by instabilities and infested "~
        "with hostile creatures.  We need you to enter the complex and "~
        "retrieve all the ores we have stored there from a prior mission.",

        "Unfortunately, due to equipment damage, we are unable to transport "~
        "you into the facility itself, but only to a nearby area.  The "~
        "entrance is locked, but may be opened by an emergency access lever "~
        "located nearby. Once inside, beware of structural damage and "~
        "unstable ceilings.",

        "Be careful!",
    ], (ref int[4] startPos) {
        BipartiteGenArgs args;
        args.region = region(vec(11,11,11,11));
        args.axis = ValRange(1, 4);
        args.pivot = ValRange(5, 7);

        args.subargs[0].nBackEdges = ValRange(3, 5);
        args.subargs[0].nPitTraps = ValRange(0, 4);
        args.subargs[0].nRockTraps = ValRange(1, 3);
        args.subargs[0].nMonstersA = ValRange(1, 2);
        args.subargs[0].nMonstersC = ValRange(1, 2);
        args.subargs[0].sharpRockPct = 7.0;

        args.subargs[1].tree.splitVolume = ValRange(64, 120);
        args.subargs[1].tree.minNodeDim = 4;
        args.subargs[1].nBackEdges = ValRange(1, 3);
        args.subargs[1].nPitTraps = ValRange(5, 10);
        args.subargs[1].nRockTraps = ValRange(15, 20);
        args.subargs[1].goldPct = 4.0;
        args.subargs[1].nMonstersA = ValRange(4, 6);
        args.subargs[1].sharpRockPct = 15.0;

        int[4] doorPos;
        Region!(int,4) bounds1, bounds2;
        auto w = genBipartiteLevel(args, startPos, doorPos, bounds1, bounds2);

        genDoorAndLever(w, doorPos, w.map.tree.left, bounds1);
        return w;
    }),

    StoryNode([
        "Something is wrong.",

        "As you step out of the portal, expecting to be back in Tetraworld "~
        "Corp, you find yourself instead in a strange new location, with no "~
        "indication as to what happened.  With a sudden loud, sizzling "~
        "noise, the portal behind you vibrates violently and then explodes "~
        "with a deafening pop.",

        "When you recover from the shock, there is no trace left of the "~
        "portal, nor any indication of any instructions or communications "~
        "from Tetraworld Corp.  It seems that you are now stranded in an "~
        "unknown 4D location, and you have to somehow find a way to survive "~
        "long enough to find out what happened, and, hopefully, find a way "~
        "out of here.",

        "As you take your first steps forward, you hear faint echoes of "~
        "unfriendly noises wafting from the distance.  This area seems even "~
        "vaster than the one you have just been to, and fraught with new, "~
        "unknown dangers. You will have to use every wit at your disposal to "~
        "survive in this unfriendly terrain.",

        "You brace yourself and prepare for the worst."
    ], (ref int[4] startPos) {
        MapGenArgs args;
        args.nBackEdges = ValRange(200, 300);
        args.nPitTraps = ValRange(175, 250);
        args.nRockTraps = ValRange(150, 250);
        args.goldPct = 0.8;
        args.waterLevel = ValRange(12, 15);
        args.nMonstersA = ValRange(25, 40);
        args.nMonstersC = ValRange(12, 20);
        args.nScubas = ValRange(1, 2);
        return genBspLevel(region(vec(20,20,20,20)), args, startPos);
    }),
];

// vim:set ai sw=4 ts=4 et:
