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

import core.thread : Fiber;
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

    private this(GuiBackend _impl) { impl = _impl; }

    override @property int width() { return impl.gridWidth; }
    override @property int height() { return impl.gridHeight; }
    override void moveTo(int x, int y)
    {
        impl.curX = x;
        impl.curY = y;
    }

    override void writefImpl(string s)
    {
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
            paint.drawText(Point(pixPos.x + i*impl.font.charWidth, pixPos.y),
                           s[i .. i+j]);
            i += j;
            impl.curX++;
        }
    }

    override bool canShowHideCursor() { return true; }
    override void showCursor() { impl.showCur = true; }
    override void hideCursor() { impl.showCur = false; }

    override bool hasColor() { return true; }

    override void color(ushort fg, ushort bg)
    {
        impl.fgColor = xlatTermColor(fg, Color.black);
        impl.bgColor = xlatTermColor(bg, Color.white);
    }

    override bool canClear() { return true; }
    override void clear()
    {
        auto paint = impl.paint;
        paint.outlineColor = impl.bgColor;
        paint.fillColor = impl.bgColor;
        paint.drawRectangle(Point(0,0), impl.window.width, impl.window.height);
    }

    override bool hasCursorXY() { return true; }
    override @property int cursorX() { return impl.curX; }
    override @property int cursorY() { return impl.curY; }

    override bool hasFlush() { return true; }
    override void flush() { impl.commitPaint(); }
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

    private Fiber userFiber;
    private void delegate(dchar key) keyConsumer;
    private void delegate(int x, int x, uint buttons) mouseConsumer;
    private void delegate(int w, int h) resizeConsumer;

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

    private GuiTerminal terminal;

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

        terminal = new GuiTerminal(this);
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

    override dchar getch()
    {
        auto caller = Fiber.getThis();
        dchar result;

        auto oldkc = keyConsumer;
        keyConsumer = (dchar key) {
            result = key;
            caller.call();
        };
        scope(exit) keyConsumer = oldkc;

        Fiber.yield();
        return result;
    }

    override UiEvent nextEvent()
    {
        auto caller = Fiber.getThis();
        UiEvent ev;

        auto oldkc = keyConsumer;
        keyConsumer = (dchar key) {
            ev.type = UiEvent.Type.kbd;
            ev.key = key;
            caller.call();
        };
        scope(exit) keyConsumer = oldkc;

        auto oldmc = mouseConsumer;
        mouseConsumer = (int x, int y, uint buttons) {
            ev.type = UiEvent.Type.mouse;
            ev.mouseX = x;
            ev.mouseY = y;
            ev.buttons = buttons;
            caller.call();
        };
        scope(exit) mouseConsumer = oldmc;

        auto oldrc = resizeConsumer;
        resizeConsumer = (int w, int h) {
            ev.type = UiEvent.Type.resize;
            ev.newWidth = w;
            ev.newHeight = h;
            caller.call();
        };
        scope(exit) resizeConsumer = oldrc;

        Fiber.yield();
        return ev;
    }

    override void sleep(int msecs)
    {
        auto caller = Fiber.getThis;
        auto timer = new Timer(msecs, () {
            caller.call();
        });

        Fiber.yield();
        timer.destroy();
    }

    override void quit()
    {
        _quit = true;
    }

    void run(void delegate() _userFiber)
    {
        // Need large stack to prevent stack overflow.
        enum fiberStackSz = 256*1024;
        userFiber = new Fiber(_userFiber, fiberStackSz);

        window.visibleForTheFirstTime = () {
            // Don't run user fiber until window is visible; we may get X11
            // errors if user fiber starts calling drawing functions too early
            // on.
            userFiber.call();
        };
        window.windowResized = (int w, int h) {
            computeGridDim();
            window.draw.clear();

            if (resizeConsumer !is null)
                resizeConsumer(gridWidth, gridHeight);
        };

        window.eventLoop(0,
            delegate(dchar ch) {
                {
                    scope(exit) commitPaint();

                    // Enter key remapping hack
                    if (ch == '\x0D')
                        ch = '\n';

                    if (keyConsumer !is null)
                    {
                        keyConsumer(ch);
                    }
                }
                if (_quit)
                    window.close();
            },
            delegate(MouseEvent event) {
                {
                    scope(exit) commitPaint();

                    auto gridX = (event.x - offsetX) / font.charWidth;
                    auto gridY = (event.y - offsetY) / font.charHeight;

                    if (mouseConsumer !is null)
                    {
                        // TBD: button state: see event.modifierState and
                        // ModifierState.
                        mouseConsumer(gridX, gridY, 0 /* FIXME */);
                    }
                }
                if (_quit)
                    window.close();
            },
        );
    }
}

// vim:set ai sw=4 ts=4 et:
