if (!dojo._hasResource["openils.FlattenerStore"]) {
    dojo._hasResource["openils.FlattenerStore"] = true;

    dojo.provide("openils.FlattenerStore");

    dojo.require("DojoSRF");
    dojo.require("openils.User");
    dojo.require("openils.Util");

    /* An exception class specific to openils.FlattenerStore */
    function FlattenerStoreError(message) { this.message = message; }
    FlattenerStoreError.prototype.toString = function() {
        return "openils.FlattenerStore: " + this.message;
    };

    dojo.declare(
        "openils.FlattenerStore", null, {

        "_last_fetch": null,        /* used internally */
        "_flattener_url": "/opac/extras/flattener",

        /* Everything between here and the constructor can be specified in
         * the constructor's args object. */

        "fmClass": null,
        "mapClause": null,
        "sloClause": null,
        "limit": 25,
        "offset": 0,
        "baseSort": null,
        "defaultSort": null,

        "constructor": function(/* object */ args) {
            dojo.mixin(this, args);
            this._current_items = {};
        },

        /* turn dojo-style sort into flattener-style sort */
        "_prepare_sort": function(dsort) {
            if (!dsort || !dsort.length)
                return this.baseSort || this.defaultSort || [];

            return (this.baseSort || []).concat(
                dsort.map(
                    function(d) {
                        var o = {};
                        o[d.attribute] = d.descending ? "desc" : "asc";
                        return o;
                    }
                )
            );
        },

        "_prepare_flattener_params": function(req) {
            var params = {
                "hint": this.fmClass,
                "ses": openils.User.authtoken
            };

            /* If we're asked for a specific identity, we don't use
             * any query or sort/count/start (sort/limit/offset).  */
            if ("identity" in req) {
                var where = {};
                where[this.fmIdentifier] = req.identity;

                params.where = dojo.toJson(where);
            } else {
                var limit = (!isNaN(req.count) && req.count != Infinity) ?
                    req.count : this.limit;
                var offset = (!isNaN(req.start) && req.start != Infinity) ?
                    req.start : this.offset;

                dojo.mixin(
                    params, {
                        "where": dojo.toJson(req.query),
                        "slo": dojo.toJson({
                            "sort": this._prepare_sort(req.sort),
                            "limit": limit,
                            "offset": offset
                        })
                    }
                );
            }

            if (this.mapKey) { /* XXX TODO, get a map key */
                params.key = this.mapKey;
            } else {
                params.map = dojo.toJson(this.mapClause);
            }

            for (var key in params)
                console.debug("flattener param " + key + " -> " + params[key]);

            return params;
        },

        "_display_attributes": function() {
            var self = this;

            return openils.Util.objectProperties(this.mapClause).filter(
                function(key) { return self.mapClause[key].display; }
            );
        },

        "_get_map_key": function() {
            //console.debug("mapClause: " + dojo.toJson(this.mapClause));
            this.mapKey = fieldmapper.standardRequest(
                ["open-ils.fielder",
                    "open-ils.fielder.flattened_search.prepare"], {
                    "params": [openils.User.authtoken, this.fmClass,
                        this.mapClause],
                    "async": false
                }
            );
        },

        /* *** Begin dojo.data.api.Read methods *** */

        "getValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ defaultValue) {
            //console.log("getValue(" + lazy(item) + ", " + attribute + ", " + defaultValue + ")")
            if (!this.isItem(item))
                throw new FlattenerStoreError("getValue(): bad item " + item);
            else if (typeof attribute != "string")
                throw new FlattenerStoreError("getValue(): bad attribute");

            var value = item[attribute];
            return (typeof value == "undefined") ? defaultValue : value;
        },

        "getValues": function(/* object */ item, /* string */ attribute) {
            //console.log("getValues(" + item + ", " + attribute + ")");
            if (!this.isItem(item) || typeof attribute != "string")
                throw new FlattenerStoreError("bad arguments");

            var result = this.getValue(item, attribute, []);
            return dojo.isArray(result) ? result : [result];
        },

        "getAttributes": function(/* object */ item) {
            //console.log("getAttributes(" + item + ")");
            if (!this.isItem(item))
                throw new FlattenerStoreError("getAttributes(): bad args");
            else
                return this._display_attributes();
        },

        "hasAttribute": function(/* object */ item, /* string */ attribute) {
            //console.log("hasAttribute(" + item + ", " + attribute + ")");
            if (!this.isItem(item) || typeof attribute != "string") {
                throw new FlattenerStoreError("hasAttribute(): bad args");
            } else {
                return dojo.indexOf(this._display_attributes(), attribute) > -1;
            }
        },

        "containsValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ value) {
            //console.log("containsValue(" + item + ", " + attribute + ", " + value + ")");
            if (!this.isItem(item) || typeof attribute != "string")
                throw new FlattenerStoreError("bad data");
            else
                return (
                    dojo.indexOf(this.getValues(item, attribute), value) >= -1
                );
        },

        "isItem": function(/* anything */ something) {
            //console.log("isItem(" + lazy(something) + ")");
            if (typeof something != "object" || something === null)
                return false;

            var fields = this._display_attributes();

            for (var i = 0; i < fields.length; i++) {
                var cur = fields[i];
                if (!(cur in something))
                    return false;
            }
            return true;
        },

        "isItemLoaded": function(/* anything */ something) {
            /* XXX if 'something' is not an item at all, are we just supposed
             * to return false or throw an exception? */
            return this.isItem(something) && (
                something[this.fmIdentifier] in this._current_items
            );
        },

        "close": function(/* object */ request) { /* no-op */ return; },

        "getLabel": function(/* object */ item) {
            console.warn("[unimplemented] getLabel()");
        },

        "getLabelAttributes": function(/* object */ item) {
            console.warn("[unimplemented] getLabelAttributes()");
        },

        "loadItem": function(/* object */ keywordArgs) {
            if (!keywordArgs.force && this.isItemLoaded(keywordArgs.item))
                return;

            keywordArgs.identity = this.getIdentity(keywordArgs.item);
            return this.fetchItemByIdentity(keywordArgs);
        },

        "fetch": function(/* request-object */ req) {
            //  Respect the following properties of the *req* object:
            //
            //      query    a dojo-style query, which will need modest
            //                  translation for our server-side service
            //      count    an int
            //      onBegin  a callback that takes the number of items
            //                  that this call to fetch() *could* have
            //                  returned, with a higher limit. We do
            //                  tricks with this.
            //      onItem   a callback that takes each item as we get it
            //      onComplete  a callback that takes the list of items
            //                      after they're all fetched
            //
            //  The onError callback is ignored for now (haven't thought
            //  of anything useful to do with it yet).
            //
            //  The Read API also charges this method with adding an abort
            //  callback to the *req* object for the caller's use, but
            //  the one we provide does nothing but issue an alert().

            //console.log("fetch(" + dojo.toJson(req) + ")");
            var self = this;
            var callback_scope = req.scope || dojo.global;

            if (!this.mapKey) {
                try {
                    this._get_map_key();
                } catch (E) {
                    if (req.onError)
                        req.onError.call(callback_scope, E);
                    else
                        throw E;
                }
            }

            var post_params = this._prepare_flattener_params(req);

            if (!post_params) {
                if (typeof req.onComplete == "function")
                    req.onComplete.call(callback_scope, [], req);
                return;
            }

            var process_fetch = function(obj, when) {
                if (when < self._last_fetch) /* Stale response. Discard. */
                    return;

                self._retried_map_key_already = false;

                /* The following is apparently the "right" way to call onBegin,
                 * and is very necessary (at least in Dojo 1.3.3) to get
                 * the Grid's fetch-more-when-I-need-it logic to work
                 * correctly. *grumble* crummy documentation *snarl!*
                 */
                if (typeof req.onBegin == "function") {
                    /* We lie to onBegin like this because we don't know how
                     * many more rows we might be able to fetch if the
                     * user keeps scrolling.  Once we get a number of
                     * results that is less than the limit we asked for,
                     * we stop exaggerating, and the grid is smart enough to
                     * know we're at the end and it does the right thing. */
                    var might_be_a_lie = req.start;
                    if (obj.length >= req.count)
                        might_be_a_lie += obj.length + req.count;
                    else
                        might_be_a_lie += obj.length;

                    req.onBegin.call(callback_scope, might_be_a_lie, req);
                }

                dojo.forEach(
                    obj,
                    function(item) {
                        /* Cache items internally. */
                        self._current_items[item[self.fmIdentifier]] = item;

                        if (typeof req.onItem == "function")
                            req.onItem.call(callback_scope, item, req);
                    }
                );

                if (typeof req.onComplete == "function")
                    req.onComplete.call(callback_scope, obj, req);
            };

            req.abort = function() {
                throw new FlattenerStoreError(
                    "The 'abort' operation is not supported"
                );
            };

            var fetch_time = this._last_fetch = (new Date().getTime());

            dojo.xhrPost({
                "url": this._flattener_url,
                "content": post_params,
                "handleAs": "json",
                "sync": false,
                "preventCache": true,
                "headers": {"Accept": "application/json"},
                "load": function(obj) { process_fetch(obj, fetch_time); },
                "error": function(response, ioArgs) {
                    if (response.status == 402) {   /* 'Payment Required' stands
                                                       in for cache miss */
                        if (self._retried_map_key_already) {
                            var e = new FlattenerStoreError(
                                "Server won't cache flattener map?"
                            );
                            if (typeof req.onError == "function")
                                req.onError.call(callback_scope, e);
                            else
                                throw e;
                        } else {
                            self._retried_map_key_already = true;
                            delete self.mapKey;
                            return self.fetch(req);
                        }
                    }
                }
            });

            return req;
        },

        /* *** Begin dojo.data.api.Identity methods *** */

        "getIdentity": function(/* object */ item) {
            if (!this.isItem(item))
                throw new FlattenerStoreError("not an item");

            return item[this.fmIdentifier];
        },

        "getIdentityAttributes": function(/* object */ item) {
            // console.log("getIdentityAttributes(" + item + ")");
            return [this.fmIdentifier];
        },

        "fetchItemByIdentity": function(/* object */ keywordArgs) {
            var callback_scope = keywordArgs.scope || dojo.global;
            var identity = keywordArgs.identity;

            if (typeof identity == "undefined")
                throw new FlattenerStoreError(
                    "fetchItemByIdentity() needs identity in keywordArgs"
                );

            /* First of force's two implications:
             * fetch even if already loaded. */
            if (this._current_items[identity] && !keywordArgs.force) {
                keywordArgs.onItem.call(
                    callback_scope, this._current_items[identity]
                );

                return;
            }

            var post_params = this._prepare_flattener_params(keywordArgs);

            var process_fetch_one = dojo.hitch(
                this, function(obj, when) {
                    if (when < this._last_fetch) /* Stale response. Discard. */
                        return;

                    if (dojo.isArray(obj)) {
                        if (obj.length <= 1) {
                            obj = obj.pop() || null;    /* safe enough */
                            /* Second of force's two implications: call setValue
                             * ourselves.  Makes a DataGrid update. */
                            if (keywordArgs.force && obj &&
                                (origitem = this._current_items[identity])) {
                                for (var prop in origitem)
                                    this.setValue(origitem, prop, obj[prop]);
                            }
                            if (keywordArgs.onItem)
                                keywordArgs.onItem.call(callback_scope, obj);
                        } else {
                            var e = new FlattenerStoreError("Too many results");
                            if (keywordArgs.onError)
                                keywordArgs.onError.call(callback_scope, e);
                            else
                                throw e;
                        }
                    } else {
                        var e = new FlattenerStoreError("Bad response");
                        if (keywordArgs.onError)
                            keywordArgs.onError.call(callback_scope, e);
                        else
                            throw e;
                    }
                }
            );

            var fetch_time = this._last_fetch = (new Date().getTime());

            dojo.xhrPost({
                "url": this._flattener_url,
                "content": post_params,
                "handleAs": "json",
                "sync": false,
                "preventCache": true,
                "headers": {"Accept": "application/json"},
                "load": function(obj){ process_fetch_one(obj, fetch_time); }
            });
        },

        /* dojo.data.api.Write - only very partially implemented, because
         * for FlattenerGrid, the intended client of this store, we don't
         * need most of the methods. */

        "deleteItem": function(item) {
            //console.log("deleteItem()");

            var identity = this.getIdentity(item);
            delete this._current_items[identity];   /* safe even if missing */

            this.onDelete(item);
        },

        "setValue": function(item, attribute, value) {
            /* Silently do nothing when setValue()'s caller wants to change
             * the identifier.  They must be confused anyway. */
            if (attribute == this.fmIdentifier)
                return;

            var old_value = dojo.clone(item[attribute]);

            item[attribute] = dojo.clone(value);
            this.onSet(item, attribute, old_value, value);
        },

        "setValues": function(item, attribute, values) {
            console.warn("[unimplemented] setValues()");    /* unneeded */
        },

        "newItem": function(keywordArgs, parentInfo) {
            console.warn("[unimplemented] newItem()");    /* unneeded */
        },

        "unsetAttribute": function() {
            console.warn("[unimplemented] unsetAttribute()");   /* unneeded */
        },

        "save": function() {
            console.warn("[unimplemented] save()"); /* unneeded */
        },

        "revert": function() {
            console.warn("[unimplemented] revert()");   /* unneeded */
        },

        "isDirty": function() { /* I /think/ this will be ok for our purposes */
            console.info("[stub] isDirty() will always return false");

            return false;
        },

        /* dojo.data.api.Notification - Keep these no-op methods because
         * clients will dojo.connect() to them.  */

        "onNew" : function(item) { /* no-op */ },
        "onDelete" : function(item) { /* no-op */ },
        "onSet": function(item, attr, oldval, newval) { /* no-op */ },

        /* *** Classes implementing any Dojo APIs do this to list which
         *     APIs they're implementing. *** */

        "getFeatures": function() {
            return {
                "dojo.data.api.Read": true,
                "dojo.data.api.Identity": true,
                "dojo.data.api.Notification": true,
                "dojo.data.api.Write": true     /* well, only partly */
            };
        }
    });
}
