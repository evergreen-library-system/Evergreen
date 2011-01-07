if (!dojo._hasResource["openils.PermaCrud.Store"]) {
    dojo._hasResource["openils.PermaCrud.Store"] = true;
    dojo.provide("openils.PermaCrud.Store");
    dojo.require("openils.PermaCrud");

    /* an exception class specific to openils.PermaCrud.Store */
    function PCSError(message) { this.message = message; }
    PCSError.prototype.toString = function() {
        return "openils.PermaCrud.Store: " + this.message;
    };

    /* PCSQueryCache is a here to prevent openils.PermaCrud.Store from asking
     * openils.PermaCrud redundant questions within short time frames.
     */
    function PCSQueryCache() {
        var self = this;

        this._init = function(max_age) {
            if (typeof (this.max_age = max_age) == "undefined")
                throw new PCSError("PCSQueryCache requires max_age parameter");
            this._cached_items = {};
        };

        this._is_left_anchored = function(key) {
            return key.slice(-1) == "%";
        };

        /* Find any reasonably close matches for key  */
        this._similar_key = function(key) {
            var key_is_left_anchored = this._is_left_anchored(key);

            for (var candidate in this._cached_items) {
                if (key == candidate) {
                    return candidate;
                } else if (!key_is_left_anchored &&
                    this._is_left_anchored(candidate)) {
                    if (candidate.slice(0, -1) == key)
                        return candidate;
                }
            }

            return null;
        };

        this._get_if_fresh = function(key) {
            /* XXX This is passive cache aging. Make it active w/ setTimeout? */
            var age = new Date().getTime() - this._cached_items[key].when;
            if (age > this.max_age) {
                delete this._cached_items[key];
                return [];
            } else {
                return this._cached_items[key].data;
            }
        };

        this.put = function(key, data) {
            this._cached_items[key] = {
                "when": new Date().getTime(), "data": data
            };
        };

        this.get = function(key) {
            if (similar = this._similar_key(key)) { /* assignment */
                var results = this._get_if_fresh(similar);
                if (results.length)
                    console.log("cache hit: " + key);
                return results;
            } else {
                return [];
            }
        };

        this.clear = function(key) {
            this.put(key, []);
        };

        this.add = function(key, datum) {
            this._cached_items[key].data.push(datum);
            this._cached_items[key].when = new Date().getTime();
        };

        this._init.apply(this, arguments);
    }

    dojo.declare(
        "openils.PermaCrud.Store", null, {
        //  summary:
        //      This is a data store implementing the Read and Identity APIs,
        //      making it possible to lazy-load fieldmapper objects via the
        //      PermaCrud service.
        //  description:
        //      Two "levels" of laziness are possible. You get one
        //      level of laziness by default: no retrieve-all queries are
        //      honored, and fetch() only retrieves objects matching
        //      substantive queries. This is great for autocompleting dijits.
        //      The second level of laziness is invoked by using stubby mode.
        //      In stubby mode, fetch() only retrieves IDs and returns place-
        //      holder objects, while getValue() or anything like it will
        //      actually retrieve the full object.  This may be more useful for
        //      grids.  In any event, huge datasets don't have to be retrieved
        //      just to provide a widget whereby a user can select a single item.
        //
        //      Later it is hoped that we will also implement the Notification
        //      and Write APIs here, which will enable vastly simpler interfaces
        //      to be developed (and existing interfaces to be vastly simplified)
        //      in Evergreen. Think no more keeping track at the interface layer
        //      of dirty objects, nor manually updating one dijit's store when a
        //      value in another changes.
        //
        //      Note that the methods of this class may throw exceptions in cases
        //      where such behavior is prescribed by the dojo data API from
        //      which said methods originate.  These might not be documented in
        //      the method summaries below.
        //
        //      The Thought behind all this came from Mike Rylander, who has a
        //      pretty clear vision of what this needs to be and how it needs
        //      to get there. The actual typing, testing, and gradually dawning
        //      understanding is brought to you by Lebbeous Fogle-Weekley.

        "constructor": function(/* object */ args) {
            //  summary:
            //      Insantiates the store.
            //  description:
            //      Requires the object argument *args*.
            //  args:
            //      An object with these properties:
            //      {
            //          fmclass:            (string required),
            //          fetch_limit:        (int default 50),
            //          max_query_cache_age:(int default 10000 ms),
            //          stubby:             (bool default false),
            //          honor_retrieve_all: (bool default value of *stubby*),
            //          label_attributes:   (optional array of attribute names)
            //          label_separator:    (string default " ")
            //          base_filter:        (optional object pcrud search filter)
            //          pcrud:              (optional openils.PermaCrud object),
            //          authtoken:          (optional string authtoken)
            //      }
            //
            //  The *fmclass* parameter.
            //      This is required, and should be a class hint from the IDL.
            //      In this way you specify the class that the store will deal
            //      with.
            //
            //  The *fetch_limit* parameter.
            //      The maximum number of items the store will fetch at a time.
            //
            //  The *max_query_cache_age* parameter.
            //      An internal cache is used to avoid re-issuing the same query
            //      repeatedly to PermaCrud. This is necessary because some
            //      dijits (dijit.form.FilteringSelect, for example) get pretty
            //      talky with the fetch() method.  With this parameter you're
            //      specifying the maximum age of entry in this cache. After
            //      this length of time, a fresh call to fetch(), even with
            //      the same query as it was issued in a previous call, will
            //      result in a call to PermaCrud.
            //
            //  The *stubby* parameter.
            //      In stubby mode, fetch() only retrieves IDs and returns
            //      place-holder objects, while getValue or anything like it
            //      will /then/ actually retrieve the full object.
            //
            //  The *honor_retrive_all* parameter.
            //      This is normally set to whatever the value of *stubby* is,
            //      meaning that queries from dijits of the form
            //      {query: {key: ""}} and {query: {key: "*"}} are ignored by
            //      default in non-stubby mode, and translated to pcrud
            //      search filters of {id: {"!=": null}} in stubby mode (where
            //      id is the primary key for the class in question).  Set this
            //      boolean parameter to override the default behavior.
            //
            //  The *label_attributes* parameter.
            //      getLabelAttributes() will figure out what to return based
            //      on 1) fields with a selector attribute for our class in the
            //      IDL and, failing that, 2) the Identity field for our class
            //      _unless_ you want to override that by providing an array
            //      (single element is fine) of field names to use as label
            //      attributes here.
            //
            //  The *label_separator* parameter.
            //      In the event of dealing with a class that has more than one
            //      attribute contributing to the label, this string, which
            //      defaults to " " defines the token that is placed between
            //      the value of each field as the label string is built.
            //
            //  The *base_filter* parameter.
            //      This optional object will be mixed in with any search queries
            //      produced for pcrud, giving the user a way to limit the result
            //      set beyond the query that will be issued by the dijit. For
            //      example, you can provide an autocompleting widget against
            //      the acqpl class, set base_filter to
            //      {"owner": openils.User.user.id()}
            //      and have the dijit query against name, so that as you type
            //      the store issues queries like
            //      {"owner": 1, "name": {"ilike": "new boo%"}}
            //
            //  The *pcrud* paramter.
            //      Optionally pass in your own openils.PermaCrud object, if
            //      you already have one.
            //
            //  The *authtoken* parameter.
            //      Optionally pass in your authtoken string.  If you're in
            //      certain parts of the Evergreen environment, we may be able
            //      to get this automagically from openils.User anyway, so that's
            //      why this parameter is optional.
            if (typeof(this.fmclass = args.fmclass) != "string")
                throw new PCSError("Must have fmclass");

            this.pkey = fieldmapper.IDL.fmclasses[this.fmclass].pkey;
            this.fetch_limit = args.fetch_limit || 50;
            this.max_query_cache_age = args.max_query_cache_age || 10000; /*ms*/
            this.stubby = args.stubby || false;

            if (typeof args.honor_retrieve_all != undefined)
                this.honor_retrieve_all = args.honor_retrieve_all;
            else
                this.honor_retrieve_all = args.stubby;

            this.label_attributes = args.label_attributes || null;
            this.label_separator = args.label_separator || " ";

            this.base_filter = args.base_filter || {};
            this.pcrud = args.pcrud || new openils.PermaCrud(
                args.authtoken ? {"authtoken": args.authtoken} : null
            );

            this._stored_items = {};
            this._query_cache = new PCSQueryCache(this.max_query_cache_age);
        },

        "_dojo_query_to_pcrud": function(/* request-object */ req) {
            //  summary:
            //      Internal method to convery queries from dijits into pcrud
            //      search filters. Messy. Called by fetch().
            var qkeys = openils.Util.objectProperties(req.query);
            if (qkeys.length < 1)
                throw new PCSError("Not enough meat on that query");

            var first_term;
            for (var qkey in req.query) {
                var value = req.query[qkey];
                var type = typeof value;
                if (
                    type == "number" ||
                    type == "string" ||
                    (type == "object" && dojo.isArray(value))
                ) continue;
                throw new PCSError(
                    "Can't deal with query key " + qkey + " (" + type + ")"
                );
            }

            var pcrud_query = {};
            var hashparts = [];

            for (var i = 0; i < qkeys.length; i++) {
                var key = qkeys[i];
                var term = req.query[key];
                var op;
                /* TODO: break this down into smaller separate methods:
                 *  key & term munging
                 *  offset & limit
                 *  sort -> order_by
                 */

                if (term == "" || term == "*") {
                    if (qkeys.length != 1) {
                        continue;   /* query: {name: "bar", id: "*"}
                                       makes no sense; we could just leave
                                       out the id: part */
                    } else if (!this.honor_retrieve_all) {
                        return req; /* totally bail */
                    } else {
                        key = this.pkey; /*ignore given key: may not be unique*/
                        pcrud_query[key] = {"!=": null};
                        hashparts[i] = key + ":%";
                    }
                } else {
                    term = term.replace("%", "%%");
                    term = term.replace(/\*$/, "%");

                    if (dojo.indexOf(term, "%") != -1) op = "like";
                    if (req.queryOptions && req.queryOptions.ignoreCase)
                        op = "ilike";

                    if (!first_term) first_term = key;
                    if (op) {
                        pcrud_query[key] = {};
                        pcrud_query[key][op] = term;
                        hashparts[i] = key + ":" + op + ":" + term;
                    } else {
                        pcrud_query[key] = term;
                        hashparts[i] = key + ":" + term;
                    }
                }
            }

            var hashkey = hashparts.join(":");
            var opts = {};

            opts.offset = req.start || 0;
            hashkey = "offset:" + opts.offset + ":" + hashkey;

            opts.limit = (req.count && req.count != Infinity) ?
                req.count : this.fetch_limit;
            hashkey = "limit:" + opts.limit + ":" + hashkey;

            if (dojo.isArray(req.sort)) {
                opts.order_by = {};
                opts.order_by[this.fmclass] = dojo.map(
                    req.sort, function(key) {
                        return (key.attribute + " ") + (
                            key.descending ? "DESC" : "ASC"
                        );
                    }
                ).join(",");
                /* XXX not sure whether multiple columns will work as such. */
                hashkey = "order_by:" + opts.order_by[this.fmclass] + ":" +
                    hashkey;
            } else if (first_term) {
                opts.order_by = {};
                opts.order_by[this.fmclass] = first_term + " ASC";
            }

            opts.id_list = this.stubby;

            return [dojo.mixin(this.base_filter, pcrud_query), opts, hashkey];
        },

        /* *** Begin dojo.data.api.Read methods *** */

        "getValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ defaultValue) {
            //  summary:
            //      Given an *item* and the name of an *attribute* on that item,
            //      return that attribute's value.  Load the item first if
            //      it's not actually loaded yet (stubby mode).
            if (!this.isItem(item))
                throw new PCSError("getValue(): bad item: " + item);
            else if (typeof attribute != "string")
                throw new PCSError("getValue(): bad attribute");

            var value;
            try {
                if (this.isItemLoaded(item)) {
                    value = item[attribute]();
                } else {
                    value = this.loadItem({"item": item})[attribute]();
                }
            } catch (E) {
                console.log(E);
                return undefined;
            }

            /* XXX This method by proscription can't return an array, but what
             * the heck is it supposed to do if the value of the field
             * indicated IS an array? */
            return (typeof value == "undefined") ? defaultValue : value;
        },

        "getValues": function(/* object */ item, /* string */ attribute) {
            //  summary:
            //      Same as getValue(), except the result is always an array
            //      and there is no way to specify a default value.
            if (!this.isItem(item) || typeof attribute != "string")
                throw new PCSError("bad arguments");

            var result = this.getValue(item, attribute, []);
            return dojo.isArray(result) ? result : [result];
        },

        "getAttributes": function(/* object */ item) {
            //  summary:
            //      Return an array of all of the given *item*'s *attribute*s.
            //      This is done by consulting fieldmapper.
            if (!this.isItem(item) || typeof attribute != "string")
                throw new PCSError("getAttributes(): bad arguments");
            else
                return fieldmapper.IDL.fmclasses[item.classname].fields;
        },

        "hasAttribute": function(/* object */ item, /* string */ attribute) {
            //  summary:
            //      Return true or false based on whether *item* has an
            //      attribute by the name specified in *attribute*.
            if (!this.isItem(item) || typeof attribute != "string") {
                throw new PCSError("hasAttribute(): bad arguments");
            } else {
                /* tested as autovivification-safe */
                return (
                    typeof fieldmapper.IDL.fmclasses[item.classname].
                        fields[attribute] != "undefined"
                );
            }
        },

        "containsValue": function(
            /* object */ item,
            /* string */ attribute,
            /* anything */ value) {
            //  summary:
            //      Return true or false based on whether *item* has any value
            //      matching *value* for *attribute*.
            if (!this.isItem(item) || typeof attribute != "string")
                throw new PCSError("bad data");
            else
                return (
                    dojo.indexOf(this.getValues(item, attribute), value) != -1
                );
        },

        "isItem": function(/* anything */ something) {
            //  summary:
            //      Return true if *something* is an item (loaded or not), else
            //      false.
            /* XXX Shouldn't this really check to see whether the item came from
             * our store? Checking type (fieldmapper class) may suffice. */
            return (
                typeof something == "object" && something !== null &&
                something._isfieldmapper && something.classname == this.fmclass
            );
        },

        "isItemLoaded": function(/* anything */ something) {
            //  summary:
            //      Return true if *something* is an item and is loaded.
            //      In stubby mode, something that is an item but isn't yet
            //      loaded is possible.
            return this.isItem(something) && something._loaded;
        },

        "close": function(/* object */ request) {
            //  summary:
            //      This is a no-op.
            return;
        },

        "getLabel": function(/* object */ item) {
            //  summary:
            //      Return the name of the attribute that should serve as the
            //      label for objects of the same class as *item*.  This is
            //      done by consulting fieldmapper and looking for the field
            //      with "selector" set to true.
            var self = this;

            return dojo.map(
                this.getLabelAttributes(),
                function(o) { self.getValue(item, o); }
            ).join(this.label_separator);
        },

        "getLabelAttributes": function(/* object */ item) {
            //  summary:
            //      This is simply a deeper method supporting getLabel().
            if (dojo.isArray(this.label_attributes)) {
                return this.label_attributes;
            }

            var fmclass = fieldmapper.IDL.fmclasses[item];
            var sels = dojo.filter(
                fmclass.fields,
                function(c) { return Boolean(c.selector); }
            );
            if (sels.length) return sels;
            else return [fmclass.pkey];
        },

        "loadItem": function(/* object */ keywordArgs) {
            //  summary:
            //      Fully load the item specified in the *item* property of
            //      *keywordArgs* by retrieving it from PermaCrud.
            //
            //  description:
            //      In non-stubby mode (default) this ultimately just returns the
            //      same object it's given.  In stubby mode, the object might
            //      not really be fully loaded, so we go to PermaCrud for it.
            //
            //      This method (part of the Read API) is dependent on
            //      fetchItemByIdentity() (part of the Identity API), so don't
            //      split the two up unless you know what you're doing.
            if (!this.isItem(keywordArgs.item))
                throw new PCSError("that's not an item; can't load it");

            keywordArgs.identity = keywordArgs.item[this.pkey]();
            return this.fetchItemByIdentity(keywordArgs);
        },

        "fetch": function(/* request-object */ req) {
            //  summary:
            //      Basically, fetch objects matching the *query* property of
            //      the *req* parameter.
            //
            //  description:
            //      In non-stubby mode (default) this means translaating the
            //      *query* in to a pcrud search filter and storing all the
            //      objects that result from that search, up to fetch_limit
            //      (a property of the store itself, set via the constructor).
            //
            //      In stubby mode, this means the same as above except that
            //      we only ask pcrud for an ID list, and what we store are
            //      "fake" objects with only the identifier field set.
            //
            //      In both modes, we also respect the following properties
            //      of the *req* object (all optional):
            //
            //          sort     an object that gets translated to order_by
            //          count    an int that gets translated to limit
            //          start    an int that gets translated to offset
            //          onBegin  a callback that takes the number of items
            //                      that this call to fetch() will return, but
            //                      we always give it -1 (i.e. unknown)
            //          onItem   a callback that takes each item as we get it
            //          onComplete  a callback that takes the list of items
            //                          after they're all fetched
            //
            //      The onError callback is ignored. I've never seen PermaCrud
            //      actually execute its own onerror callback, so this remains
            //      to be figured out.
            //
            //      The Read API also charges this method with adding an abort
            //      callback to the *req* object for the caller's use, but
            //      the one we provide does nothing but issue an alert().
            var parts = this._dojo_query_to_pcrud(req);
            var filter = parts[0];
            var opts = parts[1];
            var hashkey = parts[2];

            if (!filter) return req; /* nothing to do */

            /* set up some closures... */
            var self = this;
            var fetch_results = [];
            var callback_scope = req.scope || dojo.global;

            var process_fetch = function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (self.stubby) {
                        var id = r;
                        r = new fieldmapper[self.fmclass]();
                        r[self.pkey](id);
                        r._loaded = false;
                    } else {
                        r._loaded = true;
                    }
                    if (typeof req.onItem == "function")
                        req.onItem.call(callback_scope, r, req);

                    self._stored_items[r[self.pkey]()] = r;
                    fetch_results.push(r);
                    self._query_cache.add(hashkey, r);
                }
            };
            req.abort = function() {
                alert("The 'abort' operation is not supported");
            };

            /* ... and proceed. */

            if (typeof req.onBegin == "function")
                req.onBegin.call(callback_scope, -1, req);

            fetch_results = this._query_cache.get(hashkey);
            if (!fetch_results.length) {
                this._query_cache.clear(hashkey);
                this.pcrud.search(
                    this.fmclass, filter, dojo.mixin(opts, {
                        "streaming": true,
                        "timeout": 10,  /* important: streaming but sync */
                        "onresponse": process_fetch
                    })
                );
            }

            /* XXX at the moment, I don't believe we need either to call
             * onItem nor to add to our internal "_stored_items" those items
             * that we just got from cache. */

            /* as for onError: I don't believe openils.PermaCrud supports any
             * onerror-like callback in an actually working way at this time */

            if (typeof req.onComplete == "function")
                req.onComplete.call(callback_scope, fetch_results, req);

            return req;
        },

        /* *** Begin dojo.data.api.Identity methods *** */

        "getIdentity": function(/* object */ item) {
            //  summary:
            //      Given an *item* return its unique identifier (the value
            //      of its primary key).
            if (!this.isItem(item)) throw new PCSError("not an item");
            if (this._stored_items[item[this.pkey]()] == item)
                return item[this.pkey]();
            else
                return null;
        },

        "getIdentityAttributes": function(/* object */ item) {
            //  summary:
            //      Given an *item* return the list of the name of the fields
            //      that constitute the item's unique identifier.  Since we
            //      deal with fieldmapper objects, that's always a list of one.
            return [this.pkey];
        },

        "fetchItemByIdentity": function(/* object */ keywordArgs) {
            //  summary:
            //      Given an *identity* property in the *keywordArgs* object,
            //      retrieve an item, unless we already have the fully loaded
            //      item in the store's internal memory.
            //
            //  description:
            //      Once we've have the item we want one way or another, issue
            //      the *onItem* callback from the *keywordArgs* object.  If we
            //      tried to retrieve the item with pcrud but didn't get an item
            //      back, issue the *onError* callback.
           if (keywordArgs.identity == undefined)
                return null; // Identity API spec unclear whether error callback
                             // would need to be run, so we won't.  Matters
                             // because in some cases pcrud times out when attempting
                             // to retrieve by a null PK value
            var callback_scope = keywordArgs.scope || dojo.global;
            var test_item = this._stored_items[keywordArgs.identity];

            if (test_item && this.isItemLoaded(test_item)) {
                console.log(
                    "fetchItemByIdentity(): already have " +
                    keywordArgs.identity
                );
                if (typeof keywordArgs.onItem == "function")
                    keywordArgs.onItem.call(callback_scope, test_item);

                return test_item;
            } else {
                console.log(
                    "fetchItemByIdentity(): going to pcrud for " +
                    keywordArgs.identity
                );
                try {
                    var item =
                        this.pcrud.retrieve(this.fmclass, keywordArgs.identity);

                    if (!item)
                        throw new PCSError(
                            "No item of class " + this.fmclass +
                            " with identity " + keywordArgs.identity +
                            " could be retrieved."
                        );

                    item._loaded = true;
                    this._stored_items[item[this.pkey]()] = item;

                    if (typeof keywordArgs.onItem == "function")
                        keywordArgs.onItem.call(callback_scope, item);

                    return item;
                } catch (E) {
                    if (typeof keywordArgs.onError == "function")
                        keywordArgs.onError.call(callback_scope, E);

                    return null;
                }
            }
        },

        /* *** This last method is for classes implementing any dojo APIs *** */

        "getFeatures": function() {
            return {
                "dojo.data.api.Read": true,
                "dojo.data.api.Identity": true
            };
        }
    });
}
