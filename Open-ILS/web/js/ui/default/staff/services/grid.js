angular.module('egGridMod', 
    ['egCoreMod', 'egUiMod', 'ui.bootstrap'])

.directive('egGrid', function() {
    return {
        restrict : 'AE',
        transclude : true,
        scope : {

            // IDL class hint (e.g. "aou")
            idlClass : '@',

            // default page size
            pageSize : '@',

            // if true, grid columns are derived from all non-virtual
            // fields on the base idlClass
            autoFields : '@',

            // grid preferences will be stored / retrieved with this key
            persistKey : '@',

            // field whose value is unique and may be used for item
            // reference / lookup.  This will usually be someting like
            // "id".  This is not needed when using autoFields, since we
            // can determine the primary key directly from the IDL.
            idField : '@',

            // Reference to externally provided egGridDataProvider
            itemsProvider : '=',

            // Reference to externally provided item-selection handler
            onSelect : '=',

            // Reference to externally provided after-item-selection handler
            afterSelect : '=',

            // comma-separated list of supported or disabled grid features
            // supported features:
            //  startSelected : init the grid with all rows selected by default
            //  allowAll : add an "All" option to row count (really 10000)
            //  -menu : don't show any menu buttons (or use space for them)
            //  -picker : don't show the column picker
            //  -pagination : don't show any pagination elements, and set
            //                the limit to 10000
            //  -actions : don't show the actions dropdown
            //  -index : don't show the row index column (can't use "index"
            //           as the idField in this case)
            //  -display : columns are hidden by default
            //  -sort    : columns are unsortable by default 
            //  -multisort : sort priorities config disabled by default
            //  -multiselect : only one row at a time can be selected;
            //                 choosing this also disables the checkbox
            //                 column
            features : '@',

            // optional: object containing function to conditionally apply
            //    class to each row.
            rowClass : '=',

            // optional: object that enables status icon field and contains
            //    function to handle what status icons should exist and why.
            statusColumn : '=',

            // optional primary grid label
            mainLabel : '@',

            // if true, use the IDL class label as the mainLabel
            autoLabel : '=', 

            // optional context menu label
            menuLabel : '@',

            dateformat : '@', // optional: passed down to egGridValueFilter
            datecontext: '@', // optional: passed down to egGridValueFilter to choose TZ
            datefilter: '@', // optional: passed down to egGridValueFilter to choose specialized date filters
            dateonlyinterval: '@', // optional: passed down to egGridValueFilter to choose a "better" format

            // Hash of control functions.
            //
            //  These functions are defined by the calling scope and 
            //  invoked as-is by the grid w/ the specified parameters.
            //
            //  collectStarted    : function() {}
            //  itemRetrieved     : function(item) {}
            //  allItemsRetrieved : function() {}
            //
            //  ---
            //  If defined, the grid will watch the return value from
            //  the function defined at watchQuery on each digest and 
            //  re-draw the grid when query changes occur.
            //
            //  watchQuery : function() { /* return grid query */ }
            //
            //  ---------------
            //  These functions are defined by the grid and thus
            //  replace any values defined for these attributes from the
            //  calling scope.
            //
            //  activateItem  : function(item) {}
            //  allItems      : function(allItems) {}
            //  selectedItems : function(selected) {}
            //  selectItems   : function(ids) {}
            //  setQuery      : function(queryStruct) {} // causes reload
            //  setSort       : function(sortSturct) {} // causes reload
            gridControls : '=',
        },

        // TODO: avoid hard-coded url
        templateUrl : '/eg/staff/share/t_autogrid', 

        link : function(scope, element, attrs) {     

            // Give the grid config loading steps time to fetch the 
            // workstation setting and apply columns before loading data.
            var loadPromise = scope.configLoadPromise || $q.when();
            loadPromise.then(function() {

                // load auto fields after eg-grid-field's so they are not clobbered
                scope.handleAutoFields();
                scope.collect();

                scope.grid_element = element;

                if(!attrs.id){
                    $(element).attr('id', attrs.persistKey);
                }

                $(element)
                    .find('.eg-grid-content-body')
                    .bind('contextmenu', scope.showActionContextMenu);
            });
        },

        controller : [
                    '$scope','$q','egCore','egGridFlatDataProvider','$location',
                    'egGridColumnsProvider','$filter','$window','$sce','$timeout',
                    'egProgressDialog','$uibModal','egConfirmDialog','egStrings',
            function($scope,  $q , egCore,  egGridFlatDataProvider , $location,
                     egGridColumnsProvider , $filter , $window , $sce , $timeout,
                     egProgressDialog,  $uibModal , egConfirmDialog , egStrings) {

            var grid = this;
            grid.init = function() {
                grid.offset = 0;
                $scope.items = [];
                $scope.showGridConf = false;
                grid.totalCount = -1;
                $scope.selected = {};
                $scope.actionGroups = [{actions:[]}]; // Grouped actions for selected items
                $scope.menuItems = []; // global actions

                // returns true if any rows are selected.
                $scope.hasSelected = function() {
                    return grid.getSelectedItems().length > 0 };

                var features = ($scope.features) ? 
                    $scope.features.split(',') : [];
                delete $scope.features;

                $scope.showIndex = (features.indexOf('-index') == -1);

                $scope.allowAll = (features.indexOf('allowAll') > -1);
                $scope.startSelected = $scope.selectAll = (features.indexOf('startSelected') > -1);
                $scope.showActions = (features.indexOf('-actions') == -1);
                $scope.showPagination = (features.indexOf('-pagination') == -1);
                $scope.showPicker = (features.indexOf('-picker') == -1);

                $scope.showMenu = (features.indexOf('-menu') == -1);

                // remove some unneeded values from the scope to reduce bloat

                grid.idlClass = $scope.idlClass;
                delete $scope.idlClass;

                grid.persistKey = $scope.persistKey;
                delete $scope.persistKey;

                var stored_limit = 0;
                if ($scope.showPagination) {
                    // localStorage of grid limits is deprecated. Limits 
                    // are now stored along with the columns configuration.  
                    // Values found in localStorage will be migrated upon 
                    // config save.
                    if (grid.persistKey) {
                        var stored_limit = Number(
                            egCore.hatch.getLocalItem('eg.grid.' + grid.persistKey + '.limit')
                        );
                    }
                } else {
                    stored_limit = 10000; // maybe support "Inf"?
                }

                grid.limit = Number(stored_limit) || Number($scope.pageSize) || 25;

                grid.indexField = $scope.idField;
                delete $scope.idField;

                grid.dataProvider = $scope.itemsProvider;

                if (!grid.indexField && grid.idlClass)
                    grid.indexField = egCore.idl.classes[grid.idlClass].pkey;

                grid.columnsProvider = egGridColumnsProvider.instance({
                    idlClass : grid.idlClass,
                    clientSort : (features.indexOf('clientsort') > -1 && features.indexOf('-clientsort') == -1),
                    defaultToHidden : (features.indexOf('-display') > -1),
                    defaultToNoSort : (features.indexOf('-sort') > -1),
                    defaultToNoMultiSort : (features.indexOf('-multisort') > -1),
                    defaultDateFormat : $scope.dateformat,
                    defaultDateContext : $scope.datecontext,
                    defaultDateFilter : $scope.datefilter,
                    defaultDateOnlyInterval : $scope.dateonlyinterval
                });
                $scope.canMultiSelect = (features.indexOf('-multiselect') == -1);

                $scope.handleAutoFields = function() {
                    if ($scope.autoFields) {
                        if (grid.autoLabel) {
                            $scope.mainLabel = 
                                egCore.idl.classes[grid.idlClass].label;
                        }
                        grid.columnsProvider.compileAutoColumns();
                        delete $scope.autoFields;
                    }
                }
   
                if (!grid.dataProvider) {
                    // no provider, um, provided.
                    // Use a flat data provider

                    grid.selfManagedData = true;
                    grid.dataProvider = egGridFlatDataProvider.instance({
                        indexField : grid.indexField,
                        idlClass : grid.idlClass,
                        columnsProvider : grid.columnsProvider,
                        query : $scope.query
                    });
                }

                // make grid ref available in get() to set totalCount, if known.
                // this allows us disable the 'next' paging button correctly
                grid.dataProvider.grid = grid;

                grid.dataProvider.columnsProvider = grid.columnsProvider;

                $scope.itemFieldValue = grid.dataProvider.itemFieldValue;
                $scope.indexValue = function(item) {
                    return grid.indexValue(item)
                };

                grid.applyControlFunctions();

                $scope.configLoadPromise = grid.loadConfig().then(function() { 
                    // link columns to scope after loadConfig(), since it
                    // replaces the columns array.
                    $scope.columns = grid.columnsProvider.columns;
                });

                // NOTE: grid.collect() is first called from link(), not here.
            }

            // link our control functions into the gridControls 
            // scope object so the caller can access them.
            grid.applyControlFunctions = function() {

                // we use some of these controls internally, so sett
                // them up even if the caller doesn't request them.
                var controls = $scope.gridControls || {};

                controls.columnMap = function() {
                    var m = {};
                    angular.forEach(grid.columnsProvider.columns, function (c) {
                        m[c.name] = c;
                    });
                    return m;
                }

                controls.columnsProvider = function() {
                    return grid.columnsProvider;
                }

                controls.contextMenuItem = function() {
                    return $scope.contextMenuItem;
                }

                // link in the control functions
                controls.selectedItems = function() {
                    return grid.getSelectedItems()
                }

                controls.selectItemsByValue = function(c,v) {
                    return grid.selectItemsByValue(c,v)
                }

                controls.allItems = function() {
                    return $scope.items;
                }

                controls.selectItems = function(ids) {
                    if (!ids) return;
                    $scope.selected = {};
                    angular.forEach(ids, function(i) {
                        $scope.selected[''+i] = true;
                    });
                }

                // if the caller provided a functional setQuery,
                // extract the value before replacing it
                if (controls.setQuery) {
                    grid.dataProvider.query = 
                        controls.setQuery();
                }

                controls.setQuery = function(query) {
                    grid.dataProvider.query = query;
                    controls.refresh();
                }

                if (controls.watchQuery) {
                    // capture the initial query value
                    grid.dataProvider.query = controls.watchQuery();

                    // watch for changes
                    $scope.gridWatchQuery = controls.watchQuery;
                    $scope.$watch('gridWatchQuery()', function(newv) {
                        controls.setQuery(newv);
                    }, true);
                }

                // if the caller provided a functional setSort
                // extract the value before replacing it
                grid.dataProvider.sort = 
                    controls.setSort ?  controls.setSort() : [];

                controls.setSort = function(sort) {
                    controls.refresh();
                }

                controls.refresh = function(noReset) {
                    if (!noReset) grid.offset = 0;
                    grid.collect();
                }

                controls.prepend = function(limit) {
                    grid.prepend(limit);
                }

                controls.setLimit = function(limit,forget) {
                    grid.limit = limit;
                    if (!forget && grid.persistKey) {
                        $scope.saveConfig();
                    }
                }
                controls.getLimit = function() {
                    return grid.limit;
                }
                controls.setOffset = function(offset) {
                    grid.offset = offset;
                }
                controls.getOffset = function() {
                    return grid.offset;
                }

                controls.saveConfig = function () {
                    return $scope.saveConfig();
                }

                grid.dataProvider.refresh = controls.refresh;
                grid.dataProvider.prepend = controls.prepend;
                grid.controls = controls;
            }

            // If a menu item provides its own HTML template, translate it,
            // using the menu item for the template scope.
            // note: $sce is required to avoid security restrictions and
            // is OK here, since the template comes directly from a
            // local HTML template (not user input).
            $scope.translateMenuItemTemplate = function(item) {
                var html = egCore.strings.$replace(item.template, {item : item});
                return $sce.trustAsHtml(html);
            }

            // add a new (global) grid menu item
            grid.addMenuItem = function(item) {
                $scope.menuItems.push(item);
                var handler = item.handler;
                item.handler = function() {
                    $scope.gridMenuIsOpen = false; // close menu
                    if (handler) {
                        handler(item, 
                            item.handlerData, grid.getSelectedItems());
                    }
                }
            }

            // add a selected-items action
            grid.addAction = function(act) {
                var done = false;
                $scope.actionGroups.forEach(function(g){
                    if (g.label === act.group) {
                        g.actions.push(act);
                        done = true;
                    }
                });
                if (!done) {
                    $scope.actionGroups.push({
                        label : act.group,
                        actions : [ act ]
                    });
                }
            }

            // remove the stored column configuration preferenc, then recover 
            // the column visibility information from the initial page load.
            $scope.resetColumns = function() {
                $scope.gridColumnPickerIsOpen = false;
                egCore.hatch.removeItem('eg.grid.' + grid.persistKey)
                .then(function() {
                    grid.columnsProvider.reset(); 
                    if (grid.selfManagedData) grid.collect();
                });
            }

            $scope.showAllColumns = function() {
                $scope.gridColumnPickerIsOpen = false;
                grid.columnsProvider.showAllColumns();
                if (grid.selfManagedData) grid.collect();
            }

            $scope.hideAllColumns = function() {
                $scope.gridColumnPickerIsOpen = false;
                grid.columnsProvider.hideAllColumns();
                // note: no need to fetch new data if no columns are visible
            }

            $scope.toggleColumnVisibility = function(col) {
                $scope.gridColumnPickerIsOpen = false;
                col.visible = !col.visible;

                // egGridFlatDataProvider only retrieves data to be
                // displayed.  When column visibility changes, it's
                // necessary to fetch the newly visible column data.
                if (grid.selfManagedData) grid.collect();
            }

            // save the columns configuration (position, sort, width) to
            // eg.grid.<persist-key>
            $scope.saveConfig = function() {
                $scope.gridColumnPickerIsOpen = false;

                if (!grid.persistKey) {
                    console.warn(
                        "Cannot save settings without a grid persist-key");
                    return;
                }

                // only store information about visible columns.
                var cols = grid.columnsProvider.columns.filter(
                    function(col) {return Boolean(col.visible) });

                // now scrunch the data down to just the needed info
                cols = cols.map(function(col) {
                    var c = {name : col.name}
                    // Apart from the name, only store non-default values.
                    // No need to store col.visible, since that's implicit
                    if (col.align != 'left') c.align = col.align;
                    if (col.flex != 2) c.flex = col.flex;
                    if (Number(col.sort)) c.sort = Number(col.sort);
                    return c;
                });

                var conf = {
                    version: 2,
                    limit: grid.limit,
                    columns: cols
                };

                egCore.hatch.setItem('eg.grid.' + grid.persistKey, conf)
                .then(function() { 
                    // Save operation performed from the grid configuration UI.
                    // Hide the configuration UI and re-draw w/ sort applied
                    if ($scope.showGridConf) 
                        $scope.toggleConfDisplay();

                    // Once a version-2 grid config is saved (with limit
                    // included) we can remove the local limit pref.
                    egCore.hatch.removeLocalItem(
                        'eg.grid.' + grid.persistKey + '.limit');
                });
            }


            // load the columns configuration (position, sort, width) from
            // eg.grid.<persist-key> and apply the loaded settings to the
            // columns on our columnsProvider
            grid.loadConfig = function() {
                if (!grid.persistKey) return $q.when();

                return egCore.hatch.getItem('eg.grid.' + grid.persistKey)
                .then(function(conf) {
                    if (!conf) return;

                    // load all column options before validating saved columns
                    $scope.handleAutoFields();

                    var columns = grid.columnsProvider.columns;
                    var new_cols = [];

                    if (Array.isArray(conf)) {
                        console.debug(  
                            'upgrading version 1 grid config to version 2');
                        conf = {
                            version : 2,
                            columns : conf
                        };
                    }

                    if (conf.limit) {
                        grid.limit = Number(conf.limit);
                    }

                    angular.forEach(conf.columns, function(col) {
                        var grid_col = columns.filter(
                            function(c) {return c.name == col.name})[0];

                        if (!grid_col) {
                            // saved column does not match a column in the 
                            // current grid.  skip it.
                            return;
                        }

                        grid_col.align = col.align || 'left';
                        grid_col.flex = col.flex || 2;
                        grid_col.sort = col.sort || 0;
                        // all saved columns are assumed to be true
                        grid_col.visible = true;
                        if (new_cols
                                .filter(function (c) {
                                    return c.name == grid_col.name;
                                }).length == 0
                        )
                            new_cols.push(grid_col);
                    });

                    // columns which are not expressed within the saved 
                    // configuration are marked as non-visible and 
                    // appended to the end of the new list of columns.
                    angular.forEach(columns, function(col) {
                        var found = conf.columns.filter(
                            function(c) {return (c.name == col.name)})[0];
                        if (!found) {
                            col.visible = false;
                            new_cols.push(col);
                        }
                    });

                    grid.columnsProvider.columns = new_cols;
                    grid.compileSort();

                });
            }

            $scope.onContextMenu = function($event) {
                var col = angular.element($event.target).attr('column');
                console.log('selected column ' + col);
            }

            $scope.page = function() {
                return (grid.offset / grid.limit) + 1;
            }

            $scope.goToPage = function(page) {
                page = Number(page);
                if (angular.isNumber(page) && page > 0) {
                    grid.offset = (page - 1) * grid.limit;
                    grid.collect();
                }
            }

            $scope.offset = function(o) {
                if (angular.isNumber(o))
                    grid.offset = o;
                return grid.offset 
            }

            $scope.limit = function(l) { 
                if (angular.isNumber(l)) {
                    grid.limit = l;
                    if (grid.persistKey) {
                        $scope.saveConfig();
                    }
                }
                return grid.limit 
            }

            $scope.onFirstPage = function() {
                return grid.offset == 0;
            }

            $scope.hasNextPage = function() {
                // we have less data than requested, there must
                // not be any more pages
                if (grid.count() < grid.limit) return false;

                // if the total count is not known, assume that a full
                // page of data implies more pages are available.
                if (grid.totalCount == -1) return true;

                // we have a full page of data, but is there more?
                return grid.totalCount > (grid.offset + grid.count());
            }

            $scope.incrementPage = function() {
                grid.offset += grid.limit;
                grid.collect();
            }

            $scope.decrementPage = function() {
                if (grid.offset < grid.limit) {
                    grid.offset = 0;
                } else {
                    grid.offset -= grid.limit;
                }
                grid.collect();
            }

            // number of items loaded for the current page of results
            grid.count = function() {
                return $scope.items.length;
            }

            // returns the unique identifier value for the provided item
            // for internal consistency, indexValue is always coerced 
            // into a string.
            grid.indexValue = function(item) {
                if (angular.isObject(item)) {
                    if (item !== null) {
                        if (angular.isFunction(item[grid.indexField]))
                            return ''+item[grid.indexField]();
                        return ''+item[grid.indexField]; // flat data
                    }
                }
                // passed a non-object; assume it's an index
                return ''+item; 
            }

            // fires the hide handler function for a context action
            $scope.actionHide = function(action) {
                if (typeof action.hide == 'undefined') {
                    return false;
                }
                if (angular.isFunction(action.hide))
                    return action.hide(action);
                return action.hide;
            }

            // fires the disable handler function for a context action
            $scope.actionDisable = function(action) {
                if (!action.handler) {
                    // we're probably a divider, so there's no action
                    // to enable
                    return true;
                }
                if (grid.getSelectedItems().length == 0 && action.handler.length > 0) {
                    return true;
                }
                if (typeof action.disabled == 'undefined') {
                    return false;
                }
                if (angular.isFunction(action.disabled))
                    return action.disabled(action);
                return action.disabled;
            }

            // fires the action handler function for a context action
            $scope.actionLauncher = function(action) {
                if (!action.handler) {
                    console.error(
                        'No handler specified for "' + action.label + '"');
                } else {

                    try {
                        action.handler(grid.getSelectedItems());
                    } catch(E) {
                        console.error('Error executing handler for "' 
                            + action.label + '" => ' + E + "\n" + E.stack);
                    }

                    if ($scope.action_context_showing) $scope.hideActionContextMenu();
                }

            }

            $scope.hideActionContextMenu = function () {
                $($scope.menu_dom).css({
                    display: '',
                    width: $scope.action_context_width,
                    top: $scope.action_context_y,
                    left: $scope.action_context_x
                });
                $($scope.action_context_parent).append($scope.menu_dom);
                $scope.action_context_oldy = $scope.action_context_oldx = 0;
                $('body').unbind('click.remove_context_menu_'+$scope.action_context_index);
                $scope.action_context_showing = false;
            }

            $scope.action_context_showing = false;
            $scope.showActionContextMenu = function ($event) {

                // Have to gather these here, instead of inside link()
                if (!$scope.menu_dom) $scope.menu_dom = $($scope.grid_element).find('.grid-action-dropdown')[0];
                if (!$scope.action_context_parent) $scope.action_context_parent = $($scope.menu_dom).parent();

                // we need the the row that got right-clicked...
                var e = $event.target; // the DOM element
                var s = undefined;     // the angular scope for that element
                while(e){ // searching for the row
                    // abort & use the browser default context menu for links (lp1669856):
                    if(e.tagName.toLowerCase() === 'a' && e.href){ return true; }
                    s = angular.element(e).scope();
                    if(s.hasOwnProperty('item')){ break; }
                    e = e.parentElement;
                }
                
                $scope.contextMenuItem = grid.indexValue(s.item);
                
                // select the right-clicked row if it is not already selected (lp1776557):
                if(!$scope.selected[grid.indexValue(s.item)]){ $event.target.click(); }

                if (!$scope.action_context_showing) {
                    $scope.action_context_width = $($scope.menu_dom).css('width');
                    $scope.action_context_y = $($scope.menu_dom).css('top');
                    $scope.action_context_x = $($scope.menu_dom).css('left');
                    $scope.action_context_showing = true;
                    $scope.action_context_index = Math.floor((Math.random() * 1000) + 1);

                    $('body').append($($scope.menu_dom));
                    $('body').bind('click.remove_context_menu_'+$scope.action_context_index, $scope.hideActionContextMenu);
                }

                $($scope.menu_dom).css({
                    display: 'block',
                    width: $scope.action_context_width,
                    top: $event.pageY,
                    left: $event.pageX
                });

                return false;
            }

            // returns the list of selected item objects
            grid.getSelectedItems = function() {
                return $scope.items.filter(
                    function(item) {
                        return Boolean($scope.selected[grid.indexValue(item)]);
                    }
                );
            }

            grid.getItemByIndex = function(index) {
                for (var i = 0; i < $scope.items.length; i++) {
                    var item = $scope.items[i];
                    if (grid.indexValue(item) == index) 
                        return item;
                }
            }

            // selects one row after deselecting all of the others
            grid.selectOneItem = function(index) {
                $scope.selected = {};
                $scope.selected[index] = true;
            }

            // selects items by a column value, first clearing selected list.
            // we overwrite the object so that we can watch $scope.selected
            grid.selectItemsByValue = function(column, value) {
                $scope.selected = {};
                angular.forEach($scope.items, function(item) {
                    var col_value;
                    if (angular.isFunction(item[column]))
                        col_value = item[column]();
                    else
                        col_value = item[column];

                    if (value == col_value) $scope.selected[grid.indexValue(item)] = true
                }); 
            }

            // selects or deselects an item, without affecting the others.
            // returns true if the item is selected; false if de-selected.
            // we overwrite the object so that we can watch $scope.selected
            grid.toggleSelectOneItem = function(index) {
                if ($scope.selected[index]) {
                    delete $scope.selected[index];
                    $scope.selected = angular.copy($scope.selected);
                    return false;
                } else {
                    $scope.selected[index] = true;
                    $scope.selected = angular.copy($scope.selected);
                    return true;
                }
            }

            $scope.updateSelected = function(index) {
                // values have already been toggled by the checkbox
                if (!$scope.canMultiSelect && $scope.selected[index]) {
                    $scope.selected = { [index]: true };
                }
                $scope.selected = angular.copy($scope.selected);
                return $scope.selected;
            };

            grid.selectAllItems = function() {
                angular.forEach($scope.items, function(item) {
                    $scope.selected[grid.indexValue(item)] = true
                }); 
                $scope.selected = angular.copy($scope.selected);
            }

            $scope.$watch('selectAll', function(newVal) {
                if (newVal) {
                    grid.selectAllItems();
                } else {
                    $scope.selected = {};
                }
            });

            if ($scope.onSelect) {
                $scope.$watch('selected', function(newVal) {
                    $scope.onSelect(grid.getSelectedItems());
                    if ($scope.afterSelect) $scope.afterSelect();
                });
            }

            // returns true if item1 appears in the list before item2;
            // false otherwise.  this is slightly more efficient that
            // finding the position of each then comparing them.
            // item1 / item2 may be an item or an item index
            grid.itemComesBefore = function(itemOrIndex1, itemOrIndex2) {
                var idx1 = grid.indexValue(itemOrIndex1);
                var idx2 = grid.indexValue(itemOrIndex2);

                // use for() for early exit
                for (var i = 0; i < $scope.items.length; i++) {
                    var idx = grid.indexValue($scope.items[i]);
                    if (idx == idx1) return true;
                    if (idx == idx2) return false;
                }
                return false;
            }

            // 0-based position of item in the current data set
            grid.indexOf = function(item) {
                var idx = grid.indexValue(item);
                for (var i = 0; i < $scope.items.length; i++) {
                    if (grid.indexValue($scope.items[i]) == idx)
                        return i;
                }
                return -1;
            }

            grid.modifyColumnFlex = function(column, val) {
                column.flex += val;
                // prevent flex:0;  use hiding instead
                if (column.flex < 1)
                    column.flex = 1;
            }
            $scope.modifyColumnFlex = function(col, val) {
                $scope.lastModColumn = col;
                grid.modifyColumnFlex(col, val);
            }

            $scope.isLastModifiedColumn = function(col) {
                if ($scope.lastModColumn)
                    return $scope.lastModColumn === col;
                return false;
            }

            grid.modifyColumnPos = function(col, diff) {
                var srcIdx, targetIdx;
                angular.forEach(grid.columnsProvider.columns,
                    function(c, i) { if (c.name == col.name) srcIdx = i });

                targetIdx = srcIdx + diff;
                if (targetIdx < 0) {
                    targetIdx = 0;
                } else if (targetIdx >= grid.columnsProvider.columns.length) {
                    // Target index follows the last visible column.
                    var lastVisible = 0;
                    angular.forEach(grid.columnsProvider.columns, 
                        function(column, idx) {
                            if (column.visible) lastVisible = idx;
                        }
                    );

                    // When moving a column (down) causes one or more
                    // visible columns to shuffle forward, our column
                    // moves into the slot of the last visible column.
                    // Otherwise, put it into the slot directly following 
                    // the last visible column.
                    targetIdx = 
                        srcIdx <= lastVisible ? lastVisible : lastVisible + 1;
                }

                // Splice column out of old position, insert at new position.
                grid.columnsProvider.columns.splice(srcIdx, 1);
                grid.columnsProvider.columns.splice(targetIdx, 0, col);
            }

            $scope.modifyColumnPos = function(col, diff) {
                $scope.lastModColumn = col;
                return grid.modifyColumnPos(col, diff);
            }


            // handles click, control-click, and shift-click
            $scope.handleRowClick = function($event, item) {
                var index = grid.indexValue(item);

                var origSelected = Object.keys($scope.selected);

                if (!$scope.canMultiSelect) {
                    grid.selectOneItem(index);
                    grid.lastSelectedItemIndex = index;
                    return;
                }

                if ($event.ctrlKey || $event.metaKey /* mac command */) {
                    // control-click
                    if (grid.toggleSelectOneItem(index)) 
                        grid.lastSelectedItemIndex = index;

                } else if ($event.shiftKey) { 
                    // shift-click

                    if (!grid.lastSelectedItemIndex || 
                            index == grid.lastSelectedItemIndex) {
                        grid.selectOneItem(index);
                        grid.lastSelectedItemIndex = index;

                    } else {

                        var selecting = false;
                        var ascending = grid.itemComesBefore(
                            grid.lastSelectedItemIndex, item);
                        var startPos = 
                            grid.indexOf(grid.lastSelectedItemIndex);

                        // update to new last-selected
                        grid.lastSelectedItemIndex = index;

                        // select each row between the last selected and 
                        // currently selected items
                        while (true) {
                            startPos += ascending ? 1 : -1;
                            var curItem = $scope.items[startPos];
                            if (!curItem) break;
                            var curIdx = grid.indexValue(curItem);
                            $scope.selected[curIdx] = true;
                            if (curIdx == index) break; // all done
                        }
                        $scope.selected = angular.copy($scope.selected);
                    }
                        
                } else {
                    grid.selectOneItem(index);
                    grid.lastSelectedItemIndex = index;
                }
            }

            // Builds a sort expression from column sort priorities.
            // called on page load and any time the priorities are modified.
            grid.compileSort = function() {
                var sortList = grid.columnsProvider.columns.filter(
                    function(col) { return Number(col.sort) != 0 }
                ).sort( 
                    function(a, b) { 
                        if (Math.abs(a.sort) < Math.abs(b.sort))
                            return -1;
                        return 1;
                    }
                );

                if (sortList.length) {
                    grid.dataProvider.sort = sortList.map(function(col) {
                        var blob = {};
                        blob[col.name] = col.sort < 0 ? 'desc' : 'asc';
                        return blob;
                    });
                }
            }

            // builds a sort expression using a single column, 
            // toggling between ascending and descending sort.
            $scope.quickSort = function(col_name) {
                var sort = grid.dataProvider.sort;
                if (sort && sort.length &&
                    sort[0] == col_name) {
                    var blob = {};
                    blob[col_name] = 'desc';
                    grid.dataProvider.sort = [blob];
                } else {
                    grid.dataProvider.sort = [col_name];
                }

                grid.offset = 0;
                grid.collect();
            }

            // show / hide the grid configuration row
            $scope.toggleConfDisplay = function() {
                if ($scope.showGridConf) {
                    $scope.showGridConf = false;
                    if (grid.columnsProvider.hasSortableColumn()) {
                        // only refresh the grid if the user has the
                        // ability to modify the sort priorities.
                        grid.compileSort();
                        grid.offset = 0;
                        grid.collect();
                    }
                } else {
                    $scope.showGridConf = true;
                }

                delete $scope.lastModColumn;
                $scope.gridColumnPickerIsOpen = false;
            }

            // called when a dragged column is dropped onto itself
            // or any other column
            grid.onColumnDrop = function(target) {
                if (angular.isUndefined(target)) return;
                if (target == grid.dragColumn) return;
                var srcIdx, targetIdx, srcCol;
                angular.forEach(grid.columnsProvider.columns,
                    function(col, idx) {
                        if (col.name == grid.dragColumn) {
                            srcIdx = idx;
                            srcCol = col;
                        } else if (col.name == target) {
                            targetIdx = idx;
                        }
                    }
                );

                if (srcIdx < targetIdx) targetIdx--;

                // move src column from old location to new location in 
                // the columns array, then force a page refresh
                grid.columnsProvider.columns.splice(srcIdx, 1);
                grid.columnsProvider.columns.splice(targetIdx, 0, srcCol);
                $scope.$apply(); 
            }

            // prepares a string for inclusion within a CSV document
            // by escaping commas and quotes and removing newlines.
            grid.csvDatum = function(str) {
                str = ''+str;
                if (!str) return '';
                str = str.replace(/\n/g, '');
                if (str.match(/\,/) || str.match(/"/)) {                                     
                    str = str.replace(/"/g, '""');
                    str = '"' + str + '"';                                           
                } 
                return str;
            }

            /** Export the full data set as CSV.
             *  Flow of events:
             *  1. User clicks the 'download csv' link
             *  2. All grid data is retrieved asychronously
             *  3. Once all data is all present and CSV-ized, the download 
             *     attributes are linked to the href.
             *  4. The href .click() action is prgrammatically fired again,
             *     telling the browser to download the data, now that the
             *     data is available for download.
             *  5 Once downloaded, the href attributes are reset.
             */
            grid.csvExportInProgress = false;
            $scope.generateCSVExportURL = function($event) {

                if (grid.csvExportInProgress) {
                    // This is secondary href click handler.  Give the
                    // browser a moment to start the download, then reset
                    // the CSV download attributes / state.
                    $timeout(
                        function() {
                            $scope.csvExportURL = '';
                            $scope.csvExportFileName = ''; 
                            grid.csvExportInProgress = false;
                        }, 500
                    );
                    return;
                } 

                grid.csvExportInProgress = true;
                $scope.gridColumnPickerIsOpen = false;

                // let the file name describe the grid
                $scope.csvExportFileName = 
                    ($scope.mainLabel || grid.persistKey || 'eg_grid_data')
                    .replace(/\s+/g, '_') + '_' + $scope.page();

                // toss the CSV into a Blob and update the export URL
                grid.generateCSV().then(function(csv) {
                    var blob = new Blob([csv], {type : 'text/plain'});
                    $scope.csvExportURL = 
                        ($window.URL || $window.webkitURL).createObjectURL(blob);

                    // Fire the 2nd click event now that the browser has
                    // information on how to download the CSV file.
                    $timeout(function() {$event.target.click()});
                });
            }

            /*
             * TODO: does this serve any purpose given we can 
             * print formatted HTML?  If so, generateCSV() now
             * returns a promise, needs light refactoring...
            $scope.printCSV = function() {
                $scope.gridColumnPickerIsOpen = false;
                egCore.print.print({
                    context : 'default', 
                    content : grid.generateCSV(),
                    content_type : 'text/plain'
                });
            }
            */

            // Given a row item and column definition, extract the
            // text content for printing.  Templated columns must be
            // processed and parsed as HTML, then boiled down to their 
            // text content.
            grid.getItemTextContent = function(item, col) {
                var val;
                if (col.template) {
                    val = $scope.translateCellTemplate(col, item);
                    if (val) {
                        var node = new DOMParser()
                            .parseFromString(val, 'text/html');
                        val = $(node).text();
                    }
                } else {
                    val = grid.dataProvider.itemFieldValue(item, col);
                    if (val === null || val === undefined || val === '') return '';
                    val = $filter('egGridValueFilter')(val, col, item);
                }
                return val;
            }

            $scope.getHtmlTooltip = function(col, item) {
                return grid.getItemTextContent(item, col);
            }

            /**
             * Fetches all grid data and transates each item into a simple
             * key-value pair of column name => text-value.
             * Included in the response for convenience is the list of 
             * currently visible column definitions.
             * TODO: currently fetches a maximum of 10k rows.  Does this
             * need to be configurable?
             */
            grid.getAllItemsAsText = function() {
                var text_items = [];

                // we don't know the total number of rows we're about
                // to retrieve, but we can indicate the number retrieved
                // so far as each item arrives.
                var progressDialog = egProgressDialog.open({value : 0});
                return progressDialog.opened.then(function() {
                    var visible_cols = grid.columnsProvider.columns.filter(
                        function(c) { return c.visible });
    
                    return grid.dataProvider.get(0, 10000).then(
                        function() { 
                            return {items : text_items, columns : visible_cols};
                        }, 
                        null,
                        function(item) { 
                            egProgressDialog.increment();
                            var text_item = {};
                            angular.forEach(visible_cols, function(col) {
                                text_item[col.name] = 
                                    grid.getItemTextContent(item, col);
                            });
                            text_items.push(text_item);
                        }
                    ).finally(egProgressDialog.close);
                });
            }

            // Fetch "all" of the grid data, translate it into print-friendly 
            // text, and send it to the printer service.
            $scope.printHTML = function() {
                $scope.gridColumnPickerIsOpen = false;
                return grid.getAllItemsAsText().then(function(text_items) {
                    return egCore.print.print({
                        template : 'grid_html',
                        scope : text_items
                    });
                });
            }

            $scope.printSelectedRows = function() {
                $scope.gridColumnPickerIsOpen = false;

                var columns = grid.columnsProvider.columns.filter(
                    function(c) { return c.visible }
                );
                var selectedItems = grid.getSelectedItems();
                var scope = {items: [], columns};
                var template = 'grid_html';

                angular.forEach(selectedItems, function(item) {
                    var textItem = {};
                    angular.forEach(columns, function(col) {
                        textItem[col.name] = 
                            grid.getItemTextContent(item, col);
                    });
                    scope.items.push(textItem);
                });

                egCore.print.print({template, scope});
            };

            $scope.showColumnDialog = function() {
                return $uibModal.open({
                    templateUrl: './share/t_grid_columns',
                    backdrop: 'static',
                    size : 'lg',
                    controller: ['$scope', '$uibModalInstance',
                        function($dialogScope, $uibModalInstance) {
                            $dialogScope.modifyColumnPos = $scope.modifyColumnPos;
                            $dialogScope.disableMultiSort = $scope.disableMultiSort;
                            $dialogScope.columns = $scope.columns;

                            // Push visible columns to the top of the list
                            $dialogScope.elevateVisible = function() {
                                var new_cols = [];
                                angular.forEach($dialogScope.columns, function(col) {
                                    if (col.visible) new_cols.push(col);
                                });
                                angular.forEach($dialogScope.columns, function(col) {
                                    if (!col.visible) new_cols.push(col);
                                });

                                // Update all references to the list of columns
                                $dialogScope.columns = 
                                    $scope.columns = 
                                    grid.columnsProvider.columns = 
                                    new_cols;
                            }

                            $dialogScope.toggle = function(col) {
                                col.visible = !Boolean(col.visible);
                            }
                            $dialogScope.ok = $dialogScope.cancel = function() {
                                delete $scope.lastModColumn;
                                if (grid.columnsProvider.hasSortableColumn()) {
                                    // only refresh the grid if the user has the
                                    // ability to modify the sort priorities.
                                    grid.compileSort();
                                    grid.offset = 0;
                                    grid.collect();
                                }
                                $uibModalInstance.close()
                            }
                        }
                    ]
                });
            },

            // generates CSV for the currently visible grid contents
            grid.generateCSV = function() {
                return grid.getAllItemsAsText().then(function(text_items) {
                    var columns = text_items.columns;
                    var items = text_items.items;
                    var csvStr = '';

                    // column headers
                    angular.forEach(columns, function(col) {
                        csvStr += grid.csvDatum(col.label);
                        csvStr += ',';
                    });

                    csvStr = csvStr.replace(/,$/,'\n');

                    // items
                    angular.forEach(items, function(item) {
                        angular.forEach(columns, function(col) {
                            csvStr += grid.csvDatum(item[col.name]);
                            csvStr += ',';
                        });
                        csvStr = csvStr.replace(/,$/,'\n');
                    });

                    return csvStr;
                });
            }

            // Interpolate the value for column.linkpath within the context
            // of the row item to generate the final link URL.
            $scope.generateLinkPath = function(col, item) {
                return egCore.strings.$replace(col.linkpath, {item : item});
            }

            // If a column provides its own HTML template, translate it,
            // using the current item for the template scope.
            // note: $sce is required to avoid security restrictions and
            // is OK here, since the template comes directly from a
            // local HTML template (not user input).
            $scope.translateCellTemplate = function(col, item) {
                var html = egCore.strings.$replace(col.template, {item : item});
                return $sce.trustAsHtml(html);
            }

            $scope.collect = function() { grid.collect() }


            $scope.confirmAllowAllAndCollect = function(){
                egConfirmDialog.open(egStrings.CONFIRM_LONG_RUNNING_ACTION_ALL_ROWS_TITLE,
                    egStrings.CONFIRM_LONG_RUNNING_ACTION_MSG)
                    .result
                    .then(function(){
                        $scope.offset(0);
                        $scope.limit(10000);
                        grid.collect();
                });
            }

            // asks the dataProvider for a page of data
            grid.collect = function() {

                // avoid firing the collect if there is nothing to collect.
                if (grid.selfManagedData && !grid.dataProvider.query) return;

                if (grid.collecting) return; // avoid parallel collect()
                grid.collecting = true;

                console.debug('egGrid.collect() offset=' 
                    + grid.offset + '; limit=' + grid.limit);

                // ensure all of our dropdowns are closed
                // TODO: git rid of these and just use dropdown-toggle, 
                // which is more reliable.
                $scope.gridColumnPickerIsOpen = false;
                $scope.gridRowCountIsOpen = false;
                $scope.gridPageSelectIsOpen = false;

                $scope.items = [];
                $scope.selected = {};

                // Inform the caller we've asked the data provider
                // for data.  This is useful for knowing when collection
                // has started (e.g. to display a progress dialg) when 
                // using the stock (flattener) data provider, where the 
                // user is not directly defining a get() handler.
                if (grid.controls.collectStarted)
                    grid.controls.collectStarted(grid.offset, grid.limit);

                grid.dataProvider.get(grid.offset, grid.limit).then(
                function() {
                    if (grid.controls.allItemsRetrieved)
                        grid.controls.allItemsRetrieved();
                },
                null, 
                function(item) {
                    if (item) {
                        $scope.items.push(item)
                        if (grid.controls.itemRetrieved)
                            grid.controls.itemRetrieved(item);
                        if ($scope.selectAll)
                            $scope.selected[grid.indexValue(item)] = true
                    }
                }).finally(function() { 
                    console.debug('egGrid.collect() complete');
                    grid.collecting = false 
                    $scope.selected = angular.copy($scope.selected);
                });
            }

            grid.prepend = function(limit) {
                var ran_into_duplicate = false;
                var sort = grid.dataProvider.sort;
                if (sort && sort.length) {
                    // If sorting is in effect, we have no way
                    // of knowing that the new item should be
                    // visible _if the sort order is retained_.
                    // However, since the grids that do prepending in
                    // the first place are ones where we always
                    // want the new row to show up on top, we'll
                    // remove the current sort options.
                    grid.dataProvider.sort = [];
                }
                if (grid.offset > 0) {
                    // if we're prepending, we're forcing the
                    // offset back to zero to display the top
                    // of the list
                    grid.offset = 0;
                    grid.collect();
                    return;
                }
                if (grid.collecting) return; // avoid parallel collect() or prepend()
                grid.collecting = true;
                console.debug('egGrid.prepend() starting');
                // Note that we can count on the most-recently added
                // item being at offset 0 in the data provider only
                // for arrayNotifier data sources that do not have
                // sort options currently set.
                grid.dataProvider.get(0, 1).then(
                null,
                null,
                function(item) {
                    if (item) {
                        var newIdx = grid.indexValue(item);
                        angular.forEach($scope.items, function(existing) {
                            if (grid.indexValue(existing) == newIdx) {
                                console.debug('egGrid.prepend(): refusing to add duplicate item ' + newIdx);
                                ran_into_duplicate = true;
                                return;
                            }
                        });
                        $scope.items.unshift(item);
                        if (limit && $scope.items.length > limit) {
                            // this accommodates the checkin grid that
                            // allows the user to set a definite limit
                            // without requiring that entire collect()
                            $scope.items.length = limit;
                        }
                        if ($scope.items.length > grid.limit) {
                            $scope.items.length = grid.limit;
                        }
                        if (grid.controls.itemRetrieved)
                            grid.controls.itemRetrieved(item);
                        if ($scope.selectAll)
                            $scope.selected[grid.indexValue(item)] = true
                    }
                }).finally(function() {
                    console.debug('egGrid.prepend() complete');
                    grid.collecting = false;
                    $scope.selected = angular.copy($scope.selected);
                    if (ran_into_duplicate) {
                        grid.collect();
                    }
                });
            }

            grid.init();
        }]
    };
})

/**
 * eg-grid-field : used for collecting custom field data from the templates.
 * This directive does not direct display, it just passes data up to the 
 * parent grid.
 */
.directive('egGridField', function() {
    return {
        require : '^egGrid',
        restrict : 'AE',
        scope : {
            flesher: '=', // optional; function that can flesh a linked field, given the value
            comparator: '=', // optional; function that can sort the thing at the end of 'path' 
            name  : '@', // required; unique name
            path  : '@', // optional; flesh path
            ignore: '@', // optional; fields to ignore when path is a wildcard
            label : '@', // optional; display label
            flex  : '@',  // optional; default flex width
            align  : '@',  // optional; default alignment, left/center/right
            dateformat : '@', // optional: passed down to egGridValueFilter
            datecontext: '@', // optional: passed down to egGridValueFilter to choose TZ
            datefilter: '@', // optional: passed down to egGridValueFilter to choose specialized date filters
            dateonlyinterval: '@', // optional: passed down to egGridValueFilter to choose a "better" format

            // if a field is part of an IDL object, but we are unable to
            // determine the class, because it's nested within a hash
            // (i.e. we can't navigate directly to the object via the IDL),
            // idlClass lets us specify the class.  This is particularly
            // useful for nested wildcard fields.
            parentIdlClass : '@', 

            // optional: for non-IDL columns, specifying a datatype
            // lets the caller control which display filter is used.
            // datatype should match the standard IDL datatypes.
            datatype : '@',

            // optional hash of functions that can be imported into
            // the directive's scope; meant for cases where the "compiled"
            // attribute is set
            handlers : '=',

            // optional: CSS class name that we want to have for this field.
            // Auto generated from path if nothing is passed in via eg-grid-field declaration
            cssSelector : "@"
        },
        link : function(scope, element, attrs, egGridCtrl) {

            // boolean fields are presented as value-less attributes
            angular.forEach(
                [
                    'visible', 
                    'compiled', 
                    'hidden', 
                    'sortable', 
                    'nonsortable',
                    'multisortable',
                    'nonmultisortable',
                    'required' // if set, always fetch data for this column
                ],
                function(field) {
                    if (angular.isDefined(attrs[field]))
                        scope[field] = true;
                }
            );

            scope.cssSelector = attrs['cssSelector'] ? attrs['cssSelector'] : "";

            // auto-generate CSS selector name for field if none declared in tt2 and there's a path
            if (scope.path && !scope.cssSelector){
                var cssClass = 'grid' + "." + scope.path;
                cssClass = cssClass.replace(/\./g,'-');
                element.addClass(cssClass);
                scope.cssSelector = cssClass;
            }

            // any HTML content within the field is its custom template
            var tmpl = element.html();
            if (tmpl && !tmpl.match(/^\s*$/))
                scope.template = tmpl

            egGridCtrl.columnsProvider.add(scope);
            scope.$destroy();
        }
    };
})

/**
 * eg-grid-action : used for specifying actions which may be applied
 * to items within the grid.
 */
.directive('egGridAction', function() {
    return {
        require : '^egGrid',
        restrict : 'AE',
        transclude : true,
        scope : {
            group   : '@', // Action group, ungrouped if not set
            label   : '@', // Action label
            handler : '=',  // Action function handler
            hide    : '=',
            disabled : '=', // function
            divider : '='
        },
        link : function(scope, element, attrs, egGridCtrl) {
            egGridCtrl.addAction({
                hide  : scope.hide,
                group : scope.group,
                label : scope.label,
                divider : scope.divider,
                handler : scope.handler,
                disabled : scope.disabled,
            });
            scope.$destroy();
        }
    };
})

.factory('egGridColumnsProvider', ['egCore', function(egCore) {

    function ColumnsProvider(args) {
        var cols = this;
        cols.columns = [];
        cols.stockVisible = [];
        cols.idlClass = args.idlClass;
        cols.clientSort = args.clientSort;
        cols.defaultToHidden = args.defaultToHidden;
        cols.defaultToNoSort = args.defaultToNoSort;
        cols.defaultToNoMultiSort = args.defaultToNoMultiSort;
        cols.defaultDateFormat = args.defaultDateFormat;
        cols.defaultDateContext = args.defaultDateContext;

        // resets column width, visibility, and sort behavior
        // Visibility resets to the visibility settings defined in the 
        // template (i.e. the original egGridField values).
        cols.reset = function() {
            angular.forEach(cols.columns, function(col) {
                col.align = 'left';
                col.flex = 2;
                col.sort = 0;
                if (cols.stockVisible.indexOf(col.name) > -1) {
                    col.visible = true;
                } else {
                    col.visible = false;
                }
            });
        }

        // returns true if any columns are sortable
        cols.hasSortableColumn = function() {
            return cols.columns.filter(
                function(col) {
                    return col.sortable || col.multisortable;
                }
            ).length > 0;
        }

        cols.showAllColumns = function() {
            angular.forEach(cols.columns, function(column) {
                column.visible = true;
            });
        }

        cols.hideAllColumns = function() {
            angular.forEach(cols.columns, function(col) {
                delete col.visible;
            });
        }

        cols.indexOf = function(name) {
            for (var i = 0; i < cols.columns.length; i++) {
                if (cols.columns[i].name == name) 
                    return i;
            }
            return -1;
        }

        cols.findColumn = function(name) {
            return cols.columns[cols.indexOf(name)];
        }

        cols.compileAutoColumns = function() {
            var idl_class = egCore.idl.classes[cols.idlClass];

            angular.forEach(
                idl_class.fields,
                function(field) {
                    if (field.virtual) return;
                    // Columns declared in the markup take precedence
                    // of matching auto-columns.
                    if (cols.findColumn(field.name)) return;
                    if (field.datatype == 'link' || field.datatype == 'org_unit') {
                        // if the field is a link and the linked class has a
                        // "selector" field specified, use the selector field
                        // as the display field for the columns.
                        // flattener will take care of the fleshing.
                        if (field['class']) {
                            var selector_field = egCore.idl.classes[field['class']].fields
                                .filter(function(f) { return Boolean(f.selector) })[0];
                            if (selector_field) {
                                field.path = field.name + '.' + selector_field.selector;
                            }
                        }
                    }
                    cols.add(field, true);
                }
            );
        }

        // if a column definition has a path with a wildcard, create
        // columns for all non-virtual fields at the specified 
        // position in the path.
        cols.expandPath = function(colSpec) {

            var ignoreList = [];
            if (colSpec.ignore)
                ignoreList = colSpec.ignore.split(' ');

            var dotpath = colSpec.path.replace(/\.?\*$/,'');
            var class_obj;
            var idl_field;

            if (colSpec.parentIdlClass) {
                class_obj = egCore.idl.classes[colSpec.parentIdlClass];
            } else {
                class_obj = egCore.idl.classes[cols.idlClass];
            }
            var idl_parent = class_obj;
            var old_field_label = '';

            if (!class_obj) return;

            //console.debug('egGrid: auto dotpath is: ' + dotpath);
            var path_parts = dotpath.split(/\./);

            // find the IDL class definition for the last element in the
            // path before the .*
            // an empty path_parts means expand the root class
            if (path_parts) {
                var old_field;
                for (var path_idx in path_parts) {
                    old_field = idl_field;

                    var part = path_parts[path_idx];
                    idl_field = class_obj.field_map[part];

                    // unless we're at the end of the list, this field should
                    // link to another class.
                    if (idl_field && idl_field['class'] && (
                        idl_field.datatype == 'link' || 
                        idl_field.datatype == 'org_unit')) {
                        if (old_field_label) old_field_label += ' : ';
                        old_field_label += idl_field.label;
                        class_obj = egCore.idl.classes[idl_field['class']];
                        if (old_field) idl_parent = old_field;
                    } else {
                        if (path_idx < (path_parts.length - 1)) {
                            // we ran out of classes to hop through before
                            // we ran out of path components
                            console.error("egGrid: invalid IDL path: " + dotpath);
                        }
                    }
                }
            }

            if (class_obj) {
                angular.forEach(class_obj.fields, function(field) {

                    // Only show wildcard fields where we have data to show
                    // Virtual and un-fleshed links will not have any data.
                    if (field.virtual ||
                        (field.datatype == 'link' || field.datatype == 'org_unit') ||
                        ignoreList.indexOf(field.name) > -1
                    )
                        return;

                    var col = cols.cloneFromScope(colSpec);
                    col.path = (dotpath ? dotpath + '.' + field.name : field.name);

                    // log line below is very chatty.  disable until needed.
                    // console.debug('egGrid: field: ' +field.name + '; parent field: ' + js2JSON(idl_parent));
                    cols.add(col, false, true, 
                        {idl_parent : idl_parent, idl_field : field, idl_class : class_obj, field_parent_label : old_field_label });
                });

                cols.columns = cols.columns.sort(
                    function(a, b) {
                        if (a.explicit) return -1;
                        if (b.explicit) return 1;

                        if (a.idlclass && b.idlclass) {
                            if (a.idlclass < b.idlclass) return -1;
                            if (b.idlclass < a.idlclass) return 1;
                        }

                        if (a.path && b.path && a.path.lastIndexOf('.') && b.path.lastIndexOf('.')) {
                            if (a.path.substring(0, a.path.lastIndexOf('.')) < b.path.substring(0, b.path.lastIndexOf('.'))) return -1;
                            if (b.path.substring(0, b.path.lastIndexOf('.')) < a.path.substring(0, a.path.lastIndexOf('.'))) return 1;
                        }

                        if (a.label && b.label) {
                            if (a.label < b.label) return -1;
                            if (b.label < a.label) return 1;
                        }

                        return a.name < b.name ? -1 : 1;
                    }
                );


            } else {
                console.error(
                    "egGrid: wildcard path does not resolve to an object: "
                    + dotpath);
            }
        }

        // angular.clone(scopeObject) is not permittable.  Manually copy
        // the fields over that we need (so the scope object can go away).
        cols.cloneFromScope = function(colSpec) {
            return {
                flesher  : colSpec.flesher,
                comparator  : colSpec.comparator,
                name  : colSpec.name,
                label : colSpec.label,
                path  : colSpec.path,
                align  : colSpec.align || 'left',
                flex  : Number(colSpec.flex) || 2,
                sort  : Number(colSpec.sort) || 0,
                required : colSpec.required,
                linkpath : colSpec.linkpath,
                template : colSpec.template,
                visible  : colSpec.visible,
                compiled : colSpec.compiled,
                handlers : colSpec.handlers,
                hidden   : colSpec.hidden,
                datatype : colSpec.datatype,
                sortable : colSpec.sortable,
                nonsortable      : colSpec.nonsortable,
                multisortable    : colSpec.multisortable,
                nonmultisortable : colSpec.nonmultisortable,
                dateformat       : colSpec.dateformat,
                datecontext      : colSpec.datecontext,
                datefilter      : colSpec.datefilter,
                dateonlyinterval : colSpec.dateonlyinterval,
                parentIdlClass   : colSpec.parentIdlClass,
                cssSelector      : colSpec.cssSelector
            };
        }


        // Add a column to the columns collection.
        // Columns may come from a slim eg-columns-field or 
        // directly from the IDL.
        cols.add = function(colSpec, fromIDL, fromExpand, idl_info) {

            // First added column with the specified path takes precedence.
            // This allows for specific definitions followed by wildcard
            // definitions.  If a match is found, back out.
            if (cols.columns.filter(function(c) {
                return (c.path == colSpec.path) })[0]) {
                console.debug('skipping pre-existing column ' + colSpec.path);
                return;
            }

            var column = fromExpand ? colSpec : cols.cloneFromScope(colSpec);

            if (column.path && column.path.match(/\*$/)) 
                return cols.expandPath(colSpec);

            if (!fromExpand) column.explicit = true;

            if (!column.name) column.name = column.path;
            if (!column.path) column.path = column.name;

            if (column.visible || (!cols.defaultToHidden && !column.hidden))
                column.visible = true;

            if (column.sortable || (!cols.defaultToNoSort && !column.nonsortable))
                column.sortable = true;

            if (column.multisortable || 
                (!cols.defaultToNoMultiSort && !column.nonmultisortable))
                column.multisortable = true;

            if (cols.defaultDateFormat && ! column.dateformat) {
                column.dateformat = cols.defaultDateFormat;
            }

            if (cols.defaultDateOnlyInterval && ! column.dateonlyinterval) {
                column.dateonlyinterval = cols.defaultDateOnlyInterval;
            }

            if (cols.defaultDateContext && ! column.datecontext) {
                column.datecontext = cols.defaultDateContext;
            }

            if (cols.defaultDateFilter && ! column.datefilter) {
                column.datefilter = cols.defaultDateFilter;
            }

            cols.columns.push(column);

            // Track which columns are visible by default in case we
            // need to reset column visibility
            if (column.visible) 
                cols.stockVisible.push(column.name);

            if (fromIDL) return; // directly from egIDL.  nothing left to do.

            // lookup the matching IDL field
            if (!idl_info && cols.idlClass) 
                idl_info = cols.idlFieldFromPath(column.path);

            if (!idl_info) {
                // column is not represented within the IDL
                column.adhoc = true; 
                return; 
            }

            column.datatype = idl_info.idl_field.datatype;
            
            if (!column.label) {
                column.label = idl_info.idl_field.label || column.name;
            }

            if (fromExpand && idl_info.idl_class) {
                column.idlclass = '';
                if (idl_info.field_parent_label && idl_info.idl_parent.label != idl_info.idl_class.label) {
                    column.idlclass = (idl_info.field_parent_label || idl_info.idl_parent.label || idl_info.idl_parent.name);
                } else {
                    column.idlclass += idl_info.idl_class.label || idl_info.idl_class.name;
                }
            }
        },

        // finds the IDL field from the dotpath, using the columns
        // idlClass as the base.
        cols.idlFieldFromPath = function(dotpath) {
            var class_obj = egCore.idl.classes[cols.idlClass];
            if (!dotpath) return null;

            var path_parts = dotpath.split(/\./);

            var idl_parent;
            var idl_field;
            for (var path_idx in path_parts) {
                var part = path_parts[path_idx];
                idl_parent = idl_field;
                idl_field = class_obj.field_map[part];

                if (idl_field) {
                    if (idl_field['class'] && (
                        idl_field.datatype == 'link' || 
                        idl_field.datatype == 'org_unit')) {
                        class_obj = egCore.idl.classes[idl_field['class']];
                    }
                } else {
                    return null;
                }
            }

            return {
                idl_parent: idl_parent,
                idl_field : idl_field,
                idl_class : class_obj
            };
        }
    }

    return {
        instance : function(args) { return new ColumnsProvider(args) }
    }
}])


/*
 * Generic data provider template class.  This is basically an abstract
 * class factory service whose instances can be locally modified to 
 * meet the needs of each individual grid.
 */
.factory('egGridDataProvider', 
           ['$q','$timeout','$filter','egCore',
    function($q , $timeout , $filter , egCore) {

        function GridDataProvider(args) {
            var gridData = this;
            if (!args) args = {};

            gridData.sort = [];
            gridData.get = args.get;
            gridData.query = args.query;
            gridData.idlClass = args.idlClass;
            gridData.columnsProvider = args.columnsProvider;
            gridData.comparators = {
                "string":function(x,y){
                        var l_x = x.toLowerCase();
                        var l_y = y.toLowerCase();
                        if (l_x < l_y) return -1;
                        if (l_x > l_y) return 1;
                        return 0;
                    },
                "default":function(x,y){ 
                        if (x < y) return -1;
                        if (x > y) return 1;
                        return 0;
                    }
                };
            // Delivers a stream of array data via promise.notify()
            // Useful for passing an array of data to egGrid.get()
            // If a count is provided, the array will be trimmed to
            // the range defined by count and offset
            gridData.arrayNotifier = function(arr, offset, count) {
                if (!arr || arr.length == 0) return $q.when();

                if (gridData.columnsProvider.clientSort
                    && gridData.sort
                    && gridData.sort.length > 0
                ) {
                    var sorter_cache = [];
                    arr.sort(function(a,b) {
                        for (var si = 0; si < gridData.sort.length; si++) {
                            if (!sorter_cache[si]) { // Build sort structure on first comparison, reuse thereafter
                                var field = gridData.sort[si];
                                var dir = 'asc';

                                if (angular.isObject(field)) {
                                    dir = Object.values(field)[0];
                                    field = Object.keys(field)[0];
                                }

                                var path = gridData.columnsProvider.findColumn(field).path || field;
                                var comparator = gridData.columnsProvider.findColumn(field).comparator;

                                sorter_cache[si] = {
                                    field       : path,
                                    dir         : dir,
                                    comparator  : comparator
                                };
                            }

                            var sc = sorter_cache[si];

                            var af,bf;

                            if (a._isfieldmapper || angular.isFunction(a[sc.field])) {
                                try {af = a[sc.field](); bf = b[sc.field]() } catch (e) {};
                            } else {
                                af = a[sc.field]; bf = b[sc.field];
                            }
                            if (af === undefined && sc.field.indexOf('.') > -1) { // assume an object, not flat path
                                var parts = sc.field.split('.');
                                af = a;
                                bf = b;
                                angular.forEach(parts, function (p) {
                                    if (af) {
                                        if (af._isfieldmapper || angular.isFunction(af[p])) af = af[p]();
                                        else af = af[p];
                                    }
                                    if (bf) {
                                        if (bf._isfieldmapper || angular.isFunction(bf[p])) bf = bf[p]();
                                        else bf = bf[p];
                                    }
                                });
                            }

                            if (af === undefined) af = null;
                            if (bf === undefined) bf = null;

                            if (af === null && bf !== null) return 1;
                            if (bf === null && af !== null) return -1;
                            
                            var comparator =  sc.comparator || (
                            gridData.comparators[typeof af] ? gridData.comparators[typeof af]:gridData.comparators["default"]
                            );

                            if (!(bf === null && af === null)) {
                                var partial = comparator(af,bf);
                                if (partial) {
                                    if (sc.dir == 'desc') {
                                        if (partial > 0) return -1;
                                        return 1;
                                    }
                                    return partial;
                                }
                            }
                        }

                        return 0;
                    });
                }

                if (count) arr = arr.slice(offset, offset + count);
                var def = $q.defer();
                // promise notifications are only witnessed when delivered
                // after the caller has his hands on the promise object
                $timeout(function() {
                    angular.forEach(arr, def.notify);
                    def.resolve();
                });
                return def.promise;
            }

            // Calls the grid refresh function.  Once instantiated, the
            // grid will replace this function with it's own refresh()
            gridData.refresh = function(noReset) { }
            gridData.prepend = function(limit) { }

            if (!gridData.get) {
                // returns a promise whose notify() delivers items
                gridData.get = function(index, count) {
                    console.error("egGridDataProvider.get() not implemented");
                }
            }

            // attempts a flat field lookup first.  If the column is not
            // found on the top-level object, attempts a nested lookup
            // TODO: consider a caching layer to speed up template 
            // rendering, particularly for nested objects?
            gridData.itemFieldValue = function(item, column) {
                var val;
                if (column.name in item) {
                    if (typeof item[column.name] == 'function') {
                        val = item[column.name]();
                    } else {
                        val = item[column.name];
                    }
                } else {
                    val = gridData.nestedItemFieldValue(item, column);
                }

                return val;
            }

            // TODO: deprecate me
            gridData.flatItemFieldValue = function(item, column) {
                console.warn('gridData.flatItemFieldValue deprecated; '
                    + 'leave provider.itemFieldValue unset');
                return item[column.name];
            }

            // given an object and a dot-separated path to a field,
            // extract the value of the field.  The path can refer
            // to function names or object attributes.  If the final
            // value is an IDL field, run the value through its
            // corresponding output filter.
            gridData.nestedItemFieldValue = function(obj, column) {
                item = obj; // keep a copy around

                if (obj === null || obj === undefined || obj === '') return '';
                if (!column.path) return obj;

                var idl_field;
                var parts = column.path.split('.');

                angular.forEach(parts, function(step, idx) {
                    // object is not fleshed to the expected extent
                    if (typeof obj != 'object') {
                        if (typeof obj != 'undefined' && column.flesher) {
                            obj = column.flesher(obj, column, item);
                        } else {
                            obj = '';
                            return;
                        }
                    }

                    if (!obj) return '';

                    var cls = obj.classname;
                    if (cls && (class_obj = egCore.idl.classes[cls])) {
                        idl_field = class_obj.field_map[step];
                        obj = obj[step] ? obj[step]() : '';
                    } else {
                        if (angular.isFunction(obj[step])) {
                            obj = obj[step]();
                        } else {
                            obj = obj[step];
                        }
                    }
                });

                // We found a nested IDL object which may or may not have 
                // been configured as a top-level column.  Grab the datatype.
                if (idl_field && !column.datatype) 
                    column.datatype = idl_field.datatype;

                if (obj === null || obj === undefined || obj === '') return '';
                return obj;
            }
        }

        return {
            instance : function(args) {
                return new GridDataProvider(args);
            }
        };
    }
])


// Factory service for egGridDataManager instances, which are
// responsible for collecting flattened grid data.
.factory('egGridFlatDataProvider', 
           ['$q','egCore','egGridDataProvider',
    function($q , egCore , egGridDataProvider) {

        return {
            instance : function(args) {
                var provider = egGridDataProvider.instance(args);

                provider.get = function(offset, count) {

                    // no query means no call
                    if (!provider.query || 
                            angular.equals(provider.query, {})) 
                        return $q.when();

                    // find all of the currently visible columns
                    var queryFields = {}
                    angular.forEach(provider.columnsProvider.columns, 
                        function(col) {
                            // only query IDL-tracked columns
                            if (!col.adhoc && col.name && col.path && (col.required || col.visible))
                                queryFields[col.name] = col.path;
                        }
                    );

                    return egCore.net.request(
                        'open-ils.fielder',
                        'open-ils.fielder.flattened_search',
                        egCore.auth.token(), provider.idlClass, 
                        queryFields, provider.query,
                        {   sort : provider.sort,
                            limit : count,
                            offset : offset
                        }
                    );
                }
                //provider.itemFieldValue = provider.flatItemFieldValue;
                return provider;
            }
        };
    }
])

.directive('egGridColumnDragSource', function() {
    return {
        restrict : 'A',
        require : '^egGrid',
        link : function(scope, element, attrs, egGridCtrl) {
            angular.element(element).attr('draggable', 'true');

            element.bind('dragstart', function(e) {
                egGridCtrl.dragColumn = attrs.column;
                egGridCtrl.dragType = attrs.dragType || 'move'; // or resize
                egGridCtrl.colResizeDir = 0;

                if (egGridCtrl.dragType == 'move') {
                    // style the column getting moved
                    angular.element(e.target).addClass(
                        'eg-grid-column-move-handle-active');
                }
            });

            element.bind('dragend', function(e) {
                if (egGridCtrl.dragType == 'move') {
                    angular.element(e.target).removeClass(
                        'eg-grid-column-move-handle-active');
                }
            });
        }
    };
})

.directive('egGridColumnDragDest', function() {
    return {
        restrict : 'A',
        require : '^egGrid',
        link : function(scope, element, attrs, egGridCtrl) {

            element.bind('dragover', function(e) { // required for drop
                e.stopPropagation();
                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';

                if (egGridCtrl.colResizeDir == 0) return; // move

                var cols = egGridCtrl.columnsProvider;
                var srcCol = egGridCtrl.dragColumn;
                var srcColIdx = cols.indexOf(srcCol);

                if (egGridCtrl.colResizeDir == -1) {
                    if (cols.indexOf(attrs.column) <= srcColIdx) {
                        egGridCtrl.modifyColumnFlex(
                            egGridCtrl.columnsProvider.findColumn(
                                egGridCtrl.dragColumn), -1);
                        if (cols.columns[srcColIdx+1]) {
                            // source column shrinks by one, column to the
                            // right grows by one.
                            egGridCtrl.modifyColumnFlex(
                                cols.columns[srcColIdx+1], 1);
                        }
                        scope.$apply();
                    }
                } else {
                    if (cols.indexOf(attrs.column) > srcColIdx) {
                        egGridCtrl.modifyColumnFlex( 
                            egGridCtrl.columnsProvider.findColumn(
                                egGridCtrl.dragColumn), 1);
                        if (cols.columns[srcColIdx+1]) {
                            // source column grows by one, column to the 
                            // right grows by one.
                            egGridCtrl.modifyColumnFlex(
                                cols.columns[srcColIdx+1], -1);
                        }

                        scope.$apply();
                    }
                }
            });

            element.bind('dragenter', function(e) {
                e.stopPropagation();
                e.preventDefault();
                if (egGridCtrl.dragType == 'move') {
                    angular.element(e.target).addClass('eg-grid-col-hover');
                } else {
                    // resize grips are on the right side of each column.
                    // dragenter will either occur on the source column 
                    // (dragging left) or the column to the right.
                    if (egGridCtrl.colResizeDir == 0) {
                        if (egGridCtrl.dragColumn == attrs.column) {
                            egGridCtrl.colResizeDir = -1; // west
                        } else {
                            egGridCtrl.colResizeDir = 1; // east
                        }
                    }
                }
            });

            element.bind('dragleave', function(e) {
                e.stopPropagation();
                e.preventDefault();
                if (egGridCtrl.dragType == 'move') {
                    angular.element(e.target).removeClass('eg-grid-col-hover');
                }
            });

            element.bind('drop', function(e) {
                e.stopPropagation();
                e.preventDefault();
                egGridCtrl.colResizeDir = 0;
                if (egGridCtrl.dragType == 'move') {
                    angular.element(e.target).removeClass('eg-grid-col-hover');
                    egGridCtrl.onColumnDrop(attrs.column); // move the column
                }
            });
        }
    };
})
 
.directive('egGridMenuItem', function() {
    return {
        restrict : 'AE',
        require : '^egGrid',
        scope : {
            label : '@',  
            checkbox : '@',  
            checked : '=',  
            standalone : '=',  
            handler : '=', // onclick handler function
            divider : '=', // if true, show a divider only
            handlerData : '=', // if set, passed as second argument to handler
            disabled : '=', // function
            hidden : '=' // function
        },
        link : function(scope, element, attrs, egGridCtrl) {
            egGridCtrl.addMenuItem({
                checkbox : scope.checkbox,
                checked : scope.checked ? true : false,
                label : scope.label,
                standalone : scope.standalone ? true : false,
                handler : scope.handler,
                divider : scope.divider,
                disabled : scope.disabled,
                hidden : scope.hidden,
                handlerData : scope.handlerData
            });
            scope.$destroy();
        }
    };
})

/* https://stackoverflow.com/questions/17343696/adding-an-ng-click-event-inside-a-filter/17344875#17344875 */
.directive('compile', ['$compile', function ($compile) {
    return function(scope, element, attrs) {
      // pass through column defs from grid cell's scope
      scope.col = scope.$parent.col;
      scope.$watch(
        function(scope) {
          // watch the 'compile' expression for changes
          return scope.$eval(attrs.compile);
        },
        function(value) {
          // when the 'compile' expression changes
          // assign it into the current DOM
          element.html(value);

          // compile the new DOM and link it to the current
          // scope.
          // NOTE: we only compile .childNodes so that
          // we don't get into infinite loop compiling ourselves
          $compile(element.contents())(scope);
        }
    );
  };
}])



/**
 * Translates bare IDL object values into display values.
 * 1. Passes dates through the angular date filter
 * 2. Converts bools to translated Yes/No strings
 * Others likely to follow...
 */
.filter('egGridValueFilter', ['$filter','egCore', 'egStrings', function($filter,egCore,egStrings) {
    function traversePath(obj,path) {
        var list = path.split('.');
        for (var part in path) {
            if (obj[path]) obj = obj[path]
            else return null;
        }
        return obj;
    }

    var GVF = function(value, column, item) {
        switch(column.datatype) {
            case 'bool':
                switch(''+value) {
                    case 't' : 
                    case '1' :  // legacy
                    case 'true':
                        return egStrings.YES;
                    case 'f' : 
                    case '0' :  // legacy
                    case 'false':
                        return egStrings.NO;
                    // value may be null,  '', etc.
                    default : return '';
                }
            case 'timestamp':
                var interval = angular.isFunction(item[column.dateonlyinterval])
                    ? item[column.dateonlyinterval]()
                    : item[column.dateonlyinterval];

                if (column.dateonlyinterval && !interval) // try it as a dotted path
                    interval = traversePath(item, column.dateonlyinterval);

                var context = angular.isFunction(item[column.datecontext])
                    ? item[column.datecontext]()
                    : item[column.datecontext];

                if (column.datecontext && !context) // try it as a dotted path
                    context = traversePath(item, column.datecontext);

                var date_filter = column.datefilter || 'egOrgDateInContext';

                return $filter(date_filter)(value, column.dateformat, context, interval);
            case 'money':
                return $filter('currency')(value);
            default:
                return value;
        }
    };

    GVF.$stateful = true;
    return GVF;
}]);

