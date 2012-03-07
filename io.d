/+
 + Generic I/O wrappers
 +/

import std.array;
import std.stdio;
import std.string;

class DataSource {
}

class DataSink {
	void writef(T...)(string fmt, T args) {
		put(fmt.format(args));
	}
	void writefln(T...)(string fmt, T args) {
		writef(fmt, args);
		put("\n");
	}
	abstract void put(string data);
}

class StdoutSink : DataSink {
	override void put(string data) {
		write(data);
	}
}

class NullSink : DataSink {
	override void put(string data) {}
}

class StringSink : DataSink {
	private Appender!string buf;

	this() {
		buf = appender!string();
	}

	override void put(string data) {
		buf.put(data);
	}

	string data() {
		return buf.data;
	}
}
