/**
 * Various UDAs for entity store objects.
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
module store_traits;

/**
 * UDA to identify component types.
 */
enum Component;

/**
 * UDA to mark components that upon load, needs entries filtered by _filter
 * from the old table to be merged into the new table.
 *
 * Typically, this UDA is used along with loadsave.SaveFilter (with a
 * complementary filter) for skipping over special entities during save and
 * copying them over from a preinitialized Store during load.
 */
struct MergeOnLoad(alias _filter)
{
    alias filter = _filter;
}

/**
 * UDA to mark components that have an additional index mapping an instance of
 * the component to a list of ThingIds.
 *
 * Components marked with this UDA will have an additional .getAllBy method in
 * the Store that can be used to lookup ThingIds by component instances.
 */
struct Indexed { }

/**
 * UDA to mark components that have an additional list tracking new entries.
 *
 * The intended usage is for systems that need to be informed of new entities
 * that have acquired the component since the last check.
 *
 * Components marked with this UDA will have additional .getAllNew and
 * .clearNew methods in the Store for accessing ThingId's that have recently
 * acquired the component.
 */
struct TrackNew { }

// vim: set ts=4 sw=4 et ai:
