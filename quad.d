/**
 * 4D vector representations
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

import std.algorithm;
import std.string;

version(unittest) {
	import std.stdio;
}

/**
 * A 4D vector.
 */
struct quad {
	short[4] x;
	alias x this;

	unittest {
		quad q;
		q = [1,2,3,4];
		q[2] = 4;
		assert(q == quad(1,2,4,4));
	}

	this(short[4] args...) {
		x[] = args[];
	}

	/**
	 * Returns: volume of the hypercube with dimensions $(D this).
	 */
	@property const long volume() {
		return reduce!"a * b"(x);
	}

	unittest {
		assert(quad(2,3,4,5).volume == 2*3*4*5);
	}

	/**
	 * Computes the offset of $(D this) from the beginning of a row-major
	 * array of dimensions $(D bounds).
	 */
	const long offsetInto(quad bounds)
	in {
		for (auto i=0; i < x.length; i++) {
			assert(x[i] >= 0 && x[i] < bounds[i]);
		}
	} out(result) {
		assert(result >= 0 && result < bounds.volume);
	} body {
		alias bounds b;
		return ((x[0]*b[2] + x[1])*b[1] + x[2])*b[0] + x[3];
	}

	unittest {
		auto q = quad(1,2,3,4);
		assert(q.offsetInto(quad(5,5,5,5)) == 1*125 + 2*25 + 3*5 + 4);
	}

	/**
	 * Given an offset from the beginning of a row-major array of
	 * dimensions $(D this), returns the corresponding vector location.
	 */
	const quad locationOf(long offset)
	in {
		assert(offset >= 0 && offset < this.volume);
	} out(result) {
		for (auto i=0; i < this.length; i++) {
			assert(result[i] >= 0 && result[i] < this[i]);
		}
	} body {
		return quad(
			cast(short)(offset / x[0] / x[1] / x[2]),
			cast(short)((offset / x[0] / x[1]) % x[2]),
			cast(short)((offset / x[0]) % x[1]),
			cast(short)(offset % x[0])
		);
	}

	unittest {
		assert(quad(3,3,3,3).locationOf(80) == quad(2,2,2,2));

		quad q = [5,5,5,5];
		quad r = [4,3,2,1];
		assert(q.locationOf(r.offsetInto(q)) == r);
	}

	/**
	 * Returns the string representation of $(D this).
	 */
	const string toString() {
		return "<%d,%d,%d,%d>".format(x[0], x[1], x[2], x[3]);
	}
}
