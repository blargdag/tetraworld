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
ldcoptflags = [ '-O', '-linkonce-templates' ]

if release:
	ldcoptflags = [
        '-O3',
        '-linkonce-templates'
    ]

if debug:
	ldcflags += ['-g', '-gc', '-d-debug']
	ldcoptflags = [ ]


#
# Build rules
#

sources = Split("""
	tetraworld.d
	action.d
	agent.d
	ai.d
	bsp.d
	components.d
	config.d
	damage.d
	dir.d
	display.d
	fov.d
    hiscore.d
	lang.d
	loadsave.d
	mapgen.d
	game.d
	gamemap.d
	gravity.d
	medium.d
	objects.d
	rndutil.d
	stacking.d
	store.d
	store_traits.d
	terrain.d
	testutil.d
	tile.d
	tui.d
	ui.d
	vector.d
	widgets.d
	world.d

	arsd/terminal.d
""")

env = Environment(
	LDC = ldc,
	LDCFLAGS = ldcflags,
	LDCOPTFLAGS = ldcoptflags,
	LDCTESTFLAGS = [ '--unittest' ],
)

# Convenience shorthand for building both the 'real' executable and a
# unittest-only executable.
def DProgram(env, target, sources):
	# Build real executable
	env.Command(target, sources, "$LDC $LDCFLAGS $LDCOPTFLAGS $SOURCES -of$TARGET")

	# Build test executable
	testprog = File(target + '-test').path
	teststamp = '.' + target + '-teststamp'
	env.Depends(target, teststamp)
	env.Command(teststamp, sources, [
		"$LDC $LDCFLAGS $LDCTESTFLAGS $SOURCES -of%s" % testprog,
		"./%s" % testprog,
		"\\rm -f %s*" % testprog,
		"touch $TARGET"
	])
AddMethod(Environment, DProgram)


# Tetraworld main program
env.DProgram('tetraworld', sources)


# Utilities
env.DProgram('uniwidth', Split("""
	uniwidth.d
"""))

env.DProgram('bspbuild', Split("""
	bspbuild.d
"""))

# FIXME: upload.d has no unittests, and --unittest somehow runs main()?!
env.Command('upload', 'upload.d', "$LDC $LDCFLAGS $SOURCES -of$TARGET")


# Cross-compiled Windows build
winenv = env.Clone()
winenv.Append(LDCFLAGS = [ '-mtriple=x86_64-windows-msvc' ])
winenv.Command('tetraworld.exe', sources, "$LDC $LDCFLAGS $LDCOPTFLAGS -of$TARGET $SOURCES")

