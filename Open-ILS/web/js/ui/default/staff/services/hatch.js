/**
 * Core Service - egHatch
 *
 * Dispatches print and data storage requests to the appropriate handler.
 *
 * With each top-level request, if a connection to Hatch is established,
 * the request is relayed.  If a connection has not been attempted, an
 * attempt is made then the request is handled.  If Hatch is known to be
 * inaccessible, requests are routed to local handlers.
 *
 * Most handlers also provide direct remote and local variants to the
 * application can decide to which to use as needed.
 *
 * Local storage requests are handled by $window.localStorage.
 *
 * Note that all top-level and remote requests return promises.  All
 * local requests return immediate values, since local requests are
 * never asynchronous.
 *
 * BEWARE: never store "fieldmapper" objects, since their structure
 * may change over time as the IDL changes.  Always flatten objects
 * into key/value pairs before calling set*Item()
 *
 */
angular.module('egCoreMod')

.factory('egHatch',
           ['$q','$window','$timeout','$interpolate','$http','$cookies',
    function($q , $window , $timeout , $interpolate , $http , $cookies) {

    var service = {};
    service.msgId = 1;
    service.messages = {};
    service.pending = [];
    service.hatchAvailable = null;
    service.cachedPrintConfig = {};
    service.state = 'IDLE'; // IDLE, INIT, CONNECTED, NO_CONNECTION

    // write a message to the Hatch port
    service.sendToHatch = function(msg) {
        var msg2 = {};

        // shallow copy and scrub msg before sending
        angular.forEach(msg, function(val, key) {
            if (key.match(/deferred/)) return;
            msg2[key] = val;
        });

        console.debug("sending to Hatch: " + JSON.stringify(msg2,null,2));

        msg2.from = 'page';
        $window.postMessage(msg2, $window.location.origin);
    }

    // Send the request to Hatch if it's available.  
    // Otherwise handle the request locally.
    service.attemptHatchDelivery = function(msg) {

        msg.msgid = service.msgId++;
        msg.deferred = $q.defer();

        if (service.state == 'NO_CONNECTION') {
            msg.deferred.reject(msg);

        } else if (service.state.match(/CONNECTED|INIT/)) {
            // Hatch is known to be open
            service.messages[msg.msgid] = msg;
            service.sendToHatch(msg);

        } else if (service.state == 'IDLE') { 
            service.messages[msg.msgid] = msg;
            service.pending.push(msg);
            $timeout(service.openHatch);
        }

        return msg.deferred.promise;
    }


    // resolve the promise on the given request and remove
    // it from our tracked requests.
    service.resolveRequest = function(msg) {

        if (!service.messages[msg.msgid]) {
            console.warn('no cached message for ' 
                + msg.msgid + ' : ' + JSON.stringify(msg, null, 2));
            return;
        }

        // for requests sent through Hatch, only the cached 
        // request will have the original promise attached
        msg.deferred = service.messages[msg.msgid].deferred;
        delete service.messages[msg.msgid]; // un-cache

        switch (service.state) {

            case 'CONNECTED': // received a standard Hatch response
                if (msg.status == 200) {
                    msg.deferred.resolve(msg.content);
                } else {
                    msg.deferred.reject();
                    console.warn("Hatch command failed with status=" 
                        + msg.status + " and message=" + msg.message);
                }
                break;

            case 'INIT':
                if (msg.status == 200) {
                    service.hatchAvailable = true; // public flag
                    service.state = 'CONNECTED';
                    service.hatchOpened();
                } else {
                    msg.deferred.reject();
                    service.hatchWontOpen(msg.message);
                }
                break;

            default:
                console.warn(
                    "Received message in unexpected state: " + service.state); 
        }
    }

    service.openHatch = function() {

        // When the Hatch extension loads, it tacks an attribute onto
        // the page body to indicate it's available.

        if (!$window.document.body.getAttribute('hatch-is-open')) {
            service.hatchWontOpen('Hatch is not available');
            return;
        }

        $window.addEventListener("message", function(event) {
            // We only accept messages from our own content script.
            if (event.source != window) return;

            // We only care about messages from the Hatch extension.
            if (event.data && event.data.from == 'extension') {

                console.debug('Hatch says: ' 
                    + JSON.stringify(event.data, null, 2));

                service.resolveRequest(event.data);
            }
        }); 

        service.state = 'INIT';
        service.attemptHatchDelivery({action : 'init'});
    }

    service.hatchWontOpen = function(err) {
        console.debug("Hatch connection failed: " + err);
        service.state = 'NO_CONNECTION';
        service.hatchAvailable = false;
        service.hatchClosed();
    }

    service.hatchClosed = function() {
        service.printers = [];
        service.printConfig = {};
        while ( (msg = service.pending.shift()) ) {
            msg.deferred.reject(msg);
            delete service.messages[msg.msgid];
        }
        if (service.onHatchClose)
            service.onHatchClose();
    }

    // Returns true if Hatch is required or if we are currently
    // communicating with the Hatch service. 
    service.usingHatch = function() {
        return service.state == 'CONNECTED' || service.hatchRequired();
    }

    // Returns true if this browser (via localStorage) is 
    // configured to require Hatch.
    service.hatchRequired = function() {
        return service.getLocalItem('eg.hatch.required');
    }

    service.hatchOpened = function() {
        // let others know we're connected
        if (service.onHatchOpen) service.onHatchOpen();

        // Deliver any previously queued requests 
        while ( (msg = service.pending.shift()) ) {
            service.sendToHatch(msg);
        };
    }

    service.remotePrint = function(
        context, contentType, content, withDialog) {

        return service.getPrintConfig(context).then(
            function(config) {
                // print configuration retrieved; print
                return service.attemptHatchDelivery({
                    action : 'print',
                    settings : config,
                    content : content, 
                    contentType : contentType,
                    showDialog : withDialog,
                });
            }
        );
    }

    // 'force' avoids using the config cache
    service.getPrintConfig = function(context, force) {
        if (service.cachedPrintConfig[context] && !force) {
            return $q.when(service.cachedPrintConfig[context])
        }
        return service.getRemoteItem('eg.print.config.' + context)
        .then(function(config) {
            return service.cachedPrintConfig[context] = config;
        });
    }

    service.setPrintConfig = function(context, config) {
        service.cachedPrintConfig[context] = config;
        return service.setRemoteItem('eg.print.config.' + context, config);
    }

    service.getPrinterOptions = function(name) {
        return service.attemptHatchDelivery({
            action : 'printer-options',
            printer : name
        });
    }

    service.getPrinters = function() {
        if (service.printers) // cached printers
            return $q.when(service.printers);

        return service.attemptHatchDelivery({action : 'printers'}).then(

            // we have remote printers; sort by name and return
            function(printers) {
                service.printers = printers.sort(
                    function(a,b) {return a.name < b.name ? -1 : 1});
                return service.printers;
            },

            // remote call failed and there is no such thing as local
            // printers; return empty set.
            function() { return [] } 
        );
    }

    // get the value for a stored item
    service.getItem = function(key) {
        return service.getRemoteItem(key)['catch'](
            function(msg) {
                if (service.hatchRequired()) {
                    console.error("Unable to getItem: " + key
                     + "; hatchRequired=true, but hatch is not connected");
                     return null;
                }
                return service.getLocalItem(msg.key);
            }
        );
    }

    service.getRemoteItem = function(key) {
        return service.attemptHatchDelivery({
            key : key,
            action : 'get'
        })
    }

    service.getLocalItem = function(key) {
        var val = $window.localStorage.getItem(key);
        if (val == null) return;
        return JSON.parse(val);
    }

    service.getLoginSessionItem = function(key) {
        var val = $cookies.get(key);
        if (val == null) return;
        return JSON.parse(val);
    }

    service.getSessionItem = function(key) {
        var val = $window.sessionStorage.getItem(key);
        if (val == null) return;
        return JSON.parse(val);
    }

    /**
     * @param tmp bool Store the value as a session cookie only.  
     * tmp values are removed during logout or browser close.
     */
    service.setItem = function(key, value) {
        return service.setRemoteItem(key, value)['catch'](
            function(msg) {
                if (service.hatchRequired()) {
                    console.error("Unable to setItem: " + key
                     + "; hatchRequired=true, but hatch is not connected");
                     return null;
                }
                return service.setLocalItem(msg.key, value);
            }
        );
    }

    // set the value for a stored or new item
    service.setRemoteItem = function(key, value) {
        return service.attemptHatchDelivery({
            key : key, 
            content : value, 
            action : 'set',
        });
    }

    // Set the value for the given key.
    // "Local" items persist indefinitely.
    // If the value is raw, pass it as 'value'.  If it was
    // externally JSONified, pass it via jsonified.
    service.setLocalItem = function(key, value, jsonified) {
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);
        $window.localStorage.setItem(key, jsonified);
    }

    // Set the value for the given key.  
    // "LoginSession" items are removed when the user logs out or the 
    // browser is closed.
    // If the value is raw, pass it as 'value'.  If it was
    // externally JSONified, pass it via jsonified.
    service.setLoginSessionItem = function(key, value, jsonified) {
        service.addLoginSessionKey(key);
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);
        $cookies.put(key, jsonified);
    }

    // Set the value for the given key.  
    // "Session" items are browser tab-specific and are removed when the
    // tab is closed.
    // If the value is raw, pass it as 'value'.  If it was
    // externally JSONified, pass it via jsonified.
    service.setSessionItem = function(key, value, jsonified) {
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);
        $window.sessionStorage.setItem(key, jsonified);
    }

    // assumes the appender and appendee are both strings
    // TODO: support arrays as well
    service.appendLocalItem = function(key, value) {
        var item = service.getLocalItem(key);
        if (item) {
            if (typeof item != 'string') {
                logger.warn("egHatch.appendLocalItem => "
                    + "cannot append to a non-string item: " + key);
                return;
            }
            value = item + value; // concatenate our value
        }
        service.setLocalitem(key, value);
    }

    // remove a stored item
    service.removeItem = function(key) {
        return service.removeRemoteItem(key)['catch'](
            function(msg) { 
                return service.removeLocalItem(msg.key) 
            }
        );
    }

    service.removeRemoteItem = function(key) {
        return service.attemptHatchDelivery({
            key : key,
            action : 'remove'
        });
    }

    service.removeLocalItem = function(key) {
        $window.localStorage.removeItem(key);
    }

    service.removeLoginSessionItem = function(key) {
        service.removeLoginSessionKey(key);
        $cookies.remove(key);
    }

    service.removeSessionItem = function(key) {
        $window.sessionStorage.removeItem(key);
    }

    /**
     * Remove all "LoginSession" items.
     */
    service.clearLoginSessionItems = function() {
        angular.forEach(service.getLoginSessionKeys(), function(key) {
            service.removeLoginSessionItem(key);
        });

        // remove the keys cache.
        service.removeLocalItem('eg.hatch.login_keys');
    }

    // if set, prefix limits the return set to keys starting with 'prefix'
    service.getKeys = function(prefix) {
        return service.getRemoteKeys(prefix)['catch'](
            function() { 
                if (service.hatchRequired()) {
                    console.error("Unable to get pref keys; "
                     + "hatchRequired=true, but hatch is not connected");
                     return [];
                }
                return service.getLocalKeys(prefix) 
            }
        );
    }

    service.getRemoteKeys = function(prefix) {
        return service.attemptHatchDelivery({
            key : prefix,
            action : 'keys'
        });
    }

    service.getLocalKeys = function(prefix) {
        var keys = [];
        var idx = 0;
        while ( (k = $window.localStorage.key(idx++)) !== null) {
            // key prefix match test
            if (prefix && k.substr(0, prefix.length) != prefix) continue; 
            keys.push(k);
        }
        return keys;
    }


    /**
     * Array of "LoginSession" keys.
     * Note we have to store these as "Local" items so browser tabs can
     * share them.  We could store them as cookies, but it's more data
     * that has to go back/forth to the server.  A "LoginSession" key name is
     * not private, though, so it's OK if they are left in localStorage
     * until the next login.
     */
    service.getLoginSessionKeys = function(prefix) {
        var keys = [];
        var idx = 0;
        var login_keys = service.getLocalItem('eg.hatch.login_keys') || [];
        angular.forEach(login_keys, function(k) {
            // key prefix match test
            if (prefix && k.substr(0, prefix.length) != prefix) return;
            keys.push(k);
        });
        return keys;
    }

    service.addLoginSessionKey = function(key) {
        var keys = service.getLoginSessionKeys();
        if (keys.indexOf(key) < 0) {
            keys.push(key);
            service.setLocalItem('eg.hatch.login_keys', keys);
        }
    }

    service.removeLoginSessionKey = function(key) {
        var keys = service.getLoginSessionKeys().filter(function(k) {
            return k != key;
        });
        service.setLocalItem('eg.hatch.login_keys', keys);
    }

    return service;
}])

