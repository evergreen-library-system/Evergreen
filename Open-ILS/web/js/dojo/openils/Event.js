/* ---------------------------------------------------------------------------
 * Copyright (C) 2008  Georgia Public Library Service
 * Bill Erickson <erickson@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource["openils.Event"]) {

    dojo._hasResource["openils.Event"] = true;
    dojo.provide("openils.Event");
    dojo.declare('openils.Event', null, {

        constructor : function(kwargs) {
            this.code = kwargs.ilsevent;
            this.textcode = kwargs.textcode;
            this.desc = kwargs.desc;
            this.payload = kwargs.payload;
            this.debug = kwargs.stacktrace;
            this.servertime = kwargs.servertime;
            this.ilsperm = kwargs.ilsperm;
            this.ilspermloc = kwargs.ilspermloc;
        },

        toString : function() {
            var s = 'Event: ' + (this.code || '') + ':' + this.textcode + ' -> ' + new String(this.desc);
            if(this.ilsperm)
                s += ' ' + this.ilsperm + '@' + this.ilspermloc;
            return s;
        }
    });

    /**
     * Parses a proposed event object.  If this object is an
     * event, a new openils.Event is returned.  Otherwise,
     * null is returned
     */
    openils.Event.parse = function(evt) {
        if(evt && typeof evt == 'object' && 'ilsevent' in evt && 'textcode' in evt)
            return new openils.Event(evt);
        return null;
    }

    /**
     * If the provided object is a non-success event, the
     * event is thrown as an exception.
     */
    openils.Event.parse_and_raise = function(evt) {
        var e = openils.Event.parse(evt);
        if(e && e.ilsevent != 0)    
            throw e;
    }
}
