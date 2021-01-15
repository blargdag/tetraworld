/**
 * Loading/saving module.
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
module loadsave;

import std.conv : to;
import std.format : format, formattedWrite;
import std.range.primitives;
import std.range.interfaces;
import std.stdio;
import std.typecons : Tuple;

/**
 * The current savegame major/minor version.
 */
enum curVerMaj = 1;
enum curVerMin = 0;
enum curVer = curVerMaj*1000 | curVerMin;

/**
 * Check whether the given type conforms to the SaveFile interface.
 */
enum isSaveFile(T) = is(typeof(T.init.push(""))) &&
                     is(typeof(T.init.put("", ""))) &&
                     is(typeof(T.init.pop()));

/**
 * UDA to skip fields that we don't want to serialize in the savegame file.
 */
struct NoSave {}

/**
 * UDA to mark an enum as an OR-able set of bit flags.
 */
struct BitFlags {}

/**
 * UDA to mark structs that should be saved by conversion to a string via
 * std.conv.to!string, and loaded by passing a string to the constructor.
 *
 * BUGS: Currently this only works for structs.
 */
struct TreatAsString {}

/**
 * UDA to specify a filter on which entries of an aggregate should be saved,
 * and which should be skipped.
 *
 * Currently, only AA filtering is supported.
 *
 * Params:
 *  _filter = A function that takes an AA key and returns true if it should be
 *      included in the save file, false otherwise.
 *
 * Limitations:
 *
 * Currently, only one SaveFilter is supported per AA, and it must be attached
 * to the AA's value type, which must be a struct, not a basic type.
 */
struct SaveFilter(alias _filter)
{
    alias filter = _filter;
}

private void saveClassFields(T,S)(T value, S savefile)
    if (is(T == class) && isSaveFile!S)
{
    import std.meta : AliasSeq;
    import std.traits : BaseClassesTuple, FieldNameTuple, hasUDA;

    static foreach (B; AliasSeq!(BaseClassesTuple!T, T))
    {
        foreach (field; FieldNameTuple!B)
        {
            static if (!hasUDA!(__traits(getMember, value, field), NoSave))
            {
                alias F = typeof(__traits(getMember, value, field));
                static if (is(F == class))
                    bool cond = __traits(getMember, value, field) !is null;
                else
                    bool cond = __traits(getMember, value, field) != F.init;

                if (cond)
                    savefile.put(field, __traits(getMember, value, field));
            }
        }
    }
}

/**
 * Write handle to a savegame file.
 */
struct SaveFile
{
    private OutputRange!(const(char)[]) sink;
    private int indentLvl = 0;

    this(R)(R _sink)
        if (isOutputRange!(R, dchar))
    {
        sink = outputRangeObject!(const(char)[])(_sink);
    }

    private auto indent()
    {
        import std.range : replicate;
        return " ".replicate(indentLvl);
    }

    /**
     * Start a nested block in the save file.
     */
    void push(string blockName)
    {
        sink.formattedWrite("%s%s {\n", indent, blockName);
        indentLvl++;
    }

    /**
     * Store a key-value pair in the save file.
     *
     * Warning: Only classes with default ctors are supported. For recursive
     * class types, be sure that there are no cyclic references (e.g., N
     * classes that refer to each other in a cycle), otherwise this function
     * will get stuck in an infinite loop. Use @NoSave and a custom .save
     * function instead to handle such cases.
     */
    void put(T)(string key, T value)
    {
        import std.traits : hasMember, hasUDA, getUDAs;

        static if (isInputRange!T && !is(ElementType!T == dchar))
        {
            import std.traits : isAggregateType;
            alias U = ElementType!T;
            static if (!isAggregateType!U && !is(U == V[], V))
            {
                sink.formattedWrite("%s%s [ %(%s %) ]\n", indent, key, value);
            }
            else
            {
                this.push(key);
                size_t idx = 0;
                foreach (elem; value)
                {
                    this.put(idx.to!string, elem);
                    idx++;
                }
                this.pop();
            }
        }
        else static if (is(T == struct) && hasUDA!(T, TreatAsString))
        {
            sink.formattedWrite("%s%s %s\n", indent, key, value.to!string);
        }
        else static if (is(T == struct))
        {
            this.push(key);

            static if (hasMember!(T, "save"))
            {
                value.save(this);
            }
            else
            {
                import std.traits : FieldNameTuple;

                T defVal = T.init;

                foreach (field; FieldNameTuple!T)
                {
                    static if (!hasUDA!(__traits(getMember, value, field), NoSave))
                    {
                        if (__traits(getMember, value, field) !=
                            __traits(getMember, defVal, field))
                        {
                            this.put(field, __traits(getMember, value, field));
                        }
                    }
                }
            }

            this.pop();
        }
        else static if (is(T == class))
        {
            // Classes need extra care, because we need to extract base class
            // fields, and also need to skip nulls for recursive classes like
            // tree nodes. Since there is currently no way to extract the
            // default value of class fields, unlike structs we resort to the
            // default value for the field type instead.
            this.push(key);

            static if (hasMember!(T, "save"))
            {
                value.save(this);
            }
            else
            {
                saveClassFields(value, this);
            }

            this.pop();
        }
        else static if (is(T == V[K], V, K))
        {
            this.push(key);
            foreach (p; value.byKeyValue)
            {
                static if (is(V == struct) && hasUDA!(V, SaveFilter))
                {
                    alias uda = getUDAs!(V, SaveFilter)[0];
                    if (!uda.filter(p.key))
                        continue;
                }
                this.put(p.key.to!string, p.value);
            }
            this.pop();
        }
        else static if (is(T == enum) && hasUDA!(T, BitFlags))
        {
            import std.traits : EnumMembers, hasUDA;
            if (value != 0)
            {
                sink.formattedWrite("%s%s", indent, key);
                alias Bits = EnumMembers!T;
                static foreach (i; 0 .. Bits.length)
                {
                    if (value & Bits[i])
                        sink.formattedWrite(" %s",
                            __traits(identifier, Bits[i]));
                }
                .put(sink, "\n");
            }
        }
        else static if (is(T == U*, U))
            static assert(0, "Cannot serialize pointers");
        else
            sink.formattedWrite("%s%s %s\n", indent, key, value);
    }

    /**
     * End a nested block in the save file.
     */
    void pop()
        in (indentLvl > 0)
    {
        indentLvl--;
        sink.formattedWrite("%s}\n", indent);
    }
}

/// ditto
auto saveFile(R)(R sink)
    if (isOutputRange!(R, dchar))
{
    auto sf = SaveFile(sink);
    sf.put("version", curVer);
    return sf;
}

/**
 * Exception thrown when loading a savegame file.
 *
 * Usually indicates savegame file is incompatible or otherwise corrupt.
 */
class LoadException : Exception
{
    this(Args...)(string fmt, Args args,
                  string file = __FILE__, size_t line = __LINE__)
    {
        super(fmt.format(args), file, line);
    }
}

/**
 * Checks whether the given type implements the LoadFile interface.
 */
enum isLoadFile(T) = is(typeof(T.init.empty) : bool) &&
                     is(typeof(T.init.checkAndEnterBlock("")) : bool) &&
                     is(typeof(T.init.checkAndLeaveBlock()) : bool) &&
                     is(typeof(T.init.parse!int("")) : int) &&
                     is(typeof(T.init.parse!(int[])("")) : int[]) &&
                     is(typeof(T.init.parse!(int[string])("")) : int[string]) &&
                     is(typeof(T.init.parse!string("")) : string);

/**
 * Dynamically-populated polymorphic class object loaders.
 */
private alias ClassLoader = Object function(ref LoadFile, const(char)[] key);
private ClassLoader[string] loaders;

private void loadClassFields(T,L)(T result, ref L loadfile, const(char)[] key)
    if (is(T == class) && isLoadFile!L)
{
    while (!loadfile.checkAndLeaveBlock())
    {
        import std.meta : AliasSeq;
        import std.traits : BaseClassesTuple, FieldNameTuple, hasUDA;

        if (loadfile.empty)
            throw new LoadException("Expecting end of block "~ "(%s), got EOF",
                                    key);
        SW: switch (loadfile.curKey)
        {
            static foreach (B; AliasSeq!(BaseClassesTuple!T, T))
            {
                static foreach (field; FieldNameTuple!B)
                {
                    static if (!hasUDA!(__traits(getMember, result, field),
                                        NoSave))
                    {
                        case field:
                            alias U = typeof(__traits(getMember, result,
                                                      field));
                            __traits(getMember, result, field) =
                                loadfile.parse!U(field);
                            break SW;
                    }
                }
            }

            default:
                // TBD: warn of unknown fields (probably removed from an older
                // version)?
                loadfile.parseNext();
                break SW;
        }
    }
}

/**
 * Read handle to a savegame file.
 */
struct LoadFile
{
    private InputRange!(const(char)[]) src;
    private const(char)[] curKey, curVal;

    bool empty = true;

    this(R)(R _src)
        if (isInputRange!R && is(ElementType!R : const(char)[]))
    {
        import std.algorithm : map;
        src = inputRangeObject(_src.map!(l => cast(const(char)[]) l));
        parseCur();
    }

    private void parseNext()
        in (!src.empty)
    {
        src.popFront();
        empty = src.empty;
        if (!empty)
            parseCur();
    }

    private void parseCur()
    {
        import std.algorithm : startsWith;
        import std.string : indexOf;

        const(char)[] line = src.front;
        while (line.startsWith(' '))
            line = line[1 .. $];

        auto keyEnd = line.indexOf(' ');
        if (keyEnd == -1)
            keyEnd = line.length;

        curKey = line[0 .. keyEnd];
        if (keyEnd + 1 >= line.length)
            curVal = [];
        else
            curVal = line[keyEnd+1 .. $];
    }

    /**
     * Check whether the current point in the savegame file is a block with the
     * given identifier, and enter it (consume the opening marker) if so.
     */
    bool checkAndEnterBlock(const(char)[] key)
    {
        if (curKey != key || curVal != "{")
            return false;
        parseNext();
        return true;
    }

    /**
     * Checks that the current point in the savegame file is the end of a
     * block, and leave it (consume the end marker) if so.
     */
    bool checkAndLeaveBlock()
    {
        if (curKey != "}" || curVal != "")
            return false;
        parseNext();
        return true;
    }

    /**
     * Returns: The current key in the load file to be processed.
     */
    const(char)[] currentKey() { return curKey; }

    /**
     * Parse a value or block of the given type from the current point in the
     * savegame file.
     *
     * To get the raw value for custom processing, just use parse!string.
     *
     * Throws: LoadException, if the current key doesn't match the expected
     * key.
     */
    T parse(T)(const(char)[] key)
    {
        if (curKey != key)
            throw new LoadException("Expecting '%s', got '%s'", key, curKey);

        import std.traits : hasMember, hasUDA;

        static if (is(T == U[], U) && !is(ElementType!T == dchar))
        {
            if (checkAndEnterBlock(key))
            {
                T result;
                size_t i = 0;
                while (!checkAndLeaveBlock())
                {
                    result ~= parse!U(i.to!string);
                    i++;
                }

                return result;
            }

            // Not a block; try to parse the array as the compact form.
            // Note that compact forms are only supported for non-aggregate
            // item types.
            import std.traits : isAggregateType;
            import std.algorithm : startsWith, endsWith, splitter, map;
            import std.array : array;
            import std.string : strip;

            static if (!isAggregateType!U)
            {
                if (!curVal.startsWith("[ ") || !curVal.endsWith(" ]"))
                    throw new LoadException("Expecting array, got: %s", curVal);

                T result = curVal[2 .. $-2]
                           .splitter(' ')
                           .map!(v => v.strip.to!U)
                           .array;
                parseNext();
                return result;
            }
            else
            {
                throw new LoadException("Expecting array block, got %s",
                                        curVal);
            }
        }
        else static if (is(T == struct) && hasUDA!(T, TreatAsString))
        {
            auto result = T(curVal.to!string);
            parseNext();
            return result;
        }
        else static if (is(T == struct))
        {
            if (!checkAndEnterBlock(key))
                throw new LoadException("Expecting block '%s', got '%s %s'",
                                        key, curKey, curVal);

            T result;

            static if (hasMember!(T, "load"))
            {
                result.load(this);

                if (!checkAndLeaveBlock())
                    throw new LoadException("Unclosed block '%s', got '%s %s'",
                                            key, curKey, curVal);
            }
            else
            {
                while (!checkAndLeaveBlock())
                {
                    import std.traits : FieldNameTuple;

                    if (empty)
                        throw new LoadException("Expecting end of block (%s), "~
                                                "got EOF", key);
                    SW: switch (curKey)
                    {
                        static foreach (field; FieldNameTuple!T)
                        {
                            static if (!hasUDA!(__traits(getMember, result, field),
                                                NoSave))
                            {
                                case field:
                                    alias U = typeof(__traits(getMember, result,
                                                              field));
                                    __traits(getMember, result, field) =
                                        parse!U(field);
                                    break SW;
                            }
                        }

                        default:
                            // TBD: warn of unknown fields (probably removed from
                            // an older version)?
                            parseNext();
                            break SW;
                    }
                }
            }

            return result;
        }
        else static if (is(T == class))
        {
            if (!checkAndEnterBlock(key))
                throw new LoadException("Expecting block '%s', got '%s %s'",
                                        key, curKey, curVal);

            if (curKey == "@type")
            {
                auto loader = curVal in loaders;
                if (loader is null)
                    throw new LoadException("Unknown polymorphic type '%s'",
                                            curVal);
                parseNext();
                return cast(T)((*loader)(this, key));
            }

            auto result = new T;

            static if (hasMember!(T, "load"))
            {
                result.load(this);

                if (!checkAndLeaveBlock())
                    throw new LoadException("Unclosed block '%s', got '%s %s'",
                                            key, curKey, curVal);
            }
            else
            {
                loadClassFields(result, this, key);
            }

            return result;
        }
        else static if (is(T == V[K], V, K))
        {
            if (!checkAndEnterBlock(key))
                throw new LoadException("Expecting block '%s', got '%s %s'",
                                        key, curKey, curVal);
            T result;
            while (!checkAndLeaveBlock())
            {
                if (empty)
                    throw new LoadException("Expecting end of block (%s), "~
                                            "got EOF", key);

                auto k = curKey.to!K;
                result[k] = parse!V(curKey);
            }

            return result;
        }
        else static if (is(T == enum) && hasUDA!(T, BitFlags))
        {
            import std.algorithm : splitter;
            import std.traits : EnumMembers;

            auto result = cast(T) 0;
            foreach (id; curVal.splitter(" "))
            {
                SW: switch (id)
                {
                    alias Bits = EnumMembers!T;
                    static foreach (i; 0 .. Bits.length)
                    {
                        case __traits(identifier, Bits[i]):
                            result |= Bits[i];
                            break SW;
                    }

                    default:
                        // TBD: should ignore for backward compat?
                        throw new LoadException("Invalid bitflag: %s", id);
                }
            }
            parseNext();
            return result;
        }
        else static if (is(T == U*, U))
            static assert(0, "Cannot deserialize pointers");
        else
        {
            // POD, just convert it directly.
            auto result = curVal.to!T;
            parseNext();
            return result;
        }
    }
}

/// ditto
auto loadFile(R)(R src)
    if (isInputRange!R && is(ElementType!R : const(char)[]))
{
    auto lf = LoadFile(src);
    static assert(isLoadFile!(typeof(lf)));

    auto ver = lf.parse!int("version");
    auto vermaj = ver / 1000;
    auto vermin = ver % 1000;

    if (vermaj != curVerMaj)
        throw new LoadException("Save file version (%d) is incompatible with "~
                                "current version (%d)", ver, curVer);

    return lf;
}

unittest
{
    auto lf = LoadFile([
        "key1 val",
        "key2 ",
        "key3"
    ]);

    assert(lf.curKey == "key1");
    assert(lf.curVal == "val");

    lf.parseNext();
    assert(lf.curKey == "key2");
    assert(lf.curVal == "");

    lf.parseNext();
    assert(lf.curKey == "key3");
    assert(lf.curVal == "");
}

unittest
{
    import std.exception : assertThrown, assertNotThrown;

    assertThrown!LoadException(loadFile([
        "key1 val",
        "key2 ",
        "key3"
    ]));

    assertThrown!LoadException(loadFile([
        "version 0001",
        "key2 ",
        "key3"
    ]));

    assertThrown!LoadException(loadFile([
        "version 2003",
        "key2 ",
        "key3"
    ]));

    assertNotThrown!LoadException(loadFile([
        "version 1591",
        "key2 ",
        "key3"
    ]));

    auto lf = loadFile([
        "version 1591",
        "key1 val",
        "key2 123"
    ]);

    assert(!lf.empty);
    assert(lf.parse!string("key1") == "val");
    assert(lf.parse!int("key2") == 123);
}

unittest
{
    auto lf = loadFile([
        "version 1591",
        "block {",
        "abc 123",
        "}"
    ]);

    assert(lf.checkAndEnterBlock("block"));
    assert(!lf.checkAndEnterBlock("klob"));
    assert(!lf.checkAndEnterBlock("abc"));
    assert(lf.parse!int("abc") == 123);
    assert(lf.checkAndLeaveBlock());
    assert(lf.empty);
}

unittest
{
    struct Data
    {
        int x, y;
        string name;
    }

    struct HasSkip
    {
        int x;
        @NoSave int y; // this should not be set even if present in save file
        string name;
    }

    auto lf = loadFile([
        "version 1591",
        "data {",
        " x 123",
        " y 321",
        " name abc",
        "}",
        "has_skip {",
        " x 123",
        " y 321",
        " name abc",
        "}",
    ]);

    assert(lf.parse!Data("data") == Data(123, 321, "abc"));
    assert(lf.parse!HasSkip("has_skip") == HasSkip(123, 0, "abc"));
    assert(lf.empty);
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "table {",
        " 123 abc",
        " 321 def",
        "}",
    ]);

    assert(lf.parse!(string[int])("table") == [
        123: "abc",
        321: "def"
    ]);
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "table {",
        " 0 abc",
        " 1 def",
        " 2 ghi",
        "}",
        "unsorted {",
        " 0 abc",
        " 2 ghi",
        " 1 def",
        "}",
    ]);

    assert(lf.parse!(string[])("table") == [ "abc", "def", "ghi" ]);

    import std.exception : assertThrown;
    assertThrown!LoadException(lf.parse!(string[])("unsorted"));
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "invalid {",
        " 0 abc",
        " 1 ghi",
        " z def", // invalid array index
        "}",
    ]);

    import std.exception : assertThrown;
    assertThrown!Exception(lf.parse!(string[])("invalid"));
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "shortform [ 1 2 3 ]",
        "shortform [ a b c ]",
    ]);

    assert(lf.parse!(int[])("shortform") == [ 1, 2, 3 ]);
    assert(lf.parse!(string[])("shortform") == [ "a", "b", "c" ]);
}

// Roundtrip tests
unittest
{
    struct Item
    {
        int x, y;
    }
    struct Nested
    {
        Item it;
        int i;
    }
    @BitFlags enum Flags
    {
        abc = 1,
        def = 2,
    }
    struct Data
    {
        string name;
        int[] numbers;
        Item[] items;
        int[string] aa;
        Item[int] bb;
        Nested[] nests;
        Flags flags;
    }

    auto data = Data(
        "myname",
        [ 1, 2, 3 ],
        [ Item(1, 2), Item(3, 4) ],
        [ "a": 123, "b": 456 ],
        [ 100: Item(5, 6), 101: Item(7, 8) ],
        [ Nested(Item(9, 10), 123), Nested(Item(11, 12), 321) ],
        Flags.abc | Flags.def
    );

    import std.algorithm : splitter;
    import std.array : appender;

    auto app = appender!string;
    auto sf = saveFile(app);
    sf.put("data", data);

    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto data2 = lf.parse!Data("data");
    assert(data2 == data);
}

unittest
{
    auto lf = loadFile([
        "version 1000",
        "empty [  ]",
    ]);
    assert(lf.parse!(int[])("empty") == []);
}

unittest
{
    @SaveFilter!(k => k < 100)
    struct Data
    {
        string str;
    }
    Data[int] aa = [
        10: Data("abc"),
        100: Data("def"),
        110: Data("ghi"),
    ];

    import std.array : appender;
    auto app = appender!string;
    auto sf = saveFile(app);

    sf.put("data", aa);

    assert(app.data ==
        "version 1000\n"~
        "data {\n"~
        " 10 {\n"~
        "  str abc\n"~
        " }\n"~
        "}\n"
    );
}

// Test classes
unittest
{
    static class Base(D)
    {
        int x;
        float y;
        D next;
    }
    static class Derived : Base!Derived
    {
        string str;
    }

    auto d = new Derived;
    d.x = 1;
    d.y = 2.0;
    d.str = "abc";
    d.next = new Derived;
    d.next.x = 2;
    d.next.y = 3.0;
    d.next.str = "def";

    import std.array : appender;
    auto app = appender!string;
    auto sf = saveFile(app);

    sf.put("obj", d);

    assert(app.data == 
        "version 1000\n"~
        "obj {\n"~
        " x 1\n"~
        " y 2\n"~
        " next {\n"~
        "  x 2\n"~
        "  y 3\n"~
        "  str def\n"~
        " }\n"~
        " str abc\n"~
        "}\n"
    );

    import std.algorithm : splitter;
    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto d2 = lf.parse!Derived("obj");

    assert(d2.x == d.x);
    assert(d2.y == d.y);
    assert(d2.str == d.str);
    assert(d2.next.x == d.next.x);
    assert(d2.next.y == d.next.y);
    assert(d2.next.str == d.next.str);
}

// Test static arrays
unittest
{
    static struct S
    {
        int[4] x;
    }
    auto data = S([ 1, 2, 3, 4 ]);

    import std.array : appender;
    auto app = appender!string;
    auto sf = saveFile(app);

    sf.put("data", data);

    import std.algorithm : splitter;
    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto data2 = lf.parse!S("data");

    assert(data == data2);
}

// Test @TreatAsString
unittest
{
    static struct S { int x; }

    @TreatAsString static struct T
    {
        int x;
        this(string s) { x = s.to!int - 100; }
        void toString(R)(R sink) { put(sink, (x + 100).to!string); }
    }

    static struct U
    {
        S s;
        T t;
    }

    import std.array : appender;
    auto app = appender!string;
    auto sf = saveFile(app);

    U u;
    sf.put("data", u);

    import std.algorithm : splitter;
    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto u2 = lf.parse!U("data");

    assert(u == u2);
}

/**
 * Polymorphic derived class wrapper for automatic class save/load support.
 *
 * Derive your classes from this class using CRTC to get automatic polymorphic
 * load/save support. The top of your hierarchy should derive from
 * Saveable!Object; which will inject the top-level save/load methods. Derived
 * classes will get override methods instead.
 *
 * Since template functions cannot be overloaded, we standardize on SaveFile
 * instantiated with Phobos' OutputRange interface to provide a fixed runtime
 * API for overloading.
 *
 * Params:
 *  Derived = The derived class.
 *  Base = The base class to derive from.
 *
 * Limitations: Only classes with no constructors or default constructors are
 * supported.  Furthermore, only public data fields are supported; objects with
 * private fields or members that require special construction (e.g., custom
 * getters/setters) may not work correctly.
 */
class Saveable(Derived, Base = Object) : Base
{
    static if (is(Base == Object))
    {
        void save(ref SaveFile savefile)
        {
            saveImpl(savefile);
        }
    }
    else
    {
        override void save(ref SaveFile savefile)
        {
            saveImpl(savefile);
        }
    }

    private void saveImpl(ref SaveFile savefile)
    {
        savefile.put("@type", Derived.stringof);
        saveClassFields(cast(Derived) this, savefile);
    }

    static this()
    {
        loaders[Derived.stringof] = (ref LoadFile loadfile, const(char)[] key)
        {
            auto obj = new Derived;
            loadClassFields(obj, loadfile, key);
            return obj;
        };
    }
}

unittest
{
    static class Base : Saveable!Base
    {
        int x;
    }

    static class Derived1 : Saveable!(Derived1, Base)
    {
        int y;
        this() { x = 1; }
    }

    static class Derived2 : Saveable!(Derived2, Base)
    {
        string z;
        this() { x = 2; }
    }

    struct Data
    {
        Base obj1;
        Base obj2;
    }

    auto d1 = new Derived1;
    d1.y = 123;

    auto d2 = new Derived2;
    d2.z = "abc";

    Data data;
    data.obj1 = d1;
    data.obj2 = d2;

    import std.array : appender;
    import std.algorithm : splitter;

    auto app = appender!string;
    auto sf = saveFile(app);

    sf.put("data", data);

    auto saved = app.data;
    auto lf = loadFile(saved.splitter("\n"));
    auto data2 = lf.parse!Data("data");

    auto f1 = cast(Derived1) data2.obj1;
    assert(f1 !is null && f1.y == 123);

    auto f2 = cast(Derived2) data2.obj2;
    assert(f2 !is null && f2.z == "abc");
}

// vim: set ts=4 sw=4 et ai:
