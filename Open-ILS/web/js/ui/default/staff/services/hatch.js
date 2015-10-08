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
           ['$q','$window','$timeout','$interpolate','$http',
    function($q , $window , $timeout , $interpolate , $http) {

    var service = {};
    service.msgId = 0;
    service.messages = {};
    service.pending = [];
    service.socket = null;
    service.hatchAvailable = null;
    service.defaultHatchURL = 'wss://localhost:8443/hatch'; 

    // write a message to the Hatch websocket
    service.sendToHatch = function(msg) {
        var msg2 = {};

        // shallow copy and scrub msg before sending
        angular.forEach(msg, function(val, key) {
            if (key.match(/deferred/)) return;
            msg2[key] = val;
        });

        console.debug("sending to Hatch: " + JSON.stringify(msg2,null,2));
        service.socket.send(JSON.stringify(msg2));
    }

    // Send the request to Hatch if it's available.  
    // Otherwise handle the request locally.
    service.attemptHatchDelivery = function(msg) {

        msg.msgid = service.msgId++;
        msg.deferred = $q.defer();

        if (service.hatchAvailable === false) { // Hatch is closed
            msg.deferred.reject(msg);

        } else if (service.hatchAvailable === true) { // Hatch is open
            // Hatch is known to be open
            service.messages[msg.msgid] = msg;
            service.sendToHatch(msg);

        } else {  // Hatch status unknown; attempt to connect
            service.messages[msg.msgid] = msg;
            service.pending.push(msg);
            service.hatchConnect();
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

        // resolve / reject
        if (msg.error) {
            throw new Error(
            "egHatch command failed : " 
                + JSON.stringify(msg.error, null, 2));
        } else {
            msg.deferred.resolve(msg.content);
        } 
    }

    service.hatchClosed = function() {
        service.socket = null;
        service.printers = [];
        service.printConfig = {};
        while ( (msg = service.pending.shift()) ) {
            msg.deferred.reject(msg);
            delete service.messages[msg.msgid];
        }
        if (service.onHatchClose)
            service.onHatchClose();
    }

    service.hatchURL = function() {
        return service.getLocalItem('eg.hatch.url') 
            || service.defaultHatchURL;
    }

    // Returns true if Hatch is required or if we are currently
    // communicating with the Hatch service. 
    service.usingHatch = function() {
        return service.hatchAvailable || service.hatchRequired();
    }

    // Returns true if this browser (via localStorage) is 
    // configured to require Hatch.
    service.hatchRequired = function() {
        return service.getLocalItem('eg.hatch.required');
    }

    service.hatchConnect = function() {

        if (service.socket && 
            service.socket.readyState == service.socket.CONNECTING) {
            // connection in progress.  Nothing to do.  Our queued
            // message will be delivered when onopen() fires
            return;
        }

        try {
            service.socket = new WebSocket(service.hatchURL());
        } catch(e) {
            service.hatchAvailable = false;
            service.hatchClosed();
            return;
        }

        service.socket.onopen = function() {
            console.debug('connected to Hatch');
            service.hatchAvailable = true;
            if (service.onHatchOpen) 
                service.onHatchOpen();
            while ( (msg = service.pending.shift()) ) {
                service.sendToHatch(msg);
            };
        }

        service.socket.onclose = function() {
            if (service.hatchAvailable === false) return; // already registered

            // onclose() will be called regularly as we disconnect from
            // Hatch via timeouts.  Return hatchAvailable to its unknow state
            service.hatchAvailable = null;
            service.hatchClosed();
        }

        service.socket.onerror = function() {
            if (service.hatchAvailable === false) return; // already registered
            service.hatchAvailable = false;
            console.debug(
                "unable to connect to Hatch server at " + service.hatchURL());
            service.hatchClosed();
        }

        service.socket.onmessage = function(evt) {
            var msgStr = evt.data;
            if (!msgStr) throw new Error("Hatch returned empty message");

            var msgObj = JSON.parse(msgStr);
            console.debug('Hatch says ' + JSON.stringify(msgObj, null, 2));
            service.resolveRequest(msgObj); 
        }
    }

    service.getPrintConfig = function() {
        if (service.printConfig) 
            return $q.when(service.printConfig);

        return service.getRemoteItem('eg.print.config')
        .then(function(conf) { 
            return (service.printConfig = conf || {}) 
        });
    }

    service.setPrintConfig = function(conf) {
        service.printConfig = conf;
        return service.setRemoteItem('eg.print.config', conf);
    }


    service.remotePrint = function(
        context, contentType, content, withDialog) {

        return service.getPrintConfig().then(
            function(conf) {
                // print configuration retrieved; print
                return service.attemptHatchDelivery({
                    action : 'print',
                    config : conf[context],
                    content : content, 
                    contentType : contentType,
                    showDialog : withDialog,
                });
            }
        );
    }

    // launch the print dialog then attach the resulting configuration
    // to the requested context, then store the final values.
    service.configurePrinter = function(context, printer) {

        // load current settings
        return service.getPrintConfig()

        // dispatch the print configuration request
        .then(function(config) {

            // loaded remote config
            if (!config[context]) config[context] = {};
            config[context].printer = printer;
            return service.attemptHatchDelivery({
                key : 'no-op', 
                action : 'print-config',
                config : config[context]
            })
        })

        // set the returned settings to the requested context
        .then(function(newconf) {
            if (angular.isObject(newconf)) {
                newconf.printer = printer;
                return service.printConfig[context] = newconf;
            } else {
                console.warn("configurePrinter() returned " + newconf);
            }
        })

        // store the newly linked settings
        .then(function() {
            service.setItem('eg.print.config', service.printConfig);
        })

        // return the final settings to the caller
        .then(function() {return service.printConfig});
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
            action : 'get', 
        });
    }

    service.getLocalItem = function(key) {
        var val = $window.localStorage.getItem(key);
        if (val == null) return;
        return JSON.parse(val);
    }

    service.getSessionItem = function(key) {
        var val = $window.sessionStorage.getItem(key);
        if (val == null) return;
        return JSON.parse(val);
    }

    service.setItem = function(key, value) {
        var str = JSON.stringify(value);
        return service.setRemoteItem(key, str)['catch'](
            function(msg) {
                if (service.hatchRequired()) {
                    console.error("Unable to setItem: " + key
                     + "; hatchRequired=true, but hatch is not connected");
                     return null;
                }
                return service.setLocalItem(msg.key, null, str);
            }
        );
    }

    // set the value for a stored or new item
    service.setRemoteItem = function(key, value) {
        return service.attemptHatchDelivery({
            key : key, 
            value : value, 
            action : 'set',
        });
    }

    // Set the value for the given key
    // If the value is raw, pass it as 'value'.  If it was
    // externally JSONified, pass it via jsonified.
    service.setLocalItem = function(key, value, jsonified) {
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);
        $window.localStorage.setItem(key, jsonified);
    }

    service.setSessionItem = function(key, value, jsonified) {
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);
        $window.sessionStorage.setItem(key, jsonified);
    }

    // appends the value to the existing item stored at key.
    // If not item is found at key, this behaves just like setItem()
    service.appendItem = function(key, value) {
        return service.appendRemoteItem(key, value)['catch'](
            function(msg) {
                if (service.hatchRequired()) {
                    console.error("Unable to appendItem: " + key
                     + "; hatchRequired=true, but hatch is not connected");
                     return null;
                }
                service.appendLocalItem(msg.key, msg.value);
            }
        );
    }

    service.appendRemoteItem = function(key, value) {
        return service.attemptHatchDelivery({
            key : key, 
            value : value, 
            action : 'append',
        });
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

    service.removeSessionItem = function(key) {
        $window.sessionStorage.removeItem(key);
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

    return service;
}])

