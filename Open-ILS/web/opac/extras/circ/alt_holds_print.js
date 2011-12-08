dojo.require("dojo.cookie");
dojo.require("dojox.xml.parser");
dojo.require("openils.BibTemplate");
dojo.require("openils.widget.ProgressDialog");

var authtoken;
var cgi;

function do_pull_list() {
    progress_dialog.show(true);

    var any = false;

    fieldmapper.standardRequest(
        ['open-ils.circ','open-ils.circ.hold_pull_list.print.stream'],
        { async : true,
          params: [
            authtoken, {
              org_id     : cgi.param('o'),
              limit      : cgi.param('limit'),
              offset     : cgi.param('offset'),
              chunk_size : cgi.param('chunk_size'),
              sort       : sort_order
            }
          ],
          onresponse : function (r) {
            any = true;
            dojo.forEach( openils.Util.readResponse(r), function (hold_fm) {

                // hashify the hold
                var hold = hold_fm.toHash(true);
                hold.usr = hold_fm.usr().toHash(true);
                hold.usr.card = hold_fm.usr().card().toHash(true);
                hold.current_copy = hold_fm.current_copy().toHash(true);
                hold.current_copy.location = hold_fm.current_copy().location().toHash(true);
                hold.current_copy.call_number = hold_fm.current_copy().call_number().toHash(true);
                hold.current_copy.call_number.record = hold_fm.current_copy().call_number().record().toHash(true);
                hold.current_copy.call_number.prefix = hold_fm.current_copy().call_number().prefix().toHash(true);
                hold.current_copy.call_number.suffix = hold_fm.current_copy().call_number().suffix().toHash(true);
                hold.current_copy.parts_stringified = '';
                dojo.forEach( hold_fm.current_copy().parts(), function(part) {
                    hold.current_copy.parts_stringified += ' ' + part.label();
                });


                // clone the template's html
                var tr = dojo.clone(
                    dojo.query("tr", dojo.byId('template'))[0]
                );
                dojo.query("td:not([type])", tr).forEach(
                    function(td) {
                        td.innerHTML =
                            dojo.string.substitute(td.innerHTML, hold);
                    }
                );

                new openils.BibTemplate({
                    root : tr,
                    xml  : dojox.xml.parser.parse(hold.current_copy.call_number.record.marc),
                    delay: false
                });

                dojo.place(tr, "target");
            });
          },
          oncomplete : function () {
            progress_dialog.hide();
            setTimeout(
                function() {
                    if (any) window.print();
                    else alert(dojo.byId("no_results").innerHTML);
                }, 500  /* give the progress_dialog more time to go away */
            );
          }
        }
    );
}

function place_by_sortkey(node, container) {
    /*Don't use a forEach() or anything like that here. too slow.*/
    var sortkey = dojo.attr(node, "sortkey");
    for (var i = 0; i < container.childNodes.length; i++) {
        var rover = container.childNodes[i];
        if (rover.nodeType != 1) continue;
        if (dojo.attr(rover, "sortkey") > sortkey) {
            dojo.place(node, rover, "before");
            return;
        }
    }
    dojo.place(node, container, "last");
}

function hashify_fields(fields) {
    var hold  = {
        "usr": {},
        "current_copy": {
            "barcode": fields.barcode,
            "call_number": {
                "label": fields.label,
                "record": {"marc": fields.marc}
            },
            "location": {"name": fields.name}
        }
    };

    if (fields.alias) {
        hold.usr.display_name = fields.alias;
    } else {
        hold.usr.display_name = [
            (fields.family_name ? fields.family_name : ""),
            (fields.first_given_name ? fields.first_given_name : ""),
            (fields.second_given_name ? fields.second_given_name : "")
        ].join(" ");
    }

    ["first_given_name","second_given_name","family_name","alias"].forEach(
        function(k) { hold.usr[k] = fields[k]; }
    );

    hold.current_copy.call_number.prefix = fields.prefix;
    hold.current_copy.call_number.suffix = fields.suffix;
    hold.current_copy.parts_stringified = '';   /* no real support for parts here */
    return hold;
}

function do_clear_holds() {
    progress_dialog.show(true);

    var launcher;
    fieldmapper.standardRequest(
        ["open-ils.circ", "open-ils.circ.hold.clear_shelf.process"], {
            "async": true,
            "params": [authtoken, cgi.param("o")],
            "onresponse": function(r) {
                if (r = openils.Util.readResponse(r)) {
                    if (r.cache_key) { /* complete */
                        launcher = dojo.byId("clear_holds_launcher");
                        launcher.innerHTML = "Re-fetch for Printing"; /* XXX i18n */
                        launcher.onclick =
                            function() { do_clear_holds_from_cache(r.cache_key); };
                        dojo.byId("clear_holds_set_label").innerHTML = r.cache_key;
                    } else if (r.maximum) {
                        progress_dialog.update(r);
                    }
                }
            },
            "oncomplete": function() {
                progress_dialog.hide();
                if (launcher) launcher.onclick();
                else alert(dojo.byId("no_results").innerHTML);
            }
        }
    );
}

function do_clear_holds_from_cache(cache_key) {
    progress_dialog.show(true);

    var any = 0;
    var target = dojo.byId("target");
    dojo.empty(target);
    var template = dojo.query("tr", dojo.byId("template"))[0];
    fieldmapper.standardRequest(
        ["open-ils.circ",
            "open-ils.circ.hold.clear_shelf.get_cache"], {
            "async": true,
            "params": [authtoken, cache_key, cgi.param("chunk_size")],
            "onresponse": function(r) {
                dojo.forEach(
                    openils.Util.readResponse(r),
                    function(resp) {
                        if (resp.maximum) {
                            progress_dialog.update(resp);
                            return;
                        }

                        var hold = hashify_fields(resp.hold_details);
                        hold.action = resp.action;

                        var tr = dojo.clone(template);
                        any++;

                        dojo.query("td:not([type])", tr).forEach(
                            function(td) {
                                td.innerHTML =
                                    dojo.string.substitute(td.innerHTML, hold);
                            }
                        );

                        new openils.BibTemplate({
                            "root": tr,
                            "xml": dojox.xml.parser.parse(
                                hold.current_copy.call_number.record.marc
                            ),
                            "delay": false
                        });

                        dojo.attr(tr, "sortkey", hold.usr.display_name);
                        place_by_sortkey(tr, target);
                    }
                );
                progress_dialog.update({"progress": any});
            },
            "oncomplete": function() {
                progress_dialog.hide();
                setTimeout(
                    function() {
                        if (any) window.print();
                        else alert(dojo.byId("no_results").innerHTML);
                    }, 500  /* give the progress_dialog more time to go away */
                );
            }
        }
    );
}

