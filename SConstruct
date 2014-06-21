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

dmd = '/usr/src/d/dmd/src/dmd'

arsd_incdir = '../ext'
arsd_path = arsd_incdir + os.sep + 'arsd'
arsd_flags = ['-version=with_eventloop']


#
# Environment setup
#

dflags = []
if release:
	dflags += ['-release']
else:
	dflags += ['-unittest']

if debug:
	dflags += ['-g', '-debug']
else:
	dflags += ['-O']

dflags = dflags + ['-I' + arsd_incdir]


#
# Build rules
#

env = Environment(
	DMD = dmd,
	DFLAGS = dflags,

	DCOM = "$DMD $DFLAGS -of$TARGET $SOURCES",

	ARSD_FLAGS = arsd_flags,
	ARSD_COM = "$DMD $DFLAGS $ARSD_FLAGS -of$TARGET -c $SOURCE"
)

# Tetraworld main program
env.Command('tetraworld', Split("""
		tetraworld.d
		display.d
		map.d
		rect.d

		eventloop.o
		terminal.o
	"""),
	"$DMD $DFLAGS -of$TARGET $SOURCES"
)


# arsd modules
env.Command('eventloop.o', arsd_path + os.sep + 'eventloop.d',
	"$ARSD_COM"
)
env.Command('terminal.o', arsd_path + os.sep + 'terminal.d',
	"$ARSD_COM"
)
