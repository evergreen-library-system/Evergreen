dojo.require("openils.CGI");
dojo.require("openils.Util");
dojo.require("MARC.FixedFields");
dojo.require("openils.AuthorityControlSet");
var cgi;

attachEvt("common", "init", doAuthorityBrowse);

/* repeatable, supports all args or no args */
function doAuthorityBrowse(axis, term, page, per_page) {
    if (!axis) {
        if (!cgi) cgi = new openils.CGI();
        axis = cgi.param(PARAM_AUTHORITY_BROWSE_AXIS);
        term = cgi.param(PARAM_AUTHORITY_BROWSE_TERM);
        page = 0;
        per_page = 20;
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
        "load": displayAuthorityRecords
    });
}

function renderAuthorityTagContent(m, af) {
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
    dojo.create(
        "td", {
            "className": "authority-tag-content authority-record-main",
            "innerHTML": content,
            "colspan": 2
        }, tr
    );
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

function renderAuthorityRecord(m, control_set) {
    var main_entries = openils.Util.objectSort(
        dojo.filter(
            control_set.authority_fields(),
            function(o) { return o.main_entry() == null; }
        ), "tag"
    );

    var table = dojo.create("table", {"className": "authority-record"});
    var tbody = dojo.create("tbody", null, table);

    dojo.forEach(
        main_entries, function(af) { renderAuthorityMainEntry(m, af, tbody); }
    );

    return table;
}

function displayAuthorityRecords(doc) {
    var acs_helper = new openils.AuthorityControlSet();

    /* XXX I wanted to use bibtemplate here, but now I'm not sure it makes
     * sense: the template itself would have to be dynamic, as it would vary
     * from record to record when different control sets were in use.
     */
    dojo.query("record", doc).forEach(
        function(record) {
            var m = new MARC.Record({"xml": record});
            var s = m.extractFixedField("Subj");
            var cs = acs_helper.controlSetByThesaurusCode(s);
            dojo.place(renderAuthorityRecord(m, cs.raw), "test-holder");
        }
    );
}
