if (!dojo._hasResource["openils.URLVerify.CreateSession"]) {
    dojo.require("dojo.data.ItemFileWriteStore");
    dojo.require("dojox.jsonPath");
    dojo.require("fieldmapper.OrgUtils");
    dojo.require("openils.Util");
    dojo.require("openils.PermaCrud");
    dojo.require("openils.widget.FilteringTreeSelect");

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
                    }
                }
            }
        );
    };

    /* 2) save the tag/subfield sets for URL extraction, */
    module.save_tags = function() {
        module.progress_dialog.attr("title", localeStrings.SAVING_TAGS);
        module.progress_dialog.show(); /* sic */

        uvus_progress = 0;

        /* Note we're not using openils.PermaCrud, which is inadequate
         * when you want transactions. Thanks for figuring it out, Bill. */
        var pcrud_raw = new OpenSRF.ClientSession("open-ils.pcrud");

        pcrud_raw.connect();

        pcrud_raw.request({
            "method": "open-ils.pcrud.transaction.begin",
            "params": [openils.User.authtoken],
            "oncomplete": function(r) {
                module._create_uvus_one_at_a_time(
                    pcrud_raw,
                    module.tag_and_subfields.generate_uvus(
                        module.session_id
                    )
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

                uvus_list.shift();  /* /now/ actually shorten the list */

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
    var search_result_count = 0;
    module.perform_search = function() {
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
                        location.href = oilsBasePath +
                            "/url_verify/validation_review?" +
                            "session_id=" + module.session_id +
                            "&validate=1";
                    } else {
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
        var pcrud = new openils.PermaCrud();
        var list = pcrud.retrieveAll(
            "asq", {"order_by": {"asq": "label"}}
        );

        dojo.forEach(
            list,
            function(o) {
                dojo.create(
                    "option", {
                        "innerHTML": o.label(),
                        "value": o.id(),
                        "title": o.query_text()
                    }, node, "last"
                );
            }
        );

        pcrud.disconnect();
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

    module.setup = function(saved_search_id, org_selector_id, progress_dialog) {
        module.progress_dialog = progress_dialog;

        module.progress_dialog.attr("title", localeStrings.INTERFACE_SETUP);
        module.progress_dialog.show(true);

        module._populate_saved_searches(dojo.byId(saved_search_id));
        module._prepare_org_selector(dojo.byId(org_selector_id));

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

            this.counter++;
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
                    var tag = dojo.query(".t-and-s-tag", row)[0].innerHTML;
                    var subfield = dojo.query(".t-and-s-subfields", row)[0].innerHTML;

                    var existing;
                    if ((existing = uniquely_grouped[tag])) { /* sic, assignment */
                        existing = openils.Util.uniqueElements(
                            (existing + subfield).split("")
                        ).sort().join("");
                    } else {
                        uniquely_grouped[tag] = subfield;
                    }
                }
            );

            var uvus_list = [];
            for (var tag in uniquely_grouped) {
                var obj = new uvus();

                obj.session(session_id);

                /* XXX TODO handle control fields (no subfields) */
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
