/**
 * Game objects
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

import std.conv;
import std.stdio;
import std.traits;

import io;
import quad;


/**
 * Base class of game world objects.
 * Note that game world objects are auto-serialized; members that should be NOT
 * be serialized should be prefixed with an underscore.
 */
class GameObj {
	mixin(Serializable!());

	quad loc;
	string name = "";
}

class Item : GameObj {
	mixin(Serializable!());

	int count = 1;
}

class Decoration : GameObj {
	mixin(Serializable!());

	bool blocking = false;
	this() {
		name = "furniture";
	}
}

class Portal : GameObj {
	string dest;
}


/*
 * Template to insert serialization stuff into a class.
 */
template Serializable() {
	enum Serializable = q{
		static if (__traits(hasMember, typeof(this), "serialize")) {
			override void serialize(DataSink dest) {
				__serialize(this, dest);
			}
			override void deserialize(DataSource src) {
				__deserialize(src, this);
			}
		} else {
			void serialize(DataSink dest) {
				__serialize(this, dest);
			}
			void deserialize(DataSource src) {
				__deserialize(src, this);
			}
			static GameObj deserialize(DataSource src) {
				assert(false);
			}
		}
	};
}

/*
 * Generic object serialization function
 */
private void __serialize(T)(in T obj, DataSink dest) {
	dest.writefln("%s {", typeid(obj));
	foreach (name; __traits(allMembers, T)) {
		static if (__traits(compiles, &__traits(getMember, obj,
							name)))
		{
			alias typeof(__traits(getMember, obj, name))
				type;
			static if (!is(type==function))
			{
				auto val = __traits(getMember, obj, name);
				static if (is(type : const(char)[])) {
					dest.writefln("\t%s = \"%s\"", name,
						val);
				} else {
					dest.writefln("\t%s = %s", name,
						to!string(val));
				}
			}
		}
	}
	dest.writefln("}");
}

/*
 * Generic object deserialization function
 */
private void __deserialize(T)(DataSource src, T obj) {
}

unittest {
	GameObj[] objs;
	objs ~= new Item;
	objs ~= new Decoration;
	objs ~= new Portal;

	auto output = new StringSink;

	foreach (obj; objs) {
		obj.serialize(output);
	}

	write(output.data);
}
