/**
 * TUI module
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
module tui;

import arsd.terminal;
import display;
import ui;
import widgets : UiEvent; // FIXME, should be split

class TerminalUiBackend : UiBackend
{
    private Terminal* _term;
    private DisplayObject wrappedterm;
    private RealTimeConsoleInput* input;

    this()
    {
        _term = new Terminal(ConsoleOutputType.cellular);
        wrappedterm = displayObject(_term);
        input = new RealTimeConsoleInput(_term,
            ConsoleInputFlags.raw | ConsoleInputFlags.size);
    }

    ~this() { quit(); }

    override DisplayObject term() { return wrappedterm; }

    override dchar getch() { return input.getch(); }

    override UiEvent nextEvent()
    {
        UiEvent result;
        do
        {
            auto event = input.nextEvent();
            switch (event.type)
            {
                case InputEvent.Type.KeyboardEvent:
                    auto ev = event.get!(InputEvent.Type.KeyboardEvent);
                    result.type = UiEvent.Type.kbd;
                    result.key = ev.which;
                    return result;

                case InputEvent.Type.SizeChangedEvent:
                    auto ev = event.get!(InputEvent.Type.SizeChangedEvent);
                    result.type = UiEvent.Type.resize;
                    result.newWidth = ev.newWidth;
                    result.newHeight = ev.newHeight;
                    return result;

                default:
                    // TBD
                    break;
            }
        } while(true);
    }

    override void sleep(int msecs)
    {
        import core.thread : Thread;
        import core.time : dur;
        Thread.sleep(dur!"msecs"(msecs));
    }

    void quit()
    {
        if (_term)
        {
            destroy(*_term);
            _term = null;
            wrappedterm = null;
        }
        if (input)
        {
            destroy(*input);
            input = null;
        }
    }
}

/**
 * Initializes and runs the given code with the console terminal backend.
 */
T runTerminalBackend(T, Args...)(T function(UiBackend, Args) cb, Args args)
{
    auto uiBackend = new TerminalUiBackend;
    scope(exit) uiBackend.quit();

    return cb(uiBackend, args);
}

// vim:set ai sw=4 ts=4 et:
