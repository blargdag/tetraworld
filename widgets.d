/**
 * UI widgets
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
module widgets;

import std.format;
import arsd.terminal;

import display;

version(Posix)
    enum keyEnter = '\n';
else version(Windows)
    enum keyEnter = '\r';
else static assert(0);

/**
 * A UI interaction mode. Basically, a set of event handlers and render hooks.
 */
struct Mode
{
    void delegate() render;
    void delegate(dchar) onCharEvent;
}

/**
 * Input dispatcher.
 */
struct InputDispatcher
{
    private Mode[] modestack;

    private void setup()()
    {
        if (modestack.length == 0)
            modestack.length = 1;
    }

    /**
     * Returns: The current mode (at the top of the stack).
     */
    Mode top()
    {
        setup();
        return modestack[$-1];
    }

    /**
     * Push a new mode onto the mode stack.
     */
    void push(Mode mode)
    {
        modestack.assumeSafeAppend();
        modestack ~= mode;

        if (mode.render !is null)
            mode.render();
    }

    /**
     * Pop the current mode off the stack and revert to the previous mode.
     */
    void pop()
    {
        modestack.length--;
        if (top.render !is null)
            top.render();
    }

    void handleEvent(InputEvent event)
    {
        switch (event.type)
        {
            case InputEvent.Type.KeyboardEvent:
                auto ev = event.get!(InputEvent.Type.KeyboardEvent);
                assert(top.onCharEvent !is null);
                top.onCharEvent(ev.which);
                break;

            default:
                // TBD
                return;
        }

        if (top.render !is null)
            top.render();
    }
}

/**
 * Message buffer that accumulates in-game messages between turns, and prompts
 * player for keypress if messages overflow message window size before player's
 * next turn.
 */
struct MessageBox(Disp)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    private enum morePrompt = "--MORE--";

    private Disp impl;
    private size_t moreLen;
    private int curX = 0;

    this(Disp disp)
    {
        impl = disp;
        moreLen = morePrompt.displayLength;
    }

    private void showPrompt(void delegate() waitForKeypress)
    {
        // FIXME: this assumes impl.height==1.
        impl.moveTo(curX, 0);
        impl.color(Color.white, Color.blue);
        impl.writef("%s", morePrompt);
        waitForKeypress();

        impl.moveTo(0, 0);
        impl.clearToEol();
        curX = 0;
    }

    /**
     * Post a message to this MessageBox. If it fits in the current space,
     * print it immediately. Otherwise, display a prompt for the user to
     * acknowledge reading the previous messages first, then clear the line and
     * display this one.
     */
    void message(string str, void delegate() waitForKeypress)
    {
        auto len = str.displayLength;
        if (curX + len + moreLen >= impl.width)
        {
            showPrompt(waitForKeypress);
            assert(curX == 0);
        }

        // FIXME: this assumes impl.height==1.
        // FIXME: support the case where len > impl.width.
        impl.moveTo(curX, 0);
        impl.color(Color.DEFAULT, Color.DEFAULT);
        impl.writef("%s", str);
        impl.clearToEol();

        curX += len + 1;
    }

    /**
     * Inform this MessageBox that the player has read all messages, and the
     * next one should start from the beginning again.
     */
    void sync()
    {
        curX = 0;
    }

    /**
     * Prompt if the message box is not empty, otherwise do nothing.
     *
     * Basically, this is intended for when the game is about to quit, or the
     * message box is about to get covered up by a different mode, and we want
     * to ensure the player has read the current messages first.
     */
    void flush(void delegate() waitForKeypress)
    {
        if (curX > 0)
            showPrompt(waitForKeypress);
    }
}

/// ditto
auto messageBox(Disp)(Disp disp)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    return MessageBox!Disp(disp);
}

unittest
{
    struct TestDisp
    {
        enum width = 20;
        enum height = 1;
        char[width*height] impl;
        int curX, curY;

        void moveTo(int x, int y)
            in (x >= 0 && x < width)
            in (y >= 0 && y < height)
        {
            curX = x;
            curY = y;
        }

        void writef(Args...)(string fmt, Args args)
        {
            foreach (ch; format(fmt, args))
            {
                impl[curX + width*curY] = ch;
                curX++;
            }
        }
        void color(ushort, ushort) {}
        @property int cursorX() { return curX; }
        @property int cursorY() { return curY; }
    }

    TestDisp disp;

    foreach (ref ch; disp.impl) { ch = ' '; }
    auto box = messageBox(&disp);

    box.message("Blehk.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blehk.              ");

    box.message("Eh?", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blehk. Eh?          ");

    box.sync();

    box.message("Blah.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blah.               ");

    box.message("Bleh.", { assert(false, "should not wait for keypress"); });
    assert(disp.impl == "Blah. Bleh.         ");

    bool keypress;
    box.message("Kaboom.", {
        assert(disp.impl == "Blah. Bleh. --MORE--");
        keypress = true;
    });
    assert(keypress && disp.impl == "Kaboom.             ");
}

/**
 * Convert the given dchar to a printable string.
 *
 * Returns: An object whose toString method returns a printable string
 * representation of the given dchar. If the dchar is already printable, this
 * will be a string containing the dchar itself. If it matches one of a list of
 * named control characters, it will be that name. Otherwise, it will be "^X"
 * for ASCII control characters or "(\Uxxxx)" for general Unicode characters.
 */
auto toPrintable(dchar ch)
{
    static struct PrintableChar
    {
        dchar ch;
        void toString(W)(W sink)
        {
            import std.format : formattedWrite;
            import std.uni : isGraphical;

            if (ch == ' ')
                sink.formattedWrite("<space>");
            else if (ch.isGraphical)
                sink.formattedWrite("%s", ch);
            else switch (ch)
            {
                case keyEnter:  sink.formattedWrite("<enter>");   break;
                case '\t':      sink.formattedWrite("<tab>");     break;
                default:
                    if (ch < 0x20)
                        sink.formattedWrite("^%s", cast(dchar)(ch + 0x40));
                    else
                        sink.formattedWrite("(\\u%04X)", ch);
            }
        }

        unittest
        {
            import std.array : appender;
            auto pc = PrintableChar('a');
            auto app = appender!string;
            pc.toString(app);
        }
    }
    return PrintableChar(ch);
}

unittest
{
    assert(format("%s", 'a'.toPrintable) == "a");
    assert(format("%s", '\x01'.toPrintable) == "^A");
    assert(format("%s", '\uFFFF'.toPrintable) == "(\\uFFFF)");

    assert(format("%s", keyEnter.toPrintable) == "<enter>");
    assert(format("%s", '\t'.toPrintable) == "<tab>");
    assert(format("%s", ' '.toPrintable) == "<space>");
}

// vim:set ai sw=4 ts=4 et:
