#!/usr/bin/scons

debug = ARGUMENTS.get('debug', 0)
release = ARGUMENTS.get('release', 0)

if release:
	dflags = '-frelease'
else:
	dflags = '-funittest'

if debug:
	dflags = dflags + ' -g3 -fdebug'
else:
	dflags = dflags + ' -O3'

# Note: some infelicities (which we probably should post to the SCons mailing
# list to get it fixed):
#  - $DCOM currently assumes the dmd command syntax, so it uses -of instead of
#    -o, which causes gdc to break.
#  - We had to replace LINKCOM 'cos the default dmd tool was doing something
#    strange to the linker line; it uses the wrong library (-lgphobos instead
#    of -lgphobos2) and for some reason repeats it thrice.
#     - We can be spared all this pain simply by using gdc for linking instead
#       of ld.
env = Environment(
	DC = '/usr/bin/gdc-4.6',
	DCOM = '$DC $_DINCFLAGS $_DVERFLAGS $_DDEBUGFLAGS $_DFLAGS -c -o $TARGET $SOURCES',
	LINKCOM = '/usr/bin/gdc-4.6 -o $TARGET $SOURCES $_LIBFLAGS',
	_DFLAGS = dflags
)

env.Program('tetraworld', Split("""
		tetraworld.d
		io.d
		obj.d
		quad.d
"""))
