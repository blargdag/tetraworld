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

Color xlatTermColor(ushort c)
{
    static import arsd.terminal;
    auto result = Color.black;

    ubyte value = (c & arsd.terminal.Bright) ? 255 : 127;
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
        paint.pen = Pen(impl.bgColor, 1);
        paint.drawRectangle(pixPos, Point(pixPos.x + w*impl.font.charWidth,
                                          pixPos.y + impl.font.charHeight));

        int i = 0, j;
        paint.pen = Pen(impl.fgColor, 1);
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
        impl.fgColor = xlatTermColor(fg);
        impl.bgColor = xlatTermColor(bg);
    }

    override bool canClear() { return true; }
    override void clear()
    {
        impl.paint.clear();
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

    private ScreenPainter* curPaint;
    private int curX, curY, lastX, lastY;
    private bool showCur, shownCur;
    private Color fgColor, bgColor;

    private Fiber userFiber;
    private void delegate(dchar key) keyConsumer;
    private void delegate(int x, int x, uint buttons) mouseConsumer;
    private void delegate(int w, int h) resizeConsumer;

    private ScreenPainter paint()()
    {
        if (curPaint) return *curPaint;

        version(all)
            return window.draw();
        else
        {
            curPaint = new ScreenPainter;
            *curPaint = window.draw();
            if (shownCur)
            {
                auto pos = gridToPix(Point(lastX, lastY));
                curPaint.pen = Pen(Color.white);
                curPaint.rasterOp = RasterOp.xor;
                curPaint.drawRectangle(pos, font.charWidth, font.charHeight);
                shownCur = false;
            }
            return *curPaint;
        }
    }

    private void commitPaint()
    {
        version(none)
        {
            if (curPaint is null)
                return;

            if (showCur)
            {
                auto pos = gridToPix(Point(curX, curY));
                curPaint.pen = Pen(Color.white);
                curPaint.rasterOp = RasterOp.xor;
                curPaint.drawRectangle(pos, font.charWidth, font.charHeight);

                shownCur = true;
                lastX = curX;
                lastY = curY;
            }

            destroy(*curPaint);
            curPaint = null;
        }
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
        dchar result;
        keyConsumer = (dchar key) {
            result = key;
            userFiber.call();
        };
        Fiber.yield();

        keyConsumer = null;
        return result;
    }

    override UiEvent nextEvent()
    {
        UiEvent ev;
        keyConsumer = (dchar key) {
            ev.type = UiEvent.Type.kbd;
            ev.key = key;
            userFiber.call();
        };
        mouseConsumer = (int x, int y, uint buttons) {
            ev.type = UiEvent.Type.mouse;
            ev.mouseX = x;
            ev.mouseY = y;
            ev.buttons = buttons;
            userFiber.call();
        };
        resizeConsumer = (int w, int h) {
            ev.type = UiEvent.Type.resize;
            ev.newWidth = w;
            ev.newHeight = h;
            userFiber.call();
        };
        Fiber.yield();

        keyConsumer = null;
        mouseConsumer = null;
        resizeConsumer = null;

        return ev;
    }

    override void sleep(int msecs)
    {
        auto timer = new Timer(msecs, () {
            userFiber.call();
        });

        Fiber.yield();
        timer.destroy();
    }

    override void quit()
    {
        window.close();
    }

    void run(void delegate() _userFiber)
    {
        window.windowResized = (int w, int h) {
            computeGridDim();
            window.draw.clear();

            if (resizeConsumer !is null)
                resizeConsumer(gridWidth, gridHeight);
        };

        // Need large stack to prevent stack overflow.
        enum fiberStackSz = 256*1024;
        userFiber = new Fiber(_userFiber, fiberStackSz);
        userFiber.call();

        window.eventLoop(0,
            delegate(dchar ch) {
                auto d = window.draw();
                curPaint = &d;
                scope(exit) curPaint = null;

                if (keyConsumer !is null)
                    keyConsumer(ch);
            },
            delegate(MouseEvent event) {
                auto gridX = (event.x - offsetX) / font.charWidth;
                auto gridY = (event.y - offsetY) / font.charHeight;

                if (mouseConsumer !is null)
                {
                    // TBD: button state: see event.modifierState and
                    // ModifierState.
                    mouseConsumer(gridX, gridY, 0 /* FIXME */);
                }
            },
        );
    }
}

// vim:set ai sw=4 ts=4 et:
