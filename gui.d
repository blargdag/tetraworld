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
class GuiTerminal : DisplayObject, UiBackend
{
    private GuiImpl impl;

    private Color fg, bg;
    private int startX, startY;
    private int curX, curY;
    private bool _showCursor;
    private char[] buf;

    // Cached values, 'cos this is very frequently accessed and it's ridiculous
    // to incur a context switch and mutex lock every single time!
    private int w, h;

    private this(GuiImpl _impl, int gridWidth, int gridHeight)
    {
        impl = _impl;
        w = gridWidth;
        h = gridHeight;

        fg = Color.white;
        bg = Color.black;
    }

    override @property int width() { return w; }
    override @property int height() { return h; }

    override void moveTo(int x, int y)
    {
        if (curX != x || curY != y)
        {
            flushImpl(false);
            startX = curX = x;
            startY = curY = y;
        }
    }

    private int renderLength(const(char)[] s)
    {
        import std.uni;
        int w;
        for (size_t i=0; i < s.length; i += graphemeStride(s, i))
        {
            w++;
        }
        return w;
    }

    override void writefImpl(string s)
    {
        auto w = renderLength(s);
        buf ~= s;
        curX += w;
    }

    override bool canShowHideCursor() { return true; }
    override void showCursor() { _showCursor = true; }
    override void hideCursor() { _showCursor = false; }

    override bool hasColor() { return true; }

    override void color(ushort fgColor, ushort bgColor)
    {
        auto newFg = xlatTermColor(fgColor, Color.black);
        auto newBg = xlatTermColor(bgColor, Color.white);
        if (fg != newFg || bg != newBg)
        {
            flushImpl(false);
            fg = newFg;
            bg = newBg;
        }
    }

    override bool canClear() { return true; }

    override void clear()
    {
        // Buffer contents no longer relevant since we're erasing it all, so
        // just drop it.
        buf.length = 0;
        startX = startY = curX = curY = 0;

        runInGuiThread({
            auto paint = impl.paint;
            paint.outlineColor = bg;
            paint.fillColor = bg;
            paint.drawRectangle(Point(0,0), impl.window.width,
                                impl.window.height);
        });
    }

    override bool hasCursorXY() { return true; }
    override @property int cursorX() { return curX; }
    override @property int cursorY() { return curY; }

    override bool hasFlush() { return true; }

    /**
     * WARNING: this function MUST be run only the GUI thread, otherwise it
     * will cause problems!
     */
    private void guiThreadFlush(bool commit)
    {
        if (buf.length > 0)
        {
            auto pixPos = impl.gridToPix(Point(startX, startY));

            // Poor man's grid-based font rendering. Just to get that
            // deliberately ugly look. :-/
            auto w = renderLength(buf);
            auto paint = impl.paint;

            paint.setFont(impl.font.osfont);
            paint.outlineColor = bg;
            paint.fillColor = bg;
            paint.drawRectangle(pixPos, w*impl.font.charWidth,
                                impl.font.charHeight);

            int i = 0;
            paint.outlineColor = fg;
            paint.fillColor = fg;
            while (i < buf.length)
            {
                import std.uni : graphemeStride;
                auto j = graphemeStride(buf, i);
                paint.drawText(Point(pixPos.x, pixPos.y), buf[i .. i+j]);
                pixPos.x += impl.font.charWidth;
                i += j;
            }

            buf.length = 0;
            startX = curX;
            startY = curY;
        }

        if (commit)
        {
            impl.curX = curX;
            impl.curY = curY;
            impl.showCur = _showCursor;
            impl.commitPaint();
        }
    }

    private void flushImpl(bool commit)
    {
        if (buf.length == 0 && !commit)
            return;

        runInGuiThread({
            guiThreadFlush(commit);
        });
    }

    override void flush()
    {
        flushImpl(true);
    }

    override DisplayObject term() { return this; }

    private void updateDim(UiEvent ev)
    {
        if (ev.type == UiEvent.Type.resize)
        {
            w = ev.newWidth;
            h = ev.newHeight;
        }
    }

    override UiEvent nextEvent()
    {
        UiEvent ev;
        bool mustBlock;

        runInGuiThread({
            guiThreadFlush(true); // Flush updates before potentially blocking.
            if (!impl.popEvent(ev))
            {
                mustBlock = true;
                return;
            }
        });

        while (mustBlock)
        {
            impl.hasEvent.wait();
            mustBlock = false;
            runInGuiThread({
                if (!impl.popEvent(ev))
                {
                    mustBlock = true;
                    return;
                }
            });
        }

        updateDim(ev);
        return ev;
    }

    override void sleep(int msecs)
    {
        // Flush updates before potentially blocking.
        flush();

        import core.time : dur;
        Thread.sleep(dur!"msecs"(msecs));
    }

    override void quit()
    {
        runInGuiThread({
            guiThreadFlush(true);
            impl.window.close();
        });
    }
}

/**
 * GUI-based terminal.
 *
 * Mostly to stop depending on command.exe on Windows, which is stupidly slow.
 */
private class GuiImpl
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

    private GuiTerminal terminal;
    private UiEvent[] events;
    private core.sync.event.Event hasEvent;

    private void addEvent(UiEvent ev)
    {
        events ~= ev;
        hasEvent.set();
    }

    private bool popEvent(out UiEvent ev)
    {
        if (events.length == 0)
            return false;

        import std.algorithm : remove;
        ev = events[0];
        events = events.remove(0);
        return true;
    }

    private ScreenPainter paint()()
    {
        if (hasCurPaint) return curPaint;

        curPaint = window.draw();
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

        if (showCur)
        {
            auto pos = gridToPix(Point(curX, curY));
            curPaint.outlineColor = Color.white;
            curPaint.fillColor = Color.white;
            curPaint.rasterOp = RasterOp.xor;
            curPaint.drawRectangle(pos, font.charWidth, font.charHeight);
            curPaint.rasterOp = RasterOp.normal;

            shownCur = true;
            lastX = curX;
            lastY = curY;
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

        window.draw.clear();

        terminal = new GuiTerminal(this, gridWidth, gridHeight);
        hasEvent.initialize(false, false);
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

    void run(void delegate() userCode)
    {
        Thread userThread = new Thread(userCode);
        window.visibleForTheFirstTime = () {
            // Don't run user code until window is visible; we may get X11
            // errors if user code starts calling drawing functions too early
            // on.
            userThread.start();
        };

        window.windowResized = (int w, int h) {
            computeGridDim();
            paint.clear();

            auto ev = UiEvent(UiEvent.type.resize);
            ev.newWidth = gridWidth;
            ev.newHeight = gridHeight;
            addEvent(ev);
        };

        window.eventLoop(0,
            delegate(dchar ch) {
                // Enter key remapping hack
                if (ch == '\x0D')
                    ch = '\n';

                auto ev = UiEvent(UiEvent.Type.kbd);
                ev.key = ch;
                addEvent(ev);
            },
            delegate(MouseEvent event) {
                auto ev = UiEvent(UiEvent.Type.mouse);
                ev.mouseX = (event.x - offsetX) / font.charWidth;
                ev.mouseY = (event.y - offsetY) / font.charHeight;
                ev.buttons = 0; // FIXME: TBD
                addEvent(ev);
            },
        );

        userThread.join();
    }
}

/**
 * Initializes and runs the given code with the console terminal backend.
 */
T runGuiBackend(T, Args...)(int width, int height, string title,
                            T function(UiBackend, Args) cb, Args args)
{
    auto gui = new GuiImpl(width, height, title);
    scope(exit) gui.terminal.quit();

    T result;
    gui.run({
        scope(exit) gui.terminal.quit();
        try
        {
            result = cb(gui.terminal, args);
        }
        catch(Throwable t)
        {
            // DEBUG
            import std.stdio : stderr;
            stderr.writefln("[%x:%s:%d] user thread crash: %s",cast(void*)Thread.getThis,__FUNCTION__,__LINE__ ,t.msg);
            throw t;
        }
    });
    return result;
}

// vim:set ai sw=4 ts=4 et: