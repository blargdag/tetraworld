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
 * Unique global ID for game objects.
 */
alias ThingId = ulong;

/**
 * Indicates invalid or missing global ID.
 */
enum invalidId = 0;

/**
 * The number of ThingId's reserved for terrain objects.
 *
 * All terrains will have fixed IDs between 1 and this number (exclusive), and
 * all non-terrain objects will have IDs above this number.
 */
enum terrainMaxId = 256;

/**
 * First ThingId not reserved for special purposes.
 *
 * IDs below this one serve a special purpose, such as IDs shared by terrain
 * tiles, built-in objects with hard-coded IDs, etc..
 */
enum specialMaxId = 1024;

/**
 * UDA to identify component types.
 */
enum Component;

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
