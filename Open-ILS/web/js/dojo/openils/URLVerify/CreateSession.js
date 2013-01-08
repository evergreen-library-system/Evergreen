if (!dojo._hasResource["openils.URLVerify.CreateSession"]) {
    dojo.require("dojo.data.ItemFileWriteStore");
    dojo.require("dojox.jsonPath");
    dojo.require("fieldmapper.OrgUtils");
    dojo.require("openils.Util");
    dojo.require("openils.CGI");
    dojo.require("openils.PermaCrud");
    dojo.require("openils.widget.FilteringTreeSelect");
    dojo.require("openils.URLVerify.Verify");

    dojo.requireLocalization("openils.URLVerify", "URLVerify");

    dojo._hasResource["openils.URLVerify.CreateSession"] = true;
    dojo.provide("openils.URLVerify.CreateSession");

    dojo.declare("openils.URLVerify.CreateSession", null, {});

    /* Take care that we add nothing to the global namespace. */

(function() {
    var module = openils.URLVerify.CreateSession;
    var localeStrings =
        dojo.i18n.getLocalization("openils.URLVerify", "URLVerify");
    var uvus_progress = 0;

    /* Take search text box input, selected saved search ids, and selected
     * scope shortname to produce one search string. */
    module._prepare_search = function(basic, saved, scope) {
        if (saved.length) {
            basic += " " + dojo.map(
                saved, function(s) { return "saved_query(" + s + ")"; }
            ).join(" ");
        }

        if (scope && !basic.match(/site\(.+\)/))
            basic += " site(" + scope + ")";

        return basic;
    };

    /* Reacting to the interface's "Begin" button, this function triggers the
     * first of three server-side processes necessary to create a session:
     *
     * 1) create the session itself (API call), */
    module.begin = function() {
        var name = uv_session_name.attr("value");

        var scope;
        try {
            scope = module.org_selector.store.getValue(
                module.org_selector.item,
                "shortname"
            );
        } catch (E) {
            /* probably nothing valid is selected; move on */
            void(0);
        }

        var search = module._prepare_search(
            uv_search.attr("value"),
            dojo.filter(
                dojo.byId("saved-searches").options,
                function(o) { return o.selected; }
            ).map(
                function(o) { return o.value; }
            ),
            scope
        );

        if (!module.tag_and_subfields.any()) {
            alert(localeStrings.NEED_UVUS);
            return;
        }

        module.progress_dialog.attr("title", localeStrings.CREATING);
        module.progress_dialog.show(true);
        fieldmapper.standardRequest(
            ["open-ils.url_verify", "open-ils.url_verify.session.create"], {
                "params": [openils.User.authtoken, name, search],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        /* I think we're modal enough to get away with this. */
                        module.session_id = r;
                        module.save_tags();
                    } else {
                        module.progress_dialog.hide();
                    }
                }
            }
        );
    };

    /* 2a) save the tag/subfield sets for URL extraction, */
    module.save_tags = function() {
        module.progress_dialog.attr("title", localeStrings.SAVING_TAGS);
        module.progress_dialog.show(); /* sic */

        uvus_progress = 0;

        /* Note we're not using openils.PermaCrud, which is inadequate
         * when you need one big transaction. Thanks for figuring it
         * out Bill. */
        var pcrud_raw = new OpenSRF.ClientSession("open-ils.pcrud");

        pcrud_raw.connect();

        pcrud_raw.request({
            "method": "open-ils.pcrud.transaction.begin",
            "params": [openils.User.authtoken],
            "oncomplete": function(r) {
                module._create_uvus_one_at_a_time(
                    pcrud_raw,
                    module.tag_and_subfields.generate_uvus(module.session_id)
                );
            }
        }).send();
    };

    /* 2b */
    module._create_uvus_one_at_a_time = function(pcrud_raw, uvus_list) {
        pcrud_raw.request({
            "method": "open-ils.pcrud.create.uvus",
            "params": [openils.User.authtoken, uvus_list[0]],
            "oncomplete": function(r) {
                var new_uvus = openils.Util.readResponse(r);
                module.progress_dialog.update(
                    {"maximum": uvus_list.length, "progress": ++uvus_progress}
                );

                uvus_list.shift();  /* /now/ actually shorten working list */

                if (uvus_list.length < 1) {
                    pcrud_raw.request({
                        "method": "open-ils.pcrud.transaction.commit",
                        "params": [openils.User.authtoken],
                        "oncomplete": function(r) {
                            pcrud_raw.disconnect();
                            module.perform_search();
                        }
                    }).send();

                } else {
                    module._create_uvus_one_at_a_time(
                        pcrud_raw, uvus_list
                    );
                }
             }
        }).send();
    };

    /* 3) search and populate the container (API call). */
    module.perform_search = function() {
        var search_result_count = 0;

        module.progress_dialog.attr("title", localeStrings.PERFORMING_SEARCH);
        module.progress_dialog.show(true);

        fieldmapper.standardRequest(
            ["open-ils.url_verify",
                "open-ils.url_verify.session.search_and_extract"], {
                "params": [openils.User.authtoken, module.session_id],
                "async": true,
                "onresponse": function(r) {
                    r = openils.Util.readResponse(r);
                    if (!search_result_count) {
                        search_result_count = Number(r);

                        module.progress_dialog.show(); /* sic */
                        module.progress_dialog.attr(
                            "title", localeStrings.EXTRACTING_URLS
                        );
                        module.progress_dialog.update(
                            {"maximum": search_result_count, "progress": 0}
                        );
                    } else {
                        module.progress_dialog.update({"progress": r.length})
                    }
                },
                "oncomplete": function() {
                    module.progress_dialog.attr(
                        "title", localeStrings.REDIRECTING
                    );
                    module.progress_dialog.show(true);

                    if (no_url_selection.checked) {
                        /* verify URLs and ultimately redirect to review page */
                        openils.URLVerify.Verify.go(
                            module.session_id, null, module.progress_dialog
                        );
                    } else {
                        /* go to the URL selection page, allowing users to
                         * selectively verify URLs */
                        location.href = oilsBasePath +
                            "/url_verify/select_urls?session_id=" +
                            module.session_id;
                    }
                }
            }
        );
    };

    /* At least in Dojo 1.3.3 (I know, I know), dijit.form.MultiSelect does
     * not behave like FilteringSelect, like you might expect, or work from a
     * data store.  So we'll use a native <select> control, which will have
     * fewer moving parts that can go haywire anyway.
     */
    module._populate_saved_searches = function(node) {
        var list = module.pcrud.retrieveAll(
            "asq", {"order_by": {"asq": "label"}}
        );

        dojo.forEach(
            list, function(o) {
                dojo.create(
                    "option", {
                        "innerHTML": o.label(),
                        "value": o.id(),
                        "title": o.query_text()
                    }, node, "last"
                );
            }
        );
    };

    /* set up an all-org-units-in-the-tree selector */
    module._prepare_org_selector = function(node) {
        var widget = new openils.widget.FilteringTreeSelect(null, node);
        widget.searchAttr = "name";
        widget.labelAttr = "name";
        widget.tree = fieldmapper.aou.globalOrgTree;
        widget.parentField = 'parent_ou';
        widget.startup();
        widget.attr("value", openils.User.user.ws_ou());

        module.org_selector = widget;
    };

    /* Can only be called by setup() */
    module._clone = function(id) {
        module.progress_dialog.attr("title", localeStrings.CLONING);
        var old_session = module.pcrud.retrieve(
            "uvs", id, {"flesh": 1, "flesh_fields": {"uvs": ["selectors"]}}
        );

        /* Set name to "Copy of [old name]" */
        uv_session_name.attr(
            "value", dojo.string.substitute(
                localeStrings.CLONE_SESSION_NAME, [old_session.name()]
            )
        );

        /* Set search field. */
        uv_search.attr("value", old_session.search());

        /* Explain to user why we don't affect the saved searches picker. */
        if (old_session.search().match(/saved_query/))
            openils.Util.show("clone-saved-search-warning");

        /* Add related xpaths (URL selectors) to TagAndSubfieldsMgr. */
        module.tag_and_subfields.add_xpaths(old_session.selectors());
    };

    module.setup = function(saved_search_id, org_selector_id, progress_dialog) {
        module.pcrud = new openils.PermaCrud(); /* only used for setup */

        module.progress_dialog = progress_dialog;

        module.progress_dialog.attr("title", localeStrings.INTERFACE_SETUP);
        module.progress_dialog.show(true);

        module._populate_saved_searches(dojo.byId(saved_search_id));
        module._prepare_org_selector(dojo.byId(org_selector_id));

        var cgi = new openils.CGI();
        if (cgi.param("clone"))
            module._clone(cgi.param("clone"));

        module.pcrud.disconnect();

        module.progress_dialog.hide();
    };

    /* This is the thing that lets you add/remove rows of tab/subfield pairs */
    function TagAndSubfieldsMgr(container_id) {
        var self = this;

        this.container_id = container_id;
        this.counter = 0;

        this.read_new = function() {
            var controls = dojo.query(".tag-and-subfield-add-another input");

            return {
                "tag": controls[0].value,
                "subfields": openils.Util.uniqueElements(
                    controls[1].value.replace(/[^0-9a-z]/g, "").split("")
                ).sort().join("")
            };
        };

        this.add = function() {
            var newdata = this.read_new();
            var newid = "t-and-s-row-" + String(this.counter++);
            var div = dojo.create(
                "div", {
                    "id": newid,
                    "innerHTML": "<span class='t-and-s-tag'>" +
                        newdata.tag +
                        "</span> \u2021<span class='t-and-s-subfields'>" +
                        newdata.subfields + "</span> "
                }, this.container_id, "last"
            );
            dojo.create(
                "a", {
                    "href": "javascript:void(0);",
                    "onclick": function() {
                        var me = dojo.byId(newid);
                        me.parentNode.removeChild(me);
                    },
                    "innerHTML": "[X]" /* XXX i18n */
                }, div, "last"
            );
        };

        this.add_xpaths = function(xpaths) {
            if (!dojo.isArray(xpaths)) {
                console.info("No xpaths to add");
                return;
            }

            dojo.forEach(
                xpaths, dojo.hitch(this, function(xpath) {
                    var newid = "t-and-s-row-" + String(this.counter++);
                    var div = dojo.create(
                        "div", {
                            "id": newid,
                            "innerHTML": localeStrings.XPATH +
                                " <span class='t-and-s-xpath'>" +
                                xpath.xpath() + "</span>"
                        }, this.container_id, "last"
                    );
                    dojo.create(
                        "a", {
                            "href": "javascript:void(0);",
                            "onclick": function() {
                                var me = dojo.byId(newid);
                                me.parentNode.removeChild(me);
                            },
                            "innerHTML": "[X]" /* XXX i18n */
                        }, div, "last"
                    );
                })
            );
        };

        /* return a boolean indicating whether or not we have any rows */
        this.any = function() {
            return Boolean(
                dojo.query(
                    '[id^="t-and-s-row-"]', dojo.byId(this.container_id)
                ).length
            );
        };

        /* Return one uvus object for each unique tag we have a row for,
         * and use the given session_id for the uvus.session field. */
        this.generate_uvus = function(session_id) {
            var uniquely_grouped = {};
            dojo.query(
                '[id^="t-and-s-row-"]', dojo.byId(this.container_id)
            ).forEach(
                function(row) {
                    var holds_xpath = dojo.query(".t-and-s-xpath", row);
                    if (holds_xpath.length) {
                        uniquely_grouped.xpath = uniquely_grouped.xpath || [];
                        uniquely_grouped.xpath.push(holds_xpath[0].innerHTML);
                    } else {
                        var tag = dojo.query(".t-and-s-tag", row)[0].innerHTML;
                        var subfield =
                            dojo.query(".t-and-s-subfields", row)[0].innerHTML;

                        var existing;
                        if ((existing = uniquely_grouped[tag])) { // assignment
                            existing = openils.Util.uniqueElements(
                                (existing + subfield).split("")
                            ).sort().join("");
                        } else {
                            uniquely_grouped[tag] = subfield;
                        }
                    }
                }
            );

            var uvus_list = [];
            /* Handle things that are already in XPath form first (these
             * come from cloning link checker sessions. */
            if (uniquely_grouped.xpath) {
                dojo.forEach(
                    uniquely_grouped.xpath,
                    function(xpath) {
                        var obj = new uvus();

                        obj.session(session_id);
                        obj.xpath(xpath);
                        uvus_list.push(obj);
                    }
                );
                delete uniquely_grouped.xpath;
            }

            /* Now handle anything entered by hand. */
            for (var tag in uniquely_grouped) {
                var obj = new uvus();

                obj.session(session_id);

                /* XXX TODO Handle control fields (No subfields. but would
                 * control fields ever contain URLs? Don't know.) */
                obj.xpath(
                    "//*[@tag='" + tag + "']/*[" +
                    uniquely_grouped[tag].split("").map(
                        function(c) { return "@code='" + c + "'"; }
                    ).join(" or ") +
                    "]"
                );

                uvus_list.push(obj);
            }

            return uvus_list;
        };

    }

    module.tag_and_subfields =
        new TagAndSubfieldsMgr("uv-tags-and-subfields");

}());

}
