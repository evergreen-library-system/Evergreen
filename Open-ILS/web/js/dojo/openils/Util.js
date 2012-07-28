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
    dojo.require("dojo.date.locale");
    dojo.require("dojo.date.stamp");
    dojo.require('openils.Event');
    dojo.declare('openils.Util', null, {});


    openils.Util.timeStampRegexp =
        /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[\+-]\d{2})(\d{2})$/;

    openils.Util.timeStampAsDateObj = function(s) {
        if (s.constructor.name == "Date") return s;
        return dojo.date.stamp.fromISOString(
            s.replace(openils.Util.timeStampRegexp, "$1:$2")
        );
    }

    /**
     * Returns a locale-appropriate representation of a timestamp when the
     * timestamp (first argument) is actually a string as provided by
     * fieldmapper objects.
     * The second argument is an optional argument that will be provided
     * as the second argument to dojo.date.locale.format()
     */
    openils.Util.timeStamp = function(s, opts) {
        if (typeof(opts) == "undefined") opts = {};

        return dojo.date.locale.format(
            openils.Util.timeStampAsDateObj(s), opts
        );
    };

    openils.Util._userFullNameFields = [
        "prefix", "first_given_name", "second_given_name",
        "family_name", "suffix", "alias", "usrname"
    ];

    /**
     * Return an array of all the name-related attributes, with nulls replaced
     * by empty strings, from a given actor.usr fieldmapper object, to be used
     * as the arguments to any string formatting function that wants them.
     * Code to do this is duplicated all over the place and should be
     * simplified as we go.
     */
    openils.Util.userFullName = function(user) {
        return dojo.map(
            openils.Util._userFullNameFields,
            function(a) { return user[a]() || ""; }
        );
    };

    /**
     * Same as openils.Util.userFullName, but with a hash of results instead
     * of an array (dojo.string.substitute(), for example, can use this too).
     */
    openils.Util.userFullNameHash = function(user) {
        var hash = {};
        dojo.forEach(
            openils.Util._userFullNameFields,
            function(a) { hash[a] = user[a]() || ""; }
        );
        return hash;
    };

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
            if(eventOk || e.textcode == 'SUCCESS') return e;
            console.log(e.toString());

            // session timed out.  Stop propagation of requests queued by Util.onload 
            // and launch the XUL login dialog if possible
            var retryLogin = false;
            if(e.textcode == 'NO_SESSION') {
                openils.User.authtoken = null; 
                if(openils.XUL.isXUL()) {
                    retryLogin = true;
                    openils.XUL.getNewSession( function() { location.href = location.href } );
                } else {
                    // TODO: make the oilsLoginDialog templated via dojo so it can be 
                    // used as a standalone widget
                }
            }

            if(openils.Util.alertEvent && !retryLogin)
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
            if (typeof(cls) == "object") { /* assume regex */
                if (!cls.test(classList[i])) {
                    if(i == 0)
                        className = classList[i];
                    else
                        className += ' ' + classList[i];
                }
            } else {
                if (classList[i] != cls) {
                    if(i == 0)
                        className = classList[i];
                    else
                        className += ' ' + classList[i];
                }
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
     * Convenience function to trim leading and trailing whitespace at once.
     */
    openils.Util.trimString = function(s) {
        return s.replace(/^\s*(.+)?\s*$/,"$1");
    }

    /**
     * Assume a space-separated interval string, with optional comma
     * E.g. "1 year, 2 days"  "3 days 6 hours"
     */
    openils.Util.intervalToSeconds = function(interval) {
        var d = new Date();
        var start = d.getTime();
        var parts = interval.split(' ');
        for(var i = 0; i < parts.length; i += 2)  {
            var type = parts[i+1].replace(/s?,?$/,'');
            switch(type) {
                case 'mon': // postgres
                    type = 'month'; // dojo
                    break;
                // add more as necessary
            }

            d = dojo.date.add(d, type, Number(parts[i]));
        }
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

    /**
     * Plays a sound file via URL.  Only works with browsers
     * that support HTML 5 <audio> element.  E.g. Firefox 3.5
     */
    openils.Util.playAudioUrl = function(urlString) {
        if(!urlString) return;
        var audio = document.createElement('audio');
        audio.setAttribute('src', urlString);
        audio.setAttribute('autoplay', 'true');
        document.body.appendChild(audio);
        document.body.removeChild(audio);
    }

    /**
     * Return the properties of an object as a list. Saves typing.
     */
    openils.Util.objectProperties = function(obj) {
        var K = [];
        for (var k in obj) K.push(k);
        return K;
    }

    /**
     * Return the values of an object as a list. There may be a Dojo
     * idiom or something that makes this redundant. Check into that.
     */
    openils.Util.objectValues = function(obj) {
        var V = [];
        for (var k in obj) V.push(obj[k]);
        return V;
    }

    openils.Util.uniqueElements = function(L) {
        var o = {};
        for (var k in L) o[L[k]] = true;
        return openils.Util.objectProperties(o);
    }

    openils.Util.uniqueObjects = function(list, field) {
        var sorted = openils.Util.objectSort(list, field);
        var results = [];
        for (var i = 0; i < sorted.length; i++) {
            if (!i || (sorted[i][field]() != sorted[i-1][field]()))
                results.push(sorted[i]);
        }
        return results;
    };

    /**
     * Highlight instances of each pattern in the given DOM node
     * Inspired by the jquery plugin
     * http://johannburkard.de/blog/programming/javascript/highlight-javascript-text-higlighting-jquery-plugin.html
     */
    openils.Util.hilightNode = function(node, patterns, args) {

        args = args ||{};
        var hclass = args.classname || 'oils-highlight';

        function _hilightNode(node, pat) {

            if(node.nodeType == 3) { 

                pat = pat.toUpperCase();
                var text = node.data.toUpperCase();
                var pos = -1;

                // find each instance of pat in the current node
                while( (pos =  text.indexOf(pat, pos + 1)) >= 0 ) {

                    var wrapper = dojo.create('span', {className : hclass});
                    var midnode = node.splitText(pos);
                    midnode.splitText(pat.length);
                    wrapper.appendChild(midnode.cloneNode(true));
                    midnode.parentNode.replaceChild(wrapper, midnode);
                }

            } else if(node.nodeType == 1 && node.childNodes[0]) {

                // not a text node?  have you checked the children?
                dojo.forEach(
                    node.childNodes,
                    function(child) { _hilightNode(child, pat); }
                );
            }
        }

        // descend the tree for each pattern, since nodes are changed during highlighting
        dojo.forEach(patterns, function(pat) { _hilightNode(node, pat); });
    };

    openils.Util._legacyModulePaths = {};
    /*****
     * Take the URL of a JS file and magically turn it into something that
     * dojo.require can load by registering a module path for it ... and load it.
     *****/
    openils.Util.requireLegacy = function(url) {
        var bURL = url.replace(/\/[^\/]+$/,'');
        var file = url.replace(/^.*\/([^\/]+)$/,'$1');
        var libname = url.replace(/^.*?\/(.+)\/[^\/]+$/,'$1').replace(/[^a-z]/ig,'_');
        var modname = libname + '.' + file.replace(/\.js$/,'');

        if (!openils.Util._legacyModulePaths[libname]) {
            dojo.registerModulePath(libname,bURL);
            openils.Util._legacyModulePaths[libname] = {};
        }

        if (!openils.Util._legacyModulePaths[libname][modname]) {
            dojo.require(modname, true);
            openils.Util._legacyModulePaths[libname][modname] = true;
        }

        return openils.Util._legacyModulePaths[libname][modname];
    };

    /**
     * Takes a chunk of HTML, inserts it into a new window, prints the window, 
     * then closes the windw.  To provide ample printer queueing time, automatically
     * wait a short time before closing the window after calling .print().  The amount
     * of time to wait is based on the size of the data to be printed.
     * @param html The HTML string
     * @param callback Optional post-printing callback
     */
    openils.Util.printHtmlString = function(html, callback) {

        var win = window.open('', 'Print Window', 'resizable,width=800,height=600,scrollbars=1,chrome'); 

        // force the new window to the background
        win.blur(); 
        window.focus(); 

        win.document.body.innerHTML = html;
        win.print();

        setTimeout(
            function() { 
                win.close();
                if(callback)
                    callback();
            },
            // 1k == 1 second pause, max 10 seconds
            Math.min(html.length, 10000)
        );
    };

}

