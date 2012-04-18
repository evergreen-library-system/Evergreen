if (!dojo._hasResource["openils.AutoSuggestStore"]) {
    dojo._hasResource["openils.AutoSuggestStore"] = true;

    dojo.provide("openils.AutoSuggestStore");

    dojo.require("dojo.cookie");
    dojo.require("DojoSRF");
    dojo.require("openils.Util");

    /* Here's an exception class specific to openils.AutoSuggestStore */
    function AutoSuggestStoreError(message) { this.message = message; }
    AutoSuggestStoreError.prototype.toString = function() {
        return "openils.AutoSuggestStore: " + this.message;
    };

    function TermString(str, field) { this.str = str; this.field = field; }
    /* It doesn't seem to be possible to subclass builtins like String, but
     * these are the only methods of String we should actually need */
    TermString.prototype.toString=function(){return this.str;};
    TermString.prototype.toLowerCase=function(){return this.str.toLowerCase();};
    TermString.prototype.substr=function(){return this.str.substr(arguments);};

    var _autosuggest_fields = ["id", "match", "term", "field"];

    dojo.declare(
        "openils.AutoSuggestStore", null, {

        "_last_fetch": null,        /* used internally */

        /* Everything between here and the constructor can be specified in
         * the constructor's args object. */

        "type_selector": null,      /* HTMLSelect object w/ options whose values
                                       are search_classes (required) */
        "org_unit_getter": null,    /* function that returns int (OU ID) */

        "limit": 10,                /* number of suggestions at once */
        "highlight_max": null,      /* TS_HEADLINE()'s MaxWords option */
        "highlight_min": null,      /* TS_HEADLINE()'s MinWords option */
        "short_word_length": null,  /* TS_HEADLINE()'s ShortWord option */
        "normalization": null,      /* TS_RANK_CD()'s normalization argument */

        "constructor": function(/* object */ args) {
            dojo.mixin(this, args); /* XXX very sloppy */
            this._current_items = {};
            this._setup_config_metabib_caches();
        },

        "_setup_config_metabib_cache": function(key, field_list, oncomplete) {
            var self = this;

            if (this.cm_cache[key]) return;

            /* Try to get cache of cmc's or cmf's from
             * openils.widget.Searcher */
            try {
                /* openils.widget.Searcher may not even be loaded;
                 * that's ok; just try. */
                this.cm_cache[key] =
                    openils.widget.Searcher._cache.obj[key];
                /* Don't try to set a cookie here; o.w.Searcher has
                 * tried and failed. */
            } catch (E) {
                void(0);
            }

            if (this.cm_cache[key]) return oncomplete();

            /* now try talking to fielder ourselves, and cache the result */
            var pkey = field_list[0];
            var query = {};
            query[pkey] = {"!=": null};

            OpenSRF.CachedClientSession("open-ils.fielder").request({
                "method": "open-ils.fielder." + key + ".atomic",
                "params": [{"query": query, "fields": field_list}],
                "async": true,
                "cache": true,
                "oncomplete": function(r) {
                    var result_arr = openils.Util.readResponse(r);

                    self.cm_cache[key] = {};
                    dojo.forEach(
                        result_arr,
                        function(o) { self.cm_cache[key][o[pkey]] = o; }
                    );
                    oncomplete();
                }
            }).send();
        },

        "_setup_config_metabib_caches": function() {
            var self = this;

            this.cm_cache = {};

            var field_lists = {
                "cmf": ["id", "field_class", "name", "label"],
                "cmc": ["name", "label"]
            };
            var class_list = openils.Util.objectProperties(field_lists);

            var is_done = function(k) { return Boolean(self.cm_cache[k]); };

            dojo.forEach(
                class_list, function(key) {
                    self._setup_config_metabib_cache(
                        key, field_lists[key], function() {
                            if (dojo.every(class_list, is_done))
                                self.cm_cache.is_done = true;
                        }
                    );
                }
            );
        },

        "_prepare_match_for_display": function(match, field) {
            return (
                "<div class='oils_AS_match'><div class='oils_AS_match_term'>" +
                match + "</div><div class='oils_AS_match_field'>" +
                this.get_field_label(field) + "</div></div>"
            );
        },

        "_prepare_autosuggest_url": function(req) {
            var term = req.query.term;  /* affected by searchAttr on widget */
            var limit = (!isNaN(req.count) && req.count != Infinity) ?
                req.count : this.limit;

            if (!term || term.length < 1 || term == "*") return null;
            if (term.match(/[^\s*]$/)) term += " ";
            term = term.replace(/\*$/, "");

            var params = [
                "query=" + encodeURIComponent(term),
                "search_class=" + this.type_selector.value,
                "limit=" + limit
            ];

            if (typeof this.org_unit_getter == "function")
                params.push("org_unit=" + this.org_unit_getter());

            dojo.forEach(
                ["highlight_max", "highlight_min",
                    "short_word_length", "normalization"],
                dojo.hitch(this, function(arg) {
                    if (this[arg] != null)
                        params.push(arg + "=" + this[arg]);
                })
            );

            return "/opac/extras/autosuggest?" + params.join("&");
        },

        "get_field_label": function(field_id) {
            var mfield = this.cm_cache.cmf[field_id];
            var mclass = this.cm_cache.cmc[mfield.field_class];
            return mfield.label + " (" + mclass.label + ")";
        },

        /* *** Begin dojo.data.api.Read methods *** */

        "getValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ defaultValue) {
            if (!this.isItem(item))
                throw new AutoSuggestStoreError("getValue(): bad item " + item);
            else if (typeof attribute != "string")
                throw new AutoSuggestStoreError("getValue(): bad attribute");

            var value = item[attribute];
            return (typeof value == "undefined") ? defaultValue : value;
        },

        "getValues": function(/* object */ item, /* string */ attribute) {
            if (!this.isItem(item) || typeof attribute != "string")
                throw new AutoSuggestStoreError("bad arguments");

            var result = this.getValue(item, attribute, []);
            return dojo.isArray(result) ? result : [result];
        },

        "getAttributes": function(/* object */ item) {
            if (!this.isItem(item))
                throw new AutoSuggestStoreError("getAttributes(): bad args");
            else
                return _autosuggest_fields;
        },

        "hasAttribute": function(/* object */ item, /* string */ attribute) {
            if (!this.isItem(item) || typeof attribute != "string") {
                throw new AutoSuggestStoreError("hasAttribute(): bad args");
            } else {
                return (dojo.indexOf(_autosuggest_fields, attribute) >= 0);
            }
        },

        "containsValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ value) {
            if (!this.isItem(item) || typeof attribute != "string")
                throw new AutoSuggestStoreError("bad data");
            else
                return (
                    dojo.indexOf(this.getValues(item, attribute), value) != -1
                );
        },

        "isItem": function(/* anything */ something) {
            if (typeof something != "object" || something === null)
                return false;

            for (var i = 0; i < _autosuggest_fields.length; i++) {
                var cur = _autosuggest_fields[i];
                if (typeof something[cur] == "undefined")
                    return false;
            }
            return true;
        },

        "isItemLoaded": function(/* anything */ something) {
            return this.isItem(something);  /* for this store,
                                               items are always loaded */
        },

        "close": function(/* object */ request) { /* no-op */ return; },
        "getLabel": function(/* object */ item) { return "match"; },
        "getLabelAttributes": function(/* object */ item) { return ["match"]; },

        "loadItem": function(/* object */ keywordArgs) {
            if (!this.isItem(keywordArgs.item))
                throw new AutoSuggestStoreError("not an item; can't load it");

            keywordArgs.identity = this.getIdentity(item);
            return this.fetchItemByIdentity(keywordArgs);
        },

        "fetch": function(/* request-object */ req) {
            //  Respect the following properties of the *req* object:
            //
            //      query    a dojo-style query, which will need modest
            //                  translation for our server-side service
            //      count    an int
            //      onBegin  a callback that takes the number of items
            //                  that this call to fetch() will return, but
            //                  we always give it -1 (i.e. unknown)
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

            if (!this.cm_cache.is_done) {
                if (typeof req.onComplete == "function")
                    req.onComplete.call(callback_scope, [], req);
                return;
            }
            this._current_items = {};

            var callback_scope = req.scope || dojo.global;
            var url = this._prepare_autosuggest_url(req);

            if (!url) {
                if (typeof req.onComplete == "function")
                    req.onComplete.call(callback_scope, [], req);
                return;
            }

            var self = this;
            var process_fetch = function(obj, when) {
                if (when < self._last_fetch) /* Stale response. Discard. */
                    return;

                dojo.forEach(
                    obj.val,
                    function(item) {
                        item.id = item.field + "_" + item.term;
                        item.term = new TermString(item.term, item.field);

                        item.match = self._prepare_match_for_display(
                            item.match, item.field
                        );
                        self._current_items[item.id] = item;

                        if (typeof req.onItem == "function")
                            req.onItem.call(callback_scope, item, req);
                    }
                );

                if (typeof req.onComplete == "function") {
                    req.onComplete.call(
                        callback_scope,
                        openils.Util.objectValues(self._current_items),
                        req
                    );
                }
            };

            req.abort = function() {
                alert("The 'abort' operation is not supported");
            };

            if (typeof req.onBegin == "function")
                req.onBegin.call(callback_scope, -1, req);

            var fetch_time = this._last_fetch = (new Date().getTime());

            dojo.xhrGet({
                "url": url,
                "handleAs": "json",
                "sync": false,
                "preventCache": true,
                "headers": {"Accept": "application/json"},
                "load": function(obj) { process_fetch(obj, fetch_time); }
            });

            /* as for onError: what to do? */

            return req;
        },

        /* *** Begin dojo.data.api.Identity methods *** */

        "getIdentity": function(/* object */ item) {
            if (!this.isItem(item))
                throw new AutoSuggestStoreError("not an item");

            return item.id;
        },

        "getIdentityAttributes": function(/* object */ item) { return ["id"]; },

        "fetchItemByIdentity": function(/* object */ keywordArgs) {
            if (keywordArgs.identity == undefined)
                return null; // Identity API spec unclear whether error callback
                             // would need to be run, so we won't.
            var callback_scope = keywordArgs.scope || dojo.global;

            var item;
            if (item = this._current_items[keywordArgs.identity]) {
                if (typeof keywordArgs.onItem == "function")
                    keywordArgs.onItem.call(callback_scope, item);

                return item;
            } else {
                if (typeof keywordArgs.onError == "function")
                    keywordArgs.onError.call(callback_scope, E);

                return null;
            }
        },

        /* *** Classes implementing any Dojo APIs do this to list which
         *     APIs they're implementing. *** */

        "getFeatures": function() {
            return {
                "dojo.data.api.Read": true,
                "dojo.data.api.Identity": true
            };
        }
    });
}
