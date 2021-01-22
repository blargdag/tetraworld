Tetraworld: a 4D roguelike game
===============================

Check out the [official website](http://eusebeia.dyndns.org/tetraworld) for
screenshots, news, pre-built binaries, and other information.

You should already have a copy of the source code; if not, you may get it from
the [official Github repository](http://github.com/blargdag/tetraworld).


Build requirements
------------------

* [LDC](https://github.com/ldc-developers/ldc/releases)
* [SCons](http://www.scons.org/)
* [arsd library](https://github.com/adamdruppe/arsd)


Building
--------

Currently builds are only tested on Linux.  Patches are welcome to extend
support to other platforms.  Cross-compilation to Windows is available if your
LDC installation is setup for it.

Edit SConstruct, search for the line:

	ldc = '/usr/src/d/ldc/latest/bin/ldc2'

and set it to point to your installation of LDC.

To build only the game executable:

	scons tetraworld

To build the entire project:

	scons

Note that you will need to setup LDC for cross-compilation to Windows if you
want to do this.

For slightly faster turnaround during development:

	scons debug=1 tetraworld


Installation
------------

Currently, there are no external assets, so all you need is to run the program
directly.  This may change in the future.

There are some command-line options; run the program with `-h` to see a list.

Your progress is automatically saved when you exit the program, and reloaded
when you run the program again.  If your character dies, you will have to start
over from scratch.  There is no reloading from an earlier game state.  Death is
permanent.


Bugs
----

Report all bugs via email to blargdag@quickfur.ath.cx, or file issues on
Github.


Contributing
------------

You are welcome to submit patches or pull requests on Github.  Please use the
same coding style as the existing code as much as possible.

Be aware that the current code is in a state of flux, and may undergo drastic
changes without warning.


License
-------

All the code and data included with this distribution are distributed under the
terms of the GNU Public License version 2 (GPL2).  The arsd library referenced
as a submodule is licensed under the Boost license.

