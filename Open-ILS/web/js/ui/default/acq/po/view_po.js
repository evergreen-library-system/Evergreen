dojo.require("dijit.form.Button");
dojo.require("dojo.string");
dojo.require('dijit.layout.ContentPane');
dojo.require('openils.PermaCrud');

var pcrud = new openils.PermaCrud();
var PO = null;
var liTable;
var poItemTable;
var poNoteTable;
var invoiceLinkDialogManager;

function AcqPoNoteTable() {
    var self = this;

    this.notesTbody = dojo.byId("acq-po-notes-tbody");
    this.notesRow = this.notesTbody.removeChild(dojo.byId("acq-po-notes-row"));

    dojo.byId("acq-po-notes-back-button").onclick = function() { self.hide(); };
    dojo.byId("acq-po-view-notes").onclick = function() { self.show(); };

    /* widgets' event properties are cased likeThis */
    acqPoCreateNoteSubmit.onClick = function() {
        if (!acqPoCreateNoteText.attr("value")) return;

        /* prep new note */
        var note = new acqpon();
        note.vendor_public(
            Boolean(acqPoCreateNoteVendorPublic.attr('checked'))
        );
        note.value(acqPoCreateNoteText.attr("value"));
        note.purchase_order(PO.id());
        note.isnew(true);

        /* save it */
        self.updatePoNotes(note);

        /* reset fields for next use */
        acqPoCreateNoteText.attr("value", "");
        acqPoCreateNoteVendorPublic.attr("checked", false);
    };

    this.drawPoNote = function(note) {
        if (note.isdeleted())
            return;

        var row = dojo.clone(this.notesRow);

        nodeByName("value", row).innerHTML = note.value();

        if (openils.Util.isTrue(note.vendor_public()))
            nodeByName("vendor_public", row).innerHTML =
                localeStrings.VENDOR_PUBLIC;

        nodeByName("delete", row).onclick = function() {
            note.isdeleted(true);
            self.notesTbody.removeChild(row);
            self.updatePoNotes();
        };

        if (note.edit_time()) {
            nodeByName("edit_time", row).innerHTML =
                dojo.date.locale.format(
                    dojo.date.stamp.fromISOString(note.edit_time()),
                    {"formatLength": "short"}
                );
        }

        self.notesTbody.appendChild(row);
    };

    this.drawPoNotes = function() {
        /* sort */
        PO.notes(
            PO.notes().sort(
                function(a, b) {
                    return (a.edit_time() < b.edit_time()) ? 1 : -1;
                }
            )
        );

        /* remove old renderings of notes */
        dojo.empty(this.notesTbody);

        PO.notes().forEach(function(o) { self.drawPoNote(o); });
    };

    this.updatePoNotesCount = function() {
        dojo.byId("acq-po-view-notes").innerHTML =
            "(" + PO.notes().length + ")";
    };

    this.updatePoNotes = function(newNote) {
        var notes = newNote ?
            [newNote] :
            PO.notes().filter(
                function(o) {
                    if (o.ischanged() || o.isnew() || o.isdeleted())
                        return o;
                }
            );

        if (notes.length < 1)
            return;

        progressDialog.show();

        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.po_note.cud.batch"], {
                "async": true,
                "params": [openils.User.authtoken, notes],
                "onresponse": function(r) {
                    var resp = openils.Util.readResponse(r);
                    if (resp) {
                        progressDialog.update(resp);

                        if (!resp.note.isdeleted()) {
                            resp.note.isnew(false);
                            resp.note.ischanged(false);
                            PO.notes().push(resp.note);
                        }
                    }
                },
                "oncomplete": function() {
                    if (!newNote) {
                        /* remove the old changed notes */
                        var list = [];
                        PO.notes(
                            PO.notes().filter(
                                function(o) {
                                    return (!(
                                        o.ischanged() || o.isnew() ||
                                        o.isdeleted()
                                    ));
                                }
                            )
                        );
                    }

                    progressDialog.hide();
                    self.updatePoNotesCount();
                    self.drawPoNotes();
                }
            }
        );
    };

    this.hide = function() {
        openils.Util.hide("acq-po-notes-div");
        liTable.show("list");
        poItemTable.show();
    };

    this.show = function() {
        liTable.hide();
        poItemTable.hide();
        self.drawPoNotes();
        openils.Util.show("acq-po-notes-div");
    };
}

function updatePoState(po_info) {
    var data = po_info[PO.id()];
    if (data) {
        for (var key in data)
            PO[key](data[key]);
        renderPo();
    }
}

function cancellationUpdater(r) {
    var r = openils.Util.readResponse(r);
    if (r) {
        if (r.po) updatePoState(r.po);
        if (r.li) {
            for (var id in r.li) {
                liTable.liCache[id].state(r.li[id].state);
                liTable.liCache[id].cancel_reason(r.li[id].cancel_reason);
                liTable.updateLiState(liTable.liCache[id]);
            }
        }
        if (r.lid && liTable.copyCache) {
            for (var id in r.lid) {
                if (liTable.copyCache[id]) {
                    liTable.copyCache[id].cancel_reason(
                        r.lid[id].cancel_reason
                    );
                    liTable.updateLidState(liTable.copyCache[id]);
                }
            }
        }
    }
}

function makeProviderLink(node, provider) {
    return dojo.create(
        "a", {
            "href": oilsBasePath + "/conify/global/acq/provider/" + provider.id(),
            "innerHTML": provider.name() + " (" + provider.code() + ")",
        },
        node,
        "only"
    );
}
function makePrepayWidget(node, prepay) {
    if (prepay) {
        openils.Util.addCSSClass(node, "oils-acq-po-prepay");
        node.innerHTML = localeStrings.YES;
    } else {
        openils.Util.removeCSSClass(node, "oils-acq-po-prepay");
        node.innerHTML = localeStrings.NO;
    }
}

function makeCancelWidget(node, labelnode) {
    openils.Util.hide("acq-po-choose-cancel-reason");

    if (PO.cancel_reason()) {
        labelnode.innerHTML = localeStrings.CANCEL_REASON;
        node.innerHTML = PO.cancel_reason().description() + " (" +
            PO.cancel_reason().label() + ")";
    } else if (["on-order", "pending"].indexOf(PO.state()) == -1) {
        dojo.destroy(this.oldTip);
        labelnode.innerHTML = "";
        node.innerHTML = "";
    } else {
        dojo.destroy(this.oldTip);
        labelnode.innerHTML = localeStrings.CANCEL;
        node.innerHTML = "";
        if (!acqPoCancelReasonSubmit._prepared) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "cancel_reason",
                "fmClass": "acqpo",
                "parentNode": dojo.byId("acq-po-cancel-reason"),
                "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
                "forceSync": true,
                "searchOptions" : {order_by : {"acqcr":"label"}}
            });
            widget.build(
                function(w, ww) {
                    acqPoCancelReasonSubmit.onClick = function() {
                        if (w.attr("value")) {
                            if (confirm(localeStrings.PO_CANCEL_CONFIRM)) {
                                fieldmapper.standardRequest(
                                    ["open-ils.acq",
                                        "open-ils.acq.purchase_order.cancel"],
                                    {
                                        "params": [
                                            openils.User.authtoken,
                                            PO.id(), 
                                            w.attr("value")
                                        ],
                                        "async": true,
                                        "oncomplete": cancellationUpdater
                                    }
                                );
                            }
                        }
                    };
                    acqPoCancelReasonSubmit._prepared = true;
                }
            );
        }
        openils.Util.show("acq-po-choose-cancel-reason", "inline");
    }
}

function prepareInvoiceFeatures() {
    /* show the count of related invoices on the "view invoices" button */
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.invoice.unified_search.atomic"], {
            "params": [
                openils.User.authtoken,
                {"acqpo":[{"id": PO.id()}]},
                null,
                null,
                {"id_list": true}
            ],
            "async": true,
            "oncomplete": function(r) {
                dojo.byId("acq-po-view-invoice-count").innerHTML =
                    openils.Util.readResponse(r).length;
            }
        }
    );

    /* view invoices button */
    dijit.byId("acq-po-view-invoice-link").onClick = function() {
        location.href = oilsBasePath + "/acq/search/unified?so=" +
            base64Encode({"acqpo":[{"id": PO.id()}]}) +
            "&rt=invoice";
    };

    /* create invoice button */
    dijit.byId("acq-po-create-invoice-link").onClick = function() {
        location.href = oilsBasePath +
            "/acq/invoice/view?create=1&attach_po=" + PO.id();
    };

    openils.Util.show("acq-po-invoice-stuff", "table-cell");
}

function setSummaryAmounts() {
    dojo.byId("acq-po-view-total-enc").innerHTML = PO.amount_encumbered().toFixed(2);
    dojo.byId("acq-po-view-total-spent").innerHTML = PO.amount_spent().toFixed(2);
    dojo.byId("acq-po-view-total-estimated").innerHTML = PO.amount_estimated().toFixed(2);
}

function refreshPOSummaryAmounts() {
    fieldmapper.standardRequest(
        ['open-ils.acq', 
            'open-ils.acq.purchase_order.retrieve.authoritative'],
        {   async: true,
            params: [openils.User.authtoken, poId, {
                "flesh_price_summary": true
            }],
            oncomplete: function(r) {
                // update the global PO instead of replacing it, since other 
                // code outside our control may be referencing it.
                var po = openils.Util.readResponse(r);
                PO.amount_encumbered(po.amount_encumbered());
                PO.amount_spent(po.amount_spent());
                PO.amount_estimated(po.amount_estimated());
                setSummaryAmounts();
            }
        }
    );
}

/* renderPo() is the best place to add tests that depend on PO-state
 * (or simple ordered-or-not? checks) to enable/disable UI elements
 * across the whole interface. */
function renderPo() {
    var po_state = PO.state();
    dojo.byId("acq-po-view-id").innerHTML = PO.id();
    dojo.byId("acq-po-view-name").innerHTML = PO.name();
    makeProviderLink(
        dojo.byId("acq-po-view-provider"),
        PO.provider()
    );

    setSummaryAmounts();
    dojo.byId("acq-po-view-total-li").innerHTML = PO.lineitem_count();
    dojo.byId("acq-po-view-state").innerHTML = po_state; // TODO i18n

    if(PO.order_date()) {
        openils.Util.show('acq-po-activated-on', 'inline');
        liTable.enableActionsDropdownOptions("ao"); /* activated */
        liTable.initBatchUpdater(["item_count", "distribution_formula"]);

        dojo.byId('acq-po-activated-on').innerHTML = 
            dojo.string.substitute(
                localeStrings.PO_ACTIVATED_ON, [
                    openils.Util.timeStamp(PO.order_date(), {formatLength:'short'})
                ]
            );
        /* These are handled another way now */
//        if (po_state == "on-order" || po_state == "cancelled") {
//            dojo.removeAttr('receive_lineitems', 'disabled');
//        } else if(po_state == "received") {
//            dojo.removeAttr('rollback_receive_lineitems', 'disabled');
//        }

        /* cancel widgets only make sense for activate (ordered) POs */
        makeCancelWidget(
            dojo.byId("acq-po-view-cancel-reason"),
            dojo.byId("acq-po-cancel-label")
        );

        /* likewise for invoice features */
        openils.Util.show("acq-po-invoice-label", "table-cell");
        prepareInvoiceFeatures();
    } else {
        /* These things only make sense for not-ordered-yet POs */

        liTable.initBatchUpdater();
        liTable.enableActionsDropdownOptions("po");

        openils.Util.show("acq-po-zero-activate-label", "table-cell");
        openils.Util.show("acq-po-zero-activate", "table-cell");

        openils.Util.show("acq-po-item-table-controls");
    }

    makePrepayWidget(
        dojo.byId("acq-po-view-prepay"),
        openils.Util.isTrue(PO.prepayment_required())
    );
    // dojo.byId("acq-po-view-notes").innerHTML = PO.notes().length;
    poNoteTable.updatePoNotesCount();

    if (po_state == "pending") {
        checkCouldActivatePo();
        if (PO.lineitem_count() > 1)
            openils.Util.show("acq-po-split");
    } else {
        if (PO.order_date()) {
            dojo.byId("acq-po-activate-checking").innerHTML = localeStrings.PO_ALREADY_ACTIVATED;
            checkCouldBlanketFinalize();
        } else {
            dojo.byId("acq-po-activate-checking").innerHTML = localeStrings.NO;
        }
    }

    // XXX we probably don't *always* need to do this...
    poItemTable.reset();
    PO.po_items().forEach(
        function(po_item) { poItemTable.addItem(po_item); }
    );
    poItemTable.show();

    dojo.attr(
        "acq-po-view-history", "href",
        oilsBasePath + "/acq/po/history/" + PO.id()
    );
    openils.Util.show("acq-po-view-history", "inline");

    
    /* if we got here from the search/invoice page with a focused LI,
     * return to the previous page with the same LI focused */
    var cgi = new openils.CGI();
    var source = cgi.param('source');
    var focus_li = cgi.param('focus_li');
    if (focus_li && source) {
        dojo.forEach(
            ['search', 'invoice'], // perhaps a wee bit too loose
            function(srcType) {
                if (source.match(new RegExp(srcType))) {
                    openils.Util.show('acq-po-return-to-' + srcType);
                    var newCgi = new openils.CGI({url : source});
                    newCgi.param('focus_li', focus_li);
                    dojo.byId('acq-po-return-to-' + srcType + '-button').onclick = function() {
                        location.href = newCgi.url();
                    }
                }
            }
        );
    }
}


function init() {
    /* set up li table */
    liTable = new AcqLiTable();
    liTable.reset();
    liTable.isPO = poId;
    liTable.poUpdateCallback = updatePoState;

    /* set up po notes table */
    poNoteTable = new AcqPoNoteTable();

    /* retrieve data and populate */
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
        {   async: true,
            params: [openils.User.authtoken, poId, {
                "flesh_provider": true,
                "flesh_price_summary": true,
                "flesh_lineitem_count": true,
                "flesh_notes": true,
                "flesh_po_items": true
            }],
            oncomplete: function(r) {
                PO = openils.Util.readResponse(r); /* save PO globally */

                /* po item table */
                poItemTable = new PoItemTable(PO, pcrud);

                liTable.testOrderIdentPerms( PO.ordering_agency(), init2);

                renderPo();
            }
        }
    );

}

function init2() {

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.lineitem.search'],
        {   async: true,
            params: [
                openils.User.authtoken, 
                [{purchase_order:poId}, {"order_by": {"jub": "id ASC"}}], 
                {   flesh_attrs : true,
                    flesh_notes : true,
                    flesh_cancel_reason : true,
                    flesh_order_summary : true,
                    clear_marc:true
                }
            ],
            onresponse: function(r) {
                liTable.show('list');
                var li = openils.Util.readResponse(r);
                liTable.addLineitem(li);
            },

            oncomplete : function() {
                if (liFocus) liTable.drawCopies(liFocus);
            }
        }
    );

    pcrud.search(
        'acqedim', 
        {purchase_order : poId}, 
        {
            id_list : true,
            oncomplete : function(r) {
                var resp = openils.Util.readResponse(r);
                // TODO: I18n
                if(resp) {
                    dojo.byId('acq-po-view-edi-messages').innerHTML = '(' + resp.length + ')';
                    dojo.byId('acq-po-view-edi-messages').setAttribute('href', oilsBasePath + '/acq/po/edi_messages/' + poId);
                } else {
                    dojo.byId('acq-po-view-edi-messages').innerHTML = '0';
                    dojo.byId('acq-po-view-edi-messages').setAttribute('href', '');
                }
            }
        }
    );
}

function checkCouldBlanketFinalize() {

    if (PO.state() == 'received') return;

    var inv_types = [];

    // get the unique set of invoice item type IDs
    PO.po_items().forEach(function(item) { 
        if (inv_types.indexOf(item.inv_item_type()) == -1)
            inv_types.push(item.inv_item_type());
    });

    if (inv_types.length == 0) return;

    pcrud.search('aiit', 
        {code : inv_types, blanket : 't'}, {
        oncomplete : function(r) {
            r = openils.Util.readResponse(r);
            if (r.length == 0) return;
            openils.Util.show(dojo.byId('acq-po-finalize-links'), 'inline');
        }
    });
}

function checkCouldActivatePo() {
    var d = dojo.byId("acq-po-activate-checking");
    var a = dojo.byId("acq-po-activate-links");  /* <span> not <a> now, but no diff */
    d.innerHTML = localeStrings.PO_CHECKING;
    var warnings = [];
    var stops = [];
    var other = [];

    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.purchase_order.activate.dry_run"], {
            "params": [
                openils.User.authtoken,
                PO.id(),
                null,  // vandelay options
                {zero_copy_activate : dojo.byId('acq-po-activate-zero-copies').checked}
            ],
            "async": true,
            "onresponse": function(r) {
                if ((r = openils.Util.readResponse(r, true /* eventOk */))) {
                    if (typeof(r.textcode) != "undefined") {
                        switch(r.textcode) {
                            case "ACQ_FUND_EXCEEDS_STOP_PERCENT":
                                stops.push(r);
                                break;
                            case "ACQ_FUND_EXCEEDS_WARN_PERCENT":
                                warnings.push(r);
                                break;
                            default:
                                other.push(r);
                        }
                    }
                }
            },
            "oncomplete": function() {
                /* XXX in the future, this might be tweaked to display info
                 * about more than one stop or warning event from the ML. */
                if (!(warnings.length || stops.length || other.length)) {
                    d.innerHTML = localeStrings.PO_COULD_ACTIVATE;
                    openils.Util.show(a, "inline");
                    activatePoButton.attr("disabled", false);
                } else {
                    if (other.length) {
                        /* XXX make the textcode part a tooltip one day */
                        d.innerHTML = localeStrings.NO + ": " +
                            other[0].desc + " (" + other[0].textcode + ")";
                        openils.Util.hide(a);
                        
                        if (other[0].textcode == 'ACQ_LINEITEM_NO_COPIES') {
                            // when LIs w/ zero LIDs are present, list them
                            fieldmapper.standardRequest(
                                [   'open-ils.acq', 
                                    'open-ils.acq.purchase_order.no_copy_lineitems.id_list.authoritative.atomic' ],
                                {   async : true, 
                                    params : [openils.User.authtoken, poId],
                                    oncomplete : function(r) {
                                        var ids = openils.Util.readResponse(r);
                                        d.innerHTML += ' (' + ids + ')';
                                    }
                                }
                            );
                        }
                    } else if (stops.length) {
                        d.innerHTML =
                            dojo.string.substitute(
                                localeStrings.PO_STOP_BLOCKS_ACTIVATION, [
                                    stops[0].payload.fund.code(),
                                    stops[0].payload.fund.year()
                                ]
                            );
                        openils.Util.hide(a);
                    } else {
                        PO._warning_hack = true;
                        d.innerHTML =
                            dojo.string.substitute(
                                localeStrings.PO_WARNING_NO_BLOCK_ACTIVATION, [
                                    warnings[0].payload.fund.code(),
                                    warnings[0].payload.fund.year()
                                ]
                            );
                        openils.Util.show(a, "inline");
                        activatePoButton.attr("disabled", false);
                    }
                }
            }
        }
    );
}

function finalizePo() {

    if (!confirm(localeStrings.FINALIZE_PO)) return;

    finalizePoButton.attr('disabled', true);

    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.purchase_order.blanket.finalize'],
        {   async : true,
            params : [openils.User.authtoken, PO.id()],
            oncomplete : function(r) {
                if (openils.Util.readResponse(r) == 1) 
                    location.href = location.href;
            }
        }
    );
}

function activatePo(noAssets) {
    activatePoButton.attr("disabled", true);
    activatePoNoAssetsButton.attr("disabled", true);

    if (openils.Util.isTrue(PO.prepayment_required())) {
        if (!confirm(localeStrings.PREPAYMENT_REQUIRED_REMINDER)) {
            activatePoButton.attr("disabled", false);
            return false;
        }
    }

    if (PO._warning_hack) {
        if (!confirm(localeStrings.PO_FUND_WARNING_CONFIRM)) {
            activatePoButton.attr("disabled", false);
            return false;
        }
    }

    if (noAssets) {
        // no need for AssetCreator when assets are not desired
        activatePoStage2(true);
    } else {
        liTable.showAssetCreator(activatePoStage2);
    }
}

function activatePoStage2(noAssets) {

    var want_refresh = false;
    progressDialog.show(true);
    progressDialog.attr("title", localeStrings.PO_ACTIVATING);
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.purchase_order.activate"], {
            "async": true,
            "params": [
                openils.User.authtoken,
                PO.id(),
                null,  // vandelay options
                {
                    no_assets : noAssets, // no bibs/volumes/copies required
                    zero_copy_activate : dojo.byId('acq-po-activate-zero-copies').checked
                }
            ],
            "onresponse": function(r) {
                activatePoButton.attr("disabled", false);
                want_refresh = Boolean(openils.Util.readResponse(r));
            },
            "oncomplete": function() {
                progressDialog.hide();
                progressDialog.attr("title", "");
                if (want_refresh)
                    location.href = location.href;
            }
        }
    );
}

function splitPo() {
    progressDialog.show(true);
    try {
        var list;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.split_by_lineitems'],
            {   async: true,
                params: [openils.User.authtoken, PO.id()],
                onresponse : function(r) {
                    list = openils.Util.readResponse(r);
                },
                oncomplete : function() {
                    progressDialog.hide();
                    if (list) {
                        location.href = oilsBasePath + '/acq/po/search/' +
                            list.join(",");
                    }
                }
            }
        );
    } catch(E) {
        progressDialog.hide();
        alert(E);
    }
}

function updatePoName() {
    var value = prompt('Enter new purchase order name:', PO.name()); // TODO i18n
    if(!value || value == PO.name()) return;

    var orgs = fieldmapper.aou.descendantNodeList(PO.ordering_agency(), true);
    new openils.PermaCrud().search('acqpo', 
        {
            id : {'<>' : PO.id()},
            name : value, 
            ordering_agency : orgs
        },
        {async : true, oncomplete : function(r) {
            var po = openils.Util.readResponse(r);
            openils.Util.hide('acq-dupe-po-name');

            if (po && (po = po[0])) {
                var link = dojo.byId('acq-dupe-po-link');
                openils.Util.show('acq-dupe-po-name');
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

            } else {
                updatePoName2(value);
            }
       }} 
    );
 
}

function updatePoName2(value) {
    PO.name(value);
    pcrud.update(PO, {
        oncomplete : function(r, cudResults) {
            var stat = cudResults[0];
            if(stat)
                dojo.byId('acq-po-view-name').innerHTML = value;
        }
    });
}

openils.Util.addOnLoad(init);
