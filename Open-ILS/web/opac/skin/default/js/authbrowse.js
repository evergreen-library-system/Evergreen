dojo.require("openils.CGI");
dojo.require("openils.Util");
dojo.require("MARC.FixedFields");
dojo.require("openils.AuthorityControlSet");
var cgi, acs_helper, last_fetched_length = 0;

attachEvt("common", "init", doAuthorityBrowse);

/* repeatable, supports all args or no args */
function doAuthorityBrowse(axis, term, page, per_page) {
    swapCanvas(dojo.byId("loading_alt"));

    if (!axis) {
        if (!cgi) cgi = new openils.CGI();
        axis = cgi.param(PARAM_AUTHORITY_BROWSE_AXIS);
        term = cgi.param(PARAM_AUTHORITY_BROWSE_TERM);
        page = cgi.param(PARAM_AUTHORITY_BROWSE_PAGE) || 0;
        per_page = cgi.param(PARAM_AUTHORITY_BROWSE_PER_PAGE) || 20;
    }

    var url = '/opac/extras/browse/marcxml/authority.'
        + axis
        + '/1' /* this will be OU if OU ever means anything for authorities */
        + '/' + term /* FIXME urlescape or however it's spelt */
        + '/' + page
        + '/' + per_page
    ;
    dojo.xhrGet({
        "url": url,
        "handleAs": "xml",
        "content": {"format": "marcxml"},
        "preventCache": true,
        "load": function(doc) {
            displayAuthorityRecords(doc);
            setPagingLinks(axis, term, page, per_page);
        }
    });
}

function setPagingLinks(axis, term, page, per_page) {
    var up_page = Number(page) - 1;
    var down_page = Number(page) + 1;

    unHideMe(dojo.byId("authority-page-up"));
    dojo.attr(
        "authority-page-up", "onclick", function() {
            doAuthorityBrowse(axis, term, up_page, per_page);
        }
    );

    /* XXX In theory this would generally stop the "next page" link from
     * showing up when it's unwanted, but in practice the supercat/unapi
     * call we make doesn't return the number of records it's supposed to.
     */
//    if (last_fetched_length == per_page) {
        unHideMe(dojo.byId("authority-page-down"));
        dojo.attr(
            "authority-page-down", "onclick", function() {
                doAuthorityBrowse(axis, term, down_page, per_page);
            }
        );
//    } else {
//        hideMe(dojo.byId("authority-page-down"));
//    }
}

function renderAuthorityTagContent(m, af) {
    /* XXX This doesn't take into account possible tag repeatability -- a
     * bona fide library scientist could probably improve this. :-)
     */
    if (af.tag() && af.sf_list()) {
        return dojo.filter(
            dojo.map(
                af.sf_list().split(""),
                function(code) {
                    var result = m.subfield(af.tag(), code);
                    return (typeof(result[1]) == "undefined") ? "" : result[1];
                }
            ), function(datum) { return datum.length > 0; }
        ).join(" ");
    } else {
        return "";
    }
}

function renderAuthoritySubEntry(m, field, tbody) {
    var content =
        openils.Util.trimString(renderAuthorityTagContent(m, field));
    if (!content.length) return;    /* don't display empty tags */

    var tr = dojo.create("tr", null, tbody);
    dojo.create("td", {"style": {"width": "2em"}, "innerHTML": ""}, tr);
    dojo.create(
        "td", {
            "className": "authority-tag-label",
            "innerHTML": field.name() + ":",
            "title": field.description() || ""
        }, tr
    );
    dojo.create(
        "td", {
            "className": "authority-tag-content authority-record-right",
            "innerHTML": content
        }, tr
    );

    if (field.sub_entries() && field.sub_entries().length) {
        /* I *think* this shouldn't happen with good data? */
        console.log("I, too, have " + field.sub_entries().length +
            "sub_entries");
    }
}

function renderAuthorityMainEntry(m, field, tbody) {
    var content =
        openils.Util.trimString(renderAuthorityTagContent(m, field));
    if (!content.length) return;    /* don't display empty tags */

    var tr = dojo.create("tr", null, tbody);
    var content_holder = dojo.create(
        "td", {
            "className": "authority-tag-content authority-record-main",
            "colspan": 2
        }, tr
    );
    dojo.create(
        "span",
        {"className":"authority-content", "innerHTML": content},
        content_holder
    );
    dojo.create("span", {"className":"authority-count-holder"}, content_holder);
    dojo.create(
        "td", {
            "className": "authority-tag-label authority-record-right",
            "innerHTML": field.name(),
            "title": field.description() || ""
        }, tr
    );

    if (field.sub_entries()) {
        dojo.forEach(
            field.sub_entries(),
            function(f) { renderAuthoritySubEntry(m, f, tbody); }
        );
    }
}

function renderAuthorityRecord(m, control_set, auth_id) {
    var main_entries = openils.Util.objectSort(
        dojo.filter(
            control_set.authority_fields(),
            function(o) { return o.main_entry() == null; }
        ), "tag"
    );

    var table = dojo.create("table", {"className": "authority-record"});
    var tbody = dojo.create("tbody", {"id": "authority_" + auth_id}, table);

    dojo.forEach(
        main_entries, function(af) { renderAuthorityMainEntry(m, af, tbody); }
    );

    return table;
}

/* displayAuthorityRecords: given a DOM document object that contains marcxml
 * records, display each one in a table using the apporiate control set to
 * determine which fields to show.
 */
function displayAuthorityRecords(doc) {
    if (!acs_helper)
        acs_helper = new openils.AuthorityControlSet();

    /* XXX I wanted to use bibtemplate here, but now I'm not sure it makes
     * sense: the template itself would have to be dynamic, as it would vary
     * from record to record when different control sets were in use.
     */
    var auth_ids = [];

    dojo.empty("authority-record-holder");

    var records = dojo.query("record", doc);
    last_fetched_length = records.length;
    console.log("length here is " + last_fetched_length);

    dojo.forEach(
        records,
        function(record) {
            var m = new MARC.Record({"xml": record});

            /* is 001 reliable for this? I'm guessing not */
            var auth_id = m.field("001").data;
            auth_ids.push(auth_id);

            var cs = acs_helper.controlSetByThesaurusCode(
                m.extractFixedField("Subj")
            );

            dojo.place(
                renderAuthorityRecord(m, cs.raw, auth_id),
                "authority-record-holder"
            );
        }
    );
    displayRecordCounts(auth_ids);
    swapCanvas(dojo.byId("canvas_main"));
}

function displayRecordCounts(auth_ids) {
    fieldmapper.standardRequest(
        ["open-ils.cat", "open-ils.cat.authority.records.count_linked_bibs"], {
            "params": [auth_ids],
            "async": true,
            "oncomplete": function(r) {
                if ((r = openils.Util.readResponse(r))) {
                    dojo.forEach(r, function(blob) {
                        if (blob.bibs > 0) {
                            displayRecordCount(blob.authority, blob.bibs);
                        }
                    });
                }
            }
        }
    );
}

function displayRecordCount(id, count) {
    /* 1) put record count where we can see it */
    dojo.query("#authority_" + id + " .authority-count-holder")[0].innerHTML =
        "(" + count + ")"; /* XXX i18n ? */

    /* 2) also, provide a link to show those records */
    var span = dojo.query("#authority_" + id + " .authority-content")[0];

    var args = {};
    args.page = RRESULT;
    args[PARAM_DEPTH] = depthSelGetDepth();
    args[PARAM_FORM] = "all";
    args[PARAM_LOCATION] = depthSelGetNewLoc();
    args[PARAM_TERM] = "identifier|authority_id[" + id + "]";

    dojo.create(
        "a", {
            "innerHTML": span.innerHTML,
            "href": buildOPACLink(args),
            "className": "authority-content",
            "title": "Show related bibliographic holdings" /* XXX i18n! */
        },
        span, "replace"
    );
}

