/**
 * Core Service - egHatch
 *
 * Dispatches print and data storage requests to the appropriate handler.
 *
 * If Hatch is configured to honor the request -- current request types
 * are 'settings', 'offline', and 'printing' -- the request will be
 * relayed to the Hatch service.  Otherwise, the request is handled
 * locally.
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
    service.hatchAvailable = false;

    // key/value cache -- avoid unnecessary Hatch extension requests.
    // Only affects *RemoteItem calls.
    service.keyCache = {}; 

    /**
     * List string prefixes for On-Call storage keys. On-Call keys
     * are those that can be set/get/remove'd from localStorage when
     * Hatch is not avaialable, even though Hatch is configured as the
     * primary storage location for the key in question.  On-Call keys
     * are those that allow the user to login and perform basic admin
     * tasks (like disabling Hatch) even when Hatch is down.
     * AKA Browser Staff Run Level 3.
     * Note that no attempt is made to synchronize data between Hatch
     * and localStorage for On-Call keys.  Only one destation is active 
     * at a time and each maintains its own data separately.
     */
    service.onCallPrefixes = ['eg.workstation'];

    // Returns true if the key can be set/get in localStorage even when 
    // Hatch is not available.
    service.keyIsOnCall = function(key) {
        var oncall = false;
        angular.forEach(service.onCallPrefixes, function(pfx) {
            if (key.match(new RegExp('^' + pfx))) 
                oncall = true;
        });
        return oncall;
    }

    // write a message to the Hatch port
    service.sendToHatch = function(msg) {
        var msg2 = {};

        // shallow copy and scrub msg before sending
        angular.forEach(msg, function(val, key) {
            if (key.match(/deferred/)) return;
            msg2[key] = val;
        });

        console.debug("sending to Hatch: " + JSON.stringify(msg2));

        msg2.from = 'page';
        $window.postMessage(msg2, $window.location.origin);
    }

    // Send request to Hatch or reject if Hatch is unavailable
    service.attemptHatchDelivery = function(msg) {
        msg.msgid = service.msgId++;
        msg.deferred = $q.defer();

        if (service.hatchAvailable) {
            service.messages[msg.msgid] = msg;
            service.sendToHatch(msg);

        } else {
            console.error(
                'Hatch request attempted but Hatch is not available');
            msg.deferred.reject(msg);
        }

        return msg.deferred.promise;
    }


    // resolve the promise on the given request and remove
    // it from our tracked requests.
    service.resolveRequest = function(msg) {

        if (!service.messages[msg.msgid]) {
            console.error('no cached message for id = ' + msg.msgid);
            return;
        }

        // for requests sent through Hatch, only the cached 
        // request will have the original promise attached
        msg.deferred = service.messages[msg.msgid].deferred;
        delete service.messages[msg.msgid]; // un-cache

        if (msg.status == 200) {
            msg.deferred.resolve(msg.content);
        } else {
            console.warn("Hatch command failed with status=" 
                + msg.status + " and message=" + msg.message);
            msg.deferred.reject();
        }
    }

    service.openHatch = function() {

        // When the Hatch extension loads, it tacks an attribute onto
        // the top-level documentElement to indicate it's available.
        if (!$window.document.documentElement.getAttribute('hatch-is-open')) {
            console.debug("Hatch is not available");
            return;
        }

        $window.addEventListener("message", function(event) {
            // We only accept messages from our own content script.
            if (event.source != window) return;

            // We only care about messages from the Hatch extension.
            if (event.data && event.data.from == 'extension') {

                // Avoid logging full Hatch responses. they can get large.
                console.debug(
                    'Hatch responded to message ID ' + event.data.msgid);

                service.resolveRequest(event.data);
            }
        }); 

        service.hatchAvailable = true; // public flag
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

    service.getPrintConfig = function(context) {
        return service.getRemoteItem('eg.print.config.' + context);
    }

    service.setPrintConfig = function(context, config) {
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

    service.usePrinting = function() {
        return service.getLocalItem('eg.hatch.enable.printing');
    }

    service.useSettings = function() {
        return service.getLocalItem('eg.hatch.enable.settings');
    }

    service.useOffline = function() {
        return service.getLocalItem('eg.hatch.enable.offline');
    }

    // get the value for a stored item
    service.getItem = function(key) {

        if (!service.useSettings())
            return $q.when(service.getLocalItem(key));

        if (service.hatchAvailable) 
            return service.getRemoteItem(key);

        if (service.keyIsOnCall(key)) {
            console.warn("Unable to getItem from Hatch: " + key + 
                ". Retrieving item from local storage instead");

            return $q.when(service.getLocalItem(key));
        }

        console.error("Unable to getItem from Hatch: " + key);
        return $q.reject();
    }

    service.getRemoteItem = function(key) {
        
        if (service.keyCache[key] != undefined)
            return $q.when(service.keyCache[key])

        return service.attemptHatchDelivery({
            key : key,
            action : 'get'
        }).then(function(content) {
            return service.keyCache[key] = content;
        });
    }

    service.getLocalItem = function(key) {
        var val = $window.localStorage.getItem(key);
        if (val == null) return;
        try {
            return JSON.parse(val);
        } catch(E) {
            console.error(
                "Deleting invalid JSON for localItem: " + key + " => " + val);
            service.removeLocalItem(key);
            return null;
        }
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
        if (!service.useSettings())
            return $q.when(service.setLocalItem(key, value));

        if (service.hatchAvailable)
            return service.setRemoteItem(key, value);

        if (service.keyIsOnCall(key)) {
            console.warn("Unable to setItem in Hatch: " + 
                key + ". Setting in local storage instead");

            return $q.when(service.setLocalItem(key, value));
        }

        console.error("Unable to setItem in Hatch: " + key);
        return $q.reject();
    }

    // set the value for a stored or new item
    service.setRemoteItem = function(key, value) {
        service.keyCache[key] = value;
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

    // remove a stored item
    service.removeItem = function(key) {
        if (!service.useSettings())
            return $q.when(service.removeLocalItem(key));

        if (service.hatchAvailable) 
            return service.removeRemoteItem(key);

        if (service.keyIsOnCall(key)) {
            console.warn("Unable to removeItem from Hatch: " + key + 
                ". Removing item from local storage instead");

            return $q.when(service.removeLocalItem(key));
        }

        console.error("Unable to removeItem from Hatch: " + key);
        return $q.reject();
    }

    service.removeRemoteItem = function(key) {
        delete service.keyCache[key];
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
        if (service.useSettings()) 
            return service.getRemoteKeys(prefix);
        return $q.when(service.getLocalKeys(prefix));
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

    // Copy all stored settings from localStorage to Hatch.
    // If 'move' is true, delete the local settings once cloned.
    service.copySettingsToHatch = function(move) {
        var deferred = $q.defer();
        var keys = service.getLocalKeys();

        angular.forEach(keys, function(key) {

            // Hatch keys are local-only
            if (key.match(/^eg.hatch/)) return;

            console.debug("Copying to Hatch Storage: " + key);
            service.setRemoteItem(key, service.getLocalItem(key))
            .then(function() { // key successfully cloned.

                // delete the local copy if requested.
                if (move) service.removeLocalItem(key);

                // resolve the promise after processing the last key.
                if (key == keys[keys.length-1]) 
                    deferred.resolve();
            });
        });

        return deferred.promise;
    }

    // Copy all stored settings from Hatch to localStorage.
    // If 'move' is true, delete the Hatch settings once cloned.
    service.copySettingsToLocal = function(move) {
        var deferred = $q.defer();

        service.getRemoteKeys().then(function(keys) {
            angular.forEach(keys, function(key) {
                service.getRemoteItem(key).then(function(val) {

                    console.debug("Copying to Local Storage: " + key);
                    service.setLocalItem(key, val);

                    // delete the remote copy if requested.
                    if (move) service.removeRemoteItem(key);

                    // resolve the promise after processing the last key.
                    if (key == keys[keys.length-1]) 
                        deferred.resolve();
                });
            });
        });

        return deferred.promise;
    }

    // The only requirement for opening Hatch is that the DOM be loaded.
    // Open the connection now so its state will be immediately available.
    service.openHatch();

    return service;
}])

