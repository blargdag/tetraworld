/**
 * GUI module
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
module gui;

static import core.sync.event;
import core.thread.osthread;
import std.format : format;

import arsd.color;
import arsd.simpledisplay;

import display;
import ui;
import widgets : UiEvent; // TBD: should be split into own module

/**
 * Font wrapper
 */
struct Font
{
    OperatingSystemFont osfont;
    int charWidth, charHeight;
    int ascent;

    this(string fontName, int size)
    {
        version(Windows)
        {
            import core.sys.windows.windef;
            import core.sys.windows.wingdi;

            osfont = new OperatingSystemFont;
            auto buf = WCharzBuffer(fontName);
            osfont.font = CreateFont(size, 0, 0, 0, cast(int)
                                     FontWeight.medium, 0, 0, 0, 0, 0, 0, 0,
                                     FIXED_PITCH, buf.ptr);
            osfont.prepareFontInfo();
        }
        else
        {
            osfont = new OperatingSystemFont(fontName, size,
                                             FontWeight.medium);
            osfont = !osfont.isNull ? osfont : osfont.loadDefault;
        }
        charWidth = osfont.stringWidth("M");
        charHeight = osfont.height;
        ascent = osfont.ascent;
    }
}

Color xlatTermColor(ushort c, Color defColor = Color.black)
{
    static import arsd.terminal;
    if (c == arsd.terminal.Color.DEFAULT)
        return defColor;

    auto result = Color.black;

    ubyte value = (c & arsd.terminal.Bright) ? 255 : 192;
    if (c & arsd.terminal.Color.red)   result.r = value;
    if (c & arsd.terminal.Color.green) result.g = value;
    if (c & arsd.terminal.Color.blue)  result.b = value;

    return result;
}

unittest
{
    static import arsd.terminal;
    assert(xlatTermColor(arsd.terminal.Color.yellow) == Color(127, 127, 0));
    assert(xlatTermColor(arsd.terminal.Color.yellow | arsd.terminal.Bright) ==
           Color(255, 255, 0));

    assert(xlatTermColor(arsd.terminal.Color.DEFAULT, Color.yellow) ==
           Color.yellow);
    assert(xlatTermColor(arsd.terminal.Color.red, Color.yellow) ==
           Color(127, 0, 0));
}

/**
 * GUI backend wrapper with a Display interface.
 */
class GuiTerminal : DisplayObject
{
    private GuiBackend impl;

    // Cached values, 'cos this is very frequently accessed and it's ridiculous
    // to incur a context switch and mutex lock every single time!
    private int w, h;

    private this(GuiBackend _impl, int gridWidth, int gridHeight)
    {
        impl = _impl;
        w = gridWidth;
        h = gridHeight;
    }

    private T getFromGuiThread(T)(T delegate() dg)
    {
        T value;
        runInGuiThread({
            value = dg();
        });
        return value;
    }

    override @property int width() { return w; }
    override @property int height() { return h; }

    override void moveTo(int x, int y)
    {
        runInGuiThread({
            impl.curX = x;
            impl.curY = y;
        });
    }

    override void writefImpl(string s)
    {
        runInGuiThread({
            auto pixPos = impl.gridToPix(Point(impl.curX, impl.curY));

            // Poor man's grid-based font rendering. Just to get that
            // deliberately ugly look. :-/
            import std.uni;
            int w;
            for (size_t i=0; i < s.length; i += graphemeStride(s, i))
            {
                w++;
            }

            auto paint = impl.paint;
            paint.setFont(impl.font.osfont);
            paint.outlineColor = impl.bgColor;
            paint.fillColor = impl.bgColor;
            paint.drawRectangle(pixPos, w*impl.font.charWidth,
                                impl.font.charHeight);

            int i = 0, j;
            paint.outlineColor = impl.fgColor;
            paint.fillColor = impl.fgColor;
            while (i < s.length)
            {
                j = cast(int) graphemeStride(s, i);
                paint.drawText(Point(pixPos.x + i*impl.font.charWidth,
                                     pixPos.y),
                               s[i .. i+j]);
                i += j;
                impl.curX++;
            }
        });
    }

    override bool canShowHideCursor() { return true; }

    override void showCursor()
    {
        runInGuiThread({
            impl.showCur = true;
        });
    }

    override void hideCursor()
    {
        runInGuiThread({
            impl.showCur = false;
        });
    }

    override bool hasColor() { return true; }

    override void color(ushort fg, ushort bg)
    {
        runInGuiThread({
            impl.fgColor = xlatTermColor(fg, Color.black);
            impl.bgColor = xlatTermColor(bg, Color.white);
        });
    }

    override bool canClear() { return true; }

    override void clear()
    {
        runInGuiThread({
            auto paint = impl.paint;
            paint.outlineColor = impl.bgColor;
            paint.fillColor = impl.bgColor;
            paint.drawRectangle(Point(0,0), impl.window.width,
                                impl.window.height);
        });
    }

    override bool hasCursorXY() { return true; }

    override @property int cursorX()
    {
        int x;
        runInGuiThread({
            x = impl.curX;
        });
        return x;
    }

    override @property int cursorY()
    {
        return getFromGuiThread(() => impl.curY);
    }

    override bool hasFlush() { return true; }

    override void flush()
    {
import std;File("/tmp/debug","a").writefln("[thread %x] flush",cast(void*)Thread.getThis() );
        runInGuiThread({
import std;File("/tmp/debug","a").writefln("[thread %x] commitPaint",cast(void*)Thread.getThis() );
            impl.commitPaint();
        });
    }
}

private synchronized class EventQueue
{
    private UiEvent[] events;

    /**
     * Appends an event to the queue.
     */
    void append(UiEvent ev)
    {
        events ~= ev;
    }

    /**
     * Returns: The next event in the queue, or UiEvent.init if the queue is
     * empty.
     */
    @property UiEvent pop()
    {
        if (events.length == 0)
            return UiEvent.init;

        auto ev = events[0];
        events[0 .. $-1] = events[1 .. $];
        events.length--;
        return ev;
    }
}

/**
 * GUI-based terminal.
 *
 * Mostly to stop depending on command.exe on Windows, which is stupidly slow.
 */
class GuiBackend : UiBackend
{
    private SimpleWindow window;
    private Font font;
    private int gridWidth, gridHeight;
    private int offsetX, offsetY;
    private bool _quit;

    private ScreenPainter curPaint;
    private bool hasCurPaint;

    private int curX, curY, lastX, lastY;
    private bool showCur, shownCur;
    private Color fgColor = Color.black, bgColor = Color.white;

    private GuiTerminal terminal;
    private shared EventQueue events;
    private core.sync.event.Event hasEvent;

    private ScreenPainter paint()()
    {
        if (hasCurPaint) return curPaint;

        curPaint = window.draw();
        version(none)
        if (shownCur)
        {
            auto pos = gridToPix(Point(lastX, lastY));
            curPaint.outlineColor = Color.white;
            curPaint.fillColor = Color.white;
            curPaint.rasterOp = RasterOp.xor;
            curPaint.drawRectangle(pos, font.charWidth, font.charHeight);
            curPaint.rasterOp = RasterOp.normal;
            shownCur = false;
        }
        hasCurPaint = true;
        return curPaint;
    }

    private void commitPaint()
    {
        if (!hasCurPaint)
            return;

        version(none)
        if (showCur)
        {
            auto pos = gridToPix(Point(curX, curY));
            curPaint.outlineColor = Color.white;
            curPaint.fillColor = Color.white;

            version(none)
            {
                curPaint.rasterOp = RasterOp.xor;
                curPaint.drawRectangle(pos, font.charWidth, font.charHeight);
                curPaint.rasterOp = RasterOp.normal;

                shownCur = true;
                lastX = curX;
                lastY = curY;
            }
        }

        destroy(curPaint);
        hasCurPaint = false;
    }

    this(int width, int height, string title)
    {
        window = new SimpleWindow(Size(width, height), title,
                                  Resizability.allowResizing);

        //enum fontName = "DejaVu Sans Mono"; // FIXME: make this cross-platform
        enum fontName = "Courier New"; // seems pretty cross-platform... NOT
        font = Font(fontName, 16);
        computeGridDim();

        fgColor = Color.white;
        bgColor = Color.black;

        window.draw.clear();

        terminal = new GuiTerminal(this, gridWidth, gridHeight);
        events = new EventQueue;
        hasEvent.initialize(false, false);
    }

    ~this()
    {
        hasEvent.terminate();
    }

    /**
     * Convert the given grid position to pixel position.
     */
    Point gridToPix(Point pt)
    {
        return Point(pt.x * font.charWidth + offsetX,
                     pt.y * font.charHeight + offsetY);
    }

    private void computeGridDim()
    {
        gridWidth = window.width / font.charWidth;
        gridHeight = window.height / font.charHeight;
        offsetX = (window.width - gridWidth*font.charWidth) / 2;
        offsetY = (window.height - gridHeight*font.charHeight) / 2;
    }

    override DisplayObject term() { return terminal; }

    // FIXME: this is SUPER DANGEROUS and subject to race conditions because we
    // blindly assume this will be called from the user thread only. But I
    // don't know how else to optimize away the mutex lock in reading the
    // width/height, which makes things super slow.
    private void updateDim(UiEvent ev)
    {
        if (ev.type == UiEvent.Type.resize)
        {
            terminal.w = ev.newWidth;
            terminal.h = ev.newHeight;
        }
    }

    /**
     * BUGS: ALL non-keyboard events will be dropped by this function. This is
     * in general a VERY BAD API, because there is no way to handle a lot of
     * situations that may come up: e.g., while waiting for input via getch(),
     * user resizes window. We can't trigger the resize handling code, because
     * the user thread is inside getch(), and not expecting a resize. We cannot
     * return from getch() because the calling code may be deeply nested and
     * the immediate caller may not know what to do with a resize, or how to
     * get back to the equivalent state after resize. E.g., the message pane
     * calls getch() to prompt user to scroll messages; after resize the
     * message pane may be in a completely different state. It basically WILL
     * NOT WORK.
     *
     * IOW, this function is a VERY BAD IDEA; we should refactor our code to
     * get rid of dependency on getch. Instead, use a Mode to capture user
     * input while still processing other events.
     */
    override dchar getch()
    {
        UiEvent ev;
        do
        {
import std;File("/tmp/debug","a").writefln("[thread %x] getch wait",cast(void*)Thread.getThis() );
            hasEvent.wait();
import std;File("/tmp/debug","a").writefln("[thread %x] getch retrieving event",cast(void*)Thread.getThis() );
            ev = events.pop();
            updateDim(ev);
        } while (ev.type != UiEvent.Type.kbd);

        assert(ev.type == UiEvent.Type.kbd);
import std;File("/tmp/debug","a").writefln("[thread %x] getch got '%s'",cast(void*)Thread.getThis() ,ev.key);
        return ev.key;
    }

    override UiEvent nextEvent()
    {
        UiEvent ev;
        do
        {
import std;File("/tmp/debug","a").writefln("[thread %x] nextEvent wait",cast(void*)Thread.getThis() );
            hasEvent.wait();
import std;File("/tmp/debug","a").writefln("[thread %x] nextEvent retrieving event",cast(void*)Thread.getThis() );
            ev = events.pop();
        } while (ev.type == UiEvent.Type.none);

import std;File("/tmp/debug","a").writefln("[thread %x] nextEvent got '%s'",cast(void*)Thread.getThis() ,ev);
        updateDim(ev);
        return ev;
    }

    override void sleep(int msecs)
    {
        import core.time : dur;
        Thread.sleep(dur!"msecs"(msecs));
    }

    override void quit()
    {
import std;File("/tmp/debug","a").writefln("[thread %x] quit",cast(void*)Thread.getThis() );
        runInGuiThread({
import std;File("/tmp/debug","a").writefln("[thread %x] closing window",cast(void*)Thread.getThis() );
            window.close();
        });
    }

    void run(void delegate() userCode)
    {
        Thread userThread = new Thread(userCode);
        window.visibleForTheFirstTime = () {
            // Don't run user code until window is visible; we may get X11
            // errors if user code starts calling drawing functions too early
            // on.
import std;File("/tmp/debug","a").writefln("[thread %x] starting user thread",cast(void*)Thread.getThis() );
            userThread.start();
        };

        window.windowResized = (int w, int h) {
            computeGridDim();
            paint.clear();

            auto ev = UiEvent(UiEvent.type.resize);
            ev.newWidth = gridWidth;
            ev.newHeight = gridHeight;
            events.append(ev);
            hasEvent.set();
        };

        window.eventLoop(0,
            delegate(dchar ch) {
                // Enter key remapping hack
                if (ch == '\x0D')
                    ch = '\n';

                auto ev = UiEvent(UiEvent.Type.kbd);
                ev.key = ch;
import std;File("/tmp/debug","a").writefln("[thread %x] key event: %s ",cast(void*)Thread.getThis(), ev);
                events.append(ev);
import std;File("/tmp/debug","a").writefln("[thread %x] notifying event",cast(void*)Thread.getThis() );
                hasEvent.set();

                version(none) // FIXME
                {
                    scope(exit) commitPaint();
                }
import std;File("/tmp/debug","a").writefln("[thread %x] key event done",cast(void*)Thread.getThis() );
            },
            delegate(MouseEvent event) {
                auto ev = UiEvent(UiEvent.Type.mouse);
                ev.mouseX = (event.x - offsetX) / font.charWidth;
                ev.mouseY = (event.y - offsetY) / font.charHeight;
                ev.buttons = 0; // FIXME: TBD
import std;File("/tmp/debug","a").writefln("[thread %x] mouse event: %s ",cast(void*)Thread.getThis(), ev);
                events.append(ev);
import std;File("/tmp/debug","a").writefln("[thread %x] notifying event",cast(void*)Thread.getThis() );
                hasEvent.set();
import std;File("/tmp/debug","a").writefln("[thread %x] mouse event done",cast(void*)Thread.getThis() );
            },
        );

import std;File("/tmp/debug","a").writefln("[thread %x] joining user thread",cast(void*)Thread.getThis() );
        userThread.join();
import std;File("/tmp/debug","a").writefln("[thread %x] gui.run done",cast(void*)Thread.getThis() );
    }
}

// vim:set ai sw=4 ts=4 et:
