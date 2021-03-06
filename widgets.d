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

import std.algorithm;
import std.array;
import std.conv;
import std.format;
import std.range.primitives;

import arsd.terminal;

import display;
import vector;

/**
 * Enter key.  Used to be for differentiating between Windows and Posix, but
 * apparently Windows also yields \n, so collapsed into a single definition
 * now.
 */
enum keyEnter = '\n';

/**
 * A UI interaction mode. Basically, a set of event handlers and render hooks.
 */
struct Mode
{
    void delegate() render;
    void delegate(int w, int h) onResizeEvent;
    void delegate(dchar) onCharEvent;
    void delegate() onPreEvent;
}

/**
 * A UI backend event.
 *
 * Unfortunately we can't reuse existing definitions, because
 * arsd.terminal.InputEvent can only be privately constructed and it's
 * incompatible with arsd.simpledisplay.xxxEvent. So we have to translate
 * events to a common format.
 */
struct UiEvent
{
    enum Type { none, kbd, mouse, resize }
    Type type;

    union
    {
        dchar key;  // Type.kbd
        struct      // Type.mouse
        {
            int mouseX, mouseY;
            uint buttons; // TBD
        }
        struct      // Type.resize
        {
            int newWidth;
            int newHeight;
        }
    }
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

    void handleEvent(UiEvent event)
    {
        switch (event.type)
        {
            case UiEvent.Type.kbd:
                assert(top.onCharEvent !is null);
                top.onCharEvent(event.key);
                break;

            case UiEvent.Type.resize:
                // Need to reconfigure every mode, not just top, otherwise when
                // we return to them they may be misconfigured.
                foreach (ref mode; modestack)
                {
                    if (mode.onResizeEvent !is null)
                        mode.onResizeEvent(event.newWidth, event.newHeight);
                }
                if (top.render !is null)
                    top.render();
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
    enum morePrompt = "--MORE--";

    private struct Msg
    {
        string baseMsg;
        string dispStr;
        size_t dispLen;
        uint count;

        this(string msg)
        {
            baseMsg = msg;
            increment();
        }

        string toString() const pure { return dispStr; }

        void increment()
        {
            if (++count == 1)
                dispStr = format("%s ", baseMsg);
            else
                dispStr = format("%s(x%d) ", baseMsg, count);
            dispLen = displayLength(dispStr);
        }
    }

    private Disp impl;
    private size_t moreLen;
    private Msg[] msgs;
    private bool killOnNext;

    this(Disp disp)
    {
        impl = disp;
        moreLen = morePrompt.displayLength;
    }

    this(Disp disp, MessageBox oldBox) // for resizes
    {
        this = oldBox;
        impl = disp;
        moreLen = morePrompt.displayLength;
    }

    private size_t curX() { return msgs.map!(m => m.dispLen).sum; }

    void render()
    {
        // FIXME: this assumes impl.height==1.
        impl.moveTo(0, 0);
        impl.color(Color.DEFAULT, Color.DEFAULT);
        impl.writef("%-(%s%)", msgs);

        int x = impl.cursorX;
        impl.clearToEol();
        impl.moveTo(x, 0);
    }

    private void showPrompt(ref InputDispatcher dispatch,
                            void delegate() parentRefresh,
                            void delegate() onExit)
    {
        auto mode = Mode(
            () {
                if (parentRefresh) parentRefresh();

                render();
                impl.color(Color.white, Color.blue);
                impl.writef("%s", morePrompt);
            },
            null,
            (dchar ch) {
                dispatch.pop();
                if (onExit) onExit();
            }
        );

        dispatch.push(mode);
    }

    /**
     * Post a message to this MessageBox. If it fits in the current space,
     * print it immediately. Otherwise, display a prompt for the user to
     * acknowledge reading the previous messages first, then clear the line and
     * display this one.
     *
     * Returns: true if prompt mode is entered; false if the message did not
     * trigger a prompt.
     */
    bool message(ref InputDispatcher dispatch, string str,
                 void delegate() parentRefresh = null,
                 void delegate() onExit = null)
    {
        if (killOnNext)
        {
            msgs = [];
            killOnNext = false;
        }

        if (msgs.length > 0 && msgs[$-1].baseMsg == str)
        {
            // Merge repeated messages.
            auto msg = msgs[$-1];
            msg.increment();

            if (msg.dispLen + moreLen <= impl.width)
            {
                // There's enough room to insert a multiplier to the last
                // message.
                msgs[$-1] = msg;
                render();
                return false;
            }

            // Fallthrough: no more room for multiplier; don't merge, just
            // flush and start over.
        }
        else
        {
            auto msg = Msg(str);
            if (curX + msg.dispLen + moreLen <= impl.width)
            {
                msgs ~= msg;
                render();
                return false;
            }
        }

        // No more room for message; prompt then flush and start over.
        showPrompt(dispatch, parentRefresh, {
            msgs = [ Msg(str) ];
            render();
            if (onExit) onExit();
        });
        return true;
    }

    /**
     * Inform this MessageBox that the player has read all messages, and the
     * next one should start from the beginning again.
     */
    void sync()
    {
        killOnNext = true;
    }

    /**
     * Prompt if the message box is not empty, otherwise do nothing.
     *
     * Basically, this is intended for when the game is about to quit, or the
     * message box is about to get covered up by a different mode, and we want
     * to ensure the player has read the current messages first.
     */
    void flush(ref InputDispatcher dispatch, void delegate() parentRefresh,
               void delegate() onExit)
    {
        if (msgs.length > 0 && !killOnNext)
        {
            showPrompt(dispatch, parentRefresh, {
                msgs = [];
                onExit();
            });
        }
        else
            onExit();
    }
}

/// ditto
auto messageBox(Disp)(Disp disp)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    return MessageBox!Disp(disp);
}

/// ditto
auto messageBox(Disp)(Disp disp, MessageBox!Disp oldBox)
    if (isDisplay!Disp && hasColor!Disp && hasCursorXY!Disp)
{
    return MessageBox!Disp(disp, oldBox);
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
    InputDispatcher dispatch;

    foreach (ref ch; disp.impl) { ch = ' '; }
    auto box = messageBox(&disp);

    box.message(dispatch, "Blehk.");
    assert(disp.impl == "Blehk.              ");

    box.message(dispatch, "Eh?");
    assert(disp.impl == "Blehk. Eh?          ");

    box.sync();

    box.message(dispatch, "Blah.");
    assert(disp.impl == "Blah.               ");

    box.message(dispatch, "Bleh.");
    assert(disp.impl == "Blah. Bleh.         ");

    box.message(dispatch, "Kaboom.");
    assert(disp.impl == "Blah. Bleh. --MORE--");
    dispatch.handleEvent(UiEvent(UiEvent.Type.kbd, ' '));
    assert(disp.impl == "Kaboom.             ");

    box.message(dispatch, "Oh.");
    assert(disp.impl == "Kaboom. Oh.         ");
    box.message(dispatch, "Pfeh!");
    assert(disp.impl == "Kaboom. Oh. --MORE--");
    dispatch.handleEvent(UiEvent(UiEvent.Type.kbd, ' '));
    assert(disp.impl == "Pfeh!               ");

    // Test repeat folding
    box.message(dispatch, "Pfeh!");
    assert(disp.impl == "Pfeh!(x2)           ");
    box.message(dispatch, "Pfeh!");
    assert(disp.impl == "Pfeh!(x3)           ");
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

/**
 * Prompt the user to enter a number within the given range.
 *
 * Params:
 *  promptStr = The prompt string.
 *  min = The minimum allowed value.
 *  max = The maximum allowed value.
 *  dg = Callback to invoke with the inputted number.
 *  defaultVal = Default value to fill buffer with.
 */
void promptNumber(Disp)(ref Disp disp, ref InputDispatcher dispatch,
                        string promptStr, int minVal, int maxVal,
                        void delegate(int) dg, string defaultVal = "")
    if (isDisplay!Disp)
    in (defaultVal.length <= 12)
{
    auto fullPrompt = format("%s (%d-%d,*)", promptStr, minVal, maxVal);
    auto width = min(fullPrompt.displayLength() + 2, disp.width);
    enum height = 6;
    auto scrnX = (disp.width - width)/2;
    auto scrnY = (disp.height - height)/2;
    auto scrn = subdisplay(&disp, region(
        vec(scrnX, scrnY), vec(scrnX + width, scrnY + height)));

    string err;
    dchar[12] input;
    int curPos;
    bool killOnInput = (defaultVal.length > 0);

    defaultVal.copy(input[]);
    curPos = defaultVal.length.to!int;

    auto promptMode = Mode(
        () {
            scrn.hideCursor();
            scrn.color(Color.black, Color.white);

            // Can't use .clear 'cos it doesn't use color we set.
            scrn.moveTo(0, 0);
            scrn.clearToEos();
            scrn.drawBorder(BorderStyle.thin);

            auto inner = scrn.subdisplay(region(vec(1,1),
                                                vec(width-1, height-1)));
            inner.moveTo(0, 0);
            inner.writef("%s", fullPrompt);

            inner.moveTo(1, 2);
            inner.writef("%s", input[0 .. curPos]);
            inner.clearToEol();

            if (err.length > 0)
            {
                inner.moveTo(1, 3);
                inner.color(Color.red, Color.white);
                inner.writef("%s", err);
                inner.clearToEol();
                inner.color(Color.black, Color.white);
            }

            inner.moveTo(1 + curPos, 2);
            inner.showCursor();
        },
        (int w, int h) {
            width = min(fullPrompt.displayLength() + 2, w);
            scrnX = (w - width)/2;
            scrnY = (h - height)/2;
            scrn = subdisplay(&disp, region(vec(scrnX, scrnY),
                                            vec(scrnX + w, scrnY + h)));
        },
        (dchar ch) {
            import std.conv : to, ConvException;
            switch (ch)
            {
                case '0': .. case '9':
                    if (killOnInput)
                    {
                        curPos = 0;
                        killOnInput = false;
                    }
                    if (curPos + 1 < input.length)
                        input[curPos++] = ch;
                    break;

                case '*':
                    auto maxStr = format("%s", maxVal);
                    maxStr.copy(input[]);
                    curPos = maxStr.length.to!int;
                    break;

                case '\b':
                    if (curPos > 0)
                        curPos--;
                    break;

                case '\n':
                    try
                    {
                        auto result = input[0 .. curPos].to!int;
                        if (result < minVal || result > maxVal)
                        {
                            err = "Please enter a number between %d and %d"
                                  .format(minVal, maxVal);
                            curPos = 0;
                        }
                        else
                        {
                            dispatch.pop();
                            disp.color(Color.DEFAULT, Color.DEFAULT);
                            disp.clear();

                            dg(result);
                            break;
                        }
                    }
                    catch (ConvException e)
                    {
                        err = "That doesn't look like a number!";
                    }
                    break;

                default:
                    break;
            }
        }
    );

    dispatch.push(promptMode);
}

/**
 * Pager for long text.
 */
void pager(Disp)(ref Disp disp, ref InputDispatcher dispatch,
                 const(char[])[] lines, string endPrompt,
                 void delegate() exitHook)
    if (isDisplay!Disp)
{
    pager(disp, dispatch, (w,h) => lines, endPrompt, exitHook);
}

/// ditto
void pager(Disp)(ref Disp disp, ref InputDispatcher dispatch,
                 const(char[])[] delegate(int w, int h) fmtLines,
                 string endPrompt, void delegate() exitHook)
    if (isDisplay!Disp)
{
    auto pagerScreen(int w, int h)
    {
        auto width = min(80, w - 6);
        auto padding = (w - width) / 2;
        return subdisplay(&disp, region(vec(padding, 1),
                                        vec(w - padding, h - 1)));
    }

    auto scrn = pagerScreen(disp.width, disp.height);
    auto lines = fmtLines(scrn.width, scrn.height);
    const(char[])[] nextLines;

    void displayPage()
    {
        scrn.hideCursor();
        scrn.color(Color.black, Color.white);

        // Can't use .clear 'cos it doesn't use color we set.
        scrn.moveTo(0, 0);
        scrn.clearToEos();

        auto linesToPrint = min(scrn.height - 2, lines.length);
        auto offsetY = (scrn.height - linesToPrint - 1)/2;
        foreach (i; 0 .. linesToPrint)
        {
            // Vertically-center texts for better visual aesthetics.
            scrn.moveTo(1, i + offsetY);
            scrn.writef("%s", lines[i]);
        }
        nextLines = lines[linesToPrint .. $];

        scrn.moveTo(1, linesToPrint + offsetY + 1);
        scrn.color(Color.white, Color.blue);
        scrn.writef("%s", nextLines.length > 0 ? "[More]" : endPrompt);
        scrn.color(Color.black, Color.white);
        scrn.showCursor();
    }

    auto infoMode = Mode(
        () {
            displayPage();
        },
        (int w, int h) {
            scrn = pagerScreen(w, h);
            lines = fmtLines(scrn.width, scrn.height);
        },
        (dchar ch) {
            if (nextLines.length > 0)
            {
                lines = nextLines;
                displayPage();
            }
            else
            {
                scrn.color(Color.DEFAULT, Color.DEFAULT);
                scrn.clear();
                dispatch.pop();
                exitHook();
            }
        },
    );

    dispatch.push(infoMode);
}

/**
 * Pushes a Mode to the mode stack that prompts the player for a yes/no
 * response, and invokes the given callback with the answer.
 */
void promptYesNo(Disp)(Disp disp, ref InputDispatcher dispatch,
                       string promptStr, void delegate(bool answer) cb)
    if (isDisplay!Disp)
{
    string str = promptStr ~ " [yn] ";
    auto mode = Mode(
        {
            // FIXME: probably should be in a subdisplay?
            disp.moveTo(0, 0);
            disp.writef("%s", str);
            auto x = disp.cursorX;
            auto y = disp.cursorY;
            disp.clearToEol();
            disp.moveTo(x, y);
        },
        null,
        (dchar key) {
            switch (key)
            {
                case 'y':
                    dispatch.pop();
                    disp.moveTo(0,0);
                    disp.writef(str);
                    disp.writef("yes");
                    disp.clearToEol();
                    cb(true);
                    break;
                case 'n':
                    dispatch.pop();
                    disp.moveTo(0,0);
                    disp.writef(str);
                    disp.writef("no");
                    disp.clearToEol();
                    cb(false);
                    break;

                default:
            }
        }
    );

    dispatch.push(mode);
}

/**
 * A button on a select screen.
 */
struct SelectButton
{
    dchar[] keys;
    string label;
    bool exitOnClick;
    void delegate(size_t idx) onClick;
}

/**
 * UI to select an item from a list and perform some action on it.
 *
 * Params:
 *  inven = List of items to display.
 *  promptStr = Heading to display on inventory screen.
 *  buttons = The list of buttons to be placed on the screen.
 *  startIdx = Which item to select by default, or -1 if items cannot be
 *      selected with j/k.
 *
 * Returns: true if inventory UI mode is pushed on stack, otherwise false
 * (e.g., if inventory is empty).
 */
void selectScreen(S,R)(ref S disp, ref InputDispatcher dispatch,
                       R inven, string promptStr, SelectButton[] buttons,
                       int startIdx = 0)
    if (isDisplay!S && isRandomAccessRange!R && hasLength!R)
{
    string makeHintString()
    {
        string[] hints;
        if (startIdx >= 0)
            hints ~= "j/k:select";

        foreach (button; buttons)
        {
            hints ~= format("%-(%s,%):%s",
                            button.keys.map!(ch => ch.toPrintable),
                            button.label);
        }
        return hints.join(", ");
    }

    auto hintString = makeHintString();
    auto hintStringLen = hintString.displayLength;
    auto width = (max(2 + promptStr.displayLength, 2 + hintStringLen,
                      2 + inven.map!(item => item.displayLength)
                               .maxElement)).to!int;
    auto height = min(disp.height, 4 + inven.length.to!int +
                                   ((hintStringLen > 0) ? 2 : 0));
    auto scrnX = (disp.width - width)/2;
    auto scrnY = (disp.height - height)/2;
    auto scrn = subdisplay(&disp, region(vec(scrnX, scrnY),
                                         vec(scrnX + width, scrnY + height)));
    int curIdx = startIdx;

    SelectButton[dchar] keymap;
    foreach (button; buttons)
    {
        foreach (ch; button.keys)
            keymap[ch] = button;
    }

    auto invenMode = Mode(
        () {
            scrn.hideCursor();
            scrn.color(Color.black, Color.white);

            // Can't use .clear 'cos it doesn't use color we set.
            scrn.moveTo(0, 0);
            scrn.clearToEos();
            scrn.drawBorder(BorderStyle.thin);

            scrn.moveTo(1, 1);
            scrn.writef("%s", promptStr);

            scrn.moveTo(1, height-2);
            scrn.color(Color.blue, Color.white);
            scrn.writef(hintString);
            scrn.color(Color.black, Color.white);

            auto inner = scrn.subdisplay(region(vec(1,3),
                                                vec(width-1, height-1)));
            foreach (i; 0 .. inven.length)
            {
                inner.moveTo(0, i.to!int);

                auto fg = Color.black;
                auto bg = Color.white;
                if (i == curIdx)
                {
                    fg = Color.white;
                    bg = Color.blue;
                }

                static if (__traits(hasMember, inven[i], "render"))
                {
                    inven[i].render(inner, fg, bg);
                }
                else
                {
                    inner.color(fg, bg);
                    inner.writef("%s", inven[i].to!string);
                }
            }
        },
        (int w, int h) {
            height = min(h, 4 + inven.length.to!int +
                            ((hintStringLen > 0) ? 2 : 0));
            scrnX = (w - width)/2;
            scrnY = (h - height)/2;
            scrn = subdisplay(&disp, region(vec(scrnX, scrnY),
                                            vec(scrnX + width, scrnY + height)));
        },
        (dchar ch) {
            switch (ch)
            {
                case 'i', 'k':
                    if (curIdx > 0)
                        curIdx--;
                    break;

                case 'j', 'm':
                    if (curIdx >= 0 && curIdx + 1 < inven.length)
                        curIdx++;
                    break;

                default:
                    auto button = ch in keymap;
                    if (button is null)
                        break;

                    if (button.exitOnClick)
                    {
                        dispatch.pop();
                        disp.color(Color.DEFAULT, Color.DEFAULT);
                        disp.clear();
                    }

                    if (button.onClick)
                        button.onClick(curIdx);
                    break;
            }
        }
    );

    dispatch.push(invenMode);
}

// vim:set ai sw=4 ts=4 et:
