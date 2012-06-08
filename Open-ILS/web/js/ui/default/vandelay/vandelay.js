/* ---------------------------------------------------------------------------
# Copyright (C) 2008  Georgia Public Library Service
# Bill Erickson <erickson@esilibrary.com>
# 
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# --------------------------------------------------------------------------- */
dojo.require("dojo.parser");
dojo.require("dojo.io.iframe"); 
dojo.require("dijit.ProgressBar"); 
dojo.require("dijit.form.FilteringSelect"); 
dojo.require("dijit.layout.ContentPane");
dojo.require("dijit.layout.TabContainer");
dojo.require("dijit.layout.LayoutContainer");
dojo.require('dijit.form.Button');
dojo.require('dijit.form.CheckBox');
dojo.require('dijit.Toolbar');
dojo.require('dijit.Tooltip');
dojo.require('dijit.Menu');
dojo.require("dijit.Dialog");
dojo.require("dojo.cookie");
dojo.require('dojox.grid.DataGrid');
dojo.require("dojo.data.ItemFileReadStore");
dojo.require('dojo.date.locale');
dojo.require('dojo.date.stamp');
dojo.require("fieldmapper.Fieldmapper");
dojo.require("fieldmapper.dojoData");
dojo.require("fieldmapper.OrgUtils");
dojo.require('openils.CGI');
dojo.require('openils.User');
dojo.require('openils.Event');
dojo.require('openils.Util');
dojo.require('openils.MarcXPathParser');
dojo.require('openils.widget.GridColumnPicker');
dojo.require('openils.PermaCrud');
dojo.require('openils.widget.OrgUnitFilteringSelect');
dojo.require('openils.widget.AutoGrid');
dojo.require('openils.widget.AutoFieldWidget');
dojo.require('openils.widget.ProgressDialog');


var globalDivs = [
    'vl-generic-progress',
    'vl-generic-progress-with-total',
    'vl-marc-upload-div',
    'vl-queue-div',
    'vl-match-div',
    'vl-marc-html-div',
    'vl-queue-select-div',
    'vl-marc-upload-status-div',
    'vl-attr-editor-div',
    'vl-marc-export-div',
    'vl-profile-editor-div',
    'vl-item-attr-editor-div',
    'vl-import-error-div'
];

var authtoken;
var VANDELAY_URL = '/vandelay-upload';
var bibAttrDefs = [];
var authAttrDefs = [];
var queuedRecords = [];
var queuedRecordsMap = {};
var bibAttrsFetched = false;
var authAttrsFetched = false;
var attrDefMap = {}; // maps attr def code names to attr def ids
var currentType;
var currentQueueId = null;
var userCache = {};
var currentMatchedRecords; // set of loaded matched bib records
var currentOverlayRecordsMap; // map of import record to overlay record
var currentOverlayRecordsMapGid; // map of import record to overlay record grid id
var currentImportRecId; // when analyzing matches, this is the current import record
var userBibQueues = []; // only non-complete queues
var userAuthQueues = []; // only non-complete queues
var allUserBibQueues;
var allUserAuthQueues;
var selectableGridRecords;
var cgi = new openils.CGI();
var vlQueueGridColumePicker = {};
var vlBibSources = [];
var importItemDefs = [];
var matchSets = {};
var mergeProfiles = [];
var copyStatusCache = {};
var copyLocationCache = {};
var localeStrings;

/**
  * Grab initial data
  */
function vlInit() {

    dojo.requireLocalization("openils.vandelay", "vandelay");
    localeStrings = dojo.i18n.getLocalization("openils.vandelay", "vandelay");

    authtoken = openils.User.authtoken;
    var initNeeded = 8; // how many async responses do we need before we're init'd 
    var initCount = 0; // how many async reponses we've received

    openils.Util.registerEnterHandler(
        vlQueueDisplayPage.domNode, function(){retrieveQueuedRecords();});
    openils.Util.addCSSClass(dojo.byId('vl-menu-marc-upload'), 'toolbar_selected');

    function checkInitDone() {
        initCount++;
        if(initCount == initNeeded)
            runStartupCommands();
    }

    mergeProfiles = new openils.PermaCrud().retrieveAll('vmp');
    vlUploadMergeProfile.store = new dojo.data.ItemFileReadStore({data:fieldmapper.vmp.toStoreData(mergeProfiles)});
    vlUploadMergeProfile.labelAttr = 'name';
    vlUploadMergeProfile.searchAttr = 'name';
    vlUploadMergeProfile.startup();

    vlUploadMergeProfile2.store = new dojo.data.ItemFileReadStore({data:fieldmapper.vmp.toStoreData(mergeProfiles)});
    vlUploadMergeProfile2.labelAttr = 'name';
    vlUploadMergeProfile2.searchAttr = 'name';
    vlUploadMergeProfile2.startup();

    vlUploadFtMergeProfile.store = new dojo.data.ItemFileReadStore({data:fieldmapper.vmp.toStoreData(mergeProfiles)});
    vlUploadFtMergeProfile.labelAttr = 'name';
    vlUploadFtMergeProfile.searchAttr = 'name';
    vlUploadFtMergeProfile.startup();

    vlUploadFtMergeProfile2.store = new dojo.data.ItemFileReadStore({data:fieldmapper.vmp.toStoreData(mergeProfiles)});
    vlUploadFtMergeProfile2.labelAttr = 'name';
    vlUploadFtMergeProfile2.searchAttr = 'name';
    vlUploadFtMergeProfile2.startup();


    // Fetch the bib and authority attribute definitions 
    vlFetchBibAttrDefs(function () { checkInitDone(); });
    vlFetchAuthAttrDefs(function () { checkInitDone(); });

    vlRetrieveQueueList('bib', null, 
        function(list) {
            allUserBibQueues = list;
            for(var i = 0; i < allUserBibQueues.length; i++) {
                if(allUserBibQueues[i].complete() == 'f')
                    userBibQueues.push(allUserBibQueues[i]);
            }
            checkInitDone();
        }
    );

    vlRetrieveQueueList('auth', null, 
        function(list) {
            allUserAuthQueues = list;
            for(var i = 0; i < allUserAuthQueues.length; i++) {
                if(allUserAuthQueues[i].complete() == 'f')
                    userAuthQueues.push(allUserAuthQueues[i]);
            }
            checkInitDone();
        }
    );

    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.cbs.atomic'],
        {   async: true,
            params: [authtoken, {id:{"!=":null}}, {order_by:{cbs:'id'}}],
            oncomplete : function(r) {
                vlBibSources = openils.Util.readResponse(r, false, true);
                checkInitDone();
            }
        }
    );

    var owner = fieldmapper.aou.orgNodeTrail(fieldmapper.aou.findOrgUnit(new openils.User().user.ws_ou()));
    new openils.PermaCrud().search('viiad', 
        {owner: owner.map(function(org) { return org.id(); })},
        {   async: true,
            oncomplete: function(r) {
                importItemDefs = openils.Util.readResponse(r);
                checkInitDone();
            }
        }
    );

    new openils.PermaCrud().search('vms',
        {owner: owner.map(function(org) { return org.id(); })},
        {   async: true,
            oncomplete: function(r) {
                var sets = openils.Util.readResponse(r);
                dojo.forEach(sets, 
                    function(set) {
                        if(!matchSets[set.mtype()])
                            matchSets[set.mtype()] = [];
                        matchSets[set.mtype()].push(set);
                    }
                );
                checkInitDone();
            }
        }
    );

    new openils.PermaCrud().retrieveAll('ccs',
        {   async: true,
            oncomplete: function(r) {
                var stats = openils.Util.readResponse(r);
                dojo.forEach(stats, function(stat){copyStatusCache[stat.id()] = stat});
                checkInitDone();
            }
        }
    );

    vlAttrEditorInit();
    vlExportInit();
}


openils.Util.addOnLoad(vlInit);


// fetch the bib and authority attribute definitions

function vlFetchBibAttrDefs(postcomplete) {
    bibAttrDefs = [];
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqbrad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(e = openils.Event.parse(def[0])) 
                    return alert(e);
                bibAttrDefs.push(def);
            },
            oncomplete: function() {
                bibAttrDefs = bibAttrDefs.sort(
                    function(a, b) {
                        if(a.id() > b.id()) return 1;
                        if(a.id() < b.id()) return -1;
                        return 0;
                    }
                );
                postcomplete();
            }
        }
    );
}

function vlFetchAuthAttrDefs(postcomplete) {
    authAttrDefs = [];
    fieldmapper.standardRequest(
        ['open-ils.permacrud', 'open-ils.permacrud.search.vqarad'],
        {   async: true,
            params: [authtoken, {id:{'!=':null}}],
            onresponse: function(r) {
                var def = r.recv().content(); 
                if(e = openils.Event.parse(def[0])) 
                    return alert(e);
                authAttrDefs.push(def);
            },
            oncomplete: function() {
                authAttrDefs = authAttrDefs.sort(
                    function(a, b) {
                        if(a.id() > b.id()) return 1;
                        if(a.id() < b.id()) return -1;
                        return 0;
                    }
                );
                postcomplete();
            }
        }
    );
}

function vlRetrieveQueueList(type, filter, onload) {
    type = (type == 'bib') ? type : 'authority';
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.owner.retrieve.atomic'],
        {   async: true,
            params: [authtoken, null, filter],
            oncomplete: function(r) {
                var list = r.recv().content();
                if(e = openils.Event.parse(list[0]))
                    return alert(e);
                onload(list);
            }
        }
    );

}

function displayGlobalDiv(id) {
    for(var i = 0; i < globalDivs.length; i++) {
        try {
            dojo.style(dojo.byId(globalDivs[i]), 'display', 'none');
        } catch(e) {
            alert('please define div ' + globalDivs[i]);
        }
    }
    dojo.style(dojo.byId(id),'display','block');

    openils.Util.removeCSSClass(dojo.byId('vl-menu-marc-export'), 'toolbar_selected');
    openils.Util.removeCSSClass(dojo.byId('vl-menu-marc-upload'), 'toolbar_selected');
    openils.Util.removeCSSClass(dojo.byId('vl-menu-queue-select'), 'toolbar_selected');
    openils.Util.removeCSSClass(dojo.byId('vl-menu-attr-editor'), 'toolbar_selected');
    openils.Util.removeCSSClass(dojo.byId('vl-menu-profile-editor'), 'toolbar_selected');
    openils.Util.removeCSSClass(dojo.byId('vl-menu-match-set-editor'), 'toolbar_selected');

    if(dojo.byId('vl-match-set-iframe'))
        dojo.byId('vl-match-set-editor-div').removeChild(dojo.byId('vl-match-set-iframe'));

    switch(id) {
        case 'vl-marc-export-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-marc-export'), 'toolbar_selected');
            break;
        case 'vl-marc-upload-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-marc-upload'), 'toolbar_selected');
            break;
        case 'vl-queue-select-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-queue-select'), 'toolbar_selected');
            break;
        case 'vl-attr-editor-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-attr-editor'), 'toolbar_selected');
            break;
        case 'vl-profile-editor-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-profile-editor'), 'toolbar_selected');
            break;
        case 'vl-item-attr-editor-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-import-item-attr-editor'), 'toolbar_selected');
            break;
        case 'vl-match-set-editor-div':
            openils.Util.addCSSClass(dojo.byId('vl-menu-match-set-editor'), 'toolbar_selected');
            break;
    }
}

function runStartupCommands() {
    openils.Util.hide(dojo.byId('vl-page-loading'));
    openils.Util.show(dojo.byId('vl-body-wrapper'));
    currentQueueId = cgi.param('qid');
    currentType = cgi.param('qtype');
    dojo.style('vl-nav-bar', 'visibility', 'visible');
    if(currentQueueId)
        return retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
    if (cgi.param('page', 'inspectq')) {
        vlShowQueueSelect();
        return displayGlobalDiv('vl-queue-select-div');
    }
        
    vlShowUploadForm();
}

/**
  * asynchronously upload a file of MARC records
  */
function uploadMARC(onload){
    dojo.byId('vl-upload-status-count').innerHTML = '0';
    dojo.byId('vl-ses-input').value = authtoken;
    displayGlobalDiv('vl-marc-upload-status-div');
    dojo.io.iframe.send({
        url: VANDELAY_URL,
        method: "post",
        handleAs: "html",
        form: dojo.byId('vl-marc-upload-form'),
        handle: function(data,ioArgs){
            var content = data.documentElement.textContent;
            onload(content);
        }
    });
}	

/**
  * Creates a new vandelay queue
  */
function createQueue(queueName, type, onload, importDefId, matchSet) {
    var name = (type=='bib') ? 'bib' : 'authority';
    var method = 'open-ils.vandelay.'+ name +'_queue.create'
    fieldmapper.standardRequest(
        ['open-ils.vandelay', method],
        {   async: true,
            params: [authtoken, queueName, null, name, matchSet, importDefId],
            oncomplete : function(r) {
                var queue = r.recv().content();
                if(e = openils.Event.parse(queue)) 
                    return alert(e);
                onload(queue);
            }
        }
    );
}

/**
  * Tells vandelay to pull a batch of records from the cache and explode them
  * out into the vandelay tables
  */
function processSpool(key, queueId, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'.process_spool'],
        {   async: true,
            params: [authtoken, key, queueId],
            onresponse : function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp)) 
                    return alert(e);
                dojo.byId('vl-upload-status-count').innerHTML = resp;
            },
            oncomplete : function(r) {onload();}
        }
    );
}

function vlExportInit() {

    // queue export
    var qsel = dojo.byId('vl-queue-export-options');
    qsel.onchange = function(newVal) {
        var value = qsel.options[qsel.selectedIndex].value;
        qsel.selectedIndex = 0;
        if(!value) return;
        if(!confirm('Export as "' + value + '"?')) return; // TODO: i18n
        retrieveQueuedRecords(
            currentType, 
            currentQueueId, 
            function(r) { 
                exportHandler(value, r);
                displayGlobalDiv('vl-queue-div');
            },
            value
        );
    }

    // item export
    var isel = dojo.byId('vl-item-export-options');
    isel.onchange = function(newVal) {
        var value = isel.options[isel.selectedIndex].value;
        isel.selectedIndex = 0;
        if(!value) return;
        if(!confirm('Export as "' + value + '"?')) return; // TODO: i18n

        displayGlobalDiv('vl-generic-progress');
        var method = 'open-ils.vandelay.import_item.queue.export.' + value + '.atomic';

        fieldmapper.standardRequest(
            ['open-ils.vandelay', method],
            {
                params : [
                    authtoken, 
                    currentQueueId, 
                    {with_import_error: (vlImportItemsShowErrors.checked) ? 1 : null}
                ],
                async : true,
                oncomplete : function(r) {exportHandler(value, r)}
            }
        );
    }
}

function exportHandler(type, response) {
    displayGlobalDiv('vl-import-error-div');
    try {
        var content = openils.Util.readResponse(response);
        if (type=='email') {
            if (content==1) { alert('Email sent.'); return; }
            throw(content);
        }
        /* handle .atomic versus non-atomic method calls */
        content = content.constructor == Array
            ? content[0].template_output().data()
            : content.template_output().data();
        switch(type) {
            case 'print':
                openils.Util.printHtmlString(content);
            break;
            case 'csv':
                //content = content.replace(/\\t/g,'\t'); // if we really wanted to do .tsv instead
                openils.XUL.contentToFileSaveDialog(content, null, {
                    defaultString : 'VandelayExport.csv',
                    defaultExtension : '.csv',
                    filterName : 'CSV',
                    filterExtension : '*.csv',
                    filterAll : true
                } );
            break;
            default:
                alert('response = ' + response + '\tcontent:\n' + content);
        }
    } catch(E) {
        alert('Error exporting data: ' + E);
    }
}

function retrieveQueuedRecords(type, queueId, onload, doExport) {
    displayGlobalDiv('vl-generic-progress');
    queuedRecords = [];
    queuedRecordsMap = {};
    currentOverlayRecordsMap = {};
    currentOverlayRecordsMapGid = {};
    selectableGridRecords = {};

    if(!type) type = currentType;
    if(!queueId) queueId = currentQueueId;
    if(!onload) onload = handleRetrieveRecords;

    var method = 'open-ils.vandelay.'+type+'_queue.records.retrieve';

    if(doExport) method += '.export.' + doExport;
    if(vlQueueGridShowMatches.checked)
        method = method.replace('records', 'records.matches');

    method += '.atomic';

    var sel = dojo.byId('vl-queue-display-limit-selector');
    var limit = parseInt(sel.options[sel.selectedIndex].value);
    var offset = limit * parseInt(vlQueueDisplayPage.attr('value')-1);

    var params =  [authtoken, queueId, {clear_marc: 1, offset: offset, limit: limit, flesh_import_items:1}];
    if(vlQueueGridShowNonImport.checked)
        params[2].non_imported = 1;

    if(vlQueueGridShowImportErrors.checked)
        params[2].with_import_error = 1;

    fieldmapper.standardRequest(
        ['open-ils.vandelay', method],
        {   async: true,
            params: params,
            oncomplete: function(r){
                if(doExport) return onload(r);
                var recs = r.recv().content();
                if(e = openils.Event.parse(recs[0]))
                    return alert(e);
                for(var i = 0; i < recs.length; i++) {
                    var rec = recs[i];
                    queuedRecords.push(rec);
                    queuedRecordsMap[rec.id()] = rec;
                }
                onload();
            }
        }
    );
}

function vlLoadMatchUI(recId) {
    displayGlobalDiv('vl-generic-progress');
    var queuedRec = queuedRecordsMap[recId];
    var matches = queuedRec.matches();
    var records = [];
    currentImportRecId = recId;
    for(var i = 0; i < matches.length; i++)
        records.push(matches[i].eg_record());

    var retrieve = ['open-ils.search', 'open-ils.search.biblio.record_entry.slim.retrieve'];
    var params = [records];
    if(currentType == 'auth') {
        retrieve = ['open-ils.cat', 'open-ils.cat.authority.record.retrieve'];
        params = [authtoken, records, {clear_marc:1}];
    }

    fieldmapper.standardRequest(
        retrieve,
        {   async: true,
            params:params,
            oncomplete: function(r) {
                var recs = r.recv().content();
                if(e = openils.Event.parse(recs))
                    return alert(e);

                /* ui mangling */
                displayGlobalDiv('vl-match-div');
                resetVlMatchGridLayout();
                currentMatchedRecords = recs;
                vlMatchGrid.setStructure(vlMatchGridLayout);

                // build the data store of records with match information
                var dataStore = bre.toStoreData(recs, null, 
                    {virtualFields:['_id', 'match_score', 'match_quality', 'rec_quality']});
                dataStore.identifier = '_id';

                var matchSeenMap = {};

                for(var i = 0; i < dataStore.items.length; i++) {
                    var item = dataStore.items[i];
                    item._id = i; // just need something unique
                    for(var j = 0; j < matches.length; j++) {
                        var match = matches[j];
                        if(match.eg_record() == item.id && !matchSeenMap[match.id()]) {
                            if(match.match_score)
                                item.match_score = match.match_score();
                            item.match_quality = match.quality();
                            item.rec_quality = queuedRec.quality();
                            matchSeenMap[match.id()] = 1;
                            break;
                        }
                    }
                }

                // now populate the grid
                vlPopulateMatchGrid(vlMatchGrid, dataStore);
            }
        }
    );
}

function vlPopulateMatchGrid(grid, data) {
    var store = new dojo.data.ItemFileReadStore({data:data});
    grid.setStore(store);
    grid.update();
}

function showMe(id) {
    dojo.style(dojo.byId(id), 'display', 'block');
}
function hideMe(id) {
    dojo.style(dojo.byId(id), 'display', 'none');
}


function vlLoadMARCHtml(recId, inCat, oncomplete) {
    dijit.byId('vl-marc-html-done-button').onClick = oncomplete;
    displayGlobalDiv('vl-generic-progress');
    var api;
    var params = [recId, 1];

    if(inCat) {
        hideMe('vl-marc-html-edit-button'); // don't show marc editor button
        dijit.byId('vl-marc-html-edit-button').onClick = function(){}
        api = ['open-ils.search', 'open-ils.search.biblio.record.html'];
        if(currentType == 'auth')
            api = ['open-ils.search', 'open-ils.search.authority.to_html'];
    } else {
        showMe('vl-marc-html-edit-button'); // plug in the marc editor button
        dijit.byId('vl-marc-html-edit-button').onClick = 
            function() {vlLoadMarcEditor(currentType, recId, oncomplete);};
        params = [authtoken, recId];
        api = ['open-ils.vandelay', 'open-ils.vandelay.queued_bib_record.html'];
        if(currentType == 'auth')
            api = ['open-ils.vandelay', 'open-ils.vandelay.queued_authority_record.html'];
    }

    fieldmapper.standardRequest(
        api, 
        {   async: true,
            params: params,
            oncomplete: function(r) {
            displayGlobalDiv('vl-marc-html-div');
                var html = r.recv().content();
                dojo.byId('vl-marc-record-html').innerHTML = html;
            }
        }
    );
}


/*
function getRecMatchesFromAttrCode(rec, attrCode) {
    var matches = [];
    var attr = getRecAttrFromCode(rec, attrCode);
    for(var j = 0; j < rec.matches().length; j++) {
        var match = rec.matches()[j];
        if(match.matched_attr() == attr.id()) 
            matches.push(match);
    }
    return matches;
}
*/

/*
function getRecAttrFromMatch(rec, match) {
    for(var i = 0; i < rec.attributes().length; i++) {
        var attr = rec.attributes()[i];
        if(attr.id() == match.matched_attr())
            return attr;
    }
}
*/

function getRecAttrDefFromAttr(attr, type) {
    var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
    for(var i = 0; i < defs.length; i++) {
        var def = defs[i];
        if(def.id() == attr.field())
            return def;
    }
}

function getRecAttrFromCode(rec, attrCode) {
    var defId = attrDefMap[currentType][attrCode];
    var attrs = rec.attributes();
    for(var i = 0; i < attrs.length; i++) {
        var attr = attrs[i];
        if(attr.field() == defId) 
            return attr;
    }
    return null;
}

function vlGetViewMatches(rowIdx, item) {
    if(item) {
        var id = this.grid.store.getValue(item, 'id');
        var rec = queuedRecordsMap[id];
        if(rec.matches().length > 0)
            return id + ':' + rec.matches().length;
    }
    return -1
}

function vlFormatViewMatches(id) {
    if(id == -1) return '';
    var chunks = id.split(':');
    id = chunks[0];
    count = chunks[1];
    return '<a href="javascript:void(0);" onclick="vlLoadMatchUI(' + id + ');">' + this.name + ' (' + count + ')</a>';
}

function vlGetViewErrors(rowIdx, item) {
    if(item) {
        var id = this.grid.store.getValue(item, 'id');
        var rec = queuedRecordsMap[id];
        // id:rec_error:item_import_error_count
        return id + ':' + 
            (rec.import_error() ? 1 : '') + ':' + 
            (typeof rec.import_items == 'function'
                ? rec.import_items().filter(function(i) {return i.import_error()}).length
                :''
            );
    }
    return -1
}

function vlFormatViewErrors(chunk) {
    if(chunk == -1) return '';
    var id = chunk.split(':')[0];
    var rec = chunk.split(':')[1];
    var count = chunk.split(':')[2];
    var links = '';
    if(rec) 
        links += '<a href="javascript:void(0);" onclick="vlLoadErrorUI(' + id + ');">Record</a><br/>'; // TODO I18N
    if(Number(count))
        links += '<a href="javascript:void(0);" onclick="vlLoadErrorUI(' + id + ');">Items ('+count+')</a>'; // TODO I18N
    return links;
}

//var vlItemErrorColumnPicker;
function vlLoadErrorUI(id) {

    displayGlobalDiv('vl-import-error-div');
    openils.Util.hide('vl-import-error-grid-all');
    openils.Util.show('vl-import-error-record');

    var rec = queuedRecordsMap[id];

    dojo.byId('vl-error-id').innerHTML = rec.id();
    dojo.forEach( // TODO sane authority rec. fields
        ['title', 'author', 'isbn', 'issn', 'upc'],
        function(field) {
            var attr =  getRecAttrFromCode(rec, field);
            var eid = 'vl-error-' + field;
            if(attr) {
                openils.Util.show(dojo.byId(eid).parentNode, 'table-row');
                dojo.byId(eid).innerHTML = attr.attr_value();
            } else {
                openils.Util.hide(dojo.byId(eid).parentNode);
            }
        }
    );
    var iediv = dojo.byId('vl-error-import-error');
    var eddiv = dojo.byId('vl-error-error-detail');
    if(rec.import_error()) {
        openils.Util.show(iediv.parentNode, 'table-row');
        openils.Util.show(eddiv.parentNode, 'table-row');
        iediv.innerHTML = rec.import_error();
        eddiv.innerHTML = rec.error_detail();
    } else {
        openils.Util.hide(iediv.parentNode);
        openils.Util.hide(eddiv.parentNode);
    }

    var errorItems = rec.import_items().filter(function(i) {return i.import_error()});
    if(errorItems.length) {
        openils.Util.show('vl-import-error-grid-some');
        storeData = vqbr.toStoreData(errorItems);
        var store = new dojo.data.ItemFileReadStore({data:storeData});
        vlImportErrorGrid.setStore(store);
        vlImportErrorGrid.update();
    } else {
        openils.Util.hide('vl-import-error-grid-some');
    }
}

function vlLoadErrorUIAll() {

    displayGlobalDiv('vl-import-error-div');
    openils.Util.hide('vl-import-error-grid-some');
    openils.Util.hide('vl-import-error-record');
    openils.Util.show('vl-import-error-grid-all');
    vlAllImportErrorGrid.resetStore();

    vlImportErrorGrid.displayOffset = 0;

    vlAllImportErrorGrid.dataLoader = function() {

        vlAllImportErrorGrid.showLoadProgressIndicator();

        fieldmapper.standardRequest(
            ['open-ils.vandelay', 'open-ils.vandelay.import_item.queue.retrieve'],
            {
                async : true,
                params : [
                    authtoken, currentQueueId, {   
                        with_import_error: (vlImportItemsShowErrors.checked) ? 1 : null,
                        offset : vlAllImportErrorGrid.displayOffset,
                        limit : vlAllImportErrorGrid.displayLimit
                    }
                ],
                onresponse : function(r) {
                    var item = openils.Util.readResponse(r);
                    if(!item) return;
                    vlAllImportErrorGrid.store.newItem(vii.toStoreItem(item));
                },
                oncomplete : function() {
                    vlAllImportErrorGrid.hideLoadProgressIndicator();
                }
            }
        );
    };

    vlAllImportErrorGrid.dataLoader();
}

function vlGetOrg(rowIdx, item) {
    if(!item) return '';
    var value = this.grid.store.getValue(item, this.field);
    if(value) return fieldmapper.aou.findOrgUnit(value).shortname();
    return '';
}

function vlCopyStatus(rowIdx, item) {
    if(!item) return '';
    var value = this.grid.store.getValue(item, this.field);
    if(value) return copyStatusCache[value].name();
    return '';
}

// Note, we don't pre-fetch all copy locations because there could be 
// a lot of them.  Instead, fetch-and-cache on demand.
function vlCopyLocation(rowIdx, item) {
    if(item) {
        var value = this.grid.store.getValue(item, this.field);
        if(value) {
            if(!copyLocationCache[value]) {
                copyLocationCache[value] = 
                    new openils.PermaCrud().retrieve('acpl', value);
            }
            return copyLocationCache[value].name();
        }
    }
    return '';
}

function vlFormatViewMatchMARC(id) {
    return '<a href="javascript:void(0);" onclick="vlLoadMARCHtml(' + id + ', true, '+
        'function(){displayGlobalDiv(\'vl-match-div\');});">' + this.name + '</a>';
}

function getAttrValue(rowIdx, item) {
    if(!item) return '';
    var attrCode = this.field.split('.')[1];
    var rec = queuedRecordsMap[this.grid.store.getValue(item, 'id')];
    var attr = getRecAttrFromCode(rec, attrCode);
    return (attr) ? attr.attr_value() : '';
}

function vlGetDateTimeField(rowIdx, item) {
    if(!item) return '';
    var value = this.grid.store.getValue(item, this.field);
    if(!value) return '';
    var date = dojo.date.stamp.fromISOString(value);
    return dojo.date.locale.format(date, {selector:'date'});
}

function vlGetCreator(rowIdx, item) {
    if(!item) return '';
    var id = this.grid.store.getValue(item, 'creator');
    if(userCache[id])
        return userCache[id].usrname();
    var user = fieldmapper.standardRequest(
        ['open-ils.actor', 'open-ils.actor.user.retrieve'], [authtoken, id]);
    if(e = openils.Event.parse(user))
        return alert(e);
    userCache[id] = user;
    return user.usrname();
}

function vlGetViewMARC(rowIdx, item) {
    return item && this.grid.store.getValue(item, 'id');
}

function vlFormatViewMARC(id) {
    return '<a href="javascript:void(0);" onclick="vlLoadMARCHtml(' + id + ', false, '+
        'function(){displayGlobalDiv(\'vl-queue-div\');});">' + this.name + '</a>';
}

function vlGetOverlayTargetSelector(rowIdx, item) {
    if(!item) return;
    return this.grid.store.getValue(item, '_id') + ':' + this.grid.store.getValue(item, 'id');
}

function vlFormatOverlayTargetSelector(val) {
    if(!val) return '';
    var parts = val.split(':');
    var _id = parts[0];
    var id = parts[1];
    var value = '<input type="checkbox" name="vl-overlay-target-RECID" '+
        'onclick="vlHandleOverlayTargetSelected(ID, GRIDID);" gridid="GRIDID" match="ID"/>';
    value = value.replace(/GRIDID/g, _id);
    value = value.replace(/RECID/g, currentImportRecId);
    value = value.replace(/ID/g, id);
    if(_id == currentOverlayRecordsMapGid[currentImportRecId])
        return value.replace('/>', 'checked="checked"/>');
    return value;
}


/**
  * see if the user has enabled overlays for the current match set and, 
  * if so, map the current import record to the overlay target.
  */
function vlHandleOverlayTargetSelected(recId, gridId) {
    var noneSelected = true;
    var checkboxes = dojo.query('[name=vl-overlay-target-'+currentImportRecId+']');
    for(var i = 0; i < checkboxes.length; i++) {
        var checkbox = checkboxes[i];
        var matchRecId = checkbox.getAttribute('match');
        var gid = checkbox.getAttribute('gridid');
        if(checkbox.checked) {
            if(matchRecId == recId && gid == gridId) {
                noneSelected = false;
                currentOverlayRecordsMap[currentImportRecId] = matchRecId;
                currentOverlayRecordsMapGid[currentImportRecId] = gid;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = true;
                dojo.byId('vl-record-list-selected-' + currentImportRecId).parentNode.className = 'overlay_selected';
            } else {
                checkbox.checked = false;
            }
        }
    }

    if(noneSelected) {
        delete currentOverlayRecordsMap[currentImportRecId];
        delete currentOverlayRecordsMapGid[currentImportRecId];
        dojo.byId('vl-record-list-selected-' + currentImportRecId).checked = false;
        dojo.byId('vl-record-list-selected-' + currentImportRecId).parentNode.className = '';
    }
}

var valLastQueueType = null;
var vlQueueGridLayout = null;
function buildRecordGrid(type) {
    displayGlobalDiv('vl-queue-div');

    vlBibQueueGrid.canSort = function(col){ if(Math.abs(col) == 1) { return false; } else { return true; } }; 
    vlAuthQueueGrid.canSort = function(col){ if(Math.abs(col) == 1) { return false; } else { return true; } }; 

    if(type == 'bib') {
        openils.Util.show('vl-bib-queue-grid-wrapper');
        openils.Util.hide('vl-auth-queue-grid-wrapper');
        vlQueueGrid = vlBibQueueGrid;
        openils.Util.show('add-to-bucket-action', 'table-row');
    } else {
        openils.Util.show('vl-auth-queue-grid-wrapper');
        openils.Util.hide('vl-bib-queue-grid-wrapper');
        vlQueueGrid = vlAuthQueueGrid;
        openils.Util.hide('add-to-bucket-action');
    }


    if(valLastQueueType != type) {
        valLastQueueType = type;
        vlQueueGridLayout = vlQueueGrid.attr('structure');
        var defs = (type == 'bib') ? bibAttrDefs : authAttrDefs;
        attrDefMap[type] = {};
        for(var i = 0; i < defs.length; i++) {
            var def = defs[i]
            attrDefMap[type][def.code()] = def.id();
            var col = {
                name:def.description(), 
                field:'attr.' + def.code(),
                get: getAttrValue,
                selectableColumn:true
            };
            vlQueueGridLayout[0].cells[0].push(col);
        }
    }

    dojo.forEach(vlQueueGridLayout[0].cells[0], 
        function(cell) { 
            if(cell.field.match(/^\+/)) 
                cell.nonSelectable=true;
        }
    );

    var storeData;
    if(type == 'bib')
        storeData = vqbr.toStoreData(queuedRecords);
    else
        storeData = vqar.toStoreData(queuedRecords);

    var store = new dojo.data.ItemFileReadStore({data:storeData});
    vlQueueGrid.setStore(store);

    if(vlQueueGridColumePicker[type]) {
        vlQueueGrid.update();
    } else {

        vlQueueGridColumePicker[type] =
            new openils.widget.GridColumnPicker(
                authtoken, 'vandelay.queue.'+type, vlQueueGrid, vlQueueGridLayout);
        vlQueueGridColumePicker[type].load();
    }
}

function vlQueueGridPrevPage() {
    var page = parseInt(vlQueueDisplayPage.getValue());
    if(page < 2) return;
    vlQueueDisplayPage.setValue(page - 1);
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

function vlQueueGridNextPage() {
    vlQueueDisplayPage.setValue(parseInt(vlQueueDisplayPage.getValue())+1);
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

function vlDeleteQueue(type, queueId, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.delete'],
        {   async: true,
            params: [authtoken, queueId],
            oncomplete: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                onload();
            }
        }
    );
}


function vlQueueGridDrawSelectBox(rowIdx, item) {
    return item &&  this.grid.store.getValue(item, 'id');
}

function vlQueueGridFormatSelectBox(id) {
    var domId = 'vl-record-list-selected-' + id;
    if (id) { selectableGridRecords[domId] = id; }
    return "<div><input type='checkbox' id='"+domId+"'/></div>";
}

function vlSelectAllQueueGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = true;
}
function vlSelectNoQueueGridRecords() {
    for(var id in selectableGridRecords) 
        dojo.byId(id).checked = false;
}
function vlToggleQueueGridSelect() {
    if(dojo.byId('vl-queue-grid-row-selector').checked)
        vlSelectAllQueueGridRecords();
    else
        vlSelectNoQueueGridRecords();
}

var handleRetrieveRecords = function() {
    buildRecordGrid(currentType);
    vlFetchQueueSummary(currentQueueId, currentType, 
        function(summary) {
            dojo.byId('vl-queue-summary-name').innerHTML = summary.queue.name();
            dojo.byId('vl-queue-summary-total-count').innerHTML = summary.total +'';
            dojo.byId('vl-queue-summary-import-count').innerHTML = summary.imported + '';
            dojo.byId('vl-queue-summary-import-item-count').innerHTML = summary.total_items + '';
            dojo.byId('vl-queue-summary-import-item-imported-count').innerHTML = summary.total_items_imported + '';
            dojo.byId('vl-queue-summary-rec-error-count').innerHTML = summary.rec_import_errors + '';
            dojo.byId('vl-queue-summary-item-error-count').innerHTML = summary.item_import_errors + '';
           
            if (dojo.byId('create-bucket-dialog-name')) {
                dojo.byId('create-bucket-dialog-name').value = summary.queue.name();
            }
        }
    );
}

function vlFetchQueueSummary(qId, type, onload) {
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.'+type+'_queue.summary.retrieve'],
        {   async: true,
            params: [authtoken, qId],
            oncomplete : function(r) {
                var summary = r.recv().content();
                if(e = openils.Event.parse(summary))
                    return alert(e);
                return onload(summary);
            }
        }
    );
}

function handleCreateBucket(args) {
    var bname = dojo.byId('create-bucket-dialog-name').value;
    if (!bname) return;

    progressDialog.show(true);
    fieldmapper.standardRequest(
        ['open-ils.vandelay', 'open-ils.vandelay.bib_queue.to_bucket'],
        {   async : true,
            params : [authtoken, currentQueueId, bname],
            oncomplete : function(r) {
                progressDialog.hide();
                setTimeout(function() { 
                    var resp = openils.Util.readResponse(r);
                    if (resp.add_count == 0) {
                        alert(localeStrings.NO_BUCKET_ITEMS);
                    } else {
                        alert(
                            dojo.string.substitute(
                                localeStrings.BUCKET_CREATE_SUCCESS,
                                [resp.add_count, bname, resp.item_count]
                            )
                        );
                    }
                }, 200); // give the dialog a chance to hide
            }
        }
    );
}
    

var _importCancelHandler;
var _importGoHandler;
function vlHandleQueueItemsAction(action) {

    if(_importCancelHandler) dojo.disconnect(_importCancelHandler);

    _importCancelHandler = dojo.connect(
        queueItemsImportCancelButton, 
        'onClick', 
        function() {
            queueItemsImportDialog.hide();
        }
    );

    if(_importGoHandler)
        dojo.disconnect(_importGoHandler);

    _importGoHandler = dojo.connect(
        queueItemsImportGoButton,
        'onClick', 
        function() {
            queueItemsImportDialog.hide();

            // hack to set the widgets the import funcs will be looking at.  Reset them below.
            vlUploadQueueImportNoMatch.attr('value',  vlUploadQueueImportNoMatch2.attr('value'));
            vlUploadQueueAutoOverlayExact.attr('value',  vlUploadQueueAutoOverlayExact2.attr('value'));
            vlUploadQueueAutoOverlay1Match.attr('value',  vlUploadQueueAutoOverlay1Match2.attr('value'));
            vlUploadMergeProfile.attr('value',  vlUploadMergeProfile2.attr('value'));
            vlUploadFtMergeProfile.attr('value',  vlUploadFtMergeProfile2.attr('value'));
            vlUploadQueueAutoOverlayBestMatch.attr('value',  vlUploadQueueAutoOverlayBestMatch2.attr('value'));
            vlUploadQueueAutoOverlayBestMatchRatio.attr('value',  vlUploadQueueAutoOverlayBestMatchRatio2.attr('value'));

            if(action == 'import') {
                vlImportSelectedRecords();
            } else if(action == 'import_all') {
                vlImportAllRecords();
            }
            
            // reset the widgets to prevent accidental future actions
            vlUploadQueueImportNoMatch.attr('value',  false);
            vlUploadQueueImportNoMatch2.attr('value', false);
            vlUploadQueueAutoOverlayExact.attr('value', false);
            vlUploadQueueAutoOverlayExact2.attr('value', false);
            vlUploadQueueAutoOverlay1Match.attr('value', false);
            vlUploadQueueAutoOverlay1Match2.attr('value', false);
            vlUploadMergeProfile.attr('value', '');
            vlUploadMergeProfile2.attr('value', '');
            vlUploadFtMergeProfile.attr('value', '');
            vlUploadFtMergeProfile2.attr('value', '');
            vlUploadQueueAutoOverlayBestMatch.attr('value', false);
            vlUploadQueueAutoOverlayBestMatch2.attr('value', false);
            vlUploadQueueAutoOverlayBestMatchRatio.attr('value', '0.0');
            vlUploadQueueAutoOverlayBestMatchRatio2.attr('value', '0.0');
        }
    );

    queueItemsImportDialog.show();
}

function vlHandleCreateBucket() {

    create-bucket-dialog-name
}
    

/* import user-selected records */
function vlImportSelectedRecords() {
    var records = [];

    for(var id in selectableGridRecords) {
        if(dojo.byId(id).checked) {
            var recId = selectableGridRecords[id];
            var rec = queuedRecordsMap[recId];
            if(!rec.import_time()) 
                records.push(recId);
        }
    }

    vlImportRecordQueue(
        currentType, 
        currentQueueId, 
        records,
        function(){
            retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
        }
    );
}

/* import all (non-imported) queue records */
function vlImportAllRecords() {
    vlImportRecordQueue(
        currentType, 
        currentQueueId, 
        null,
        function(){
            retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
        }
    );
}

/* if recList has values, import only those records */
function vlImportRecordQueue(type, queueId, recList, onload) {
    displayGlobalDiv('vl-generic-progress-with-total');

    /* set up options */
    var options = {overlay_map : currentOverlayRecordsMap};

    if(vlUploadQueueImportNoMatch.checked) {
        options.import_no_match = true;
        vlUploadQueueImportNoMatch.checked = false;
    }

    if(vlUploadQueueAutoOverlayExact.checked) {
        options.auto_overlay_exact = true;
        vlUploadQueueAutoOverlayExact.checked = false;
    }

    if(vlUploadQueueAutoOverlayBestMatch.checked) {
        options.auto_overlay_best_match = true;
        vlUploadQueueAutoOverlayBestMatch.checked = false;
        options.match_quality_ratio = vlUploadQueueAutoOverlayBestMatchRatio.attr('value');
    }

    if(vlUploadQueueAutoOverlay1Match.checked) {
        options.auto_overlay_1match = true;
        vlUploadQueueAutoOverlay1Match.checked = false;
        options.match_quality_ratio = vlUploadQueueAutoOverlayBestMatchRatio.attr('value');
    }

    var profile = vlUploadMergeProfile.attr('value');
    if(profile != null && profile != '') {
        options.merge_profile = profile;
    }

    var ftprofile = vlUploadFtMergeProfile.attr('value');
    if(ftprofile != null && ftprofile != '') {
        options.fall_through_merge_profile = ftprofile;
    }


    /* determine which method we're calling */

    var method = 'open-ils.vandelay.bib_queue.import';
    if(type == 'auth')
        method = method.replace('bib', 'auth');

    var params = [authtoken, queueId, options];
    if(recList) {
        method = 'open-ils.vandelay.'+currentType+'_record.list.import';
        params[1] = recList;
    }

    fieldmapper.standardRequest(
        ['open-ils.vandelay', method],
        {   async: true,
            params: params,
            onresponse: function(r) {
                var resp = r.recv().content();
                if(e = openils.Event.parse(resp))
                    return alert(e);
                vlControlledProgressBar.update({maximum:resp.total, progress:resp.progress});
            },
            oncomplete: function() {onload();}
        }
    );
}


/**
  * Create queue, upload MARC, process spool, load the newly created queue 
  */
function batchUpload() {
    var queueName = dijit.byId('vl-queue-name').getValue();
    currentType = dijit.byId('vl-record-type').getValue();

    var handleProcessSpool = function() {
        if( 
            vlUploadQueueImportNoMatch.checked || 
            vlUploadQueueAutoOverlayExact.checked || 
            vlUploadQueueAutoOverlay1Match.checked ||
            vlUploadQueueAutoOverlayBestMatch.checked ) {

                vlImportRecordQueue(
                    currentType, 
                    currentQueueId, 
                    null,
                    function() {
                        retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
                    }
                );
        } else {
            retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
        }
    }

    var handleUploadMARC = function(key) {
        dojo.style(dojo.byId('vl-upload-status-processing'), 'display', 'block');
        processSpool(key, currentQueueId, currentType, handleProcessSpool);
    };

    var handleCreateQueue = function(queue) {
        currentQueueId = queue.id();
        uploadMARC(handleUploadMARC);
    };
    
    if(vlUploadQueueSelector.getValue() && !queueName) {
        currentQueueId = vlUploadQueueSelector.getValue();
        uploadMARC(handleUploadMARC);
    } else {
        createQueue(queueName, currentType, handleCreateQueue, 
            vlUploadQueueHoldingsImportProfile.attr('value'),
            vlUploadQueueMatchSet.attr('value')
        );
    }
}


function vlFleshQueueSelect(selector, type) {
    var data;
    if (type == 'bib') {
        var bibList = allUserBibQueues.filter(
            function(q) {
                return (q.queue_type() == 'bib');
            }
        );
        data = vbq.toStoreData(bibList);
    } else if (type == 'bib-acq') {
        // ACQ queues are a special type of bib queue
        var acqList = allUserBibQueues.filter(
            function(q) {
                return (q.queue_type() == 'acq');
            }
        );
        data = vbq.toStoreData(acqList);
    } else {
        data = vaq.toStoreData(allUserAuthQueues);
    }

    selector.store = new dojo.data.ItemFileReadStore({data:data});
    selector.setValue(null);
    selector.setDisplayedValue('');
    if(data[0])
        selector.setValue(data[0].id());

    var qInput = dijit.byId('vl-queue-name');

    var selChange = function(val) {
        console.log('selector onchange');
        // user selected a queue from the selector;  clear the input and 
        // set the item import profile already defined for the queue
        var queue = allUserBibQueues.filter(function(q) { return (q.id() == val) })[0];
        if(val) {
            vlUploadQueueHoldingsImportProfile.attr('value', queue.item_attr_def() || '');
            vlUploadQueueHoldingsImportProfile.attr('disabled', true);
            vlUploadQueueMatchSet.attr('value', queue.match_set() || '');
            vlUploadQueueMatchSet.attr('disabled', true);
        } else {
            vlUploadQueueHoldingsImportProfile.attr('value', '');
            vlUploadQueueHoldingsImportProfile.attr('disabled', false);
            vlUploadQueueMatchSet.attr('value', '');
            vlUploadQueueMatchSet.attr('disabled', false);
        }
        dojo.disconnect(qInput._onchange);
        qInput.attr('value', '');
        qInput._onchange = dojo.connect(qInput, 'onChange', inputChange);
    }
    
    var inputChange = function(val) {
        console.log('qinput onchange');
        // user entered a new queue name. clear the selector 
        vlUploadQueueHoldingsImportProfile.attr('disabled', false);
        vlUploadQueueMatchSet.attr('disabled', false);
        dojo.disconnect(selector._onchange);
        selector.attr('value', '');
        selector._onchange = dojo.connect(selector, 'onChange', selChange);
    }

    selector._onchange = dojo.connect(selector, 'onChange', selChange);
    qInput._onchange = dojo.connect(qInput, 'onChange', inputChange);
}

function vlUpdateMatchSetSelector(type) {
    type = (type.match(/bib/)) ? 'biblio' : 'authority';
    vlUploadQueueMatchSet.store = 
        new dojo.data.ItemFileReadStore({data:vms.toStoreData(matchSets[type])});
}

function vlShowUploadForm() {
    displayGlobalDiv('vl-marc-upload-div');
    vlFleshQueueSelect(vlUploadQueueSelector, vlUploadRecordType.getValue());
    vlUploadSourceSelector.store = 
        new dojo.data.ItemFileReadStore({data:cbs.toStoreData(vlBibSources, 'source')});
    vlUploadSourceSelector.setValue(vlBibSources[0].id());
    vlUploadQueueHoldingsImportProfile.store = 
        new dojo.data.ItemFileReadStore({data:viiad.toStoreData(importItemDefs)});
    vlUpdateMatchSetSelector(vlUploadRecordType.getValue());

    // use ratio from the merge profile if it's set
    dojo.connect(
        vlUploadMergeProfile, 
        'onChange',
        function(val) {
            if(!val) return;
            var profile = mergeProfiles.filter(function(p) { return (p.id() == val); })[0];
            if(profile.lwm_ratio() != null)
               vlUploadQueueAutoOverlayBestMatchRatio.attr('value', profile.lwm_ratio()+''); 
        }
    );
    dojo.connect(
        vlUploadMergeProfile2, 
        'onChange',
        function(val) {
            if(!val) return;
            var profile = mergeProfiles.filter(function(p) { return (p.id() == val); })[0];
            if(profile.lwm_ratio() != null)
               vlUploadQueueAutoOverlayBestMatchRatio2.attr('value', profile.lwm_ratio()+''); 
        }
    );

}

function vlShowQueueSelect() {
    displayGlobalDiv('vl-queue-select-div');
    vlFleshQueueSelect(vlQueueSelectQueueList, vlQueueSelectType.getValue());
}

function vlShowMatchSetEditor() {
    displayGlobalDiv('vl-match-set-editor-div');
    dojo.byId('vl-match-set-editor-div').appendChild(
        dojo.create('iframe', {
            id : 'vl-match-set-iframe',
            src : oilsBasePath + '/conify/global/vandelay/match_set',
            style : 'width:100%; height:500px; border:none; margin:0px;'
        })
    );
}

function vlFetchQueueFromForm() {
    currentType = vlQueueSelectType.attr('value').replace(/-.*/, ''); // trim bib-acq
    currentQueueId = vlQueueSelectQueueList.getValue();
    retrieveQueuedRecords(currentType, currentQueueId, handleRetrieveRecords);
}

function vlOpenMarcEditWindow(rec, postReloadHTMLHandler) {
    /*
        To run in Firefox directly, must set signed.applets.codebase_principal_support
        to true in about:config
    */
    netscape.security.PrivilegeManager.enablePrivilege('UniversalXPConnect');
    win = window.open('/xul/server/cat/marcedit.xul'); // XXX version?

    var type;
    if (currentType == 'bib') {
        type = 'bre';
    } else {
        type = 'are';
    }

    function onsave(r) {
        // after the record is saved, reload the HTML display
        var stat = r.recv().content();
        if(e = openils.Event.parse(stat))
            return alert(e);
        alert(dojo.byId('vl-marc-edit-complete-label').innerHTML);
        win.close();
        vlLoadMARCHtml(rec.id(), false, postReloadHTMLHandler);
    }

    win.xulG = {
        record : {marc : rec.marc(), "rtype": type},
        save : {
            label: dojo.byId('vl-marc-edit-save-label').innerHTML,
            func: function(xmlString) {
                var method = 'open-ils.permacrud.update.' + rec.classname;
                rec.marc(xmlString);
                fieldmapper.standardRequest(
                    ['open-ils.permacrud', method],
                    {   async: true,
                        params: [authtoken, rec],
                        oncomplete: onsave
                    }
                );
            },
        },
        'lock_tab' : typeof xulG != 'undefined' ? (typeof xulG['lock_tab'] != 'undefined' ? xulG.lock_tab : undefined) : undefined,
        'unlock_tab' : typeof xulG != 'undefined' ? (typeof xulG['unlock_tab'] != 'undefined' ? xulG.unlock_tab : undefined) : undefined
    };
}

function vlLoadMarcEditor(type, recId, postReloadHTMLHandler) {
    var method = 'open-ils.permacrud.search.vqbr';
    if(currentType != 'bib')
        method = method.replace(/vqbr/,'vqar');

    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true, 
            params: [authtoken, {id : recId}],
            oncomplete: function(r) {
                var rec = r.recv().content();
                if(e = openils.Event.parse(rec))
                    return alert(e);
                vlOpenMarcEditWindow(rec, postReloadHTMLHandler);
            }
        }
    );
}



//------------------------------------------------------------
// attribute editors

// attribute-editor global variables

var ATTR_EDITOR_IN_UPDATE_MODE = false;	// true on 'edit', false on 'create'
var ATTR_EDIT_ID = null;		// id of current 'edit' attribute
var ATTR_EDIT_GROUP = 'bib';		// bib-attrs or auth-attrs

function vlAttrEditorInit() {
    // set up tooltips on the edit form
    connectTooltip('attr-editor-tags'); 
    connectTooltip('attr-editor-subfields'); 
}

function vlShowAttrEditor() {
    displayGlobalDiv('vl-attr-editor-div');
    loadAttrEditorGrid();
    idHide('vl-generic-progress');
}

function setAttrEditorGroup(groupName) {
    // put us into 'bib'-attr or 'auth'-attr mode.
    if (ATTR_EDIT_GROUP != groupName) {
	ATTR_EDIT_GROUP = groupName;
	loadAttrEditorGrid();
    }
}

function onAttrEditorOpen() {
    // the "bars" have the create/update/cancel/etc. buttons.
    var create_bar = document.getElementById('attr-editor-create-bar');
    var update_bar = document.getElementById('attr-editor-update-bar');
    if (ATTR_EDITOR_IN_UPDATE_MODE) {
	update_bar.style.display='table-row';
	create_bar.style.display='none';
	// hide the dropdown-button
	idStyle('vl-create-attr-editor-button', 'visibility', 'hidden');
    } else {
	dijit.byId('attr-editor-dialog').reset();
	create_bar.style.display='table-row';
	update_bar.style.display='none';
    }
}

function onAttrEditorClose() {
    // reset the form to a "create" form. (We may have borrowed it for editing.)
    ATTR_EDITOR_IN_UPDATE_MODE = false;
    // show the dropdown-button
    idStyle('vl-create-attr-editor-button', 'visibility', 'visible');
}

function loadAttrEditorGrid() {
    var _data = (ATTR_EDIT_GROUP == 'auth') ? 
	vqarad.toStoreData(authAttrDefs) : vqbrad.toStoreData(bibAttrDefs) ;

    var store = new dojo.data.ItemFileReadStore({data:_data});
    attrEditorGrid.setStore(store);
    attrEditorGrid.onRowDblClick = onAttrEditorClick;
    attrEditorGrid.update();
}

function attrGridGetTag(n, item) {
    // grid helper: return the tags from the row's xpath column.
    return item && xpathParser.parse(this.grid.store.getValue(item, 'xpath')).tags;
}

function attrGridGetSubfield(n, item) {
    // grid helper: return the subfields from the row's xpath column.
    return item && xpathParser.parse(this.grid.store.getValue(item, 'xpath')).subfields;
}

function onAttrEditorClick() {
    var row = this.getItem(this.focus.rowIndex);
    ATTR_EDIT_ID = this.store.getValue(row, 'id');
    ATTR_EDITOR_IN_UPDATE_MODE = true;

    // populate the popup editor.
    dijit.byId('attr-editor-code').attr('value', this.store.getValue(row, 'code'));
    dijit.byId('attr-editor-description').attr('value', this.store.getValue(row, 'description'));
    var parsed_xpath = xpathParser.parse(this.store.getValue(row, 'xpath'));
    dijit.byId('attr-editor-tags').attr('value', parsed_xpath.tags);
    dijit.byId('attr-editor-subfields').attr('value', parsed_xpath.subfields);
    dijit.byId('attr-editor-xpath').attr('value', this.store.getValue(row, 'xpath'));
    dijit.byId('attr-editor-remove').attr('value', this.store.getValue(row, 'remove'));

    // set up UI for editing
    dojo.byId('vl-create-attr-editor-button').click();
}

function vlSaveAttrDefinition(data) {
    idHide('vl-attr-editor-div');
    idShow('vl-generic-progress');

    data.id = ATTR_EDIT_ID;

    // this ought to honour custom xpaths, but overwrite xpaths
    // derived from tags/subfields.
    if (data.xpath == '' || looksLikeDerivedXpath(data.xpath)) {
	var _xpath = tagAndSubFieldsToXpath(data.tag, data.subfield);
	data.xpath = _xpath;
    }

    // build up our permacrud params. Key variables here are
    // "create or update" and "bib or auth".

    var isAuth   = (ATTR_EDIT_GROUP == 'auth');
    var isCreate = (ATTR_EDIT_ID == null);
    var rad      = isAuth ? new vqarad() : new vqbrad() ;
    var method   = 'open-ils.permacrud' + (isCreate ? '.create.' : '.update.') 
	+ (isAuth ? 'vqarad' : 'vqbrad');
    var _data    = rad.fromStoreItem(data);

    _data.ischanged(1);

    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true,
            params: [authtoken, _data ],
	    onresponse: function(r) { },
            oncomplete: function(r) {
		attrEditorFetchAttrDefs(vlShowAttrEditor);
		ATTR_EDIT_ID = null;
	    },
	    onerror: function(r) {
		alert('vlSaveAttrDefinition comms error: ' + r);
	    }
        }
    );
}

function attrEditorFetchAttrDefs(callback) {
    var fn = (ATTR_EDIT_GROUP == 'auth') ? vlFetchAuthAttrDefs : vlFetchBibAttrDefs;
    return fn(callback);
}

function vlAttrDelete() {
    idHide('vl-attr-editor-div');
    idShow('vl-generic-progress');

    var isAuth = (ATTR_EDIT_GROUP == 'auth');
    var method = 'open-ils.permacrud.delete.' + (isAuth ? 'vqarad' : 'vqbrad');
    var rad    = isAuth ? new vqarad() : new vqbrad() ;
    fieldmapper.standardRequest(
        ['open-ils.permacrud', method],
        {   async: true,
	    params: [authtoken, rad.fromHash({ id : ATTR_EDIT_ID }), ],
	    oncomplete: function() {
		dijit.byId('attr-editor-dialog').onCancel(); // close the dialog
		attrEditorFetchAttrDefs(vlShowAttrEditor);
		ATTR_EDIT_ID = null;
	    },
	    onerror: function(r) {
		alert('vlAttrDelete comms error: ' + r);
	    }
        }
    );
}

// ------------------------------------------------------------
// utilities for attribute editors

// dom utilities (maybe dojo does these, and these should be replaced)

function idStyle(obId, k, v)	{ document.getElementById(obId).style[k] = v;	}
function idShow(obId)		{ idStyle(obId, 'display', 'block');		}
function idHide(obId)		{ idStyle(obId, 'display' , 'none');		}

function connectTooltip(fieldId) {
    // Given an element id, look up a tooltip element in the doc (same
    // id with a '-tip' suffix) and associate the two. Maybe dojo has
    // a better way to do this?
    var fld = dojo.byId(fieldId);
    var tip = dojo.byId(fieldId + '-tip');
    dojo.connect(fld, 'onfocus', function(evt) {
		     dijit.showTooltip(tip.innerHTML, fld, ['below', 'after']); });
    dojo.connect(fld, 'onblur', function(evt) { dijit.hideTooltip(fld); });
}

// xpath utilities

var xpathParser = new openils.MarcXPathParser();

function tagAndSubFieldsToXpath(tags, subfields) {
    // given tags, and subfields, build up an XPath.
    try {
	var parts = {
	    'tags':tags.match(/[\d]+/g), 
	    'subfields':subfields.match(/[a-zA-z]/g) };
	return xpathParser.compile(parts);
    } catch (err) {
	return {'parts':null, 'tags':null, 'error':err};
    }
}

function looksLikeDerivedXpath(path) {
    // Does this path look like it was derived from tags and subfields?
    var parsed = xpathParser.parse(path);
    if (parsed.tags == null) 
	return false;
    var compiled = xpathParser.compile(parsed);
    return (path == compiled);
}

// amazing xpath-util unit-tests
if (!looksLikeDerivedXpath('//*[@tag="901"]/*[@code="c"]'))	alert('vandelay xpath-utility error');
if ( looksLikeDerivedXpath('ba-boo-ba-boo!'))			alert('vandelay xpath-utility error');



var profileContextOrg
function vlShowProfileEditor() {
    displayGlobalDiv('vl-profile-editor-div');
    buildProfileGrid();

    var connect = function() {
        dojo.connect(profileContextOrgSelector, 'onChange',
            function() {
                profileContextOrg = this.attr('value');
                pGrid.resetStore();
                buildProfileGrid();
            }
        );
    };

    new openils.User().buildPermOrgSelector(
        'ADMIN_MERGE_PROFILE', profileContextOrgSelector, null, connect);
}

function buildProfileGrid() {

    if(profileContextOrg == null)
        profileContextOrg = openils.User.user.ws_ou();

    pGrid.loadAll( 
        {order_by : {vmp : 'name'}}, 
        {owner : fieldmapper.aou.fullPath(profileContextOrg, true)}
    );
}

/* --- Import Item Attr Grid --------------- */

var itemAttrContextOrg;
var itemAttrGridFirstTime = true;
function vlShowImportItemAttrEditor() {
    displayGlobalDiv('vl-item-attr-editor-div');

    if (itemAttrGridFirstTime) {

        buildImportItemAttrGrid();

        var connect = function() {
            dojo.connect(itemAttrContextOrgSelector, 'onChange',
                function() {
                    itemAttrContextOrg = this.attr('value');
                    itemAttrGrid.resetStore();
                    buildImportItemAttrGrid();
                }
            );
        };

        new openils.User().buildPermOrgSelector(
            'ADMIN_IMPORT_ITEM_ATTR_DEF', 
                itemAttrContextOrgSelector, null, connect);

        itemAttrGridFirstTime = false;
    }
}

function buildImportItemAttrGrid() {

    if(itemAttrContextOrg == null)
        itemAttrContextOrg = openils.User.user.ws_ou();

    itemAttrGrid.loadAll( 
        {order_by : {viiad : 'name'}}, 
        {owner : fieldmapper.aou.fullPath(itemAttrContextOrg, true)}
    );
}

