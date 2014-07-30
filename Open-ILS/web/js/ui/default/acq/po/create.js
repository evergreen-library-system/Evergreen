dojo.require("openils.widget.EditDialog");
dojo.require("openils.widget.EditPane");
dojo.require("openils.PermaCrud");
dojo.require("openils.User");
dojo.require("fieldmapper.OrgUtils");

dojo.requireLocalization('openils.acq', 'acq');
var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');

var editDialog, selectedAgency, currentName;

function toPoListing() {
    location.href = oilsBasePath + "/acq/search/unified?ca=po";
}

function toOnePo(id) {
    location.href = oilsBasePath + "/acq/po/view/" + id;
}

openils.Util.addOnLoad(
    function() {

        // apply here in case the selector never changes
        // (i.e. no onchange fires).
        selectedAgency = openils.User.user.ws_ou();

        // called each time the PO name changes
        function name_changed(new_name) {
            currentName = new_name;

            console.debug('checking for PO name collision + "' 
                + currentName + '" at ' + selectedAgency);

            if (!new_name) { // name cleared
                editDialog.editPane.saveButton.attr('disabled', false);
                return;
            }

            // disable Save option pending confirmation of uniqueness
            editDialog.editPane.saveButton.attr('disabled', true);

            var orgs = fieldmapper.aou.descendantNodeList(selectedAgency, true);
            new openils.PermaCrud().search('acqpo', 
                {name : new_name, ordering_agency : orgs},
                {async : true, oncomplete : function(r) {
                    var po = openils.Util.readResponse(r);
                    var tbody = editDialog.editPane.table.getElementsByTagName('tbody')[0];

                    // remove any previous dupe warning row
                    dojo.forEach(tbody.getElementsByTagName('tr'), function(row) {
                        if (row) { // sometimes row is undefined??
                            if (row.getAttribute('dupe-po-row'))
                                tbody.removeChild(row);
                        }
                    });

                    if (po && (po = po[0])) {
                        // duplicate found.  add info row to create dialog

                        var parent_row;
                        dojo.forEach(tbody.getElementsByTagName('tr'), function(row) {
                            if (row.getAttribute('fmfield') == 'name')
                                parent_row = row;
                        });

                        var new_tr = dojo.create('tr', {'dupe-po-row' : 1});
                        var link = dojo.create('a', {
                            href : 'javascript:;', 
                            innerHTML : localeStrings.DUPE_PO_NAME_LINK
                        });

                        var dupe_path = '/acq/po/view/' + po.id();

                        if (window.xulG) {

                            if (window.IAMBROWSER) {
                                // TODO: integration

                            } else {
                                // XUL client
                                link.onclick = function() {

                                    var loc = xulG.url_prefix('XUL_BROWSER?url=') + 
                                        window.encodeURIComponent( 
                                        xulG.url_prefix('EG_WEB_BASE' + dupe_path)
                                    );

                                    xulG.new_tab(loc, 
                                        {tab_name: '', browser:false},
                                        {
                                            no_xulG : false, 
                                            show_nav_buttons : true, 
                                            show_print_button : true, 
                                        }
                                    );
                                }
                            }

                        } else {
                            link.onclick = function() {
                                window.open(oilsBasePath + dupe_path, '_blank').focus();
                            }
                        }

                        new_tr.appendChild(dojo.create('td', 
                            {innerHTML : localeStrings.DUPE_PO_NAME_MSG}));
                        var link_td = dojo.create('td');
                        link_td.appendChild(link);
                        new_tr.appendChild(link_td);
                        tbody.insertBefore(new_tr, parent_row.nextSibling);

                    } else {
                        editDialog.editPane.saveButton.attr('disabled', false);
                    }
                }}
            );
        }

        function agency_changed(val) {
            selectedAgency = val;
            if (currentName) {
                // if the ordering agency changes, re-run the dupe name check.
                name_changed(currentName);
            }
        }

        editDialog = new openils.widget.EditDialog({
            "editPane": new openils.widget.EditPane({
                "fmObject": new acqpo(),
                /* After realizing how many fields should be excluded from this
                 * interface because users shouldn't set them arbitrarily,
                 * it hardly seems like using these Edit widgets gives much
                 * much advantage over a hardcoded interface. */
                "suppressFields": [
                    "create_time", "edit_time", "editor", "order_date",
                    "owner", "cancel_reason", "creator", "state"
                ],
                "fieldOrder": ["ordering_agency", "name", "provider"],
                "mode": "create",
                overrideWidgetArgs : {
                    provider : { dijitArgs : { store_options : { base_filter : { active :"t" } } } },
                    ordering_agency : { 
                        orgDefaultsToWs : true,
                        dijitArgs : {onChange : agency_changed}
                    },
                    name : {dijitArgs : {onChange : name_changed}}
                },
                "onSubmit": function(po) {
                    fieldmapper.standardRequest(
                        ["open-ils.acq", "open-ils.acq.purchase_order.create"],{
                            "async": false,
                            "params": [openils.User.authtoken, po],
                            "onresponse": function(r) {
                                toOnePo(
                                    openils.Util.readResponse(r).
                                    purchase_order.id()
                                );
                            }
                        }
                    );
                },
                "onCancel": function() {
                    editDialog.hide();
                    toPoListing();
                    /* I'd rather do window.close() or xulG.close_tab(),
                     * but neither of those seem to work here. */
                }
            })
        });
        editDialog.startup();
        editDialog.show();

        // modify the label of the 'name' field to make it more clear it's optional
        var row = dojo.query('[fmfield=name]', editDialog.editPane.table)[0];
        var name_td = row.getElementsByTagName('td')[0];
        name_td.innerHTML = dojo.string.substitute(
            localeStrings.PO_NAME_OPTIONAL,
            [name_td.innerHTML]
        );
    }
);
