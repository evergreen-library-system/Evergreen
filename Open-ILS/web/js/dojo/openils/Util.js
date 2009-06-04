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


/**
 * General purpose, static utility functions
 */

if(!dojo._hasResource["openils.Util"]) {
    dojo._hasResource["openils.Util"] = true;
    dojo.provide("openils.Util");
    dojo.require('openils.Event');
    dojo.declare('openils.Util', null, {});


    /**
     * Wrapper for dojo.addOnLoad that verifies a valid login session is active
     * before adding the function to the onload set
     */
    openils.Util.addOnLoad = function(func, noSes) {
        if(func) {
            if(!noSes) {
                dojo.require('openils.User');
                if(!openils.User.authtoken) 
                    return;
            }
            console.log("adding onload " + func.name);
            dojo.addOnLoad(func);
        }
    };

    /**
     * Returns true if the provided array contains the specified value
     */
    openils.Util.arrayContains = function(arr, val) {
        for(var i = 0; arr && i < arr.length; i++) {
            if(arr[i] == val)
                return true;
        }
        return false;
    };

    /**
     * Given a HTML select object, returns the currently selected value
     */
    openils.Util.selectorValue = function(sel) {
        if(!sel) return null;
        var idx = sel.selectedIndex;
        if(idx < 0) return null;
        var o = sel.options[idx];
        var v = o.value; 
        if(v == null) v = o.innerHTML;
        return v;
    }

    /**
     * Returns the character code of the provided (or current window) event
     */
    openils.Util.getCharCode = function(evt) {
        evt = (evt) ? evt : ((window.event) ? event : null); 
        if(evt) {
            return (evt.charCode ? evt.charCode : 
                ((evt.which) ? evt.which : evt.keyCode ));
        } else { return -1; }
    }


    /**
     * Registers a handler for when the Enter key is pressed while 
     * the provided DOM node has focus.
     */
    openils.Util.registerEnterHandler = function(domNode, func) {
	    if(!(domNode && func)) return;
	    domNode.onkeydown = function(evt) {
            var code = openils.Util.getCharCode(evt);
            if(code == 13 || code == 3) 
                func();
        }
	}


    /**
     * Parses opensrf response objects to see if they contain 
     * data and/or an ILS event.  This only calls request.recv()
     * once, so in a streaming context, it's necessary to loop on
     * this method. 
     * @param r The OpenSRF Request object
     * @param eventOK If true, any found events will be returned as responses.  
     * If false, they will be treated as error conditions and their content will
     * be alerted if openils.Util.alertEvent is set to true.  Also, if eventOk is
     * false, the response content will be null when an event is encountered.
     * @param isList If true, assume the response will be a list of data and
     * check the 1st item in the list for event-ness instead of the list itself.
     */
    openils.Util.alertEvent = true;
    openils.Util.readResponse = function(r, eventOk, isList) {
        var msg = r.recv();
        if(msg == null) return msg;
        var val = msg.content();
        var testval = val;
        if(isList && dojo.isArray(val))
            testval = val[0];
        if(e = openils.Event.parse(testval)) {
            if(eventOk) return e;
            console.log(e.toString());
            if(openils.Util.alertEvent)
                alert(e);
            return null;
        }
        return val;
    };


    /**
     * Given a DOM node, adds the provided class to the node 
     */
    openils.Util.addCSSClass = function(node, cls) {
        if(!(node && cls)) return; 
        var className = node.className;

        if(!className) {
            node.className = cls;
            return;
        }

        var classList = className.split(/\s+/);
        var newName = '';
            
        for (var i = 0; i < classList.length; i++) {
            if(classList[i] == cls) return;
            if(classList[i] != null)
                newName += classList[i] + " ";
        }

        newName += cls;
        node.className = newName;
    },

    /**
     * Given a DOM node, removes the provided class from the CSS class 
     * name list.
     */
    openils.Util.removeCSSClass = function(node, cls) {
        if(!(node && cls && node.className)) return;
        var classList = node.className.split(/\s+/);
        var className = '';
        for(var i = 0; i < classList.length; i++) {
            if (classList[i] != cls) {
                if(i == 0)
                    className = classList[i];
                else 
                    className += ' ' + classList[i];
            }
        }
        node.className = className;
    }

    openils.Util.objectSort = function(list, field) {
        if(dojo.isArray(list)) {
            if(!field) field = 'id';
            return list.sort(
                function(a, b) {
                    if(a[field]() > b[field]()) return 1;
                    return -1;
                }
            );
        }
        return [];
    };

    openils.Util.isTrue = function(val) {
        return (val && val != '0' && !(val+'').match(/^f$/i));
    };

    /**
     * Turns a list into a mapped object.
     * @param list The list
     * @param pkey The field to use as the map key 
     * @param isFunc If true, the map key field is an accessor function 
     * that will return the value of the map key
     */
    openils.Util.mapList = function(list, pkey, isFunc) {
        if(!(list && pkey)) 
            return null;
        var map = {};
        for(var i in list) {
            if(isFunc)
                map[list[i][pkey]()] = list[i];
            else
                map[list[i][pkey]] = list[i];
        }
        return map;
    };

    /**
     * Assume a space-separated interval string, with optional comma
     * E.g. "1 year, 2 days"  "3 days 6 hours"
     */
    openils.Util.intervalToSeconds = function(interval) {
        var d = new Date();
        var start = d.getTime();
        var parts = interval.split(' ');
        for(var i = 0; i < parts.length; i += 2) 
            d = dojo.date.add(d, parts[i+1].replace(/s?,?$/,''), Number(parts[i]));
        return Number((d.getTime() - start) / 1000);
    };

    openils.Util.hide = function(node) {
        if(typeof node == 'string')
            node = dojo.byId(node);
        dojo.style(node, 'display', 'none');
        dojo.style(node, 'visibility', 'hidden');
    };

    openils.Util.show = function(node, displayType) {
        if(typeof node == 'string')
            node = dojo.byId(node);
        displayType = displayType || 'block';
        dojo.style(node, 'display', displayType);
        dojo.style(node, 'visibility', 'visible');
    };

    /** Toggles the display using show/hide, depending on the current value for CSS 'display' */
    openils.Util.toggle = function(node, displayType) {
        if(typeof node == 'string')
            node = dojo.byId(node);
        if(dojo.style(node, 'display') == 'none')
            openils.Util.show(node, displayType);
        else
            openils.Util.hide(node);
    };

    openils.Util.appendClear = function(node, child) {
        if(typeof node == 'string')
            node = dojo.byId(node);
        while(node.childNodes[0])
            node.removeChild(node.childNodes[0]);
        node.appendChild(child);
    };

}

