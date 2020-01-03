#!/usr/bin/scons
import os;

#
# Command-line configurable parameters
#

debug = ARGUMENTS.get('debug', 0)
release = ARGUMENTS.get('release', 0)


#
# Static configuration parameters
#

ldc = '/usr/src/d/ldc/latest/bin/ldc2'
ldcflags = [ ]

if release:
	ldcflags += ['-O3']
else:
	ldcflags += ['-unittest']

if debug:
	ldcflags += ['-g', '-gc', '-d-debug']
else:
	ldcflags += ['-O']


#
# Build rules
#

env = Environment(
	LDC = ldc,
	LDCFLAGS = ldcflags,
)

sources = Split("""
	tetraworld.d
	bsp.d
	display.d
	map.d
	testutil.d
	vector.d
	world.d

	arsd/terminal.d
""")

# Tetraworld main program
env.Command('tetraworld', sources, "$LDC $LDCFLAGS -of$TARGET $SOURCES")


# Utilities
env.Command('uniwidth', Split("""
		uniwidth.d
	"""),
	"$LDC $LDCFLAGS -of$TARGET $SOURCES"
)

# Cross-compiled Windows build
winenv = env.Clone()
winenv.Append(LDCFLAGS = [ '-mtriple=x86_64-windows-msvc' ])
winenv.Command('tetraworld.exe', sources, "$LDC $LDCFLAGS -of$TARGET $SOURCES")

