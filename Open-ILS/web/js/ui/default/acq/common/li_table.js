dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require('dijit.form.Button');
dojo.require('dijit.form.TextBox');
dojo.require('dijit.form.FilteringSelect');
dojo.require('dijit.form.Textarea');
dojo.require('dijit.Tooltip');
dojo.require('dijit.ProgressBar');
dojo.require('dojox.timing.doLater');
dojo.require('openils.acq.Lineitem');
dojo.require('openils.acq.PO');
dojo.require('openils.acq.Picklist');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('dojo.data.ItemFileReadStore');
dojo.require('openils.widget.ProgressDialog');
dojo.require('openils.PermaCrud');
dojo.require("openils.widget.PCrudAutocompleteBox");
dojo.require('dijit.form.ComboBox');
dojo.require('openils.CGI');

if (!localeStrings) {   /* we can do this because javascript doesn't have block scope */
    dojo.requireLocalization('openils.acq', 'acq');
    var localeStrings = dojo.i18n.getLocalization('openils.acq', 'acq');
}
const XUL_OPAC_WRAPPER = 'chrome://open_ils_staff_client/content/cat/opac.xul';
var li_exportable_attrs = ["issn", "isbn", "upc"];

var fundLabelFormat = [
    '<span class="fund_${0}">${1} (${2})</span>', 'id', 'code', 'year'
];
var fundSearchFormat = ['${0} (${1})', 'code', 'year'];
var fundSearchFilter = {active : 't'};
var fundSort = {order_by : {"acqf":"year DESC, code"}};

function nodeByName(name, context) {
    return dojo.query('[name='+name+']', context)[0];
}

// for caching linked users.  e.g. lineitem_detail.receiver
var userCache = {};

var liDetailBatchFields = ['fund', 'owning_lib', 'location', 'collection_code', 'circ_modifier', 'cn_label'];
var liDetailFields = liDetailBatchFields.concat(['barcode', 'note']);
var fundStyles = {
    "stop": "color: #c00; font-weight: bold;",
    "warning": "color: #c93;"
};

/**
 * We're not using 'approved' today, but there is API support for it.
 * I believe it's been replaced by "order-ready".
 * LIs go new => selector-ready => order-ready/approved => pending-order => 
 * on-order => received.  'cancelled' can pop up anywhere.
 * Is this all of 'em?
 */
var li_pre_po_states = ["new", "selector-ready", "order-ready", "approved"];
var li_post_po_states = ["pending-order", "on-order", "received", "cancelled"];
var li_active_states = li_pre_po_states.concat(li_post_po_states);

function AcqLiTable() {

    var self = this;
    this.liCache = {};
    this.plCache = {};
    this.poCache = {};
    this.relCache = {};
    this.haveFundClass = {}
    this.fundBalanceState = {};
    this.realDfaCache = {};
    this.virtDfaCounts = {};
    this.virtDfaId = -1;
    this.dfeOffset = 0;
    this.claimEligibleLidByLi = {};
    this.claimEligibleLid = {};
    this.toggleState = false;
    this.tbody = dojo.byId('acq-lit-tbody');
    this.selectors = [];
    this.noteAcks = {};
    this.authtoken = openils.User.authtoken;
    this.pcrud = new openils.PermaCrud();
    this.rowTemplate = this.tbody.removeChild(dojo.byId('acq-lit-row'));
    this.copyTbody = dojo.byId('acq-lit-li-details-tbody');
    this.copyRow = this.copyTbody.removeChild(dojo.byId('acq-lit-li-details-row'));
    this.copyBatchRow = dojo.byId('acq-lit-li-details-batch-row');
    this.copyBatchWidgets = {};
    this.liNotesTbody = dojo.byId('acq-lit-notes-tbody');
    this.liNotesRow = this.liNotesTbody.removeChild(dojo.byId('acq-lit-notes-row'));
    this.realCopiesTbody = dojo.byId('acq-lit-real-copies-tbody');
    this.realCopiesRow = this.realCopiesTbody.removeChild(dojo.byId('acq-lit-real-copies-row'));
    this._copy_fields_for_acqdf = ['owning_lib', 'location', 'fund', 'circ_modifier', 'collection_code'];
    this.skipInitialEligibilityCheck = false;
    this.claimDialog = new ClaimDialogManager(
        liClaimDialog, finalClaimDialog, this.claimEligibleLidByLi,
        function(li) {    /* callback that fires when claims are made */
            self.fetchClaimInfo(li.id(), /* force update */ true);
        }
    );
    this.vlAgent = new VLAgent();
    this.batchProgress = {};

    if (dojo.byId('acq-lit-apply-idents')) {
        dojo.byId('acq-lit-apply-idents').onclick = function() {
            self.applyOrderIdentValues();
        };
    }

    this.focusLineitem = new openils.CGI().param('focus_li');

    // capture the inline copy display wrapper and row template
    this.inlineCopyContainer = 
        this.tbody.removeChild(dojo.byId('acq-inline-copies-row'));
    var tb = dojo.query(
        '[name=acq-li-inline-copies-tbody]', this.inlineCopyContainer)[0];
    this.inlineCopyTemplate = tb.removeChild(
        dojo.query('[name=acq-li-inline-copies-template]', tb)[0]);
    this.inlineNoCopies = tb.removeChild(
        dojo.query('[name=acq-li-inline-copies-none]', tb)[0]);

    // list of LI IDs that should be refreshed at next display time
    this.inlineCopiesNeedingRefresh = []; 

    dojo.byId("acq-lit-li-actions-selector").onchange = function() { 
        self.applySelectedLiAction(this.options[this.selectedIndex].value);
        this.selectedIndex = 0;
    };

    acqLitCreatePoCancel.onClick = function() {
        acqLitPoCreateDialog.hide();
    }
    acqLitCreatePoSubmit.onClick = function() {
        if (!self.createPoProviderSelector.attr("value") ||
                !self.createPoAgencySelector.attr("value")) {
            alert(localeStrings.CREATE_PO_INVALID);
            return false;
        } else if (self._confirmPoPrepaySituation()) {
            acqLitPoCreateDialog.hide();
            self._createPO(acqLitPoCreateDialog.getValues());
        } else {
            return false;
        }
    }

    acqLitSavePlButton.onClick = function() {
        acqLitSavePlDialog.hide();
        self._savePl(acqLitSavePlDialog.getValues());
    }

    acqLitCancelLiStateButton.onClick = function() {
        acqLitChangeLiStateDialog.hide();
    }
    acqLitSaveLiStateButton.onClick = function() {
        acqLitChangeLiStateDialog.hide();
        var state = acqLitChangeLiStateDialog.attr('state');
        var state_filter = ['new'];
        if (state == 'order-ready')
            state_filter.push('selector-ready');
        self._updateLiState(
            acqLitChangeLiStateDialog.getValues(), state, state_filter);
    }


    dojo.byId('acq-lit-select-toggle').onclick = function(){self.toggleSelect()};
    dojo.byId('acq-inline-copies-toggle').onclick = function(){self.toggleInlineCopies()};
    dojo.byId('acq-lit-info-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-copies-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-notes-back-button').onclick = function(){self.show('list')};
    dojo.byId('acq-lit-real-copies-back-button').onclick = function(){self.show('list')};

    this.setFundSearchFilter = function(callback) {
        new openils.User().getPermOrgList(
            ['CREATE_PURCHASE_ORDER', 'CREATE_PICKLIST', 'MANAGE_FUND'],
            function(orgs) { 
                fundSearchFilter.org = orgs;
                if (callback) callback();
            },
            true, true // descendants, id_list
        );
    }

    this.afwCopyFieldArgs = function(field, perms) {
        return {
                "fmField" : field,
                "fmClass": 'acqlid',
                "labelFormat": (field == 'fund') ? fundLabelFormat : null,
                "searchFormat": (field == 'fund') ? fundSearchFormat : null,
                "searchFilter": (field == 'fund') ? fundSearchFilter : null,
                "searchOptions": (field == 'fund') ? fundSort : null,
                "orgLimitPerms": (field == 'location') ? ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'] : [perms],
                "dijitArgs": {
                    "required": false,
                    "labelType": (field == "fund") ? "html" : null
                },
                "noCache": (field == "fund"),
                "forceSync": true
            };
    };

    /* This is the "new" batch updater that sits atop all lineitems. It does
     * use this.afwCopyFieldArgs() to borrow a little common code  from the
     * "old" batch updater atop the copy details view. 
     * @param hidden allows the batch updater to be initialized, activating
     * fund selectors, while stying invisible for UI's where the batch
     * updater is not fully integrated.
     * */
    this.initBatchUpdater = function(disabled_fields, hidden) {
        if (!hidden) openils.Util.show("acq-batch-update", "table");

        if (!dojo.isArray(disabled_fields)) disabled_fields = [];

        /* Note that this will directly contain dijits, not the AutoWidget
         * wrapper object. */
        if (!this.batchUpdateWidgets) {
            this.batchUpdateWidgets = {};
        }

        if (this.batchUpdateWidgets.item_count) this.batchUpdateWidgets.item_count.destroy();
        this.batchUpdateWidgets.item_count = new dijit.form.TextBox(
            {
                "style": {"width": "3em"},
                "disabled": Boolean(
                    dojo.indexOf(disabled_fields, "item_count") != -1
                )
            },
            "acq-bu-item_count"
        );

        if (!this.batchUpdateWidgets.distribution_formula) {
            (new openils.widget.AutoFieldWidget({
                "fmClass": "acqdf",
                "selfReference": true,
                "dijitArgs": { "required": false },
                "forceSync": true,
                "parentNode": "acq-bu-distribution_formula"
            })).build(
                function(w) {
                    dojo.style(w.domNode, {"width": "12em"});
                    self.batchUpdateWidgets.distribution_formula = w;
                }
            );
        }

        /* dijitArgs to AutoFieldWidget won't work for 'disabled' */
        self.batchUpdateWidgets.distribution_formula.attr(
            'disabled',
            dojo.indexOf(disabled_fields, "distribution_formula") != -1
        );

        function buildOneBatchWidget(field, args) {
            if (!self.batchUpdateWidgets[field]) {
                (new openils.widget.AutoFieldWidget(args)).build(
                    function(w, aw) {
                        if (field == "fund") {
                            dojo.connect(
                                w, "onChange", function(val) {
                                    self._updateFundSelectorStyle(aw, val);
                                }
                            );
                            if (w.store)
                                self._ensureCSSFundClasses(w.store);
                        }

                        dojo.style(w.domNode, {"width": "10em"});
                        self.batchUpdateWidgets[field] = w;
                    }
                );
            }

            if (self.batchUpdateWidgets[field]) {
                self.batchUpdateWidgets[field].attr(
                    "disabled",
                    dojo.indexOf(disabled_fields, field) != -1
                );
            }
        }

        dojo.forEach(
            ["owning_lib","location","collection_code","circ_modifier","fund"],
            function(field) {
                var args = self.afwCopyFieldArgs(field, "CREATE_PURCHASE_ORDER");
                args.parentNode = dojo.byId("acq-bu-" + field);

                if (field == 'fund') {
                    // The list of funds can be huge. Before fetching
                    // funds for PO or Selection LIst modification, see where the user has
                    // perms and limit the retreived funds accordingly.
                    // Note:  This is the first instance of fund list
                    // retrieval.  All future fund list retrievals will
                    // benefit directly from having applied the fund
                    // search filter org units here.
                    self.setFundSearchFilter(function() { 
                        buildOneBatchWidget(field, args); 
                    });
                    return; 
                }

                buildOneBatchWidget(field, args);
            }
        );

        acqBatchUpdateApply.onClick = function() {
            var li_id_list = self.getSelected(false, null, true /* id list */);
            if (!li_id_list.length) {
                alert(localeStrings.NO_LI_TO_UPDATE);
                return;
            }

            progressDialog.show(true);
            progressDialog.attr("title", localeStrings.LI_BATCH_UPDATE);
            progressDialog.update({"maximum": li_id_list.length,"progress": 0});

            var count = 0;

            var params = [ self.authtoken, {"lineitems": li_id_list},
                        self.batchUpdateChanges(), self.batchUpdateFormula() ];
            console.log("batch update params: " + dojo.toJson(params));

            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.lineitem.batch_update"], {
                    "async": true,
                    "params": params,
                    "onresponse": function(r) {
                        if ((r = openils.Util.readResponse(r))) { // assignment
                            progressDialog.update({"progress": ++count});
                        } else {
                            progressDialog.hide();
                            progressDialog.attr("title", "");
                        }
                    },
                    "oncomplete": function() {
                        /* XXX Is the last call to onresponse guaranteed to
                         * finish before oncomplete is fired? */
                        if (count != li_id_list.length) {
                            console.error("lineitem batch update operation failed");
                            progressDialog.hide();
                            progressDialog.attr("title", "");
                        } else {
                            location.href = location.href;
                        }
                    }
                }
            );
        };
    };

    this.batchUpdateChanges = function() {
        var o = {};

        dojo.forEach(
            openils.Util.objectProperties(this.batchUpdateWidgets),
            function(k) {
                if (k == "distribution_formula") return; /* handled elsewhere */
                if (self.batchUpdateWidgets[k].attr("disabled")) return;

                /* It's important that a value of "" should mean that a field
                 * doesn't get used in the arguments to the batch updater API,
                 * but 0 should mean an actual 0. */
                var value = self.batchUpdateWidgets[k].attr("value");
                if (value !== "")
                    o[k] = value;
            }
        );

        return o;
    };

    this.batchUpdateFormula = function() {
        if (this.batchUpdateWidgets.distribution_formula.attr("disabled")) {
            return null;
        } else {
            return (
                this.batchUpdateWidgets.distribution_formula.attr("value") ||
                null
            );
        }
    };

    this.reset = function(keep_selectors) {
        while(self.tbody.childNodes[0])
            self.tbody.removeChild(self.tbody.childNodes[0]);
        self.liCache = {};
        self.noteAcks = {};
        self.relCache = {};

        if (!keep_selectors)
            self.selectors = [];
    };
    
    this.setNext = function(handler) {
        var link = dojo.byId('acq-lit-next');
        if(handler) {
            dojo.style(link, 'visibility', 'visible');
            link.onclick = handler;
        } else {
            dojo.style(link, 'visibility', 'hidden');
        }
    };

    this.setPrev = function(handler) {
        var link = dojo.byId('acq-lit-prev');
        if(handler) {
            dojo.style(link, 'visibility', 'visible'); 
            link.onclick = handler; 
        } else {
            dojo.style(link, 'visibility', 'hidden');
        }
    };

    this.enableActionsDropdownOptions = function(mask) {
        /* 'mask' is probably a misnomer the way I'm using it, but it needs to
         * be one of pl,po,ao,gs,vp, or fs. */
        dojo.query("option", "acq-lit-li-actions-selector").forEach(
            function(option) {
                var opt_mask = dojo.attr(option, "mask");

                /* For each <option> element, an empty or non-existent mask
                 * attribute, a mask attribute of "*", or a mask attribute that
                 * matches this method's argument should result in that
                 * option's being enabled. */
                dojo.attr(
                    option, "disabled", !(
                        !opt_mask ||
                        opt_mask == "*" ||
                        opt_mask.search(mask) != -1
                    )
                );
            }
        );
    };

    /*
     * Ensures this.focusLineitem is in view and causes a brief 
     * border around the lineitem to come to life then fade.
     */
    this.focusLi = function() {
        if (!this.focusLineitem) return;

        // set during addLineitem()
        var node = dojo.byId('li-title-ref-' + this.focusLineitem);

        // LI may not yet be rendered
        if (!node) return; 

        // prevent numerous re-focuses
        this.focusLineitem = null; 
        
        // causes the full row to be visible
        dijit.scrollIntoView(node);

        // may as well..
        dojo.query('[attr=title]', node)[0].focus();

        dojo.require('dojox.fx');

        setTimeout(
            function() {
                dojox.fx.highlight({color : '#BB4433', node : node, duration : 2000}).play();
            }, 
        100);
    };

    this.show = function(div) {
        openils.Util.hide('acq-lit-table-div');
        openils.Util.hide('acq-lit-info-div');
        openils.Util.hide('acq-lit-li-details');
        openils.Util.hide('acq-lit-notes-div');
        openils.Util.hide('acq-lit-real-copies-div');
        openils.Util.hide('acq-lit-asset-creator');
        switch(div) {
            case 'list':
                openils.Util.show('acq-lit-table-div');
                this.focusLi();
                this.refreshInlineCopies();
                break;
            case 'info':
                openils.Util.show('acq-lit-info-div');
                break;
            case 'copies':
                openils.Util.show('acq-lit-li-details');
                break;
            case 'real-copies':
                openils.Util.show('acq-lit-real-copies-div');
                break;
            case 'notes':
                openils.Util.show('acq-lit-notes-div');
                break;
            case 'asset-creator':
                openils.Util.show('acq-lit-asset-creator');
                break;
            default:
                if(div) 
                    openils.Util.show(div);
        }
    }

    this.hide = function() {
        this.show(null);
    }

    this.toggleSelect = function() {
        if(self.toggleState) 
            dojo.forEach(self.selectors, function(i){i.checked = false});
        else 
            dojo.forEach(self.selectors, function(i){i.checked = true});
        self.toggleState = !self.toggleState;
    };


    this.getAll = function(callback, id_only, state) {
        /* For some uses of the li table, we may not really know about "all"
         * the lineitems that the user thinks we know about. If we're a paged
         * picklist, for example, we only know about the lineitems we've
         * displayed, but not necessarily all the lineitems on the picklist.
         * So we reach out to pcrud to inform us.
         * state: string/array.  only lineitems in one of these states are
         * included in the final result set.  Not currently supported for
         * paging mode.
         */

        var oncomplete = function(r) {
            var id_list = openils.Util.readResponse(r);
            if (id_only)
                callback(id_list);
            else
                self.fetchLineitemsById(id_list, callback);
        };

        if (this.isPL) {
            var search = {"picklist": this.isPL};
            if (state) search.state = state;
            this.pcrud.search(
                "jub", search, {
                    "id_list": true,    /* sic, even if id_only */
                    "async": true,
                    "oncomplete": oncomplete
                }
            );
            return;
        } else if (this.isPO) {
            var search = {"purchase_order": this.isPO};
            if (state) search.state = state;
            this.pcrud.search(
                "jub", search, {
                    "id_list": true,
                    "async": true,
                    "oncomplete": oncomplete
                }
            );
            return;
        } else if (this.isUni && this.pager) {
            this.pager.getAllLineitemIDs(oncomplete);
            return;
        }

        /* If execution reaches this point, we don't need or can't perform
         * any special tricks to find out the "real" list of "all" lineitems
         * in this context, so we fall back to the old method.
         */
        callback(this.getSelected(true, null, id_only, state));
    };

    /** @param all If true, assume all are selected */
    this.getSelected = function(
        all,
        callback /* If you want a "good" idea of "all" lineitems, you must
        provide a callback that accepts an array parameter, rather than
        relying on the return value of this method itself. */,
        id_only,
        state 
    ) {
        console.log("getSelected states = " + state);
        if (all && callback)
            return this.getAll(callback, id_only, state);

        var indices = {};   /* use to uniqify. needed in paging situations. */
        dojo.forEach(this.selectors,
            function(i) { 
                if(i.checked || all)
                    indices[i.parentNode.parentNode.getAttribute('li')] = true;
            }
        );

        var result = openils.Util.objectProperties(indices);

        // caller provided a lineitem state filter.  remove IDs for lineitems 
        // not in the selected state.
        if (state) {
            var trimmed = [];
            if (!dojo.isArray(state)) state = [state];
            dojo.forEach(result, function(liId) {
                console.log('filter LI state ' + self.liCache[liId].state());
                if (state.indexOf(self.liCache[liId].state()) >= 0)
                    trimmed.push(liId);
            });
            result = trimmed;
        };

        if (!id_only)
            result = result.map(function(liId) { return self.liCache[liId]; });

        if (callback)
            callback(result);
        else
            return result;
    };

    this.setRowAttr = function(td, liWrapper, field, type) {
        var val = liWrapper.findAttr(field, type || 'lineitem_marc_attr_definition') || '';
        td.appendChild(document.createTextNode(val));
    };

    this.setClaimPolicyControl = function(li, row) {
        if (!self._claimPolicyPickerLoading) {
            self._claimPolicyPickerLoading = true;

            new openils.widget.AutoFieldWidget({
                "parentNode": "acq-lit-li-claim-policy",
                "fmClass": "acqclp",
                "selfReference": true,
                "dijitArgs": {"required": true}
            }).build(
                function(w) { self.claimPolicyPicker = w; }
            );
        }

        /* dojox.timing.doLater() is the best thing ever. Resource not yet
         * ready? Just repeat my whole method when it is. */
        if (dojox.timing.doLater(self.claimPolicyPicker)) {
            return;
        } else {
            if (!row)
                row = self._findLiRow(li);

            if (li.claim_policy()) {
                /* This Dojo data dance is necessary to get a whole fieldmapper
                 * object based on a claim policy ID, since we alreay have the
                 * widget thing loaded with all that data, and can thereby
                 * avoid another request to the server. */
                self.claimPolicyPicker.store.fetchItemByIdentity({
                    "identity": li.claim_policy(),
                    "onItem": function(a) {
                        var policy = (new acqclp()).fromStoreItem(a);
                        var span = nodeByName("claim_policy", row);
                        var inner = nodeByName("claim_policy_name", row);

                        openils.Util.show(span, "inline");
                        inner.innerHTML = policy.name();
                    },
                    "onError": function(e) {
                        console.error(e);
                    }
                });
            } else {
                openils.Util.hide(nodeByName("claim_policy", row));
                nodeByName("claim_policy_name", row).innerHTML = "";
            }
        }
    };

    this.fetchClaimInfo = function(liId, force, callback, row) {
        this._fetchLineitem(
            liId, function(full) {
                self.liCache[full.id()] = full;
                self.checkClaimEligibility(full, callback, row);
            }, force
        );
    }

    // fetch an updated copy of the lineitem 
    // and add it back to the lineitem table
    this.refreshLineitem = function(li, focus) {
        var self = this;
        this._fetchLineitem(li.id(), 
            function(newLi) {
                if (focus) {
                    self.focusLineitem = li.id();
                } else {
                    self.focusLineitem = null;
                }
                var row = dojo.query('[li='+li.id()+']', self.tbody)[0];
                var nextSibling = row.nextSibling;
                self.tbody.removeChild(row);
                self.addLineitem(newLi, false, nextSibling);
            }, true
        );
    }

    /**
     * Inserts a single lineitem into the growing table of lineitems
     * @param {Object} li The lineitem object to insert
     */
    this.addLineitem = function(li, skip_final_placement, nextSibling) {
        this.liCache[li.id()] = li;

        // insert the row right away so that final order isn't
        // dependent on how long subsequent async request take
        // for a given line item
        var row = self.rowTemplate.cloneNode(true);
        if (!skip_final_placement) {
            if (!nextSibling) {
                // either no nextSibling was provided or it was null
                // meaning the row was already at the end of the table
                self.tbody.appendChild(row);
            } else {
                self.tbody.insertBefore(row, nextSibling);
            }
        }

        self.selectors.push(dojo.query('[name=selectbox]', row)[0]);

        // sort the lineitem notes on edit_time
        if(!li.lineitem_notes()) li.lineitem_notes([]);

        var liWrapper = new openils.acq.Lineitem({lineitem:li});
        row.setAttribute('li', li.id());
        var tds = dojo.query('[attr]', row);
        dojo.forEach(tds, function(td) {self.setRowAttr(td, liWrapper, td.getAttribute('attr'), td.getAttribute('attr_type'));});
        if (li.source_label() !== null)
            dojo.query('[name=source_label]', row)[0].appendChild(document.createTextNode(li.source_label()));

        // so we can scroll to it later
        dojo.query('[name=bib-info-cell]', row)[0].id = 'li-title-ref-' + li.id();

        var identifier =
            liWrapper.findAttr("isbn", "lineitem_marc_attr_definition") ||
            liWrapper.findAttr("upc", "lineitem_marc_attr_definition");

        // XXX media prefix for added content
        if (identifier) {
            nodeByName("jacket", row).setAttribute(
                "src", "/opac/extras/ac/jacket/small/" + identifier
            );
        }

        nodeByName("liid", row).innerHTML += li.id();

        var exist = nodeByName('li_existing_count', row);
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.existing_copies.count'],
            {
                params: [this.authtoken, li.id()],
                oncomplete : function(r) {
                    var count = openils.Util.readResponse(r);
                    exist.innerHTML = count;
                    if (Number(count) > 0) {
                        openils.Util.addCSSClass(
                            exist, 'acq-existing-count-warn');
                    }
                    new dijit.Tooltip({
                        connectId : [exist],
                        label : dojo.string.substitute(
                            localeStrings.LI_EXISTING_COPIES, [count])
                    });
                }
            }
        );

        if(li.eg_bib_id()) {
            openils.Util.show(nodeByName('catalog', row), 'inline');
            nodeByName("catalog_link", row).onclick = this.generateMakeRecTab(li.eg_bib_id());
        } else {
            openils.Util.show(nodeByName('link_to_catalog', row), 'inline');
            nodeByName("link_to_catalog_link", row).onclick = function() { self.drawBibFinder(li) };
        }

        if (li.queued_record()) {
            this.pcrud.retrieve('vqbr', li.queued_record(),
                {   async : true, 
                    oncomplete : function(r) {
                        var qrec = openils.Util.readResponse(r);
                        openils.Util.show(nodeByName('queue', row), 'inline');
                        var link = nodeByName("queue_link", row);
                        link.onclick = function() { 
                            var url = oilsBasePath + '/vandelay/vandelay?qtype=bib&qid=' + qrec.queue()
                            // open a new tab to the vandelay queue for this record
                            if (window.IAMBROWSER) {
                                xulG.relay_url(url);
                            } else {
                                openils.XUL.newTabEasy(url);
                            }
                        }
                    }
                }
            );
        }

        nodeByName("worksheet_link", row).href =
            oilsBasePath + "/acq/lineitem/worksheet/" + li.id() + 
            '?source=' + encodeURIComponent(location.pathname + location.search)

        if (!window.IAMBROWSER) {
            nodeByName("show_requests_link", row).href =
                oilsBasePath + "/acq/picklist/user_request?lineitem=" + li.id() +
                '?source=' + encodeURIComponent(location.pathname + location.search);
        } else {
            nodeByName("show_requests_link", row).href =
                "/eg/staff/acq/requests/lineitem/" + li.id();
            nodeByName("show_requests_link", row).setAttribute('target','_top');
        }

        dojo.query('[attr=title]', row)[0].onclick = function() {self.drawInfo(li.id())};
        dojo.query('[name=copieslink]', row)[0].onclick = function() {self.drawCopies(li.id())};
        dojo.query('[name=noteslink]', row)[0].onclick = function() {self.drawLiNotes(li)};
        dojo.query('[name=expand_inline_copies]', row)[0].onclick = 
            function() {self.drawInlineCopies(li.id())};

        var sum;
        if (sum = li.order_summary()) { // assignment
            // Only show the paid label if at least one copy is invoiced.
            // In other words, a lineitem whose every copy is canceled
            // is not "paid off"
            if (sum.invoice_count() > 0) {
                if (sum.item_count() == (
                    sum.invoice_count() + sum.cancel_count())) {
                    // Lineitem is fully paid.  Display the paid-off label
                    openils.Util.show(nodeByName('paid', row), 'inline');
                }
            }
        }

        this.drawOrderIdentSelector(li, row);

        if (!this.skipInitialEligibilityCheck)
            this.fetchClaimInfo(
                li.id(),
                false,
                function(full) { self.setClaimPolicyControl(full, row) },
                row
            );

        this.updateLiNotesCount(li, row);

        // show which PO this lineitem is a member of
        if(li.purchase_order() && !this.isPO) {
            var po = 
                this.poCache[li.purchase_order()] =
                this.poCache[li.purchase_order()] ||
                fieldmapper.standardRequest(
                    ['open-ils.acq', 'open-ils.acq.purchase_order.retrieve'],
                    {params: [
                        this.authtoken, li.purchase_order(), {
                            "flesh_price_summary": true,
                            "flesh_provider" : true,
                            "flesh_lineitem_count": true
                        }
                    ]});
            if(po && !this.isMeta) {
                openils.Util.show(nodeByName('po', row), 'inline');
                var link = nodeByName('po_link', row);
                link.setAttribute('href', oilsBasePath +
                    '/acq/po/view/' + li.purchase_order() +
                    '?focus_li=' + li.id() +
                    '&source=' + encodeURIComponent(location.pathname + location.search)
                );
                link.innerHTML += po.name();

                openils.Util.show(nodeByName('pro', row), 'inline');
                link = nodeByName('pro_link', row);
                link.setAttribute('href', oilsBasePath + '/conify/global/acq/provider/' + po.provider().id())
                link.innerHTML += po.provider().code();
            }
        }

        // show which picklist this lineitem is a member of
        if(li.picklist() && (this.isPO || this.isMeta || this.isUni)) {
            var pl = 
                this.plCache[li.picklist()] = 
                this.plCache[li.picklist()] || 
                fieldmapper.standardRequest(
                    ['open-ils.acq', 'open-ils.acq.picklist.retrieve.authoritative'],
                    {params: [this.authtoken, li.picklist()]});
            if (pl) {
                if (pl.name() == "") {
                    openils.Util.show(nodeByName("bib_origin", row), "inline");

                } else {

                    openils.Util.show(nodeByName('pl', row), 'inline');
                    var link = nodeByName('pl_link', row);
                    link.setAttribute('href', oilsBasePath +
                        '/acq/picklist/view/' + li.picklist() +
                        '?focus_li=' + li.id() +
                        '&source=' + encodeURIComponent(location.pathname + location.search)
                    );
                    link.innerHTML += pl.name();
                }
            }
        }

        var countNode = nodeByName('count', row);
        var count = li.item_count() || 0;
        if (typeof(this._copy_count_cb) == "function") {
            this._copy_count_cb(li.id(), count);
        }
        countNode.innerHTML = count;
        countNode.id = 'acq-lit-copy-count-label-' + li.id();

        // lineitem price
        var priceInput = dojo.query('[name=price]', row)[0];
        priceInput.value = li.estimated_unit_price() || '';
        priceInput.onchange = function() { self.updateLiPrice(priceInput, li) };

        // show either "mark received" or "unreceive" as appropriate
        this.updateLiState(li, row);

        if (skip_final_placement) {
            return row;
        }

        // the last LI may be rendered after the call to show('list'),
        // so make sure it's focused if necessary.
        if (this.focusLineitem == li.id())
            this.focusLi();
    };

    this._liCountClaims = function(li) {
        var total = 0;
        for (var i = 0; i < li.lineitem_details().length; i++)
            total += li.lineitem_details()[i].claims().length;
        return total;
    };

    this._findLiRow = function(li) {
        return dojo.query('tr[li="' + li.id() + '"]', "acq-lit-tbody")[0];
    };

    this.reconsiderClaimControl = function(li, row) {
        if (!row) row = this._findLiRow(li);
        var option = nodeByName("action_manage_claims", row);
        var eligible = this.claimEligibleLidByLi[li.id()].length;
        var count = this._liCountClaims(li);

        option.disabled = !(count || eligible);
        option.innerHTML =
            dojo.string.substitute(localeStrings.NUM_CLAIMS_EXISTING, [count]);
    };

    this.clearEligibility = function(li) {
        this.claimEligibleLidByLi[li.id()] = [];

        if (li.lineitem_details()) {
            li.lineitem_details().forEach(
                function(lid) { delete self.claimEligibleLid[lid.id()]; }
            );
        }

        if (this.copyCache) {
            var to_del = [];
            for (var k in this.copyCache) {
                if (this.copyCache[k].lineitem() == li.id())
                    to_del.push(k);
            }
            to_del.forEach(
                function(k) { delete self.claimEligibleLid[k]; }
            );
        }
    };

    this.applyOrderIdentValues = function() {
        this._identValuesInFlight = 
            openils.Util.objectProperties(this.liCache).length;
        for (var liId in this.liCache) {
            this._applyOrderIdentValue(this.liCache[liId]);
        }
    };

    // returns true if request was sent
    this._applyOrderIdentValue = function(li, oncomplete) {
        var self = this;

        console.log('applying ident value for lineitem ' + li.id());

        // main row
        var row = dojo.query('[li=' + li.id() + ']')[0];

        // find the selected ident value
        var typeSel = dojo.query('[name=order_ident_type]', row)[0];
        var valueSel = dojo.query('[name=order_ident_value]', row)[0];
        var name = typeSel.options[typeSel.selectedIndex].value;
        var val = typeSel._cbox.attr('value');

        console.log("selected ident is " + val);

        // it differs from the existing ident value, update it
        var oldIdent = self.getLiOrderIdent(li);
        if (oldIdent && 
            oldIdent.attr_name() == name &&
            oldIdent.attr_value() == val) {
                console.log('selected ident attr matches existing attr');
                if (--this._identValuesInFlight == 0) {
                    if (oncomplete) oncomplete(li);
                    else location.href = location.href;
                }
                return false;
        }

        // see if the selected ident value is represented
        // by an existing lineitem attr

        var args = {};
        typeSel._cbox.store.fetch({
            query : {attr_value : val},
            onItem : function(item) {                                                       
                console.log('found existing attr for ident value');
                args.source_attr_id = li.attributes().filter(
                    function(attr) { return attr.id() == item.id[0] }
                )[0];
            }                                                                      
        }); 


        if (!args.source_attr_id) {
            // user entered new text in the combobox
            // so we need to create a new attr
            console.log('creating new ident attr');
            args.lineitem_id = li.id();
            args.attr_name = name;
            args.attr_value = val;
        }

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.order_identifier.set'],
            {   async : true,
                params : [openils.User.authtoken, args],
                oncomplete : function() {
                    console.log('order_ident oncomplete');
                    if (--self._identValuesInFlight == 0) {
                        if (oncomplete) oncomplete(li);
                        else location.href = location.href;
                    }
                    console.log(self._identValuesInFlight + ' still in flight');
                }
            }
        );

        return true;
    };

    this.getLiOrderIdent = function(li) {
        var attrs = li.attributes();
        if (!attrs) return null;
        return attrs.filter(
            function(attr) {
                return (
                    attr.attr_type() == 'lineitem_local_attr_definition' &&
                    openils.Util.isTrue(attr.order_ident())
                );
            }
        )[0];
    };

    this.drawOrderIdentSelector = function(li, row) {
        var self = this;
        var typeSel = dojo.query('[name=order_ident_type]', row)[0];
        var valueSel = dojo.query('[name=order_ident_value]', row)[0];

        var attrs = li.attributes();

        // limit to MARC attr defs
        attrs = attrs.filter(
            function(attr) {
                return (attr.attr_type() == 'lineitem_marc_attr_definition');
            }
        );

        var identAttr = this.getLiOrderIdent(li);


        // collect the values for each type of identifier
        // find a reasonable default identifier type to render
        
        var values = {};
        var typeSet = null;
        dojo.forEach(['isbn', 'upc', 'issn'],
            function(name) {

                // collect the values for this attr name
                values[name] =  attrs.filter(
                    function(attr) {
                        return (attr.attr_name() == name)
                    }
                );

                // select a reasonable default name in the type-selector
                if (!typeSet) {
                    var useMe = false;
                    if (identAttr) {
                        if (identAttr.attr_name() == name)
                            useMe = true;
                    } else if (values[name].length) {
                        useMe = true;
                    }

                    if (useMe) {
                        dojo.forEach(typeSel.options, function(opt) {
                            if (opt.value == name) {
                                opt.selected = true;
                                typeSet = name;
                            }
                        });
                    }
                }
            }
        );

        function updateOrderIdent(val) {
            self._identValuesInFlight = 1;
            self._applyOrderIdentValue(
                this._lineitem,
                function(li) {
                    self.refreshLineitem(li);
                }
            );
        }

        // replace the ident combobox with a new 
        // one for the selected ident type 
        function changeComboBox(sel) {
            var name = sel.options[sel.selectedIndex].value;

            var td = dojo.query('[name=order_ident_value]', row)[0];
            if (td.childNodes[0]) 
                dojo.destroy(td.childNodes[0]);

            var store = new dojo.data.ItemFileWriteStore({
                data : acqlia.toStoreData(values[name])
            });

            var cbox = new dijit.form.ComboBox(
                {   store : store,
                    labelAttr : 'attr_value',
                    searchAttr : 'attr_value'
                }, 
                dojo.create('div', {}, td)
            );

            cbox.startup();

            // set the value for the cbox
            if (values[name].length) {
                var orderIdent = self.getLiOrderIdent(li);

                if (orderIdent && orderIdent.attr_name() == name) {
                    cbox.attr('value', orderIdent.attr_value());
                } else  {
                    cbox.attr('value', values[name][0].attr_value());
                }
            }

            if (!self.orderIdentAllowed) 
                cbox.attr('disabled', true);

            sel._cbox = cbox;
            cbox._lineitem = li;
            dojo.connect(cbox, 'onChange', updateOrderIdent);
        }

        changeComboBox(typeSel); // force the initial draw
        typeSel.onchange = function() {changeComboBox(typeSel)};
    };

    this.testOrderIdentPerms = function(org, callback) {
        var self = this;
        new openils.User().getPermOrgList(
            'ACQ_SET_LINEITEM_IDENTIFIER',
            function(orgs) { 
                console.log('found orgs = ' + orgs);
                for (var i = 0; i < orgs.length; i++) {
                    if (Number(orgs[i]) == Number(org)) {
                        self.orderIdentAllowed = true;
                        if (callback) callback();
                        return;
                    }
                }
                if (callback) callback();
            }, 
            true, true
        );
    };

    this.checkClaimEligibility = function(li, callback, row) {
        /* Assume always eligible, i.e. from this interface we don't care about
         * claim eligibility any more. this is where the user would force a
         * claime. */
        this.clearEligibility(li);
        this.claimEligibleLidByLi[li.id()] = li.lineitem_details().map(
            function(lid) { return lid.id(); }
        );
        li.lineitem_details().forEach(
            function(lid) { self.claimEligibleLid[lid.id()] = true; }
        );
        this.reconsiderClaimControl(li, row);
        if (callback) callback(li);
        /*
        this.clearEligibility(li);
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.claim.eligible.lineitem_detail"], {
                "params": [openils.User.authtoken, {"lineitem": li.id()}],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        self.claimEligibleLidByLi[li.id()].push(
                            r.lineitem_detail()
                        );
                        self.claimEligibleLid[r.lineitem_detail()] = true;
                    }
                },
                "oncomplete": function() {
                    self.reconsiderClaimControl(li, row);
                    if (typeof(callback) == "function")
                        callback();
                }
            }
        );
        */
    };

    this.updateLiNotesCount = function(li, row) {
        if (!row) row = this._findLiRow(li);

        var has_notes = (li.lineitem_notes().filter(
                function(o) { return Boolean (o.alert_text()); }
            ).length > 0);

        /* U+2691 is the code point for a filled-in flag character */
        nodeByName("notes_alert_flag", row).innerHTML =
             has_notes ? "&#x2691;" : "";
        nodeByName("noteslink", row).style.fontStyle =
            has_notes ? "italic" : "normal";
        nodeByName("notes_count", row).innerHTML = li.lineitem_notes().length;
    };

    /* XXX NOT related to _updateLiState(). rethink */
    this.updateLiState = function(li, row) {
        if (!row) row = this._findLiRow(li);

        nodeByName("actions", row).onchange = function() {
            switch(this.options[this.selectedIndex].value) {
                case 'action_update_barcodes':
                    self.showRealCopyEditUI(li);
                    nodeByName("action_none", row).selected = true;
                    break;
                case 'action_holdings_maint':
                    (self.generateMakeRecTab( li.eg_bib_id(), 'copy_browser', row ))();
                    break;
                case 'action_manage_claims':
                    self.fetchClaimInfo(li.id(), true, function(full) { self.claimDialog.show(full) }, row);
                    break;
                case 'action_view_history':
                    location.href = oilsBasePath + '/acq/lineitem/history/' + li.id();
                    break;
            }
        };
        var actUpdateBarcodes = nodeByName("action_update_barcodes", row);
        var actHoldingsMaint = nodeByName("action_holdings_maint", row);

        /* handle row coloring for based on LI state */
        openils.Util.removeCSSClass(row, /^oils-acq-li-state-/);
        openils.Util.addCSSClass(row, "oils-acq-li-state-" + li.state());

        // Expose invoice actions for any lineitem that is linked to a PO 
        if (li.purchase_order()) {
            openils.Util.show(nodeByName("invoices_span", row), "inline");
            var link = nodeByName("invoices_link", row);
            link.onclick = function() {
                var url = oilsBasePath + "/acq/search/unified?so=" +
                          base64Encode({"jub":[{"id": li.id()}]}) + "&rt=invoice"
                if (window.IAMBROWSER) {
                    xulG.relay_url(url);
                } else {
                    openils.XUL.newTabEasy(url);
                }
                return false;
            };
        }
                

        /*
         * If we haven't fleshed the lineitem_details, default to allowing access to the 
         * holdings maintenence actions.  The alternative is to flesh LIDs on every lineitem, 
         * but that will add to page render time.  Let's see if this will suffice...
         */
        var lids = li.lineitem_details();
        if( !lids || 
                (lids && !lids.filter(function(lid) { return lid.eg_copy_id() })[0] )) {

            actUpdateBarcodes.disabled = false;
            actHoldingsMaint.disabled = false;
        }

        var state_cell = nodeByName("li_state_" + li.state(), row);

        // re-hide any state label nodes which may have been un-hidden
        // through previous actions.
        dojo.query('[state-label]', row).forEach(function(node) {
            openils.Util.hide(node)
        });

        if (li.state() == 'cancelled') {
            if(typeof li.cancel_reason() == "object") {

                // clear the stock "Canceled" label, since we have more
                // information to replace it with.
                state_cell.innerHTML = '';

                var holds_state = dojo.create(
                    "span", {
                        "style": "border-bottom: 1px dashed #000;",
                        "innerHTML": li.cancel_reason().label()
                    }, state_cell, "only"
                );
                new dijit.Tooltip(
                    {
                        "label": "<em>" + li.cancel_reason().label() +
                            "</em><br />" + li.cancel_reason().description(),
                        "connectId": [holds_state]
                    }, dojo.create("span", null, state_cell, "last")
                );

                if (li.cancel_reason().keep_debits() == 't') {
                    openils.Util.removeCSSClass(row, /^oils-acq-li-state-/);
                    openils.Util.addCSSClass(row, "oils-acq-li-state-delayed");
                }
            } else {
                console.log('li cancel_reason is un-fleshed.  Please fix');
            }
        } 

        openils.Util.show(state_cell);
    };


    this._setAlertStore = function() {
        acqLitAlertAlertText.store = new dojo.data.ItemFileReadStore(
            {
                "data": acqliat.toStoreData(
                    this.pcrud.search(
                        "acqliat", {
                            "owning_lib": aou.orgNodeTrail(
                                aou.findOrgUnit(openils.User.user.ws_ou())
                            ).map(function(o) { return o.id(); })
                        }
                    )
                )
            }
        );
        acqLitAlertAlertText.setValue(); /* make the store "live" */
        acqLitAlertAlertText._store_ready = true;
    };

    /**
     * Draws and shows the lineitem notes pane
     */
    this.drawLiNotes = function(li) {
        var self = this;
        this.focusLineitem = li.id();

        if (!acqLitAlertAlertText._store_ready)
            this._setAlertStore();

        li.lineitem_notes(
            li.lineitem_notes().sort(
                function(a, b) { 
                    if(a.edit_time() < b.edit_time()) return 1;
                    return -1;
                }
            )
        );

        while(this.liNotesTbody.childNodes[0])
            this.liNotesTbody.removeChild(this.liNotesTbody.childNodes[0]);
        this.show('notes');

        acqLitCreateNoteSubmit.onClick = function() {
            var value = acqLitCreateNoteText.attr('value');
            if(!value) return;
            var note = new fieldmapper.acqlin();
            note.isnew(true);
            note.vendor_public(
                Boolean(acqLitCreateNoteVendorPublic.attr('checked'))
            );
            note.value(value);
            note.lineitem(li.id());

            self.updateLiNotes(li, note);
            acqLitCreateNoteVendorPublic.attr("checked", false);
            acqLitCreateNoteText.attr("value", "");
        }

        acqLitCreateAlertSubmit.onClick = function() {
            if (!acqLitAlertAlertText.item) {
                alert(localeStrings.ALERT_UNSELECTED);
                return;
            }

            var alert_text = new fieldmapper.acqliat().fromStoreItem(
                acqLitAlertAlertText.item
            );
            var value = acqLitAlertNoteValue.attr("value") || "";

            var note = new fieldmapper.acqlin();
            note.isnew(true);
            note.lineitem(li.id());
            note.value(value);
            note.alert_text(alert_text);

            self.updateLiNotes(li, note);
        }

        dojo.forEach(li.lineitem_notes(), function(note) { self.addLiNote(li, note) });
    }

    /**
     * Draws a single lineitem note in the notes pane
     */
    this.addLiNote = function(li, note) {
        if(note.isdeleted()) return;
        var self = this;
        var row = self.liNotesRow.cloneNode(true);
        nodeByName("value", row).innerHTML = note.value();
        var alert_node = nodeByName("alert_code", row);
        if (note.alert_text()) {
            alert_node.innerHTML = dojo.string.substitute(
                "[${0}] ${1}", [
                    aou.findOrgUnit(note.alert_text().owning_lib()).shortname(),
                    note.alert_text().code()
                ]
            );
            if (note.alert_text().description()) {
                new dijit.Tooltip(
                    {
                        "connectId": [alert_node],
                        "label": note.alert_text().description()
                    }, dojo.create("span", null, alert_node, "after")
                );
            }
        }

        if (openils.Util.isTrue(note.vendor_public()))
            nodeByName("vendor_public", row).innerHTML =
                localeStrings.VENDOR_PUBLIC;

        nodeByName("delete", row).onclick = function() {
            note.isdeleted(true);
            self.liNotesTbody.removeChild(row);
            self.updateLiNotes(li);
        };

        if(note.edit_time()) {
            nodeByName("edit_time", row).innerHTML =
                dojo.date.locale.format(
                    dojo.date.stamp.fromISOString(note.edit_time()), 
                    {formatLength:'short'});
        }

        self.liNotesTbody.appendChild(row);
    }

    /**
     * Updates any new/changed/deleted notes on the server
     */
    this.updateLiNotes = function(li, newNote) {

        var notes;
        if(newNote) {
            notes = [newNote];
        } else {
            notes = li.lineitem_notes().filter(
                function(note) {
                    if(note.ischanged() || note.isnew() || note.isdeleted())
                        return note;
                }
            );
        }

        if(notes.length == 0) return;
        progressDialog.show();

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem_note.cud.batch'],
            {   async : true,
                params : [this.authtoken, notes],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);

                    if(resp.complete) {

                        if(!newNote) {
                            // remove the old changed notes
                            var list = [];
                            dojo.forEach(li.lineitem_notes(), 
                                function(note) {
                                    if(!(note.ischanged() || note.isnew() || note.isdeleted()))
                                        list.push(note);
                                }
                            );
                            li.lineitem_notes(list);
                        }

                        progressDialog.hide();
                        self.updateLiNotesCount(li);
                        self.drawLiNotes(li);
                        return;
                    }

                    progressDialog.update(resp);
                    var newnote = resp.note;

                    if(!newnote.isdeleted()) {
                        newnote.isnew(false);
                        newnote.ischanged(false);
                        li.lineitem_notes().push(newnote);
                    }
                },
            }
        );
    }

    this.updateLiPrice = function(input, li) {
        var self = this;
        var price = input.value;
        if(Number(price) == Number(li.estimated_unit_price())) return;

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.price.set'],
            {   async : false, // redundant w/ timeout
                timeout : 10,
                params : [this.authtoken, li.id(), price],
                oncomplete : function(r) {
                    openils.Util.readResponse(r);
                    li.estimated_unit_price(price); // update local copy

                    /*
                     * If this is a PO and every visible lineitem has a price,
                     * check again to see if this PO can be activated.  Note that 
                     * every visible lineitem having a price does not guarantee it can
                     * be activated, which is why we still make the call.  Having a price
                     * set for every visiable lineitem is just the lowest barrier to entry.
                     */
                    if (self.isPO) {
                        var priceNodes = dojo.query('[name=price]', dojo.byId('acq-lit-tbody'));
                        var allSet = true;
                        dojo.forEach(priceNodes, function(node) { if (node.value == '') allSet = false});
                        if (allSet) checkCouldActivatePo();
                        refreshPOSummaryAmounts();
                    }
                }
            }
        );
    }

    this.removeLineitem = function(liId) {
        this.tbody.removeChild(dojo.query('[li='+liId+']', this.tbody)[0]);
        delete this.liCache[liId];
        //selected.push(self.liCache[i.parentNode.parentNode.getAttribute('li')]);
    }

    this.drawInfo = function(liId) {
        this.focusLineitem = liId;
        if (!this._isRelatedViewer) {
            var d = dojo.byId("acq-lit-info-related");
            if (!this.relCache[liId]) {
                fieldmapper.standardRequest(
                    [
                        "open-ils.acq",
                        "open-ils.acq.lineitems_for_bib.by_lineitem_id.count"
                    ], {
                        "async": true,
                        "params": [openils.User.authtoken, liId],
                        "onresponse": function(r) {
                            self.relCache[liId] = openils.Util.readResponse(r);
                            nodeByName("related_number", d).innerHTML =
                                self.relCache[liId];
                            openils.Util[
                                self.relCache[liId] >1 ? "show" : "hide"
                            ](d);
                        }
                    }
                );
            } else {
                nodeByName("related_number", d).innerHTML = this.relCache[liId];
                openils.Util[this.relCache[liId] > 1 ? "show" : "hide"](d);
            }
        }

        this.show('info');
        openils.acq.Lineitem.fetchAttrDefs(
            function() { 
                self._fetchLineitem(liId, function(li){self._drawInfo(li);}); 
            } 
        );
    };

    this.toggleInlineCopies = function() {
        // if any inline copies are not displayed, 
        // display them all otherwise, hide them all.

        var displayAll = false;

        for (var liId in this.liCache) {
            if (!this.inlineCopiesVisible(liId)) {
                displayAll = true;
                break;
            }
        }

        for (var liId in this.liCache) {
            var row = dojo.byId('acq-inline-copies-row-' + liId);
            if (displayAll) {
                if (!row || row._hidden) {
                    this.drawInlineCopies(liId);
                }
            } else { // hide all
                if (row) {
                    // drawInlineCopies() on a visible row will hide it.
                    this.drawInlineCopies(liId);
                }
            }
        }

    };

    this.inlineCopiesVisible = function(liId) {
        var row = dojo.byId('acq-inline-copies-row-' + liId); 
        return (row && !row._hidden);
    }

    this.refreshInlineCopies = function(all, reFetch) {
        var self = this;
        var liIds = this.inlineCopiesNeedingRefresh;
        if (all) liIds = openils.Util.objectProperties(liCache);
        liIds.forEach(function(liId) {
            if (self.inlineCopiesVisible(liId)) {
                self.drawInlineCopies(liId, reFetch); // hide
                self.drawInlineCopies(liId, reFetch); // re-draw
            }
        });
    };

    // draw inline copy table.  if the table is 
    // already visible, hide the table as-is
    // reFetch forces a retrieval of the lineitem and 
    // copies from the server.  otherwise the locally
    // cached version of each is used.
    this.drawInlineCopies = function(liId, reFetch) {
        var self = this;
            
        // find or create the row where the inline copies table will live
        var containerRow = dojo.byId('acq-inline-copies-row-' + liId);
        var liRow = dojo.query('[li=' + liId + ']')[0];

        if (!containerRow) {

            // build the inline copies container row and add it to 
            // the DOM directly after the primary lineitem row

            containerRow = self.inlineCopyContainer.cloneNode(true);
            containerRow.id = 'acq-inline-copies-row-' + liId;

            if (liRow.nextSibling) {
                self.tbody.insertBefore(containerRow, liRow.nextSibling);
            } else {
                self.tbody.appendChild(containerRow);
            }

        } else {

            // toggle the visible state
            containerRow._hidden = !containerRow._hidden;
            openils.Util.toggle(containerRow, 'table-row');

            if (containerRow._hidden) return; // hide only
        }

        var handler = function(li) {

            var tbody = dojo.query(
                '[name=acq-li-inline-copies-tbody]', 
                containerRow)[0];

            // reset the table before adding copy rows
            while (tbody.childNodes[0])
                tbody.removeChild(tbody.childNodes[0]);

            if(li.lineitem_details().length == 0) {
                tbody.appendChild(
                    self.inlineNoCopies.cloneNode(true));
                return; // no copies to show
            }

            // add a row to the inline copy table for each copy
            dojo.forEach(li.lineitem_details(),
                function(copy) {
                    var row = self.inlineCopyTemplate.cloneNode(true);
                    tbody.appendChild(row);
                    self.addInlineCopy(li, copy, row);
                }
            );
        };

        this._fetchLineitem(liId, handler, reFetch);
    };

    /** Draw read-only copy widgets for inline copies */
    this.addInlineCopy = function(li, copy, row) {

        var self = this;
        dojo.forEach(liDetailFields,
            function(field) {

                var widget = new openils.widget.AutoFieldWidget({
                    fmObject : copy,
                    fmField : field,
                    labelFormat : (field == 'fund') ? fundLabelFormat : null,
                    searchFormat : (field == 'fund') ? fundSearchFormat : null,
                    dijitArgs: {"labelType": (field == 'fund') ? "html" : null},
                    fmClass : 'acqlid',
                    parentNode : dojo.query('[name=' + field + ']', row)[0],
                    readOnly : true,
                });

                widget.build();
            }
        );
    };

    /* For a given list of lineitem ids, build a list of full lineitems
     * re-using the fetching logic that is otherwise typical to use in this
     * module.
     *
     * If we've already got a lineitem in the cache, just use that.
     *
     * Once we've built a list of lineitems, call callback(thatlist).
     */
    this.fetchLineitemsById = function(id_list, callback) {
        var total = id_list.length;
        var result_list = [];

        var inner = function(li) {
            result_list.push(li)
            if (--total <= 0)
                callback(result_list);
        };

        id_list.forEach(function(id) { self._fetchLineitem(id, inner); });
    };

    this._fetchLineitem = function(liId, handler, force) {

        var li = this.liCache[liId];
        if(li && li.marc() && li.lineitem_details() && !force)
            return handler(li);
        
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.retrieve.authoritative'],
            {   async: true,

                params: [self.authtoken, liId, {
                    flesh_attrs: true,
                    flesh_cancel_reason: true,
                    flesh_li_details: true,
                    flesh_notes: true,
                    flesh_fund_debit: true }],

                oncomplete: function(r) {
                    var li = openils.Util.readResponse(r);
                    self.liCache[liId] = li;
                    handler(li)
                }
            }
        );
    };

    this._drawInfo = function(li) {

        acqLitEditOrderMarc.onClick = function() { self.editOrderMarc(li); }

        if(li.eg_bib_id()) {
            openils.Util.hide('acq-lit-marc-order-record-label');
            openils.Util.hide(acqLitEditOrderMarc.domNode);
            openils.Util.show('acq-lit-marc-real-record-label');
        } else {
            openils.Util.show('acq-lit-marc-order-record-label');
            openils.Util.show(acqLitEditOrderMarc.domNode);
            openils.Util.hide('acq-lit-marc-real-record-label');
        }

        this.drawMarcHTML(li);
        this.infoTbody = dojo.byId('acq-lit-info-tbody');

        if(!this.infoRow)
            this.infoRow = this.infoTbody.removeChild(dojo.byId('acq-lit-info-row'));
        while(this.infoTbody.childNodes[0])
            this.infoTbody.removeChild(this.infoTbody.childNodes[0]);

        for(var i = 0; i < li.attributes().length; i++) {
            var attr = li.attributes()[i];
            var row = this.infoRow.cloneNode(true);

            var type = attr.attr_type().replace(/lineitem_(.*)_attr_definition/, '$1');
            var name = openils.acq.Lineitem.attrDefs[type].filter(
                function(a) {
                    return (a.code() == attr.attr_name());
                }
            ).pop().description();

            dojo.query('[name=label]', row)[0].appendChild(document.createTextNode(name));
            dojo.query('[name=value]', row)[0].appendChild(document.createTextNode(attr.attr_value()));
            this.infoTbody.appendChild(row);
        }

        if (!this._isRelatedViewer) {
            nodeByName("rel_link", dojo.byId("acq-lit-info-related")).href =
                oilsBasePath + "/acq/lineitem/related/" + li.id();
        }

        // if a top scroll point is defined, jump up to it here
        var node = dojo.byId('oils-scroll-to-top');
        if (node) dijit.scrollIntoView(node);
    };

    this.generateMakeRecTab = function(bib_id,default_view, row) {
        return function() {
            if(openils.XUL.isXUL() && !window.IAMBROWSER) {
                xulG.new_tab(
                    XUL_OPAC_WRAPPER,
                    {tab_name: localeStrings.XUL_RECORD_DETAIL_PAGE, browser:false},
                    {
                        no_xulG : false, 
                        show_nav_buttons : true, 
                        show_print_button : true, 
                        opac_url : xulG.url_prefix('opac_rdetail|' + bib_id),
                        default_view : default_view
                    }
                );
            } else {
                var url = '/eg/staff/cat/catalog/record/' + bib_id;
                if (default_view == 'copy_browser') {
                    url += '/holdings';
                }
                window.open(url);
            }

            if(row) nodeByName("action_none", row).selected = true;
        }
    };

    this.drawMarcHTML = function(li) {
        var params = [null, true, li.marc()];
        if(li.eg_bib_id()) 
            params = [li.eg_bib_id(), true];

        fieldmapper.standardRequest(
            ['open-ils.search', 'open-ils.search.biblio.record.html'],
            {   async: true,
                params: params,
                oncomplete: function(r) {
                    dojo.byId('acq-lit-marc-div').innerHTML = 
                        openils.Util.readResponse(r);
                }
            }
        );
    }

    this.drawCopies = function(liId, force_fetch) {
        this.focusLineitem = liId;
        if (typeof force_fetch == "undefined")
            force_fetch = false;

        var cgi = new openils.CGI();
        var source = cgi.param('source');
        if (source && source.match(/invoice/)) {
            // got here from the invoice page, show the 'return-to-invoice' button
            var cgi = new openils.CGI({url : source});
            cgi.param('focus_li', liId);
            openils.Util.show(dojo.byId('acq-lit-copies-back-to-invoice-button-wrapper'), 'inline');
            var button = dojo.byId('acq-lit-copies-back-to-invoice-button');
            button.onclick = function() { location.href = cgi.url() };
        }

        openils.acq.Lineitem.fetchAndRender(liId, {}, 
            function(li, html) {
                dojo.byId('acq-lit-copies-li-summary').innerHTML = html;
            }
        );

        this.show('copies');
        var self = this;
        this.copyCache = {};
        this.copyWidgetCache = {};
        this.oldCopyWidgetCache = {};
        this.virtDfaCounts = {};
        this.realDfaCache = {};
        this.dfeOffset = 0;

        acqLitSaveCopies.onClick = function() { self.saveCopyChanges(liId) };
        acqLitBatchUpdateCopies.onClick = function() { self.batchCopyUpdate() };
        acqLitCopyCountInput.attr('value', '0');

        if (this.isPO && PO && PO.order_date()) {
            // prevent adding copies to activated POs
            acqLitCopyCountInput.attr('disabled', true);
            acqLitAddCopyCount.attr('disabled', true);
        }

        while(this.copyTbody.childNodes[0])
            this.copyTbody.removeChild(this.copyTbody.childNodes[0]);

        this._drawBatchCopyWidgets();

        this._drawDistribApplied(liId);

        this._fetchDistribFormulas(
            function() {
                openils.acq.Lineitem.fetchAttrDefs(
                    function() { 
                        self._fetchLineitem(liId, function(li){self._drawCopies(li);}, force_fetch); 
                    } 
                );
            }
        );
    };

    this._saveDistribAppliedTemplates = function() {
        if (!this._appliedDistribTemplate) {
            this._appliedDistribTemplate =
                dojo.byId("acq-lit-distrib-applied-tbody").
                    removeChild(dojo.byId("acq-lit-distrib-applied-row"));
            dojo.attr(this._appliedDistribTemplate, "id");
        }
    };

    this._drawDistribApplied = function(liId) {
        /* Build this table while hidden to prevent rendering artifacts */
        openils.Util.hide("acq-lit-distrib-applied-tbody");

        this._saveDistribAppliedTemplates();

        /* Remove any rows in the table from previous populations */
        dojo.query("tr[formula]", "acq-lit-distrib-applied-tbody").
            forEach(dojo.destroy);

        /* Unregister all dijits previously created (for some reason this isn't
         * covered by the above destroy calls). */
        dijit.registry.forEach(
            function(w) { if (/^dfa-/.test(w.id)) w.destroyRecursive(); }
        );

        /* Populate the table with our liId */
        var total = 0;
        fieldmapper.standardRequest(
            ["open-ils.acq",
            "open-ils.acq.distribution_formula_application.ranged.retrieve"],
            {
                "async": true,
                "params": [self.authtoken, liId],
                "onresponse": function(r) {
                    var dfa = openils.Util.readResponse(r);
                    if (dfa) {
                        total++;
                        self.realDfaCache[dfa.id()] = dfa;
                        self._drawDistribAppliedUnit(dfa);
                    }
                },
                "oncomplete": function() {
                    /* Reveal built table */
                    if (total) {
                        openils.Util.show(
                            "acq-lit-distrib-applied-tbody", "table-row-group"
                        );
                    }
                }
            }
        );
    };

    this._drawDistribAppliedUnit = function(dfa) {
        var new_row = false;
        var row = dojo.query(
            'tr[formula="' + dfa.formula().id() + '"]',
            "acq-lit-distrib-applied-tbody"
        )[0];

        if (!row) {
            new_row = true;
            row = dojo.clone(this._appliedDistribTemplate);
            dojo.attr(row, "formula", dfa.formula().id());
            dojo.query("th", row)[0].innerHTML = dfa.formula().name();
        }

        var td = dojo.query("td", row)[0];

        dojo.create("span", {"id": "dfa-button-" + dfa.id()}, td, "last");
        dojo.create("span", {"id": "dfa-tip-" + dfa.id()}, td, "last");

        if (new_row)
            dojo.place(row, "acq-lit-distrib-applied-tbody", "last");

        new dijit.form.Button(
            {
                "onClick": function() {
                    if (confirm(localeStrings.EXPLAIN_DFA_MGMT))
                        self.deleteDfa(dfa);
                },
                "label": "X",
                /* XXX I /cannot/ make the following work in as a CSS class
                 * for some reason. So frustrating... */
                "style": function(id) {
                     return (id > 0 ?
                        "font-weight: bold; color: #c00;" :
                        "color: #666;");
                     }(dfa.id()) + "margin: 0 6px;display: inline;"
            }, "dfa-button-" + dfa.id()
        );
        new dijit.Tooltip(
            {
                "connectId": ["dfa-button-" + dfa.id()],
                "label": dojo.string.substitute(
                    localeStrings.DFA_TIP, dfa.id() > 0 ? [
                        openils.User.formalName(dfa.creator()),
                        dojo.date.locale.format(
                            dojo.date.stamp.fromISOString(dfa.create_time()),
                            {"formatLength":"short"}
                        )
                    ] : [localeStrings.ITS_YOU, localeStrings.JUST_NOW]
                )
            }, "dfa-tip-" + dfa.id()
        );
    }

    this.deleteDfa = function(dfa) {
        if (dfa.id() > 0) { /* real */
            this.pcrud.eliminate(
                dfa, {
                    "async": true,
                    "oncomplete": function() {
                        self._removeDistribApplied(dfa.id());
                        delete self.realDfaCache[dfa.id()];
                    }
                }
            );
        } else { /* virtual */
            if (--(this.virtDfaCounts[dfa.formula().id()]) < 0)
            this.virtDfaCounts[dfa.formula().id()] = 0;
            /* hasn't been saved yet, so no need to do anything server side */
            this._removeDistribApplied(dfa.id());
        }

    };

    this._removeDistribApplied = function(dfaId) {
        var re = new RegExp("^dfa-\\w+-" + String(dfaId));
        dijit.registry.forEach(
            function(w) { if (re.test(w.id)) w.destroyRecursive(); }
        );
        this._removeDistribAppliedEmptyRows();
    };

    this._removeAllDistribAppliedVirtual = function() {
        /* Unregister dijits */
        dijit.registry.forEach(
            function(w) { if (/^dfa-\w+--/.test(w.id)) w.destroyRecursive(); }
        );
        this._removeDistribAppliedEmptyRows();
    };

    this._removeDistribAppliedEmptyRows = function() {
        /* Remove any rows with no DFA at all */
        dojo.query("tr[formula] td", "acq-lit-distrib-applied-tbody").forEach(
            function(o) {
                if (o.childNodes.length < 1) dojo.destroy(o.parentNode);
            }
        );
    };

    /**
     * Insert a new row into the distribution formula selection form
     */
    this._addDistribFormulaRow = function() {
        var self = this;

        if (!self.distribForms) {
            // no formulas, hide the form
            openils.Util.hide('acq-lit-distrib-formula-table');
            return;
        }

        if(!this.distribFormulaTemplate) 
            this.distribFormulaTemplate = 
                dojo.byId('acq-lit-distrib-formula-tbody').removeChild(dojo.byId('acq-lit-distrib-form-row'));

        var row = this.distribFormulaTemplate.cloneNode(true);
        dojo.place(row, "acq-lit-distrib-formula-tbody", "only");

        this.dfSelector = new dijit.form.FilteringSelect(
            {"labelAttr": "dynLabel", "labelType": "html"},
            nodeByName("selector", row)
        );
        this._updateFormulaStore();
        this.dfSelector.fetchProperties =
            {"sort": [{"attribute": "use_count", "descending": true}]};

        var apply = new dijit.form.Button(
            {"label": localeStrings.APPLY},
            nodeByName('set_button', row)
        ); 

        var reset = new dijit.form.Button(
            {"label": localeStrings.RESET_FORMULAE, "disabled": true},
            nodeByName("reset_button", row)  
        );

        dojo.connect(apply, 'onClick', 
            function() {
                var form_id = self.dfSelector.attr("value");
                if(!form_id) return;
                self._applyDistribFormula(form_id);
                reset.attr("disabled", false);
            }
        );

        dojo.connect(reset, 'onClick', 
            function() {
                self.restoreCopyFieldsBeforeDF();
                self.virtDfaCounts = {};
                self.virtDfaId = -1;
                self.dfeOffset = 0;
                self._updateFormulaStore();
                self._removeAllDistribAppliedVirtual();
                reset.attr("disabled", "true");
            }
        );

    };

    /**
     * Applies a distrib formula to the current set of copies
     */
    this._applyDistribFormula = function(formula) {
        if(!formula) return;

        formula = this.distribForms.filter(
            function(form) { return form.id() == formula; }
        )[0];

        var copyRows = dojo.query('tr', self.copyTbody);

        if (this.dfeOffset >= copyRows.length) {
            alert(localeStrings.OUT_OF_COPIES);
            return;
        }

        var entries_applied = 0;
        for(
            var rowIndex = this.dfeOffset;
            rowIndex < copyRows.length;
            rowIndex++
        ) {
            
            var row = copyRows[rowIndex];
            var copy_id = row.getAttribute('copy_id');
            var copyWidgets = this.copyWidgetCache[copy_id];
            var entryIndex = this.dfeOffset;
            var entry = null;

            // find the correct entry for the current row
            dojo.forEach(formula.entries(), 
                function(e) {
                    if(!entry) {
                        entryIndex += e.item_count();
                        if(entryIndex > rowIndex)
                            entry = e;
                    }
                }
            );

            if(entry) {
                
                //console.log("rowIndex = " + rowIndex + ", entry = " + entry.id() + ", entryIndex=" + 
                //  entryIndex + ", owning_lib = " + entry.owning_lib() + ", location = " + entry.location());
    
                entries_applied++;
                this.saveCopyFieldsBeforeDF(copy_id);
                this._copy_fields_for_acqdf.forEach(
                    function(field) {
                        if(entry[field]()) {
                            copyWidgets[field].attr('value', (entry[field]()));
                        }
                    }
                );
            }
        }

        if (entries_applied) {
            this.virtDfaCounts[formula.id()] =
                ++(this.virtDfaCounts[formula.id()]) || 1;
            this._updateFormulaStore();
            this._drawDistribAppliedUnit(
                function(df) {
                    var dfa = new acqdfa();
                    dfa.formula(df); dfa.id(self.virtDfaId--); return dfa;
                }(formula)
            );
            this.dfeOffset += entries_applied;
        };
    };

    /**
     * This function updates the DF store for the dropdown so that use_counts
     * can reflect DF applications from this session before they're saved
     * server-side.
     */
    this._updateFormulaStore = function() {
        this.dfSelector.store = new dojo.data.ItemFileReadStore(
            {
                "data": self._labelFormulasWithCounts(
                    acqdf.toStoreData(self.distribForms)
                )
            }
        );
    };

    this.saveCopyFieldsBeforeDF = function(copy_id) {
        var self = this;
        if (!this.oldCopyWidgetCache[copy_id]) {
            var copyWidgets = this.copyWidgetCache[copy_id];

            this.oldCopyWidgetCache[copy_id] = {};
            this._copy_fields_for_acqdf.forEach(
                function(f) {
                    self.oldCopyWidgetCache[copy_id][f] =
                        copyWidgets[f].attr("value");
                }
            );
        }
    };

    this.restoreCopyFieldsBeforeDF = function() {
        var self = this;
        for (var copy_id in this.oldCopyWidgetCache) {
            this._copy_fields_for_acqdf.forEach(
                function(f) {
                    self.copyWidgetCache[copy_id][f].attr(
                        "value", self.oldCopyWidgetCache[copy_id][f]
                    );
                }
            );
        }
    };

    this._labelFormulasWithCounts = function(store_data) {
        for (var key in store_data.items) {
            var obj = store_data.items[key];
            obj.use_count = Number(obj.use_count); /* needed for sorting */

            if (this.virtDfaCounts[obj.id])
                obj.use_count = obj.use_count + Number(this.virtDfaCounts[obj.id]);

            obj.dynLabel = "<span class='acq-lit-distrib-form-use-count'>[" +
                obj.use_count + "]</span>&nbsp; " + obj.name;
        }
        return store_data;
    };

    /**
     * This method formerly would not refetch the DF formulas if they'd been
     * loaded already, but now it always re-fetches, since use_count changes.
     */
    /** TODO: port distrib-formula selector to autofieldwidget+pcrud/dojo store */
    this._fetchDistribFormulas = function(onload) {
        fieldmapper.standardRequest(
            ["open-ils.acq",
                "open-ils.acq.distribution_formula.ranged.retrieve.atomic"],
            {
                "async": true,
                "params": [openils.User.authtoken, 0, 500],
                "oncomplete": function(r) {
                    self.distribForms = openils.Util.readResponse(r);
                    if(!self.distribForms || self.distribForms.length == 0) {
                        self.distribForms = [];
                    }
                    self._addDistribFormulaRow();
                    onload();
                }
            }
        );
    }

    this._drawBatchCopyWidgets = function() {
        var row = this.copyBatchRow;
        dojo.forEach(liDetailBatchFields, 
            function(field) {
                if(self.copyBatchRowDrawn) {
                    self.copyBatchWidgets[field].attr('value', null);
                } else {
                    var args = self.afwCopyFieldArgs(field, "CREATE_PICKLIST");
                    args.parentNode = dojo.query('[name='+field+']', row)[0];

                    var widget = new openils.widget.AutoFieldWidget(args);
                    widget.build(
                        function(w, ww) {
                            if (field == "fund" && w.store)
                                self._ensureCSSFundClasses(w.store);
                            self.copyBatchWidgets[field] = w;
                        }
                    );
                    if (field == "fund") {
                        dojo.connect(
                            widget.widget, "onChange", function(val) {
                                self._updateFundSelectorStyle(widget, val);
                            }
                        );
                    }
                }
            }
        );
        this.copyBatchRowDrawn = true;
    };

    this.batchCopyUpdate = function() {
        var self = this;
        for(var k in this.copyWidgetCache) {
            var cache = this.copyWidgetCache[k];
            dojo.forEach(liDetailBatchFields, function(f) {
                var newval = self.copyBatchWidgets[f].attr('value');
                if(newval) cache[f].attr('value', newval);
            });
        }
    };

    this._drawCopies = function(li) {
        var self = this;

        // this button sets the total number of copies for a given lineitem
        acqLitAddCopyCount.onClick = function() { 
            var count = acqLitCopyCountInput.attr('value');

            // add new rows
            while(self.copyCount() < count)
                self.addCopy(li); 
            
            // delete rows if necessary
            var diff = self.copyCount() - count;
            if(diff > 0) {
                var rows = dojo.query('tr', self.copyTbody).reverse().slice(0, diff);
                if(confirm(dojo.string.substitute(localeStrings.DELETE_LI_COPIES_CONFIRM, [diff]))) {
                    dojo.forEach(rows, function(row) {self.deleteCopy(row); });
                } else {
                    acqLitCopyCountInput.attr('value', self.copyCount()+'');
                }
            }
        }


        if(li.lineitem_details().length > 0) {
            dojo.forEach(li.lineitem_details(),
                function(copy) {
                    self.addCopy(li, copy);
                }
            );
        } else {
            self.addCopy(li);
        }
    };

    this.copyCount = function() {
        var count = 0;
        for(var id in this.copyCache) {
            if(!this.copyCache[id].isdeleted())
                count++;
        }
        return count;
    }

    this.virtCopyId = -1;
    this.addCopy = function(li, copy) {
        var row = this.copyRow.cloneNode(true);
        this.copyTbody.appendChild(row);
        var self = this;

        if(!copy) {
            copy = new fieldmapper.acqlid();
            copy.isnew(true);
            copy.id(this.virtCopyId--);
            copy.lineitem(li.id());
        }

        this.copyCache[copy.id()] = copy;
        row.setAttribute('copy_id', copy.id());
        self.copyWidgetCache[copy.id()] = {};

        acqLitCopyCountInput.attr('value', self.copyCount()+'');

        var rcvr = copy.receiver();
        if (rcvr) {
            if (!userCache[rcvr]) {
                if(rcvr == openils.User.user.id()) {
                    userCache[rcvr] = openils.User.user;
                } else {
                    userCache[rcvr] = fieldmapper.standardRequest(
                        ['open-ils.actor', 'open-ils.actor.user.retrieve'],
                        {params: [openils.User.authtoken, rcvr]}
                    );
                }
            }
            dojo.query('[name=receiver]', row)[0].innerHTML =  userCache[rcvr].usrname();
        }

        dojo.forEach(liDetailFields,
            function(field) {
                var searchFilter;
                if (field == "fund") {
                    searchFilter = (copy.fund() ?
                        {"-or": {"active": "t", "id": copy.fund()}} :
                        {"active" : "t"});
                    searchFilter.org = fundSearchFilter.org;
                } else {
                    searchFilter = null;
                }

                var readOnly = false;
                
                // TODO: Add support for changing the owning_lib after real copies have been made.  
                // owning_lib is order data as much as its item data
                if(copy.eg_copy_id() && ['owning_lib', 'location', 'circ_modifier', 'cn_label', 'barcode'].indexOf(field) >= 0) {
                    readOnly = true;
                }

                // TODO: add support for changing the fund after debits have been created
                // Note: invoicing allows the change
                if(copy.fund_debit() && field == 'fund') {
                    readOnly = true;
                }


                var widget = new openils.widget.AutoFieldWidget({
                    fmObject : copy,
                    fmField : field,
                    labelFormat : (field == 'fund') ? fundLabelFormat : null,
                    searchFormat : (field == 'fund') ? fundSearchFormat : null,
                    dijitArgs: {"labelType": (field == 'fund') ? "html" : null},
                    searchFilter : searchFilter,
                    noCache: (field == "fund"),
                    fmClass : 'acqlid',
                    parentNode : dojo.query('[name='+field+']', row)[0],
                    orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
                    readOnly : readOnly,
                    orgDefaultsToWs : true
                });

                widget.build(
                    // make sure we capture the value from any async widgets
                    function(w, ww) { 

                        if (field == "fund" && w.store)
                            self._ensureCSSFundClasses(w.store);

                        if(!readOnly) 
                            copy[field](ww.getFormattedValue()) 

                        self.copyWidgetCache[copy.id()][field] = w;

                        dojo.connect(w, 'onChange', 
                            function(val) { 
                                if (field == "fund")
                                    self._updateFundSelectorStyle(widget, val);

                                if (!readOnly && (copy.isnew() || val != copy[field]())) {
                                    // prevent setting ischanged() automatically on widget load for existing copies
                                    copy[field](widget.getFormattedValue()) 
                                    copy.ischanged(true);
                                }
                            }
                        );
                    }
                );
            }
        );

        this.updateLidState(copy, row);
    };

    this._ensureCSSFundClass = function(id) {
        if (!this.fundStyleSheet) {
            dojo.create(
                "style", {"type": "text/css"},
                document.getElementsByTagName("head")[0], "last"
            );
            this.fundStyleSheet = document.styleSheets[
                document.styleSheets.length - 1
            ];
        }

        var cn = "fund_" + id;
        if (!this.haveFundClass[cn]) {
            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.fund.check_balance_percentages"],
                {
                    "params": [openils.User.authtoken, id],
                    "async": true,
                    "oncomplete": function(r) {
                        r = openils.Util.readResponse(r);
                        self.fundBalanceState[id] = r;
                        var style = "";
                        if (r[0] /* stop */)
                            style = fundStyles.stop;
                        else if (r[1] /* warning */)
                            style = fundStyles.warning;
                        self.fundStyleSheet.insertRule(
                            "." + cn + " { " + style + " }",
                            self.fundStyleSheet.cssRules.length
                        );
                        self.haveFundClass[cn] = true;
                    }
                }
            );
        }
    };

    this._ensureCSSFundClasses = function(store) {
        store.fetch({
            "query": {"id": "*"},
            "onItem": function(o) { self._ensureCSSFundClass(o.id[0]); }
        });
    };

    this._updateFundSelectorStyle = function(widget, fund_id) {
        openils.Util.removeCSSClass(widget.widget.domNode, /fund_\d+/);
        openils.Util.addCSSClass(widget.widget.domNode, "fund_" + fund_id);
    };

    this.updateLidState = function(copy, row) {
        var self = this;

        if (typeof(row) == "undefined") {
            row = dojo.query('tr[copy_id="' + copy.id() + '"]', this.copyTbody)[0];
        }

        // action links
        var recv_link = nodeByName("receive", row);
        var unrecv_link = nodeByName("unreceive", row);
        var del_link = nodeByName("delete", row);
        var cxl_link = nodeByName("cancel", row);
        var claim_link = nodeByName("claim", row);
        var cxl_reason_link = nodeByName("cancel_reason", row);

        // by default, hide all the actions
        openils.Util.hide(del_link.parentNode);
        openils.Util.hide(recv_link);
        openils.Util.hide(unrecv_link);
        openils.Util.hide(cxl_link);
        openils.Util.hide(claim_link);
        openils.Util.hide(cxl_reason_link);

        if (copy.id() > 0) { // real copies (LIDs)

            if (copy.cancel_reason()) { 

                /* --------- cancelled -------------------------- */

                /* XXX the following may leak memory in a long lived table: 
                 * dijits may not get destroyed... not positive. revisit. */
                var holds_reason = dojo.create(
                    "span", {
                        "style": "border-bottom: 1px dashed #000;",
                        "innerHTML": copy.cancel_reason().label()
                    }, cxl_reason_link, "only"
                );
                new dijit.Tooltip(
                    {
                        "label": "<em>" + copy.cancel_reason().label() +
                            "</em><br />" + copy.cancel_reason().description(),
                        "connectId": [holds_reason]
                    }, dojo.create("span", null, cxl_reason_link, "last")
                );
                openils.Util.show(cxl_reason_link, "inline");

                if (copy.cancel_reason().keep_debits() == 't' ) {
                    // allow further cancellation of "delayed" copies
                    
                    openils.Util.show(cxl_link, "inline");
                    cxl_link.onclick = function() { self.cancelLid(copy.id()) };
                }

            } else if (copy.recv_time()) { 

                /* --------- received -------------------------- */

                openils.Util.show(unrecv_link, "inline");
                unrecv_link.onclick = function() {
                    if (confirm(localeStrings.UNRECEIVE_LID))
                        self.issueReceive(copy, /* rollback */ true);
                };

            } else if (this.liCache[copy.lineitem()].state() == 'on-order') {
                
                /* --------- on order -------------------------- */

                openils.Util.show(recv_link, 'inline');
                openils.Util.show(cxl_link, "inline");

                recv_link.onclick = function() {
                    if (self.checkLiAlerts(copy.lineitem()))
                        self.issueReceive(copy);
                };

                cxl_link.onclick = function() { self.cancelLid(copy.id()) };

            } else {

                /* --------- pre-order copies  -------------------------- */

                del_link.onclick = function() { self.deleteCopy(row) };
                openils.Util.show(del_link.parentNode);

            }

        } else { 

            /* --------- virtual copies  -------------------------- */

            del_link.onclick = function() { self.deleteCopy(row) };
            openils.Util.show(del_link.parentNode);
        }
    };

    this.cancelLid = function(lid_id) {
        lidCancelDialog._lid_id = lid_id;
        openils.Util.show(lidCancelDialog.domNode.parentNode);
        lidCancelDialog.show();
        if (!lidCancelDialog._prepared) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "cancel_reason",
                "fmClass": "acqlid",
                "parentNode": dojo.byId("acq-lit-lid-cancel-reason"),
                "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
                "forceSync": true,
                "searchOptions" : {order_by : {"acqcr":"label"}}
            });
            widget.build(
                function(w, ww) {
                    acqLidCancelButton.onClick = function() {
                        if (w.attr("value")) {
                            if (confirm(localeStrings.LID_CANCEL_CONFIRM)) {
                                self._cancelLid(
                                    lidCancelDialog._lid_id,
                                    w.attr("value")
                                );
                            }
                            lidCancelDialog.hide();
                        }
                    };
                    lidCancelDialog._prepared = true;
                }
            );
        }
    };

    this._cancelLid = function(lid_id, reason) {
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.lineitem_detail.cancel"], {
                "params": [openils.User.authtoken, lid_id, reason],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        if (r.lid) {
                            for (var id in r.lid) {
                                /* actually this should only iterate once */
                                self.copyCache[id].cancel_reason(
                                    r.lid[id].cancel_reason
                                );
                                self.updateLidState(self.copyCache[id]);
                                if (r.li_update_needed) {
                                    location.href = location.href; // sledgehammer
                                }
                            }
                        }
                    }
                }
            }
        );
    };

    this._confirmAlert = function(li, lin) {
        return confirm(
            dojo.string.substitute(
                localeStrings.CONFIRM_LI_ALERT, [
                    (new openils.acq.Lineitem({"lineitem": li})).findAttr(
                        "title", "lineitem_marc_attr_definition"
                    ), (
                        /* XXX it's really better add a parameter and to adjust
                         * the format string rather than do this concatenation
                         * here, but if someone wants this for 2.2 in a hurry,
                         * we can sidestep the problem of updating the strings
                         * while the translators are working. */
                        "[" +
                        aou.findOrgUnit(lin.alert_text().owning_lib()).shortname() +
                        "] " +
                        lin.alert_text().code()
                    ),
                    lin.alert_text().description() || "",
                    lin.value()
                ]
            )
        );
    };

    this.checkLiAlerts = function(li_id) {
        var li = this.liCache[li_id];

        var alert_notes = li.lineitem_notes().filter(
            function(o) { return Boolean(o.alert_text()); }
        );

        /* this is _intentionally_ not done in a call to forEach() ... */
        for (var i = 0; i < alert_notes.length; i++) {
            if (this.noteAcks[alert_notes[i].id()])
                continue;
            else if (!this._confirmAlert(li, alert_notes[i]))
                return false;
            else
                this.noteAcks[alert_notes[i].id()] = true;
        }

        return true;
    };

    this.deleteCopy = function(row) {
        var copy = this.copyCache[row.getAttribute('copy_id')];
        copy.isdeleted(true);
        if(copy.isnew())
            delete this.copyCache[copy.id()];
        this.copyTbody.removeChild(row);
    }

    this._virtDfaCountsAsList = function() {
        var L = [];
        for (var key in this.virtDfaCounts) {
            for (var i = 0; i < this.virtDfaCounts[key]; i++)
                L.push(key);
        }
        return L;
    }

    this.confirmBreachedCopyFunds = function(copies) {
        var stop = 0, warning = 0;
        copies.forEach(
            function(o) {
                if (o.fund()) {
                    var state = self.fundBalanceState[o.fund()];
                    if (state[0] /* stop */)
                        stop++;
                    else if (state[1] /* warning */)
                        warning++;
                }
            }
        );

        if (stop) {
            return confirm(localeStrings.CONFIRM_FUNDS_AT_STOP);
        } else if (warning) {
            return confirm(localeStrings.CONFIRM_FUNDS_AT_WARNING);
        }
        return true;
    };

    this.saveCopyChanges = function(liId) {
        var self = this;
        var copies = [];


        var total = 0;
        for(var id in this.copyCache) {
            var c = this.copyCache[id];
            if(!c.isdeleted()) total++;
            if(c.isnew() || c.ischanged() || c.isdeleted()) {
                if(c.id() < 0) c.id(null);
                copies.push(c);
            }
        }


        dojo.byId('acq-lit-copy-count-label-' + liId).innerHTML = total;


        if (copies.length > 0) {
            if (!this.confirmBreachedCopyFunds(copies))
                return;

            if (typeof(this._copy_count_cb) == "function")
                this._copy_count_cb(liId, total);

            openils.Util.show("acq-lit-update-copies-progress");
            fieldmapper.standardRequest(
                ['open-ils.acq', 'open-ils.acq.lineitem_detail.cud.batch'],
                {   async: true,
                    params: [openils.User.authtoken, copies],
                    onresponse: function(r) {
                        var res = openils.Util.readResponse(r);
                        litUpdateCopiesProgress.update(res);
                    },
                    oncomplete: function() {
                        self.drawCopies(liId, true /* force_fetch */);
                        openils.Util.hide("acq-lit-update-copies-progress");
                        refreshPOSummaryAmounts();
                    }
                }
            );
        }

        var dfa_list = this._virtDfaCountsAsList();
        if (dfa_list.length > 0) {
            fieldmapper.standardRequest(
                ["open-ils.acq",
                "open-ils.acq.distribution_formula.record_application"],
                {
                    "async": true,
                    "params": [openils.User.authtoken, dfa_list, liId],
                    "onresponse": function(r) {
                        var res = openils.Util.readResponse(r);
                        if (res && res.length < dfa_list.length)
                            alert(localeStrings.DFA_NOT_ALL);
                    }
                }
            );
            this.virtDfaCounts = {};
        }

        if (this.inlineCopiesNeedingRefresh.indexOf(liId) < 0)
            this.inlineCopiesNeedingRefresh.push(liId);
    };

    this._updateCreatePoPrepayCheckbox = function(prepay) {
        var prepay = openils.Util.isTrue(prepay);
        this._prepayRequiredByVendor = prepay;
        dijit.byId("acq-lit-po-prepay").attr("checked", prepay);
    };

    this._confirmPoPrepaySituation = function() {
        var want_prepay = dijit.byId("acq-lit-po-prepay").attr("checked");
        if (want_prepay != this._prepayRequiredByVendor) {
            return confirm(
                want_prepay ?
                    localeStrings.VENDOR_SAYS_PREPAY_NOT_NEEDED :
                    localeStrings.VENDOR_SAYS_PREPAY_NEEDED
            );
        } else {
            return true;
        }
    };

    this.applySelectedLiAction = function(action) {
        var self = this;
        switch(action) {

            case 'delete_selected':
                this._deleteLiList(self.getSelected());
                break;

            case 'add_to_order':
                addToPoDialog._get_li = dojo.hitch(
                    this,
                    function() { 
                        return this.getSelected(
                            false, null, true, li_pre_po_states);
                    }
                );
                if (addToPoDialog._get_li().length == 0) {
                    alert(localeStrings.NO_LI_GENERAL);
                    return;
                }
                addToPoDialog.show();
                break;

            case 'create_order':
                this._loadPOSelect();
                acqLitPoCreateDialog.show();
                break;

            case 'move_picklist':
                acqLitSavePlDialog.show();
                break;

            case 'selector_ready':
            case 'order_ready':
                acqLitChangeLiStateDialog.attr('state', action.replace('_', '-'));
                acqLitChangeLiStateDialog.show();
                break;

            case 'print_po':
                this.printPO();
                break;

            case 'po_history':
                location.href = oilsBasePath + '/acq/po/history/' + this.isPO;
                break;

            case 'batch_create_invoice':
                this.batchCreateInvoice();
                break;

            case 'batch_link_invoice':
                this.batchLinkInvoice();
                break;

            case 'receive_lineitems':
                this.receiveSelectedLineitems();
                break;

            case 'rollback_receive_lineitems':
                this.rollbackReceiveLineitems();
                break;

            case 'create_assets':
                this.showAssetCreator();
                break;

            case 'export_attr_list':
                this.chooseExportAttr();
                break;

            case 'batch_apply_funds':
                this.applyBatchLiFunds();
                break;

            case 'add_brief_record':
                if(this.isPO)
                    location.href = oilsBasePath + '/acq/picklist/brief_record?po=' + this.isPO;
                else
                    location.href = oilsBasePath + '/acq/picklist/brief_record?pl=' + this.isPL;

                break;

            case "cancel_lineitems":
                console.log('HERE');
                this.maybeCancelLineitems();
                break;

            case "apply_claim_policy":
                var li_list = this.getSelected();
                this.claimPolicyPicker.attr("value", null);
                liClaimPolicyDialog.show();
                liClaimPolicySave.onClick = function() {
                    self.changeClaimPolicy(
                        li_list,
                        self.claimPolicyPicker.attr("value"),
                        function() {
                            li_list.forEach(
                                function(li) {
                                    self.setClaimPolicyControl(li);
                                    self.reconsiderClaimControl(li);
                                }
                            );
                            liClaimPolicyDialog.hide();
                        }
                    )
                };
                break;
        }
    };

    this.changeClaimPolicy = function(li_list, value, callback) {
        li_list.forEach(
            function(li) { li.claim_policy(value); }
        );
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.lineitem.update"], {
                "params": [openils.User.authtoken, li_list],
                "async": true,
                "oncomplete": function(r) {
                    r = openils.Util.readResponse(r);
                    if (callback) callback(r);
                }
            }
        );
    };

    this.showAssetCreator = function(onAssetsCreated) {
        if(!this.isPO) return;
        var self = this;
    
        // first, let's see if this PO has any LI's that need to be merged/imported
        self.pcrud.search('jub', {purchase_order : this.isPO, eg_bib_id : null}, {
            id_list : true,
            oncomplete : function(r) {
                var resp = openils.Util.readResponse(r);
                if (resp && resp.length) {
                    // PO has some non-linked jubs.  
                    
                    self.show('asset-creator');
                    if(!self.vlAgent.loaded)
                        self.vlAgent.init();

                    dojo.connect(assetCreatorButton, 'onClick', 
                        function() { self.createAssets(onAssetsCreated) });

                } else {

                    // all jubs linked, move on to asset creation
                    self.createAssets(onAssetsCreated, true); 
                }
            }
        });
    }

    this.createAssets = function(onAssetsCreated, noVl) {
        this.show('acq-lit-progress-numbers');
        var self = this;
        var vlArgs = (noVl) ? {} : {vandelay : this.vlAgent.values()};
        this.batchProgress = {};
        progressDialog.show(false);
        progressDialog.attr("title", localeStrings.LI_CREATING_ASSETS);
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.assets.create'],
            {   async: true,
                params: [this.authtoken, this.isPO, vlArgs],
                onresponse: function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, !Boolean(onAssetsCreated), onAssetsCreated, true);
                }
            }
        );
    }

    this.maybeCancelLineitems = function() {
        openils.Util.show("acq-lit-cancel-reason", "inline");
        if (!acqLitCancelLineitemsButton._prepared) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "cancel_reason",
                "fmClass": "jub",
                "parentNode": dojo.byId("acq-lit-cancel-reason-selector"),
                "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
                "forceSync": true,
                "searchOptions" : {order_by : {"acqcr":"label"}}
            });
            widget.build(
                function(w, ww) {
                    acqLitCancelLineitemsButton.onClick = function() {
                        if (w.attr("value")) {
                            if (confirm(localeStrings.LI_CANCEL_CONFIRM)) {
                                self._cancelLineitems(w.attr("value"));
                            }
                            openils.Util.hide("acq-lit-cancel-reason");
                        }
                    };
                    acqLitCancelLineitemsButton._prepared = true;
                }
            );
        }
    };

    this._cancelLineitems = function(reason) {

        var li_list = this.getSelected();

        // canceled lineitems may be canceled again if they were 
        // previously delayed (keep_debits = true).
        li_list = li_list.filter(
            function(li) {
                return (
                    li.state() != 'cancelled' ||
                    li.cancel_reason().keep_debits() == 't'
                );
            }
        );

        id_list = li_list.map(function(l) {return l.id()});

        if (!id_list.length) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }
        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.lineitem.cancel.batch"], {
                "params": [openils.User.authtoken, id_list, reason],
                "async": true,
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        if (r.li) {
                            for (var id in r.li) {
                                self.liCache[id].state(r.li[id].state);
                                self.liCache[id].cancel_reason(
                                    r.li[id].cancel_reason
                                );
                                self.updateLiState(self.liCache[id]);
                            }
                        }
                        if (r.lid && self.copyCache) {
                            for (var id in r.lid) {
                                if (self.copyCache[id]) {
                                    self.copyCache[id].cancel_reason(
                                        r.lid[id].cancel_reason
                                    );
                                    self.updateLidState(self.copyCache[id]);
                                }
                            }
                        }
                    }
                }
            }
        );
    };

    this.chooseExportAttr = function() {
        if (!acqLitExportAttrSelector._li_setup) {
            var self = this;
            acqLitExportAttrSelector.store = new dojo.data.ItemFileReadStore(
                {
                    "data": acqlimad.toStoreData(
                        this.pcrud.search(
                            "acqlimad", {"code": li_exportable_attrs}
                        )
                    )
                }
            );
            acqLitExportAttrSelector.setValue();
            acqLitExportAttrButton.onClick = function(){self.exportAttrList();};
            acqLitExportAttrSelector._li_setup = true;
        }
        openils.Util.show("acq-lit-export-attr-holder", "inline");
    };

    this.exportAttrList = function() {
        var attr_def = acqLitExportAttrSelector.item;
        var li_list = this.getSelected();
        var value_list = li_list.map(
            function(li) {
                return (new openils.acq.Lineitem({"lineitem": li})).findAttr(
                    attr_def.code, "lineitem_marc_attr_definition"
                );
            }
        ).filter(function(attr) { return Boolean(attr); });

        if (value_list.length > 0) {
            if (value_list.length < li_list.length) {
                if (!confirm(
                    dojo.string.substitute(
                        localeStrings.EXPORT_SHORT_LIST, [attr_def.description]
                    )
                )) {
                    return;
                }
            }
            try {
                if (window.IAMBROWSER) {
                    var blob = new Blob(value_list, {type: "text/plain;charset=utf-8"});
                    saveAs(blob, "export_attr_list.txt");
                } else {
                    openils.XUL.contentToFileSaveDialog(
                        value_list.join("\n"),
                        localeStrings.EXPORT_SAVE_DIALOG_TITLE
                    );
                }
            } catch (E) {
                alert(E);
            }
        } else {
            alert(dojo.string.substitute(
                localeStrings.EXPORT_EMPTY_LIST, [attr_def.description]
            ));
        }

        openils.Util.hide("acq-lit-export-attr-holder");
    };

    this.printPO = function() {
        if(!this.isPO) return;
        progressDialog.show(true);
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.purchase_order.format'],
            {   async: true,
                params: [this.authtoken, this.isPO, 'html'],
                oncomplete: function(r) {
                    progressDialog.hide();
                    var evt = openils.Util.readResponse(r);
                    if(evt && evt.template_output()) {
                        openils.Util.printHtmlString(evt.template_output().data());
                    }
                }
            }
        );
    };

    this.batchCreateInvoice = function() {
        var liIds = this.getSelected(
            false, null, true /* id_list */, li_active_states)
        if (!liIds.length) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }
        var path = oilsBasePath + '/acq/invoice/view?create=1';
        dojo.forEach(liIds, function(li, idx) { path += '&attach_li=' + li });
        if (openils.XUL.isXUL() && !window.IAMBROWSER)
            openils.XUL.newTabEasy(path, localeStrings.NEW_INVOICE, null, true);
        else
            location.href = path;
    };

    this.batchLinkInvoice = function(create) {
        var liIds = this.getSelected(
            false, null, true /* id_list */, li_active_states)
        if (!liIds.length) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }
        if (!self.invoiceLinkDialogManager) {
            self.invoiceLinkDialogManager =
                new InvoiceLinkDialogManager("li");
        }
        self.invoiceLinkDialogManager.target = liIds;
        acqLitLinkInvoiceDialog.show();
    };

    this.receiveSelectedLineitems = function() {
        var states = li_post_po_states.filter(
            function(s) { return s != 'received' });
        var li_list = this.getSelected(null, null, null, states);

        if (!li_list.length) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }

        for (var i = 0; i < li_list.length; i++) {
            var li = li_list[i];

            if (li.state() != "received" &&
                !this.checkLiAlerts(li.id())) return;
        }

        this.show('acq-lit-progress-numbers');

        var self = this;
        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.receive.batch'],
            {   async: true,
                params: [
                    this.authtoken,
                    li_list.map(function(li) { return li.id(); })
                ],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, true);
                },
            }
        );
    };

    this.issueReceive = function(obj, rollback) {
        var part =
            {"jub": "lineitem", "acqlid": "lineitem_detail"}[obj.classname];
        var method =
            "open-ils.acq." + part + ".receive" + (rollback ? ".rollback" : "");

        progressDialog.show(true);
        fieldmapper.standardRequest(
            ["open-ils.acq", method], {
                "async": true,
                "params": [this.authtoken, obj.id()],
                "onresponse": function(r) {
                    if (r = openils.Util.readResponse(r)) {
                        self.fetchClaimInfo(
                            part == "lineitem" ? obj.id() : obj.lineitem(),
                            /* force */ true,
                            function() { self.handleReceive(r); }
                        );
                        progressDialog.hide();
                    }
                }
            }
        );
    };

    /**
     * Handles the responses from receive and rollback ML calls.
     */
    this.handleReceive = function(resp) {
        if (resp) {
            if (resp.li) {
                for (var li_id in resp.li) {
                    for (var key in resp.li[li_id])
                        self.liCache[li_id][key](resp.li[li_id][key]);
                    self.updateLiState(self.liCache[li_id]);
                }
            }
            if (resp.po) {
                if (typeof(self.poUpdateCallback) == "function")
                    self.poUpdateCallback(resp.po);
            }
            if (resp.lid) {
                for (var lid_id in resp.lid) {
                    for (var key in resp.lid[lid_id])
                        self.copyCache[lid_id][key](resp.lid[lid_id][key]);
                    self.updateLidState(self.copyCache[lid_id]);
                }
            }
        }
    };

    this.rollbackReceiveLineitems = function() {
        var li_id_list = this.getSelected(false, null, true);
        if (!li_id_list.length) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }

        if (!confirm(localeStrings.ROLLBACK_LI_RECEIVE_CONFIRM)) return;

        this.show('acq-lit-progress-numbers');
        var self = this;

        fieldmapper.standardRequest(
            ['open-ils.acq', 'open-ils.acq.lineitem.receive.rollback.batch'],
            {   async: true,
                params: [this.authtoken, li_id_list],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    self._updateProgressNumbers(resp, true);
                },
            }
        );
    };

    this._updateProgressNumbers = function(resp, reloadOnComplete, onComplete, clearProgressDialog) {
        this._updateProgressDialog(resp);
        this.vlAgent.handleResponse(resp,
            function(resp, res) {
                if (clearProgressDialog) {
                    progressDialog.update({ "progress": 100});
                    progressDialog.update_message();
                    progressDialog.hide();
                    progressDialog.attr("title", "");
                }
                if(reloadOnComplete)
                     location.href = location.href;
                if (onComplete)
                    onComplete(resp, res);
            }
        );
    }

    this._updateProgressDialog = function(resp) {
        progressDialog.update({ "progress": (resp.progress / resp.total) * 100 });
        var keys = ['li', 'vqbr', 'bibs', 'lid', 'debits_accrued', 'copies'];
        for (var i = 0; i < keys.length; i++) {
            if (resp[keys[i]] > (this.batchProgress[keys[i]] || 0)) {
                progressDialog.update_message(
                    dojo.string.substitute(
                        localeStrings["ACTIVATE_" + keys[i].toUpperCase() + "_PROCESSED"],
                        [ resp[keys[i]] ]
                    )
                );
            }
        }
        this.batchProgress = resp;
    }

    this._createPO = function(fields) {
        var wantall = (fields.create_from == "all");

        /* If we're a picklist or purchase order already and the user wants
         * all lineitems, we might have pages' worth of lineitems haven't all
         * been loaded yet, so getSelected() won't find them.  The server,
         * however, should know about all our lineitems, so let's ask the
         * server for a complete list.
         */

        if (wantall) {
            this.getSelected(
                true, function(list) {
                    self._createPOFromLineitems(fields, list);
                }, /* id_list */ true, li_pre_po_states
            );
        } else {
            this._createPOFromLineitems(
                fields, this.getSelected(
                    false, null, true /* id_list */, li_pre_po_states)
            );
        }
    };

    this._createPOFromLineitems = function(fields, selected) {
        if (selected.length == 0) {
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }
        var self = this;

        var po = new fieldmapper.acqpo();
        po.provider(this.createPoProviderSelector.attr("value"));
        po.ordering_agency(this.createPoAgencySelector.attr("value"));
        po.prepayment_required(fields.prepayment_required[0] ? true : false);
        var name = this.createPoNameInput.attr('value'); 
        if (name) po.name(name); // avoid name=""

        // if we're creating assets, delay the asset creation 
        // until after the PO is created.  This will allow us to 
        // use showAssetCreator() directly.

        fieldmapper.standardRequest(
            ["open-ils.acq", "open-ils.acq.purchase_order.create"],
            {   async: true,
                params: [
                    openils.User.authtoken, 
                    po, {lineitems : selected}
                ],
                onresponse : function(r) {
                    var resp = openils.Util.readResponse(r);
                    if (resp.complete) {
                        // self.isPO is needed for showAssetCreator();
                        self.isPO = resp.purchase_order.id(); 
                        var redir = oilsBasePath + "/acq/po/view/" + self.isPO;
                        if (fields.create_assets[0]) {
                            self.showAssetCreator(
                                function() {location.href = redir}
                            );
                        } else {
                           location.href = redir;
                        }
                    }
                }
            }
        );
    };


    this.batchFundWidget = null;

    this.applyBatchLiFunds = function() {

        var liIds = this.getSelected().map(function(li) { return li.id(); });
        if(liIds.length == 0) return; // warn?

        var self = this;
        batchFundUpdateDialog.show();

        if(!this.batchFundWidget) {
            this.batchFundWidget = new openils.widget.AutoFieldWidget({
                fmClass : 'acqf',
                selfReference : true,
                labelFormat : fundLabelFormat,
                searchFormat : fundSearchFormat,
                searchFilter : fundSearchFilter,
                parentNode : dojo.byId('acq-lit-batch-fund-selector'),
                orgLimitPerms : ['CREATE_PICKLIST', 'CREATE_PURCHASE_ORDER'],
                dijitArgs : { "required": true, "labelType": "html" },
                forceSync : true
            });
            this.batchFundWidget.build();
        }

        dojo.connect(batchFundUpdateCancel, 'onClick', function() { batchFundUpdateDialog.hide(); });
        dojo.connect(batchFundUpdateSubmit, 'onClick', 
            function() { 

                // TODO: call .dry_run first to test thresholds
                fieldmapper.standardRequest(
                    ['open-ils.acq', 'open-ils.acq.lineitem.fund.update.batch'],
                    {
                        params : [
                            openils.User.authtoken, 
                            liIds,
                            self.batchFundWidget.widget.attr('value')
                        ],
                        oncomplete : function(r) {
                            var resp = openils.Util.readResponse(r);
                            if(resp) {
                                location.href = location.href;
                            }
                        }
                    }
                )
            }
        );
    }

    this._deleteLiList = function(list, idx) {
        if(idx == null) idx = 0;
        if(idx >= list.length) return;

        var li = list[idx];
        var liId = li.id();

        if (this.isPO && (li.state() == "on-order" || li.state() == "received")) {
            /* It makes little sense to delete a lineitem from a PO that has
             * already been marked 'on-order'.  Especially if EDI is in use,
             * such a purchase order will probably have already been shipped
             * off to a vendor, and mucking with it at this point could leave
             * your data in a bad state that doesn't jive with reality.
             *
             * I could see making this restriction even firmer.
             *
             * I could also see adjusting the li state comparisons, extending
             * the comparison to the PO's state, and/or providing functions
             * that house the logic for comparing states in a single location.
             *
             * Yes, this will be really annoying if you have selected a lot
             * of lineitems to cancel that have been ordered. You'll get a
             * confirm dialog for each one.
             */

            if (!confirm(localeStrings.DEL_LI_FROM_PO)) {
                self._deleteLiList(list, ++idx); /* move on to next in list */
                return;
            }
        }

        fieldmapper.standardRequest(
            ['open-ils.acq',
             this.isPO ? 'open-ils.acq.purchase_order.lineitem.delete' : 'open-ils.acq.picklist.lineitem.delete'],
            {   async: true,
                params: [openils.User.authtoken, liId],
                oncomplete: function(r) {
                    self.removeLineitem(liId);
                    self._deleteLiList(list, ++idx);
                }
            }
        );
    }

    this.editOrderMarc = function(li) {

        var self = this;
        if(window.IAMBROWSER) {
            xulG.edit_marc_order_record(li, function(li) { self.drawInfo(li.id()) });
            return;
        }

        /*  To run in Firefox directly, must set signed.applets.codebase_principal_support
            to true in about:config */
        if(openils.XUL.isXUL()) {
            win = window.open('/xul/' + openils.XUL.buildId() + '/server/cat/marcedit.xul','','chrome');
        } else {
            win = window.open('/xul/server/cat/marcedit.xul','','chrome'); 
        }
        win.xulG = {
            record : {marc : li.marc(), "rtype": "bre"},
            save : {
                label: 'Save Record', // XXX I18N
                func: function(xmlString) {
                    li.marc(xmlString);
                    fieldmapper.standardRequest(
                        ['open-ils.acq', 'open-ils.acq.lineitem.update'],
                        {   async: true,
                            params: [openils.User.authtoken, li],
                            oncomplete: function(r) {
                                openils.Util.readResponse(r);
                                win.close();
                                self.drawInfo(li.id())
                            }
                        }
                    );
                },
            },
            'lock_tab' : typeof xulG != 'undefined' ? (typeof xulG['lock_tab'] != 'undefined' ? xulG.lock_tab : undefined) : undefined,
            'unlock_tab' : typeof xulG != 'undefined' ? (typeof xulG['unlock_tab'] != 'undefined' ? xulG.unlock_tab : undefined) : undefined
        };
    }

    this._savePl = function(values) {
        this.getSelected(
            (values.which == 'all'),
            function(list) { self._savePlFromLineitems(values, list); }
        );
    };

    this._savePlFromLineitems = function(values, selected) {
        openils.Util.show("acq-lit-generic-progress");

        if(values.new_name) {
            openils.acq.Picklist.create(
                {name: values.new_name},
                function(id) {
                    self._updateLiList(
                        id, selected, 0,
                        function() {
                            location.href =
                                oilsBasePath + "/acq/picklist/view/" + id;
                        }
                    );
                }
            );
        } else if(values.existing_pl) {
            // update lineitems to use an existing picklist
            self._updateLiList(
                values.existing_pl, selected, 0,
                function(){
                    location.href =
                        oilsBasePath + "/acq/picklist/view/" +
                        values.existing_pl;
                }
            );
        }
    };

    this._updateLiState = function(values, state, state_filter) {
        progressDialog.show(true);
        this.getSelected(
            (values.which == 'all'),
            function(list) {
                self._updateLiStateFromLineitems(values, state, list);
            }, false /* id_list */, state_filter
        );
    };

    this._updateLiStateFromLineitems = function(values, state, selected) {
        if(!selected.length) {
            try { progressDialog.hide() } catch(E) {};
            alert(localeStrings.NO_LI_GENERAL);
            return;
        }
        dojo.forEach(selected, function(li) {li.state(state);});
        self._updateLiList(null, selected, 0,
            // TODO consider inline updates for efficiency
            function() { location.href = location.href }
        );
    };

    this._updateLiList = function(pl, list, idx, oncomplete) {
        if(idx >= list.length) return oncomplete();
        var li = list[idx];
        if(pl != null) li.picklist(pl);
        litGenericProgress.update({maximum: list.length, progress: idx});
        new openils.acq.Lineitem({lineitem:li}).update(
            function(r) {
                self._updateLiList(pl, list, ++idx, oncomplete);
            }
        );
    }

    this._loadPOSelect = function() {
        if (!this.createPoProviderSelector) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "provider",
                "fmClass": "acqpo",
                "searchFilter": {"active": "t"},
                "parentNode": dojo.byId("acq-lit-po-provider"),
                "dijitArgs": {
                    "onChange": function() {
                        if (this.item) {
                            self._updateCreatePoPrepayCheckbox(
                                this.item.prepayment_required()
                            );
                        }
                    }
                }
            });
            widget.build(function(w) { self.createPoProviderSelector = w; });
        }

        this.createPoCheckDupes = function() {
            var org = self.createPoAgencySelector.attr('value');
            var name = self.createPoNameInput.attr('value');
            openils.Util.hide('acq-dupe-po-name');

            if (!name) {
                acqLitCreatePoSubmit.attr('disabled', false);
                return;
            }

            acqLitCreatePoSubmit.attr('disabled', true);
            var orgs = fieldmapper.aou.descendantNodeList(org, true);
            new openils.PermaCrud().search('acqpo', 
                {name : name, ordering_agency : orgs},
                {async : true, oncomplete : function(r) {
                    var po = openils.Util.readResponse(r);

                    if (po && (po = po[0])) {

                        var link = dojo.byId('acq-dupe-po-link');
                        openils.Util.show('acq-dupe-po-name', 'table-row');
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
                        acqLitCreatePoSubmit.attr('disabled', false);
                    }
                }}
            );
        }

        if (!this.createPoAgencySelector) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "ordering_agency",
                "fmClass": "acqpo",
                "parentNode": dojo.byId("acq-lit-po-agency"),
                "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
            });
            widget.build(function(w) { 
                self.createPoAgencySelector = w; 
                dojo.connect(w, 'onChange', self.createPoCheckDupes);
            });
        }

        if (!this.createPoNameInput) {
            var widget = new openils.widget.AutoFieldWidget({
                "fmField": "name",
                "fmClass": "acqpo",
                "parentNode": dojo.byId("acq-lit-po-name"),
                "orgLimitPerms": ["CREATE_PURCHASE_ORDER"],
            });
            widget.build(function(w) { 
                self.createPoNameInput = w; 
                dojo.connect(w, 'onChange', self.createPoCheckDupes);
            });
        }
    };

    this.showRealCopyEditUI = function(li) {
        copyList = [];
        var self = this;
        this.volCache = {};

        this._fetchLineitem(li.id(), 
            function(fullLi) {
                li = self.liCache[li.id()] = fullLi;

                self.pcrud.search(
                    'acp', {
                        id : li.lineitem_details().map(
                            function(item) { return item.eg_copy_id() }
                        )
                    }, {
                        async : true,
                        oncomplete : function(r) {
                            try {
                                var r_list = openils.Util.readResponse( r );
                                for (var i = 0; i < r_list.length; i++) {
                                    var copy = r_list[i];
                                    var volId = copy.call_number();
                                    var volume = self.volCache[volId];
                                    if(!volume) {
                                        volume = self.volCache[volId] = self.pcrud.retrieve('acn', volId);
                                    }
                                    copy.call_number(volume);
                                    copyList.push(copy);
                                }
                                if (xulG) {
                                    xulG.volume_item_creator( { 'existing_copies' : copyList } );
                                }
                            } catch(E) {
                                alert('error in oncomplete: ' + E);
                            }
                        }
                    }
                );
            }
        );
    },

    this.drawBibFinder = function(li) {

        var query = '';
        var liWrapper = new openils.acq.Lineitem({lineitem:li});

        dojo.forEach(
            ['isbn', 'upc', 'issn', 'title', 'author'],
            function(field) {
                var val = liWrapper.findAttr(field, 'lineitem_marc_attr_definition');
                if(val) {
                    if(field == 'title' || field == 'author') {
                        query += field +':' + val + ' ';
                    } else {
                        query += 'identifier|' + field + ':' + val + ' ';
                    }
                }
            }
        );

        if(openils.XUL.isXUL() && !window.IAMBROWSER) {
            win = window.open(
                oilsBasePath + '/acq/lineitem/findbib?query=' + encodeURIComponent(query),
                '', 'resizable,scrollbars=1,chrome');
        } else {
            win = window.open( oilsBasePath + '/acq/lineitem/findbib?query=' + encodeURIComponent(query));
        }


        win.window.recordFound = function(bibId) { 
            win.close();

            var attrs = li.attributes();
            li.attributes(null);
            li.eg_bib_id(bibId);

            fieldmapper.standardRequest(
                ["open-ils.acq", "open-ils.acq.lineitem.update"], 
                {
                    "params": [openils.User.authtoken, li],
                    "async": true,
                    "oncomplete": function(r) {
                        if(openils.Util.readResponse(r)) {
                            location.href = location.href;
                        }
                    }
                }
            );
        }
    }
}

