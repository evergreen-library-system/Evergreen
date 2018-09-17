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
           ['$q','$window','$timeout','$interpolate','$cookies','egNet','$injector',
    function($q , $window , $timeout , $interpolate , $cookies , egNet , $injector ) {

    var service = {};
    service.msgId = 1;
    service.messages = {};
    service.hatchAvailable = false;
    service.auth = null;  // ref to egAuth loaded on-demand to avoid circular ref.
    service.disableServerSettings = false;

    // key/value cache -- avoid unnecessary Hatch extension requests.
    // Only affects *RemoteItem calls.
    service.keyCache = {}; 

    // Keep a local copy of all retrieved setting summaries, which indicate
    // which setting types exist for each setting.  
    service.serverSettingSummaries = {};

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

    /**
     * Settings with these prefixes will always live in the browser.
     */
    service.browserOnlyPrefixes = [
        'eg.workstation', 
        'eg.hatch',
        'eg.cache',
        'current_tag_table_marc21_biblio',
        'FFPos',
        'FFValue'
    ];

    service.keyStoredInBrowser = function(key) {

        if (service.disableServerSettings) {
            // When server-side storage is disabled, treat every
            // setting like it's stored locally.
            return true;
        }

        var browserOnly = false;
        service.browserOnlyPrefixes.forEach(function(pfx) {
            if (key.match(new RegExp('^' + pfx))) 
                browserOnly = true;
        });

        return browserOnly;
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
            //console.debug("Hatch is not available");
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
        return service.getItem('eg.print.config.' + context);
    }

    service.setPrintConfig = function(context, config) {
        return service.setItem('eg.print.config.' + context, config);
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

    // TODO: once Hatch is printing-only, should probably store
    // this preference on the server.
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

        console.debug('getting item: ' + key);

        if (!service.keyStoredInBrowser(key)) {
            return service.getServerItem(key);
        }

        var deferred = $q.defer();

        service.getBrowserItem(key).then(
            function(val) { deferred.resolve(val); },

            function() { // Hatch error
                if (service.keyIsOnCall(key)) {
                    console.warn("Unable to getItem from Hatch: " + key + 
                        ". Retrieving item from local storage instead");
                    deferred.resolve(service.getLocalItem(key));
                }

                deferred.reject("Unable to getItem from Hatch: " + key);
            }
        );

        return deferred.promise;
    }

    // Collect values in batch.
    // For server-stored values espeically, this is more efficient 
    // than a series of one-off calls.
    service.getItemBatch = function(keys) {
        var browserKeys = [];
        var serverKeys = [];

        // To take full advantage of the getServerItemBatch call,
        // we have to know in advance which keys to send to the server
        // vs those to handle in the browser.
        keys.forEach(function(key) {
            if (service.keyStoredInBrowser(key)) {
                browserKeys.push(key);
            } else {
                serverKeys.push(key);
            }
        });

        var settings = {};

        var serverPromise = serverKeys.length === 0 ? $q.when() : 
            service.getServerItemBatch(serverKeys).then(function(values) {
                angular.forEach(values, function(val, key) {
                    settings[key] = val;
                });
            });

        var browserPromises = [];
        browserKeys.forEach(function(key) {
            browserPromises.push(
                service.getBrowserItem(key).then(function(val) {
                    settings[key] = val;
                })
            );
        });

        return $q.all(browserPromises.concat(serverPromise))
            .then(function() {return settings});
    }

    service.getBrowserItem = function(key) {
        if (service.useSettings()) {
            if (service.hatchAvailable) {
                return service.getRemoteItem(key);
            }
        } else {
            return $q.when(service.getLocalItem(key));
        }
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
        if (val === null || val === undefined) return;
        try {
            return JSON.parse(val);
        } catch(E) {
            console.error(
                "Deleting invalid JSON for localItem: " + key + " => " + val);
            service.removeLocalItem(key);
            return null;
        }
    }

    // Force auth cookies to live under path "/" instead of "/eg/staff"
    // so they may be shared with the Angular app.
    // There's no way to tell under what path a cookie is stored in
    // the browser, all we can do is migrate it regardless.
    service.migrateAuthCookies = function() {
        [   'eg.auth.token', 
            'eg.auth.time', 
            'eg.auth.token.oc', 
            'eg.auth.time.oc'
        ].forEach(function(key) {
            var val = service.getLoginSessionItem(key);
            if (val) {
                $cookies.remove(key, {path: '/eg/staff/'});
                service.setLoginSessionItem(key, val);
            }
        });
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

        if (!service.keyStoredInBrowser(key)) {
            return service.setServerItem(key, value);
        }

        var deferred = $q.defer();
        return service.setBrowserItem(key, value).then(
            function(val) {deferred.resolve(val);},

            function() { // Hatch error

                if (service.keyIsOnCall(key)) {
                    console.warn("Unable to setItem in Hatch: " + 
                        key + ". Setting in local storage instead");

                    deferred.resolve(service.setLocalItem(key, value));
                }
                deferred.reject("Unable to setItem in Hatch: " + key);
            }
        );
    }

    service.setBrowserItem = function(key, value) {
        if (service.useSettings()) {
            if (service.hatchAvailable) {
                return service.setRemoteItem(key, value);
            } else {
                return $q.reject('Unable to get item from hatch');
            }
        } else {
            return $q.when(service.setLocalItem(key, value));
        }
    }

    service.setServerItem = function(key, value) {
        if (!service.auth) service.auth = $injector.get('egAuth');
        if (!service.auth.token()) return $q.when();

        // If we have already attempted to retrieve a value for this
        // setting, then we can tell up front whether applying a value
        // at the server will be an option.  If not, store locally.
        var summary = service.serverSettingSummaries[key];
        if (summary && !summary.has_staff_setting) {

            if (summary.has_org_setting === 't') {
                // When no user/ws setting types exist but an org unit
                // setting type does, it means the value cannot be
                // applied by an individual user.  Nothing left to do.
                return $q.when();
            }

            // No setting types of any flavor exist.
            // Fall back to local storage.

            if (value === null) {
                // a null value means clear the server setting.
                return service.removeBrowserItem(key);
            } else {
                console.warn('No server setting type exists for ' + key);
                return service.setBrowserItem(key, value); 
            }
        }

        var settings = {};
        settings[key] = value;

        return egNet.request(
            'open-ils.actor',
            'open-ils.actor.settings.apply.user_or_ws',
            service.auth.token(), settings
        ).then(function(appliedCount) {

            if (appliedCount == 0) {
                console.warn('No server setting type exists for ' + key);
                // We were unable to store the setting on the server,
                // presumably becuase no server-side setting type exists.
                // Add to local storage instead.
                service.setLocalItem(key, value);
            }

            service.keyCache[key] = value;
            return appliedCount;
        });
    }

    service.getServerItem = function(key) {
        if (key in service.keyCache) {
            return $q.when(service.keyCache[key])
        }

        if (!service.auth) service.auth = $injector.get('egAuth');
        if (!service.auth.token()) return $q.when(null);

        return egNet.request(
            'open-ils.actor',
            'open-ils.actor.settings.retrieve.atomic',
            [key], service.auth.token()
        ).then(function(settings) {
            return service.handleServerItemResponse(settings[0]);
        });
    }

    service.handleServerItemResponse = function(summary) {
        var key = summary.name;
        var val = summary.value;

        // For our purposes, we only care if a setting can be stored
        // as an org setting or a user-or-workstation setting.
        summary.has_staff_setting = (
            summary.has_user_setting === 't' || 
            summary.has_workstation_setting === 't'
        );

        summary.value = null; // avoid duplicate value caches
        service.serverSettingSummaries[key] = summary;

        if (val !== null) {
            // We have a server setting.  Nothing left to do.
            return $q.when(service.keyCache[key] = val);
        }

        if (!summary.has_staff_setting) {

            if (summary.has_org_setting === 't') {
                // An org unit setting type exists but no value is applied
                // that this workstation has access to.  The existence of 
                // an org unit setting type and no user/ws setting type 
                // means applying a value locally is not allowed.  
                return $q.when(service.keyCache[key] = undefined);
            }

            console.warn('No server setting type exists for ' 
                + key + ', using local value.');

            return service.getBrowserItem(key);
        }

        // A user/ws setting type exists, but no server value exists.
        // Migrate the local setting to the server.

        var deferred = $q.defer();
        service.getBrowserItem(key).then(function(browserVal) {

            if (browserVal === null || browserVal === undefined) {
                // No local value to migrate.
                return deferred.resolve(service.keyCache[key] = undefined);
            }

            // Migrate the local value to the server.

            service.setServerItem(key, browserVal).then(
                function(appliedCount) {
                    if (appliedCount == 1) {
                        console.info('setting ' + key + ' successfully ' +
                            'migrated to a server setting');
                        service.removeBrowserItem(key); // fire & forget
                    } else {
                        console.error('error migrating setting to server,' 
                            + ' falling back to local value');
                    }
                    deferred.resolve(service.keyCache[key] = browserVal);
                }
            );
        });

        return deferred.promise;
    }

    service.getServerItemBatch = function(keys) {
        // no cache checking for now.  assumes batch mode is only
        // called once on page load.  maybe add cache checking later.
        if (!service.auth) service.auth = $injector.get('egAuth');
        if (!service.auth.token()) return $q.when({});

        var foundValues = {};
        return egNet.request(
            'open-ils.actor',
            'open-ils.actor.settings.retrieve.atomic',
            keys, service.auth.token()
        ).then(
            function(settings) { 
                //return foundValues; 

                var deferred = $q.defer();
                function checkOne(setting) {
                    if (!setting) {
                        deferred.resolve(foundValues);
                        return;
                    }
                    service.handleServerItemResponse(setting)
                    .then(function(resp) {
                        if (resp !== undefined) {
                            foundValues[setting.name] = resp;
                        }
                        settings.shift();
                        checkOne(settings[0]);
                    });
                }

                checkOne(settings[0]);
                return deferred.promise;
            }
        );
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
        if (jsonified === undefined ) {
            jsonified = JSON.stringify(value);
        } else if (value === undefined) {
            return;
        }
        try {
            $window.localStorage.setItem(key, jsonified);
        } catch (e) {
            console.log('localStorage.setItem (overwrite) failed for '+key+': ', e);
        }
    }

    service.appendItem = function(key, value) {
        if (!service.useSettings())
            return $q.when(service.appendLocalItem(key, value));

        if (service.hatchAvailable)
            return service.appendRemoteItem(key, value);

        if (service.keyIsOnCall(key)) {
            console.warn("Unable to appendItem in Hatch: " + 
                key + ". Setting in local storage instead");

            return $q.when(service.appendLocalItem(key, value));
        }

        console.error("Unable to appendItem in Hatch: " + key);
        return $q.reject();
    }

    // append the value to a stored or new item
    service.appendRemoteItem = function(key, value) {
        service.keyCache[key] = value;
        return service.attemptHatchDelivery({
            key : key, 
            content : value, 
            action : 'append',
        });
    }

    service.appendLocalItem = function(key, value, jsonified) {
        if (jsonified === undefined ) 
            jsonified = JSON.stringify(value);

        var old_value = $window.localStorage.getItem(key) || '';
        try {
            $window.localStorage.setItem( key, old_value + jsonified );
        } catch (e) {
            console.log('localStorage.setItem (append) failed for '+key+': ', e);
        }
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
        $cookies.put(key, jsonified, {path: '/'});
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

        if (!service.keyStoredInBrowser(key)) {
            return service.removeServerItem(key);
        }

        var deferred = $q.defer();
        service.removeBrowserItem(key).then(
            function(response) {deferred.resolve(response);},
            function() { // Hatch error

                if (service.keyIsOnCall(key)) {
                    console.warn("Unable to removeItem from Hatch: " + key + 
                        ". Removing item from local storage instead");

                    deferred.resolve(service.removeLocalItem(key));
                }

                deferred.reject("Unable to removeItem from Hatch: " + key);
            }
        );

        return deferred.promise;
    }

    service.removeBrowserItem = function(key) {
        if (service.useSettings()) {
            if (service.hatchAvailable) {
                return service.removeRemoteItem(key);
            } else {
                return $q.reject('error talking to Hatch');
            }
        } else {
            return $q.when(service.removeLocalItem(key));
        }
    }

    service.removeServerItem = function(key) {
        return service.setServerItem(key, null);
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
        $cookies.remove(key, {path: '/'});
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
        var promise = service.getServerKeys(prefix);
        return service.getBrowserKeys(prefix).then(function(browserKeys) {
            return promise.then(function(serverKeys) {
                return serverKeys.concat(browserKeys);
            });
        });
    }

    service.getRemoteKeys = function(prefix) {
        return service.attemptHatchDelivery({
            key : prefix,
            action : 'keys'
        });
    }

    service.getBrowserKeys = function(prefix) {
        if (service.useSettings()) 
            return service.getRemoteKeys(prefix);
        return $q.when(service.getLocalKeys(prefix));
    }

    service.getServerKeys = function(prefix, options) {
        if (!service.auth) service.auth = $injector.get('egAuth');
        if (!service.auth.token()) return $q.when({});
        return egNet.request(
            'open-ils.actor',
            'open-ils.actor.settings.staff.applied.names.authoritative.atomic',
            service.auth.token(), prefix, options
        );
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

