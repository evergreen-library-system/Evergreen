/* ---------------------------------------------------------------------------
 * Copyright (C) 2010  Equinox Software, Inc
 * Mike Rylander <miker@esilibrary.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * ---------------------------------------------------------------------------
 */

if(!dojo._hasResource["openils.widget.Searcher"]) {

    dojo._hasResource["openils.widget.Searcher"] = true;
    dojo.provide("openils.widget.Searcher");

    dojo.require("fieldmapper.AutoIDL");
    dojo.require("openils.I18N");
    dojo.require("DojoSRF");
    dojo.require("dojo.data.ItemFileReadStore");
    dojo.require("dijit._Widget");
    dojo.require("dijit._Templated");
    dojo.require("dijit.form.Button");
    dojo.require("dijit.form.TextBox");
    dojo.require("dijit.form.FilteringSelect");
    dojo.require("dojo.cookie");
    dojo.requireLocalization("openils.widget", "Searcher");

    fieldmapper.IDL.load(['cmf','cmc','cmsa']);

//------ searching wrapper, uses dijits below -----------------------------------------------

    dojo.declare(
        'openils.widget.Searcher',
        [dijit._Widget, dijit._Templated],
        {

            templateString : 
"<div dojoAttachPoint='searcherTopNode'>" +

"  <div dojoAttachPoint='deck'>" +
"    <div dojoAttachPoint='basicSearch'>" +
"      <span dojoAttachPoint='containerNode' class='searcherSimpleSearchWrapper'></span>" +
"    </div>" +

"    <div dojoAttachPoint='advSearch' class='hide_me searcherAdvancedSearchWrapper'>" +
"      <div dojoAttachPoint='searcherClassedSearchesContainer' class='searcherClassedSearchesContainer hide_me'>" +
"        <div dojoAttachPoint='classedSearches' class='searcherClassedSearches'>" +
"          <span dojoAttachPoint='searcherClassedSearchesLabel' class='searcherClassedSearchesLabel'></span>" +
"        </div>" +
"        <div class='searcherClassedSearchesAddContainer'>" +
"          <button dojoType='dijit.form.Button' dojoAttachPoint='andClassedSearch' dojoAttachEvent='onClick:addClassAnd'></button>" +
"          <button dojoType='dijit.form.Button' dojoAttachPoint='orClassedSearch' dojoAttachEvent='onClick:addClassOr'></button>" +
"        </div>" +
"      </div>" +

"      <div dojoAttachPoint='searcherFacetedSearchesContainer' class='searcherFacetedSearchesContainer hide_me'>" +
"        <div class='searcherFacetedSearches' dojoAttachPoint='facetedSearches'>" +
"          <span dojoAttachPoint='searcherFacetedSearchesLabel' class='searcherFacetedSearchesLabel'></span>" +
"        </div>" +
"        <span>" +
"          <button dojoType='dijit.form.Button' dojoAttachPoint='addFacetedSearch' dojoAttachEvent='onClick:addFacet'></button>" +
"        </span>" +
"      </div>" +

"      <div dojoAttachPoint='searcherFilterModifierContainer' class='searcherFilterModifierContainer hide_me'>" +
"        <table width='100%'><tbody><tr>" +
"          <td dojoAttachPoint='searcherFilterContainer' class='searcherFilterContainer hide_me' valign='top' width='50%'>" +
"            <div dojoAttachPoint='filters'>" +
"              <span dojoAttachPoint='searcherFiltersLabel' class='searcherFiltersLabel'></span>" +
"            </div>" +
"            <button dojoType='dijit.form.Button' dojoAttachPoint='addFilterButton' dojoAttachEvent='onClick:addFilter'></button>" +
"          </td>" +
"          <td dojoAttachPoint='searcherModifierContainer' class='searcherModifierContainer hide_me' valign='top' width='50%'>" +
"            <div dojoAttachPoint='modifiers'>" +
"              <span dojoAttachPoint='searcherModifiersLabel' class='searcherModifiersLabel'></span>" +
"            </div>" +
"            <button dojoType='dijit.form.Button' dojoAttachPoint='addModifierButton' dojoAttachEvent='onClick:addModifier'></button>" +
"          </td>" +
"        </tr></tbody></table>" +
"      </div>" +

"      <div class='searcherGoContainer'>" +
"        <span dojoType='dijit.form.Button' dojoAttachPoint='goButton' dojoAttachEvent='onClick:performSearch'></span>" +
"      </div>" +
"    </div>" +
"  </div>" +

"  <div class='searcherDeckSwapContainer'>" +
"    <span dojoType='dijit.form.Button' dojoAttachPoint='advToggle' dojoAttachEvent='onClick:swapDeck'></span>" +
"  </div>" +
"</div>",
            widgetsInTemplate: true,
            advanced : false,
            basicTextBox : '',
            facetTextBox : '',
            withClassedSearches : true,
            withFacetedSearches : false,
            withFiltersModifiers : false,
            withFilters : false,
            withModifiers : false,
            basic_query : '',
            facet_query : '',

            compileFullSearch : function () {
                if (!this.advanced) return dojo.byId( this.basicTextBox ).attr('value');

                var query = '';

                var first_cs = true;

                // First, classed searches
                dojo.query( '.classedSearch', this.classedSearches ).forEach(
                    function (csearch) {
                        csearch = dijit.byNode(csearch);
                        var part = csearch.searchValue.attr('value');
                        if (!part || part.match(/^\s+$/)) return;

                        if (first_cs) first_cs = false;
                        else query += csearch.anded ? '' : ' ||';

                        query += ' ' + csearch.matchIndex.attr('value') + ':';
                        if (csearch.matchType.attr('value') == 'exact') {
                            query += '"';
                        } else if (csearch.matchType.attr('value') == 'notcontains') {
                            part = '-' + part.replace(/\s+/g, ' -');
                        }

                        query += part;

                        if (csearch.matchType.attr('value') == 'exact') query += '"';
                    }
                );

                var fquery = '';
                // Now facets
                dojo.query( '.facetedSearch', this.facetedSearches ).forEach(
                    function (facet) {
                        facet = dijit.byNode(facet);
                        var part = facet.searchValue.attr('value');
                        if (!part || part.match(/^\s+$/)) return;
                        fquery += ' ' + facet.matchIndex.attr('value') + '[' + part + ']';
                    }
                );

                // and filters...
                dojo.query( '.filter', this.filters ).forEach(
                    function (filt) {
                        filt = dijit.byNode(filt);
                        var part = filt.valueList.attr('value');
                        if (!part || part.match(/^\s+$/) || filt.filterSelect.attr('value') == '-') return;
                        query += ' ' + filt.filterSelect.attr('value') + '(' + part + ')';
                    }
                );

                // finally, modifiers
                dojo.query( '.modifier', this.modifiers ).forEach(
                    function (modifier) {
                        modifier = dijit.byNode(modifier);
                        var part = modifier.modifierSelect.attr('value')
                        if (!part || part == '-') return;
                        query += ' #' + part;
                    }
                );


                this.basic_query = query;
                this.facet_query = fquery;

                return query;
            },

            addFilter : function () {
                return new openils.widget.Searcher.filter({}, dojo.create('div',null,this.filters));
            },

            addModifier : function () {
                return new openils.widget.Searcher.modifier({}, dojo.create('div',null,this.modifiers));
            },

            addClassAnd : function () {
                return new openils.widget.Searcher.classedSearch({}, dojo.create('div',null,this.classedSearches));
            },

            addClassOr  : function () {
                return new openils.widget.Searcher.classedSearch({anded:false}, dojo.create('div',null,this.classedSearches));
            },

            addFacet : function () {
                return new openils.widget.Searcher.facetedSearch({}, dojo.create('div',null,this.facetedSearches));
            },

            performSearch  : function () {},
            populate  : function () {},

            startup : function () {
                if (this.advanced) {
                    dojo.query(this.basicSearch).toggleClass('hide_me');
                    dojo.query(this.advSearch).toggleClass('hide_me');
                }

                if (!this.facetTextBox) this.facetTextBox = this.basicTextBox;

                if (this.withFiltersModifiers) {
                    this.withFilters = true;
                    this.withModifiers = true;
                } else if (this.withFilters || this.withModifiers) {
                    this.withFiltersModifiers = true;
                }

                if (this.withFiltersModifiers) dojo.query(this.searcherFilterModifierContainer).toggleClass('hide_me');
                if (this.withFilters) dojo.query(this.searcherFilterContainer).toggleClass('hide_me');
                if (this.withModifiers) dojo.query(this.searcherModifierContainer).toggleClass('hide_me');
                if (this.withFacetedSearches) dojo.query(this.searcherFacetedSearchesContainer).toggleClass('hide_me');
                if (this.withClassedSearches) dojo.query(this.searcherClassedSearchesContainer).toggleClass('hide_me');

                this.populate();
                this.inherited(arguments)
            },
    
            swapDeck : function () {
                if (this.advanced) this.advanced = false;
                else this.advanced = true;

                dojo.query(this.basicSearch).toggleClass('hide_me');
                dojo.query(this.advSearch).toggleClass('hide_me');

                if (this.advanced) this.advToggle.setLabel(this.nls.basic);
                else this.advToggle.setLabel(this.nls.advanced);
            },

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");

                this.searcherClassedSearchesLabel.innerHTML = this.nls.classed_searches;
                this.searcherFacetedSearchesLabel.innerHTML = this.nls.faceted_searches;
                this.searcherFiltersLabel.innerHTML = this.nls.filters;
                this.searcherModifiersLabel.innerHTML = this.nls.modifiers;
                this.addFacetedSearch.setLabel(this.nls.new_facet);

                this.andClassedSearch.setLabel(this.nls.and);
                this.orClassedSearch.setLabel(this.nls.or);

                this.addFilterButton.setLabel(this.nls.new_filter);
                this.addModifierButton.setLabel(this.nls.new_modifier);

                this.goButton.setLabel(this.nls.perform_search);

                if (this.advanced) this.advToggle.setLabel(this.nls.basic);
                else this.advToggle.setLabel(this.nls.advanced);
                
                new openils.widget.Searcher.classedSearch(
                    { noRemove : true },
                    dojo.create('div',null,this.classedSearches)
                );
            }

        } 
    );

    openils.widget.Searcher._cache = {arr : {}, obj : {}, store : {}};

    dojo.forEach(
        [ {ident:'name',classname:'cmc',label:'label',fields:null,cookie:true}, {ident:'id',classname:'cmf',label:'label',fields:['id','field_class','name','search_field','facet_field','label']} ],
        // [ {ident:'name',classname:'cmc',label:'label',fields:null}, {ident:'id',classname:'cmf',label:'label',fields:null}, {ident:'alias',classname:'cmsa',label:'alias',fields:null} ],
        function (c) {

            var fielder_result = c.cookie ? dojo.cookie('SRCHR' + c.classname) : null;
            if (fielder_result) {
                fielder_result = dojo.fromJson(fielder_result);
            } else {
                var q = {};
                q[c.ident] = { '!=' :  null };

                fielder_result = fieldmapper.standardRequest(
                    [ 'open-ils.fielder', 'open-ils.fielder.'+c.classname+'.atomic'],
                    [ { cache : 1, query : q, fields: c.fields } ]
                );
                if (c.cookie) dojo.cookie(
                    'SRCHR' + c.classname,
                    dojo.toJson(fielder_result),
                    { path : location.href.replace(/^https?:\/\/[^\/]+(\/.*\w{2}-\w{2}\/).*/, "$1") }
                );
            }

            var sorted_fielder_result = fielder_result.sort( function(a,b) {
                if(a[c.label] > b[c.label]) return 1;
                if(a[c.label] < b[c.label]) return -1;
                return 0;
            });

            openils.widget.Searcher._cache.arr[c.classname] = sorted_fielder_result;

            var list = [];
            openils.widget.Searcher._cache.obj[c.classname] = {};

            dojo.forEach(
                openils.widget.Searcher._cache.arr[c.classname],
                function (x) {
                    openils.widget.Searcher._cache.obj[c.classname][x[c.ident]] = x;
                    list.push(x);
                }
            );

            openils.widget.Searcher._cache.store[c.classname] = new dojo.data.ItemFileReadStore( { data : {identifier : c.ident, label : c.label, items : list } } );
        }
    );

    var facet_list = [];
    var search_list = [];

    dojo.forEach(
        openils.widget.Searcher._cache.arr.cmc,
        function (cmc_obj) {
            search_list.push({
                name    : cmc_obj.name,
                label   : cmc_obj.label
            });
            dojo.forEach(
                dojo.filter(
                    openils.widget.Searcher._cache.arr.cmf,
                    function (x) {
                        if (x.field_class == cmc_obj.name) return 1;
                        return 0;
                    }
                ),
                function (cmf_obj) {
                    if (cmf_obj.search_field == 't') {
                        search_list.push({
                            name : cmc_obj.name + '|' + cmf_obj.name,
                            label : ' -- ' + cmf_obj.label
                        });
                    }
                    if (cmf_obj.facet_field == 't') {
                        facet_list.push({
                            name : cmc_obj.name + '|' + cmf_obj.name,
                            label : cmc_obj.label + ' : '  + cmf_obj.label
                        });
                    }
                }
            )
        }
    );

    openils.widget.Searcher.facetStore = new dojo.data.ItemFileReadStore( { data : {identifier : 'name', label : 'label', items : facet_list} } );
    openils.widget.Searcher.searchStore = new dojo.data.ItemFileReadStore( { data : {identifier : 'name', label : 'label', items : search_list} } );

//------ modifiers template -----------------------------------------------

    dojo._hasResource["openils.widget.Searcher.modifier"] = true;
    dojo.provide("openils.widget.Searcher.modifier");

    dojo.declare(
        'openils.widget.Searcher.modifier',
        [dijit._Widget, dijit._Templated],
        {

            templateString :
'<table dojoAttachPoint="myTop" class="modifier"><tbody><tr>' +
'   <td>' +
'     <select value="-" name="modifierSelect" dojoAttachPoint="modifierSelect" dojoType="dijit.form.FilteringSelect" >' +
'       <option dojoAttachPoint="modifierDefault" value="-">-- Select a Modifier --</option>' +
'       <option dojoAttachPoint="modifierAvailable" value="available"></option>' +
'       <option dojoAttachPoint="modifierDescending" value="descending"></option>' +
'       <option dojoAttachPoint="modifierAscending" value="ascending"></option>' +
'       <option dojoAttachPoint="modifierMetabib" value="metabib"></option>' +
'       <option dojoAttachPoint="modifierStaff" value="staff"></option>' +
'     </select>' +
'   </td> ' +
'   <td dojoAttachPoint="removeWrapper"><span dojoType="dijit.form.Button" dojoAttachPoint="removeButton" dojoAttachEvent="onClick:killMe"></span></td> ' +
'</tr></tbody></table>',
            widgetsInTemplate: true,

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");

                this.modifierDefault.innerHTML = this.nls.modifier_default;
                this.modifierAvailable.innerHTML = this.nls.available;
                this.modifierDescending.innerHTML = this.nls.descending;
                this.modifierAscending.innerHTML = this.nls.ascending;
                this.modifierMetabib.innerHTML = this.nls.metabib;
                this.modifierStaff.innerHTML = this.nls.staff;

                this.removeButton.setLabel(this.nls.remove);
            },
    
            killMe : function () {
                dijit.byNode(this.myTop).destroyRecursive();
                this.destroy();
            }
        }
    );

//------ filters template -----------------------------------------------

    dojo._hasResource["openils.widget.Searcher.filter"] = true;
    dojo.provide("openils.widget.Searcher.filter");

    dojo.declare(
        'openils.widget.Searcher.filter',
        [dijit._Widget, dijit._Templated],
        {

            templateString :
'<table dojoAttachPoint="myTop" class="filter"><tbody><tr>' +
'   <td>' +
'     <select value="-" name="filterSelect" dojoAttachPoint="filterSelect" dojoType="dijit.form.FilteringSelect">' +
'       <option dojoAttachPoint="filterDefault" value="-">-- Select a Filter --</option>' +
'       <option dojoAttachPoint="filterSite" value="site">Site</option>' +
'       <option dojoAttachPoint="filterDepth" value="depth">Search Depth</option>' +
'       <option dojoAttachPoint="filterSort" value="sort">Sort Axis</option>' +
'       <option dojoAttachPoint="filterStatuses" value="statuses">Statuses</option>' +
'       <option dojoAttachPoint="filterAudience" value="audience">Audience</option>' +
'       <option dojoAttachPoint="filterBefore" value="before">Published Before</option>' +
'       <option dojoAttachPoint="filterAfter" value="after">Published After</option>' +
'       <option dojoAttachPoint="filterBetween" value="between">Published Between</option>' +
'       <option dojoAttachPoint="filterDuring" value="during">In Publication</option>' +
'       <option dojoAttachPoint="filterForm" value="item_form">Form</option>' +
'       <option dojoAttachPoint="filterType" value="item_type">Type</option>' +
'       <option dojoAttachPoint="filterTypeForm" value="format">Type and Form</option>' +
'       <option dojoAttachPoint="filterVRFormat" value="vr_format">Videorecording Format</option>' +
'       <option dojoAttachPoint="filterLitForm" value="lit_form">Literary Form</option>' +
'       <option dojoAttachPoint="filterBibLevel" value="bib_level">Bibliographic Level</option>' +
'     </select>' +
'   </td> ' +
'   <td><div dojoAttachPoint="valueList" dojoType="dijit.form.TextBox"></div></td> ' +
'   <td dojoAttachPoint="removeWrapper"><span dojoType="dijit.form.Button" dojoAttachPoint="removeButton" dojoAttachEvent="onClick:killMe"></span></td> ' +
'</tr></tbody></table>',
            widgetsInTemplate: true,

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");

                this.filterDefault.innerHTML = this.nls.filter_default;
                this.filterSite.innerHTML = this.nls.site;
                this.filterDepth.innerHTML = this.nls.depth;
                this.filterSort.innerHTML = this.nls.sort;
                this.filterStatuses.innerHTML = this.nls.statuses;
                this.filterAudience.innerHTML = this.nls.audience;
                this.filterBefore.innerHTML = this.nls.before;
                this.filterAfter.innerHTML = this.nls.after;
                this.filterBetween.innerHTML = this.nls.between;
                this.filterDuring.innerHTML = this.nls.during;
                this.filterForm.innerHTML = this.nls.item_form;
                this.filterType.innerHTML = this.nls.item_type;
                this.filterTypeForm.innerHTML = this.nls.format;
                this.filterVRFormat.innerHTML = this.nls.vr_format;
                this.filterLitForm.innerHTML = this.nls.lit_form;
                this.filterBibLevel.innerHTML = this.nls.bib_level;

                this.removeButton.setLabel(this.nls.remove);
            },
    
            killMe : function () {
                dijit.byNode(this.myTop).destroyRecursive();
                this.destroy();
            }
        }
    );

//------ facet search template -----------------------------------------------

    dojo._hasResource["openils.widget.Searcher.facetedSearch"] = true;
    dojo.provide("openils.widget.Searcher.facetedSearch");

    dojo.declare(
        'openils.widget.Searcher.facetedSearch',
        [dijit._Widget, dijit._Templated],
        {

            templateString :
'<table dojoAttachPoint="myTop" class="facetedSearch"><tbody><tr>' +
'   <td><div dojoAttachPoint="matchIndex" searchAttr="label" dojoType="dijit.form.FilteringSelect" store="openils.widget.Searcher.facetStore"></div></td> ' +
'   <td><span style="margin-left:10px; margin-right:10px;" dojoAttachPoint="exactOption"></span></td> ' +
'   <td><div dojoAttachPoint="searchValue" dojoType="dijit.form.TextBox"></div></td> ' +
'   <td dojoAttachPoint="removeWrapper"><span dojoType="dijit.form.Button" dojoAttachPoint="removeButton" dojoAttachEvent="onClick:killMe"></span></td> ' +
'</tr></tbody></table>',
            widgetsInTemplate: true,

            noRemove : false,

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");

                this.exactOption.innerHTML = this.nls.exact;
                this.removeButton.setLabel(this.nls.remove);

                if (this.noRemove) dojo.destroy(this.removeWrapper);
            },
    
            killMe : function () {
                dijit.byNode(this.myTop).destroyRecursive();
                this.destroy();
            }
        }
    );

//------ classed search template -----------------------------------------------

    dojo._hasResource["openils.widget.Searcher.classedSearch"] = true;
    dojo.provide("openils.widget.Searcher.classedSearch");

    dojo.declare(
        'openils.widget.Searcher.classedSearch',
        [dijit._Widget, dijit._Templated],
        {

            templateString :
'<table dojoAttachPoint="myTop" class="classedSearch"><tbody><tr>' +
'   <td colspan="4" align="center"><span dojoAttachPoint="joinerSpan"></span></td></tr><tr> ' +
'   <td><div dojoAttachPoint="matchIndex" value="keyword" searchAttr="label" dojoType="dijit.form.FilteringSelect" store="openils.widget.Searcher.searchStore"></div></td> ' +
'   <td>' +
'     <select dojoAttachPoint="matchType" dojoType="dijit.form.FilteringSelect" name="matchType">' +
'       <option dojoAttachPoint="containsOption" value="contains">Contains</option>' +
'       <option dojoAttachPoint="notContainsOption" value="notcontains">Does Not Contain</option>' +
'       <option dojoAttachPoint="exactOption" value="exact"> Matches Exactly</option>' +
'     </select>' +
'   </td> ' +
'   <td><div dojoAttachPoint="searchValue" dojoType="dijit.form.TextBox"></div></td> ' +
'   <td dojoAttachPoint="removeWrapper"><span dojoType="dijit.form.Button" dojoAttachPoint="removeButton" dojoAttachEvent="onClick:killMe"></span></td> ' +
'</tr></tbody></table>',
            widgetsInTemplate: true,

            anded : true,
            noRemove : false,

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");

                this.containsOption.innerHTML = this.nls.contains;
                this.notContainsOption.innerHTML = this.nls.notcontains;
                this.exactOption.innerHTML = this.nls.exact;

                this.removeButton.setLabel(this.nls.remove);

                if (this.noRemove) dojo.destroy(this.removeWrapper);
                if (!this.noRemove && this.anded) this.joinerSpan.innerHTML = this.nls.and;
                if (!this.noRemove && !this.anded) this.joinerSpan.innerHTML = this.nls.or;
            },
    
            killMe : function () {
                dojo.destroy(this.myTop);
                this.destroy();
            }
        }
    );


}
