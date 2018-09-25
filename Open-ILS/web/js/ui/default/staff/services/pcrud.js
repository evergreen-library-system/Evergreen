/**
 * Core Service - egPCRUD
 *
 * PCRUD client.
 *
 * Factory for PCRUDContext objects with pass-through service-level API.
 *
 * For most types of communication, where the client expects to make a
 * single request which egPCRUD manages internally, use the service-
 * level API.
 *
 * All service-level APIs (except connect()) return a promise, whose
 * notfiy() channels individual responses (think: onresponse) and 
 * whose resolve() channels the last received response (think: 
 * oncomplete), consistent with egNet.request().  If only one response
 * is expected (e.g. retrieve(), or .atomic searches), notify() 
 * handlers are not required.
 *
 * egPCRUD.retrieve('aou', 1)
 * .then(function(org) { console.log(org.shortname()) });
 *
 * egPCRUD.search('aou', {id : [1,2,3]})
 * .then(function(orgs) { console.log(orgs.length) } );
 *
 * egPCRUD.search('aou', {id : {'!=' : null}}, {limit : 10})
 * .then(...);
 *
 * For requests where the caller needs to manually connect and make
 * individual API calls, the service.connect() call will create and
 * pass a PCRUDContext object as the argument to the connect promise 
 * resolver.  The PCRUDContext object can be used to make subsequent 
 * pcrud calls directly.
 *
 * egPCRUD.connnect()
 * .then(function(ctx) { return ctx.retrieve('aou', 1) })
 * .then(function(org) { console.log(org.id()); ctx.disconnect() })
 *
 */
angular.module('egCoreMod')

.factory('egPCRUD', ['$q','$rootScope','egAuth','egIDL', 
             function($q , $rootScope , egAuth , egIDL) { 
    
    var service = {};

    // create service-level pass through functions 
    // for one-off PCRUDContext actions.
    angular.forEach(['connect', 'retrieve', 'retrieveAll', 
        'search', 'create', 'update', 'remove', 'apply'],
        function(action) {
            service[action] = function() {
                var ctx = new PCRUDContext();
                return ctx[action].apply(ctx, arguments);
            }
        }
    );

    /*
     * Since services are singleton objectss, we need an internal 
     * class to manage individual PCRUD conversations.  
     */
    var PCRUDContextIdent = 0; // useful for debug logging
    function PCRUDContext() {
        var self = this;
        this.xact_close_mode = 'rollback';
        this.ident = PCRUDContextIdent++;
        this.session = new OpenSRF.ClientSession('open-ils.pcrud');

        this.toString = function() {
            return '[PCRUDContext ' + this.ident + ']';
        };

        this.log = function(msg) {
            console.debug(this + ': ' + msg);
        };

        this.err = function(msg) {
            console.error(this + ': ' + msg);
        };

        this.connect = function() {
            this.log('connect');
            var deferred = $q.defer();
            this.session.connect({onconnect : 
                function() {deferred.resolve(self)}});
            return deferred.promise;
        };

        this.disconnect = function() {
            this.log('disconnect');
            this.session.disconnect();
        };

        this.retrieve = function(fm_class, pkey, pcrud_ops, req_ops) {
            req_ops = req_ops || {};
            this.authoritative = req_ops.authoritative;
            return this._dispatch(
                'open-ils.pcrud.retrieve.' + fm_class,
                [egAuth.token(), pkey, pcrud_ops]
            );
        };

        this.retrieveAll = function(fm_class, pcrud_ops, req_ops) {
            var search = {};
            search[egIDL.classes[fm_class].pkey] = {'!=' : null};
            return this.search(fm_class, search, pcrud_ops, req_ops);
        };

        this.search = function (fm_class, search, pcrud_ops, req_ops) {
            req_ops = req_ops || {};
            this.authoritative = req_ops.authoritative;

            var return_type = req_ops.idlist ? 'id_list' : 'search';
            var method = 'open-ils.pcrud.' + return_type + '.' + fm_class;

            if (req_ops.atomic) method += '.atomic';

            return this._dispatch(method, 
                [egAuth.token(), search, pcrud_ops]);
        };

        this.create = function(list) {return this.CUD('create', list)};
        this.update = function(list) {return this.CUD('update', list)};
        this.remove = function(list) {return this.CUD('delete', list)};
        this.apply  = function(list) {return this.CUD('apply',  list)};

        this.xactClose = function() {
            return this._send_request(
                'open-ils.pcrud.transaction.' + this.xact_close_mode,
                [egAuth.token()]
            );
        };

        this.xactBegin = function() {
            return this._send_request(
                'open-ils.pcrud.transaction.begin',
                [egAuth.token()]
            );
        };

        this._dispatch = function(method, params) {
            if (this.authoritative) {
                return this._wrap_xact(
                    function() {
                        return self._send_request(method, params);
                    }
                );
            } else {
                return this._send_request(method, params)
            }
        };


        // => connect
        // => xact_begin 
        // => action
        // => xact_close(commit/rollback) 
        // => disconnect
        // Returns a promise
        // main_func should return a promise
        this._wrap_xact = function(main_func) {
            var deferred = $q.defer();

            // 1. connect
            this.connect().then(function() {

            // 2. start the transaction
            self.xactBegin().then(function() {

            // 3. execute the main body 
            main_func().then(
                // main body complete
                function(lastResp) {  

                    // 4. close the transaction
                    self.xactClose().then(function() {
                        // 5. disconnect
                        self.disconnect();
                        // 6. all done
                        deferred.resolve(lastResp);
                    });
                },

                // main body error handler
                function() {deferred.reject()}, 

                // main body notify() handler
                function(data) {deferred.notify(data)}
            );

            })}); // close 'em all up.

            return deferred.promise;
        };

        this._send_request = function(method, params) {
            this.log('_send_request(' + method + ')');
            var deferred = $q.defer();
            var lastResp;
            this.session.request({
                method : method,
                params : params,
                onresponse : function(r) {
                    var resp = r.recv();
                    if (resp && (lastResp = resp.content())) {
                        deferred.notify(lastResp);
                    } else {
                        // pcrud requests should always return something
                        self.err(method + " returned no response");
                    }
                },
                oncomplete : function() {
                    deferred.resolve(lastResp);
                },

                onmethoderror : function(req, stat, stat_text) {
                    self.err(method + " failed. \ncode => " 
                        + stat + "\nstatus => " + stat_text 
                        + "\nparams => " + js2JSON(params));

                    if (stat == 401) {
                        // 401 is the PCRUD equivalent of a NO_SESSION event
                        $rootScope.$broadcast('egAuthExpired');
                    }

                    deferred.reject(req);
                }
                // Note: no onerror handler for websockets connections,
                // because errors exist and are reported as top-level
                // conditions, not request-specific conditions.
                // Practically every error we care about (minus loss of 
                // connection) will be reported as a method error.
            }).send();

            return deferred.promise;
        };

        this.CUD = function (action, list) {
            this.log('CUD(): ' + action);

            this.cud_idx = 0;
            this.cud_action = action;
            this.xact_close_mode = 'commit';
            this.cud_list = list;
            this.cud_deferred = $q.defer();

            if (!angular.isArray(list) || list.classname)
                this.cud_list = [list];

            return this._wrap_xact(
                function() {
                    self._CUD_next_request();
                    return self.cud_deferred.promise;
                }
            );
        }

        /**
         * Loops through the list of objects to update and sends
         * them one at a time to the server for processing.  Once
         * all are done, the cud_deferred promise is resolved.
         */
        this._CUD_next_request = function() {

            if (this.cud_idx >= this.cud_list.length) {
                this.cud_deferred.resolve(this.cud_last);
                return;
            }

            var action = this.cud_action;
            var fm_obj = this.cud_list[this.cud_idx++];

            if (action == 'apply') {
                if (fm_obj.ischanged()) action = 'update';
                if (fm_obj.isnew())     action = 'create';
                if (fm_obj.isdeleted()) action = 'delete';

                if (action == 'apply') {
                    // object does not need updating; move along
                    this._CUD_next_request();
                    return;
                }
            }

            this._send_request(
                'open-ils.pcrud.' + action + '.' + fm_obj.classname,
                [egAuth.token(), fm_obj]).then(
                function(data) {
                    // update actions return one response.
                    // no notify() handler needed.
                    self.cud_last = data;
                    self.cud_deferred.notify(data);
                    self._CUD_next_request();
                },
                self.cud_deferred.reject
            );
           
        };
    }

    return service;
}]);

