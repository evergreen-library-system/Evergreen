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

/*  Example markup:

<div id='facetSidebarContainer' class='hide_me'>

    <div class="side_bar_item" style="margin-top: 10px; font-weight: bold;">
        <span>&navigate.facetRefine;</span>
    </div>

    <div
        dojoType='openils.widget.FacetSidebar'
        searchBox='facet_box'
        searchSubmit='search_submit'
        facetLimit='5'
        maxValuesPerFacet='10'
        classOrder='[{"name":"author","facetOrder":["personal","corporate"]},{"name":"subject","facetOrder":["topic"]},"series",{"name":"subject","facetOrder":["name","geographic"]}]'
    >
        <script type='dojo/method' event='populate'><![CDATA[
            var f_sidebar = this;
            attachEvt("result", "allRecordsReceived", function () {
                if(!resultFacetKey) return;
                if (f_sidebar.facetCacheKey) return; // already rendered it

                dojo.removeClass('facetSidebarContainer','hide_me');

                f_sidebar.facetCacheKey = resultFacetKey;
                f_sidebar.render();
            });
        ]]></script>
    </div>
</div>

 */


if(!dojo._hasResource["openils.widget.FacetSidebar"]) {

    dojo._hasResource["openils.widget.FacetSidebar"] = true;
    dojo.provide("openils.widget.FacetSidebar");
    dojo.require("openils.widget.Searcher");

    dojo.declare(
        'openils.widget.FacetSidebar',
        [dijit._Widget, dijit._Templated],
        {   

            templateString : '<div dojoAttachPoint="myTop"><div dojoAttachPoint="containerNode"></div><div class="facetClassContainer" dojoAttachPoint="facetClasses"></div></div>',
            widgetsInTemplate: false,

            facetData : {},
            facetCacheKey : '',
            searchBox : '',
            classOrder : null, // Array of cmc.name values, OR array of objects with name and facetOrder properties
            displayItemLimit : 999, // Number of distinctly described entries (classes or facets), that have values, to display from classOrder
            searchSubmit : '',
            facetLimit : 10,
            maxValuesPerFacet : 100,

            startup : function () {
                this.populate();
                this.inherited(arguments)
            },

            populate : function () {},

            render : function () {
                if (!this.facetCacheKey) return;

                if (openils.widget.Searcher._cache.facetData) {
                    this.facetData = openils.widget.Searcher._cache.facetData;
                    this._render_callback();
                } else {
                    var limit = dojo.isIE ? this.facetLimit : this.maxValuesPerFacet;
                    var self = this;
                    fieldmapper.standardRequest( 
                        [ 'open-ils.search', 'open-ils.search.facet_cache.retrieve'], 
                        { async : true,
                          params : [this.facetCacheKey, limit],
                          oncomplete : function(r) {
                              var facetData = r.recv().content();
                              if (!facetData) return;
                              self.facetData = openils.widget.Searcher._cache.facetData = facetData;
                              self._render_callback();
                          }
                        }
                    );
                }

            },

            _render_callback : function(facetData) {
                var facetData = this.facetData;
                var classes = openils.widget.Searcher._cache.arr.cmc;
                if (this.classOrder && this.classOrder.length > 0) {
                    classes = [];
                    dojo.forEach(
                        this.classOrder,
                        function(x) {
                            if (dojo.isObject(x)) classes.push(x);
                            else classes.push({name:x});
                        }
                    );
                }

                var displayedItems = 0;
                var me = this;
                dojo.forEach(
                    classes,
                    function (x) {
                        var possible_facets = [];
                        if (x.facetOrder) {
                            dojo.forEach(x.facetOrder, function(fname) {
                                var maybe_facet = dojo.filter(
                                    openils.widget.Searcher._cache.arr.cmf,
                                    function (y) {
                                        if (y.field_class == x.name && y.name == fname && facetData[y.id]) {
                                            if (displayedItems < me.displayItemLimit) {
                                                displayedItems++;
                                                return 1;
                                            }
                                        }
                                        return 0;
                                    }
                                )[0];
                                if (maybe_facet) possible_facets.push(maybe_facet);
                            });
                        } else {
                            possible_facets = dojo.filter(
                                openils.widget.Searcher._cache.arr.cmf,
                                function (y) {
                                    if (y.field_class == x.name && facetData[y.id]) {
                                        if (displayedItems < me.displayItemLimit) {
                                            displayedItems++;
                                            return 1;
                                        }
                                    }
                                    return 0;
                                }
                            );
                        }
                        if (possible_facets.length > 0) me.addClass( x.name, possible_facets );
                    }
                );
            },

            addClass : function (thisclass, facets) {
                return new openils.widget.FacetSidebar.facetClass(
                    { facetLimit: this.facetLimit, searchBox : this.searchBox, searchSubmit : this.searchSubmit, facetClass : thisclass, facetData : this.facetData, facetList : facets }
                ).placeAt(this.facetClasses, 'last');
            }
        }
    );

    dojo._hasResource["openils.widget.FacetSidebar.facetClass"] = true;
    dojo.provide("openils.widget.FacetSidebar.facetClass");

    dojo.declare(
        'openils.widget.FacetSidebar.facetClass',
        [dijit._Widget, dijit._Templated],
        {   

            templateString :
'<div class="facetClassLabelContainer">' +
'  <div class="facetClassLabel" dojoAttachPoint="facetClassLabel"></div>' +
'  <div class="facetFieldContainer" dojoAttachPoint="facetFields"></div>' +
'</div>',
            widgetsInTemplate: false,

            facetLimit : 10,
            facetClass : '',
            facetData : null,
            facetList : null,
            searchBox : '',
            searchSubmit : '',

            postCreate : function () {
                if (!this.facetClass) return;
                if (!this.facetData) return;

                var myclass = this.facetClass;

                var fclass = dojo.filter(openils.widget.Searcher._cache.arr.cmc, function (x) { if (x.name == myclass) return 1; return 0; })[0];
                this.facetClassLabel.innerHTML = fclass.label;

                var me = this;
                dojo.forEach(
                    this.facetList,
                    function (f) { me.addFacets(f); }
                );
            },

            addFacets : function (f) {
                return new openils.widget.FacetSidebar.facetField(
                    { facetLimit: this.facetLimit, searchBox : this.searchBox, searchSubmit : this.searchSubmit, facet : f, facetData : this.facetData[f.id] }
                ).placeAt( this.facetFields, 'last' );
            }
        }
    );

    dojo._hasResource["openils.widget.FacetSidebar.facetField"] = true;
    dojo.provide("openils.widget.FacetSidebar.facetField");

    dojo.declare(
        'openils.widget.FacetSidebar.facetField',
        [dijit._Widget, dijit._Templated],
        {   

            templateString : 
'<div class="facetField" dojoAttachPoint="myTop">' +
'  <div class="extraFacetFieldsWrapper" dojoAttachPoint="toggleExtraFacetFieldsWrapper"><button class="toggleExtraFacetFieldsButton" dojoType="dijit.form.Button" dojoAttachPoint="toggleExtraFacetFields" dojoAttachEvent="onClick:toggleExtraFacets"></button></div>' +
'  <div class="facetFieldLabel" dojoAttachPoint="facetLabel"></div>' +
'  <div class="facetFields" dojoAttachPoint="facetFields"></div>' +
'  <div class="facetFields hide_me" dojoAttachPoint="extraFacetFields"></div>' +
'</div>',

            widgetsInTemplate: true,
            facet : null,
            facetData : null,
            facetLimit : 10,
            searchBox : '',
            searchSubmit : '',
            extraHidden : true,

            postCreate : function () {
                this.nls = dojo.i18n.getLocalization("openils.widget", "Searcher");
                var me = this;
                var keylist = []; for (var i in this.facetData) { keylist.push(i); }

                keylist = keylist.sort(function(a,b){
                    if (me.facetData[a] < me.facetData[b]) return 1;
                    if (me.facetData[a] > me.facetData[b]) return -1;
                    if (a < b) return -1;
                    if (a > b) return 1;
                    return 0;
                });

                this.facetLabel.innerHTML = this.facet.label;
                this.toggleExtraFacetFields.setLabel(this.nls.more);

                var pos = 0;
                dojo.forEach(
                    keylist,
                    function(value){

                        var have_it = dojo.byId(me.searchBox).value.indexOf(me.facet.field_class + '|' + me.facet.name + '[' + value + ']') > -1;

                        var container = dojo.create('div',{'class':'facetFieldLine'});
                        dojo.create('span',{'class':'facetFieldLineCount', innerHTML: me.facetData[value]},container);

                        if (have_it) {
                            dojo.create('a',{href : '#', 'class':'facetFieldLineValue', onclick : function(){ me.undoSearch(value); return false;}, innerHTML: '<b>(' + value + ')</b>'},container);
                        } else {
                            dojo.create('a',{href : '#', 'class':'facetFieldLineValue', onclick : function(){ me.doSearch(value); return false;}, innerHTML: value},container);
                        }

                        if (pos >= me.facetLimit) dojo.place(container,me.extraFacetFields,'last');
                        else dojo.place(container,me.facetFields,'last');

                        pos++;
                    }
                );

                if (pos < me.facetLimit + 1) dojo.query(this.toggleExtraFacetFieldsWrapper).toggleClass('hide_me');

            },

            toggleExtraFacets : function () {
                dojo.query(this.extraFacetFields).toggleClass('hide_me');
                this.extraHidden = !this.extraHidden;
                this.extraHidden ? this.toggleExtraFacetFields.setLabel(this.nls.more) : this.toggleExtraFacetFields.setLabel(this.nls.less);
            },

            undoSearch : function (value) {
                var sb = dojo.byId(this.searchBox);
                sb.value = sb.value.replace(this.facet.field_class + '|' + this.facet.name + '[' + value + ']','');
                dojo.byId(this.searchSubmit).click();
            },

            doSearch : function (value) {
                dojo.byId(this.searchBox).value += ' ' + this.facet.field_class + '|' + this.facet.name + '[' + value + ']';
                dojo.byId(this.searchSubmit).click();
            }
        }
    );


}

