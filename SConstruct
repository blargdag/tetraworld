#!/usr/bin/scons

debug = ARGUMENTS.get('debug', 0)
release = ARGUMENTS.get('release', 0)

if release:
	dflags = '-release'
else:
	dflags = '-unittest'

if debug:
	dflags = dflags + ' -g -debug'
else:
	dflags = dflags + ' -O'

env = Environment(
	DMD = '/usr/src/d/dmd/src/dmd',
	DFLAGS = dflags
)

env.Command('tetraworld', Split("""
		tetraworld.d
	"""),
	"$DMD $DFLAGS -of$TARGET $SOURCES"
)
