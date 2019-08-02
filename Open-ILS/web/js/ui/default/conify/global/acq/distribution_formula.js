dojo.require("dojo.dnd.Container");
dojo.require("dojo.dnd.Source");
dojo.require('openils.widget.AutoGrid');
dojo.require('dijit.form.FilteringSelect');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.AutoFieldWidget');
dojo.requireLocalization('openils.conify', 'conify');
var localeStrings = dojo.i18n.getLocalization('openils.conify', 'conify');


var formCache = {};
var formula, entryTbody, entryTemplate, dndSource;
var virtualId = -1;
var pcrud;
var _collection_code_textboxes = [];
var _collection_code_kludge_active = false;
var fundSearchFilter = {active : 't'};
var fundLabelFormat = ['${0} (${1})', 'code', 'year'];

function gridDataLoader() {
    fListGrid.resetStore();
    fListGrid.showLoadProgressIndicator();
    fieldmapper.standardRequest(
        ["open-ils.acq", "open-ils.acq.distribution_formula.ranged.retrieve"], {
            "async": true,
            "params": [
                openils.User.authtoken,
                fListGrid.displayOffset,
                fListGrid.displayLimit
            ],
            "onresponse": function(r) {
                var form = openils.Util.readResponse(r);
                formCache[form.id()] = form;
                fListGrid.store.newItem(form.toStoreItem());
            },
            "oncomplete": function() {
                fListGrid.hideLoadProgressIndicator();
            }
        }
    );
}

function setFundSearchFilter(callback) {
    new openils.User().getPermOrgList(
        ['ADMIN_ACQ_DISTRIB_FORMULA'],
        function(orgs) { 
            fundSearchFilter.org = orgs;
            if (callback) callback();
        },
        true, true // descendants, id_list
    );
}

function draw() {

    pcrud = new openils.PermaCrud();

    if(formulaId) {
        openils.Util.hide('formula-list-div');
        setFundSearchFilter(drawFormulaSummary);
    } else {

        openils.Util.hide('formula-entry-div');
        fListGrid.onPostCreate = function(fmObject) {
            location.href = location.href + '/' + fmObject.id();
        }

        fListGrid.dataLoader = gridDataLoader;
        gridDataLoader();
    }
}

function cloneSelectedFormula() {
    var item = fListGrid.getSelectedItems()[0];
    if(!item) return;
    var formula = new fieldmapper.acqf().fromStoreItem(item);
    fieldmapper.standardRequest(
        ['open-ils.acq', 'open-ils.acq.distribution_formula.clone'],
        {
            asnyc : true,
            params : [
                openils.User.authtoken, 
                formula.id(), 
                dojo.string.substitute(localeStrings.ACQ_DISTRIB_FORMULA_NAME_CLONE, [formula.name()])
            ],
            oncomplete : function(r) {
                if(r = openils.Util.readResponse(r)) {
                    location.href = oilsBasePath + '/conify/global/acq/distribution_formula/' + r;
                }
            }
        }
    );
}

openils.Util.addOnLoad(draw);

function getItemCount(rowIndex, item) {
    if(!item) return '';
    var form = formCache[this.grid.store.getValue(item, "id")];
    if(!form) return 0;
    var count = 0;
    dojo.forEach(form.entries(), function(e) { count = count + e.item_count(); });
    return count;
}

function byName(node, name) {
    return dojo.query('[name='+name+']', node)[0];
}

function drawFormulaSummary() {
    openils.Util.show('formula-entry-div');

    var entries = pcrud.search('acqdfe', {formula: formulaId}, {order_by:{acqdfe : 'position'}});
    formula = pcrud.retrieve('acqdf', formulaId);
    formula.entries(entries);

    dojo.byId('formula_head').innerHTML = formula.name();
    dojo.byId('formula_head').onclick = function() {
        var name = prompt(localeStrings.ACQ_DISTRIB_FORMULA_NAME_PROMPT, formula.name());
        if(name && name != formula.name()) {
            formula.name(name);
            pcrud = new openils.PermaCrud();
            pcrud.update(formula);
            dojo.byId('formula_head').innerHTML = name;
        }
    }

    dojo.forEach(entries, function(entry) { addEntry(entry); } );
}

function addEntry(entry) {

    if(!entryTbody) {
        entryTbody = dojo.byId('formula-entry-tbody');
        entryTemplate = entryTbody.removeChild(dojo.byId('formula-entry-tempate'));
        dndSource = new dojo.dnd.Source(entryTbody);
        dndSource.selectAll(); 
        dndSource.deleteSelectedNodes();
        dndSource.clearItems();
    }

    if(!entry) {
        entry = new fieldmapper.acqdfe();
        entry.formula(formulaId);
        entry.item_count(1);
        entry.owning_lib(openils.User.user.ws_ou());
        entry.id(virtualId--);
        entry.isnew(true);
        formula.entries().push(entry);
    }

    var row = entryTbody.appendChild(entryTemplate.cloneNode(true));
    row.setAttribute('entry', entry.id());
    dndSource.insertNodes(false, [row]);
    byName(row, 'delete').onclick = function() {
        entry.isdeleted(true);
        entryTbody.removeChild(row);
        dndSource.sync();
    };

    dojo.forEach(
        ['owning_lib', 'location', 'fund', 'circ_modifier', 'collection_code', 'item_count'],
        function(field) {
            new openils.widget.AutoFieldWidget({
                forceSync : true,
                fmField : field, 
                fmObject : entry,
                fmClass : 'acqdfe',
                labelFormat: (field == 'fund') ? fundLabelFormat : null,
                searchFormat: (field == 'fund') ? fundLabelFormat : null,
                searchFilter : (field == 'fund') ? fundSearchFilter : null,
                parentNode : byName(row, field),
                orgDefaultsToWs : true,
                orgLimitPerms : ['ADMIN_ACQ_DISTRIB_FORMULA'],
                widgetClass : (field == 'item_count') ? 'dijit.form.NumberSpinner' : null,
                dijitArgs : (field == 'item_count') ? {min:1, places:0} : null
            }).build(
                function(w, ww) {
                    if (field == "collection_code") {
                        /* kludge for glitchy textbox */
                        _collection_code_textboxes.push(w);
                    }
                    dojo.connect(w, 'onChange', 
                        function(newVal) {
                            entry[field]( newVal );
                            entry.ischanged(true);
                        }
                    )
                }
            );
        }
    );

    /* For some reason (bug) the dndSource intercepts onMouseDown events
     * that should hit dijit textboxes in our table thingy. Other dijits
     * (buttons, filteringselects, etc) seem not to be affected.  This
     * workaround deals with the only textboxes we have for now: the ones
     * for the collection_code field. */
    if (!_collection_code_kludge_active) {
        _collection_code_kludge_active = true;
        var original = dojo.hitch(dndSource, dndSource.onMouseDown);
        dndSource.onMouseDown = function(e) {
            var hits = _collection_code_textboxes.filter(
                function(w) {
                    var c = dojo.coords(w.domNode);
                    if (e.clientX >= c.x && e.clientX < c.x + c.w) {
                        if (e.clientY >= c.y && e.clientY < c.y + c.h) {
                            return true;
                        }
                    }
                    return false;
                }
            );

            if (hits.length) {
                hits[0].focus();
            } else {
                original(e);
            }
        };
    }
}

function saveFormula() {
    var pos = 1;
    var updatedEntries = [];
    var deletedEntries = [];

    // remove deleted entries from consideration for collision protection
    for(var i = 0; i < formula.entries().length; i++) {
        if(formula.entries()[i].isdeleted())
            deletedEntries.push(formula.entries().splice(i--, 1)[0])
    }

    // update entry positions and create temporary collision avoidance entries
    dojo.forEach(
        dndSource.getAllNodes(),
        function(node) {

            var entryId = node.getAttribute('entry');
            var entry = formula.entries().filter(function(e) {return (e.id() == entryId)})[0];

            if(entry.position() != pos) {

                // update the position
                var changedEntry = entry.clone();
                changedEntry.position(pos);
                changedEntry.ischanged(true);
                updatedEntries.push(changedEntry);

                // clear the virtual ID
                if(changedEntry.isnew())
                    changedEntry.id(null); 

                var oldEntry = formula.entries().filter(function(e) {return (e.position() == pos)})[0];

                if(oldEntry) {
                    // move the entry currently in that spot temporarily into negative territory
                    var moveMe = oldEntry.clone();
                    moveMe.ischanged(true);
                    moveMe.position(moveMe.position() * -1); 
                    updatedEntries.unshift(moveMe);
                }
            }
            pos++;
        }
    );

    // finally, for every entry that changed w/o changing position
    // throw it on the list for update
    dojo.forEach(
        formula.entries(),
        function(entry) {
            if(entry.ischanged() && !entry.isdeleted() && !entry.isnew()) {
                if(updatedEntries.filter(function(e) { return (e.id() == entry.id()) }).length == 0)
                    updatedEntries.push(entry);
            }
        }
    );

    updatedEntries = deletedEntries.concat(updatedEntries);
    if(updatedEntries.length) {
        pcrud = new openils.PermaCrud();
        try { 
            pcrud.apply(updatedEntries);
        } catch(E) {
            alert('error updating: ' + E);
            return;
        }
        location.href = location.href;
    }
}


