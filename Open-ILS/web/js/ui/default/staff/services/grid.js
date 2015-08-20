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

            // optional primary grid label
            mainLabel : '@',

            // if true, use the IDL class label as the mainLabel
            autoLabel : '=', 

            // optional context menu label
            menuLabel : '@',

            // Hash of control functions.
            //
            //  These functions are defined by the calling scope and 
            //  invoked as-is by the grid w/ the specified parameters.
            //
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
            // link() is called after page compilation, which means our
            // eg-grid-field's have been parsed and loaded.  Now it's 
            // safe to perform our initial page load.

            // load auto fields after eg-grid-field's so they are not clobbered
            scope.handleAutoFields();
            scope.collect();

            scope.grid_element = element;
            $(element)
                .find('.eg-grid-content-body')
                .bind('contextmenu', scope.showActionContextMenu);
        },

        controller : [
                    '$scope','$q','egCore','egGridFlatDataProvider','$location',
                    'egGridColumnsProvider','$filter','$window','$sce','$timeout',
            function($scope,  $q , egCore,  egGridFlatDataProvider , $location,
                     egGridColumnsProvider , $filter , $window , $sce , $timeout) {

            var grid = this;

            grid.init = function() {
                grid.offset = 0;
                $scope.items = [];
                $scope.showGridConf = false;
                grid.totalCount = -1;
                $scope.selected = {};
                $scope.actionGroups = [{actions:[]}]; // Grouped actions for selected items
                $scope.menuItems = []; // global actions

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
                    defaultToHidden : (features.indexOf('-display') > -1),
                    defaultToNoSort : (features.indexOf('-sort') > -1),
                    defaultToNoMultiSort : (features.indexOf('-multisort') > -1)
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

                $scope.itemFieldValue = grid.dataProvider.itemFieldValue;
                $scope.indexValue = function(item) {
                    return grid.indexValue(item)
                };

                grid.applyControlFunctions();

                grid.loadConfig().then(function() { 
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

                // link in the control functions
                controls.selectedItems = function() {
                    return grid.getSelectedItems()
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

                controls.setLimit = function(limit,forget) {
                    if (!forget && grid.persistKey)
                        egCore.hatch.setLocalItem('eg.grid.' + grid.persistKey + '.limit', limit);
                    grid.limit = limit;
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
                var conf = grid.columnsProvider.columns.filter(
                    function(col) {return Boolean(col.visible) });

                // now scrunch the data down to just the needed info
                conf = conf.map(function(col) {
                    var c = {name : col.name}
                    // Apart from the name, only store non-default values.
                    // No need to store col.visible, since that's implicit
                    if (col.align != 'left') c.align = col.align;
                    if (col.flex != 2) c.flex = col.flex;
                    if (Number(col.sort)) c.sort = Number(c.sort);
                    return c;
                });

                egCore.hatch.setItem('eg.grid.' + grid.persistKey, conf)
                .then(function() { 
                    // Save operation performed from the grid configuration UI.
                    // Hide the configuration UI and re-draw w/ sort applied
                    if ($scope.showGridConf) 
                        $scope.toggleConfDisplay();
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

                    var columns = grid.columnsProvider.columns;
                    var new_cols = [];

                    angular.forEach(conf, function(col) {
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
                        var found = conf.filter(
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
                    if (grid.persistKey)
                        egCore.hatch.setLocalItem('eg.grid.' + grid.persistKey + '.limit', l);
                    grid.limit = l;
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

                if (!grid.getSelectedItems().length) // Nothing selected, fire the click event
                    $event.target.click();

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

            $scope.updateSelected = function () { 
                    return $scope.selected = angular.copy($scope.selected);
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
                grid.modifyColumnFlex(col, val);
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

            // sets the download file name and inserts the current CSV
            // into a Blob URL for browser download.
            $scope.generateCSVExportURL = function() {
                $scope.gridColumnPickerIsOpen = false;

                // let the file name describe the grid
                $scope.csvExportFileName = 
                    ($scope.mainLabel || grid.persistKey || 'eg_grid_data')
                    .replace(/\s+/g, '_') + '_' + $scope.page();

                // toss the CSV into a Blob and update the export URL
                var csv = grid.generateCSV();
                var blob = new Blob([csv], {type : 'text/plain'});
                $scope.csvExportURL = 
                    ($window.URL || $window.webkitURL).createObjectURL(blob);
            }

            $scope.printCSV = function() {
                $scope.gridColumnPickerIsOpen = false;
                egCore.print.print({
                    context : 'default', 
                    content : grid.generateCSV(),
                    content_type : 'text/plain'
                });
            }

            // generates CSV for the currently visible grid contents
            grid.generateCSV = function() {
                var csvStr = '';
                var colCount = grid.columnsProvider.columns.length;

                // columns
                angular.forEach(grid.columnsProvider.columns,
                    function(col) {
                        if (!col.visible) return;
                        csvStr += grid.csvDatum(col.label);
                        csvStr += ',';
                    }
                );

                csvStr = csvStr.replace(/,$/,'\n');

                // items
                angular.forEach($scope.items, function(item) {
                    angular.forEach(grid.columnsProvider.columns, 
                        function(col) {
                            if (!col.visible) return;
                            // bare value
                            var val = grid.dataProvider.itemFieldValue(item, col);
                            // filtered value (dates, etc.)
                            val = $filter('egGridValueFilter')(val, col);
                            csvStr += grid.csvDatum(val);
                            csvStr += ',';
                        }
                    );
                    csvStr = csvStr.replace(/,$/,'\n');
                });

                return csvStr;
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
            name  : '@', // required; unique name
            path  : '@', // optional; flesh path
            ignore: '@', // optional; fields to ignore when path is a wildcard
            label : '@', // optional; display label
            flex  : '@',  // optional; default flex width
            align  : '@',  // optional; default alignment, left/center/right
            dateformat : '@', // optional: passed down to egGridValueFilter

            // if a field is part of an IDL object, but we are unable to
            // determine the class, because it's nested within a hash
            // (i.e. we can't navigate directly to the object via the IDL),
            // idlClass lets us specify the class.  This is particularly
            // useful for nested wildcard fields.
            parentIdlClass : '@', 

            // optional: for non-IDL columns, specifying a datatype
            // lets the caller control which display filter is used.
            // datatype should match the standard IDL datatypes.
            datatype : '@'
        },
        link : function(scope, element, attrs, egGridCtrl) {

            // boolean fields are presented as value-less attributes
            angular.forEach(
                [
                    'visible', 
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
        cols.defaultToHidden = args.defaultToHidden;
        cols.defaultToNoSort = args.defaultToNoSort;
        cols.defaultToNoMultiSort = args.defaultToNoMultiSort;

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
                idl_class.fields.sort(
                    function(a, b) { return a.name < b.name ? -1 : 1 }),
                function(field) {
                    if (field.virtual) return;
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

            if (!class_obj) return;

            console.debug('egGrid: auto dotpath is: ' + dotpath);
            var path_parts = dotpath.split(/\./);

            // find the IDL class definition for the last element in the
            // path before the .*
            // an empty path_parts means expand the root class
            if (path_parts) {
                for (var path_idx in path_parts) {
                    var part = path_parts[path_idx];
                    idl_field = class_obj.field_map[part];

                    // unless we're at the end of the list, this field should
                    // link to another class.
                    if (idl_field && idl_field['class'] && (
                        idl_field.datatype == 'link' || 
                        idl_field.datatype == 'org_unit')) {
                        class_obj = egCore.idl.classes[idl_field['class']];
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
                    // console.debug('egGrid: field: ' +field.name + '; parent field: ' + js2JSON(idl_field));
                    cols.add(col, false, true, 
                        {idl_parent : idl_field, idl_field : field, idl_class : class_obj});
                });

                cols.columns = cols.columns.sort(
                    function(a, b) {
                        if (a.explicit) return -1;
                        if (b.explicit) return 1;
                        if (a.idlclass && b.idlclass) {
                            return a.idlclass < b.idlclass ? -1 : 1;
                            return a.idlclass > b.idlclass ? 1 : -1;
                        }
                        if (a.path && b.path) {
                            return a.path < b.path ? -1 : 1;
                            return a.path > b.path ? 1 : -1;
                        }

                        return a.label < b.label ? -1 : 1;
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
                hidden   : colSpec.hidden,
                datatype : colSpec.datatype,
                sortable : colSpec.sortable,
                nonsortable      : colSpec.nonsortable,
                multisortable    : colSpec.multisortable,
                nonmultisortable : colSpec.nonmultisortable,
                dateformat       : colSpec.dateformat,
                parentIdlClass   : colSpec.parentIdlClass
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
                if (idl_info.idl_parent) {
                    column.idlclass = idl_info.idl_parent.label || idl_info.idl_parent.name;
                } else {
                    column.idlclass += idl_info.idl_class.label || idl_info.idl_class.name;
                }
            }
        },

        // finds the IDL field from the dotpath, using the columns
        // idlClass as the base.
        cols.idlFieldFromPath = function(dotpath) {
            var class_obj = egCore.idl.classes[cols.idlClass];
            var path_parts = dotpath.split(/\./);

            var idl_parent;
            var idl_field;
            for (var path_idx in path_parts) {
                var part = path_parts[path_idx];
                idl_parent = idl_field;
                idl_field = class_obj.field_map[part];

                if (idl_field && idl_field['class'] && (
                    idl_field.datatype == 'link' || 
                    idl_field.datatype == 'org_unit')) {
                    class_obj = egCore.idl.classes[idl_field['class']];
                }
                // else, path is not in the IDL, which is fine
            }

            if (!idl_field) return null;

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

            // Delivers a stream of array data via promise.notify()
            // Useful for passing an array of data to egGrid.get()
            // If a count is provided, the array will be trimmed to
            // the range defined by count and offset
            gridData.arrayNotifier = function(arr, offset, count) {
                if (!arr || arr.length == 0) return $q.when();
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
                            if (!col.adhoc && (col.required || col.visible))
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



/**
 * Translates bare IDL object values into display values.
 * 1. Passes dates through the angular date filter
 * 2. Translates bools to Booleans so the browser can display translated 
 *    value.  (Though we could manually translate instead..)
 * Others likely to follow...
 */
.filter('egGridValueFilter', ['$filter', function($filter) {                         
    return function(value, column) {                                             
        switch(column.datatype) {                                                
            case 'bool':                                                       
                switch(value) {
                    // Browser will translate true/false for us                    
                    case 't' : 
                    case '1' :  // legacy
                    case true:
                        return ''+true;
                    case 'f' : 
                    case '0' :  // legacy
                    case false:
                        return ''+false;
                    // value may be null,  '', etc.
                    default : return '';
                }
            case 'timestamp':                                                  
                // canned angular date filter FTW                              
                if (!column.dateformat) 
                    column.dateformat = 'shortDate';
                return $filter('date')(value, column.dateformat);
            case 'money':                                                  
                return $filter('currency')(value);
            default:                                                           
                return value;                                                  
        }                                                                      
    }                                                                          
}]);

