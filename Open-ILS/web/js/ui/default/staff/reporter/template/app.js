/*
 * Report template builder
 */

angular.module('egReporter',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod', 'egReportMod', 'treeControl', 'ngToast'])

.config(['ngToastProvider', function(ngToastProvider) {
  ngToastProvider.configure({
    verticalPosition: 'bottom',
    animation: 'fade'
  });
}])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export
	
    var resolver = {delay : function(egStartup) {return egStartup.go()}};

    $routeProvider.when('/reporter/template/clone/:folder/:id', {
        templateUrl: './reporter/t_edit_template',
        controller: 'ReporterTemplateEdit',
        resolve : resolver
    });

    $routeProvider.when('/reporter/legacy/template/clone/:folder/:id', {
        templateUrl: './reporter/t_legacy',
        controller: 'ReporterTemplateLegacy',
        resolve : resolver
    });

    $routeProvider.when('/reporter/template/new/:folder', {
        templateUrl: './reporter/t_edit_template',
        controller: 'ReporterTemplateEdit',
        resolve : resolver
    });

    $routeProvider.when('/reporter/legacy/main', {
        templateUrl: './reporter/t_legacy',
        controller: 'ReporterTemplateLegacy',
        resolve : resolver
    });

    // default page
    $routeProvider.otherwise({redirectTo : '/reporter/legacy/main'});
})

/**
 * controller for legacy template stuff
 */
.controller('ReporterTemplateLegacy',
       ['$scope','$routeParams','$location','egCore',
function($scope , $routeParams , $location , egCore) {

    var template_id = $routeParams.id;
    var folder_id = $routeParams.folder;

    $scope.rurl = '/reports/oils_rpt.xhtml?ses=' + egCore.auth.token();

    if (folder_id) {
        $scope.rurl = '/reports/oils_rpt_builder.xhtml?ses=' +
                        egCore.auth.token() + '&folder=' + folder_id;

        if (template_id) $scope.rurl += '&ct=' + template_id;
    }

}])

/**
 * Uber-controller for template editing
 */
.controller('ReporterTemplateEdit',
       ['$scope','$q','$routeParams','$location','$timeout','$window','egCore','$uibModal','egPromptDialog',
        'egGridDataProvider','egReportTemplateSvc','$uibModal','egConfirmDialog','egSelectDialog','ngToast',
function($scope , $q , $routeParams , $location , $timeout , $window,  egCore , $uibModal , egPromptDialog ,
         egGridDataProvider , egReportTemplateSvc , $uibModal , egConfirmDialog , egSelectDialog , ngToast) {

    function values(o) { return Object.keys(o).map(function(k){return o[k]}) };

    var template_id = $routeParams.id;
    var folder_id = $routeParams.folder;

    $scope.grid_display_fields_provider = egGridDataProvider.instance({
        get : function (offset, count) {
            return this.arrayNotifier(egReportTemplateSvc.display_fields, offset, count);
        }
    });
    $scope.grid_filter_fields_provider = egGridDataProvider.instance({
        get : function (offset, count) {
            return this.arrayNotifier(egReportTemplateSvc.filter_fields, offset, count);
        }
    });

    var dgrid = $scope.display_grid_controls = {};
    var fgrid = $scope.filter_grid_controls = {};

    var default_filter_obj = {
        op : '=',
        label     : egReportTemplateSvc.Filters['='].label
    };

    var default_transform_obj = {
        transform : 'Bare',
        label     : egReportTemplateSvc.Transforms.Bare.label,
        aggregate : false
    };

    function mergePaths (items) {
        var tree = {};

        items.forEach(function (item) {
            var t = tree;
            var join_path = '';

            var last_jtype = '';
            item.path.forEach(function (p, i, a) {
                var alias; // unpredictable hashes are fine for intermediate tables

                if (i) { // not at the top of the tree
                    if (i == 1) join_path = join_path.split('-')[0];

                    // SQLBuilder relies on the first dash-separated component
                    // of the join key to specify the column of left-hand relation
                    // to join on; for has_many and might_have link types, we have to grab the
                    // primary key of the left-hand table; otherwise, we can
                    // just use the field/column name found in p.uplink.name.
                    var uplink = (p.uplink.reltype == 'has_many' || p.uplink.reltype == 'might_have') ?
                        egCore.idl.classes[p.from.split('.').slice(-1)[0]].pkey + '-' + p.uplink.name :
                        p.uplink.name;
                    join_path += '-' + uplink;
                    alias = hex_md5(join_path);

                    var uplink_alias = uplink + '-' + alias;

                    if (!t.join) t.join = {};
                    if (!t.join[uplink_alias]) t.join[uplink_alias] = {};

                    t = t.join[uplink_alias];

                    var djtype = 'inner';
                    // we use LEFT JOINs for might_have and has_many, AND
                    // also if our previous JOIN was a LEFT JOIN
                    //
                    // The last piece prevents later joins from limiting those
                    // closer to the core table
                    if (p.uplink.reltype != 'has_a' || last_jtype == 'left') djtype = 'left';

                    t.type = p.jtype || djtype;
                    last_jtype = t.type;
                    t.key = p.uplink.key;
                } else {
                    join_path = p.classname + '-' + p.classname;
                    alias = hex_md5(join_path);
                }

                if (!t.alias) t.alias = alias;
                t.path = join_path;

                t.table = p.struct.source ? p.struct.source : p.table;
                t.idlclass = p.classname;

                if (a.length == i + 1) { // end of the path array, need a predictable hash
                    t.label = item.path_label;
                    t.alias = hex_md5(item.path_label);
                }

            });
        });

        return tree;
    };
    // expose for testing
    $scope._mergePaths = mergePaths;

    $scope.constructTemplate = function () {
        var param_counter = 0;
        return {
            version     : 5,
            doc_url     : $scope.templateDocURL,
            core_class  : egCore.idl.classTree.top.classname,
            select      : dgrid.allItems().map(function (i) {
                            return {
                                alias     : i.label,
                                path      : i.path[i.path.length - 1].classname + '-' + i.name,
                                field_doc : i.doc_text,
                                relation  : hex_md5(i.path_label),
                                column    : {
                                    colname         : i.name,
                                    transform       : i.transform ? i.transform.transform : '',
                                    transform_label : i.transform ? i.transform.label : '',
                                    aggregate       : !!i.transform.aggregate
                                }
                            }
                          }),
            from        : mergePaths( dgrid.allItems().concat(fgrid.allItems()) ),
            where       : fgrid.allItems().filter(function(i) {
                            return !i.transform.aggregate;
                          }).map(function (i) {
                            var cond = {};
                            if (
                                i.operator.op == 'is' ||
                                i.operator.op == 'is not' ||
                                i.operator.op == 'is blank' ||
                                i.operator.op == 'is not blank'
                            ) {
                                cond[i.operator.op] = null;
                            } else {
                                if (i.value === undefined) {
                                    cond[i.operator.op] = '::P' + param_counter++;
                                }else {
                                    cond[i.operator.op] = i.value;
                                }
                            }
                            return {
                                alias     : i.label,
                                path      : i.path[i.path.length - 1].classname + '-' + i.name,
                                field_doc : i.doc_text,
                                relation  : hex_md5(i.path_label),
                                column    : {
                                    colname         : i.name,
                                    transform       : i.transform.transform,
                                    transform_label : i.transform.label,
                                    aggregate       : 0
                                },
                                condition : cond // constructed above
                            }
                          }),
            having      : fgrid.allItems().filter(function(i) {
                            return !!i.transform.aggregate;
                          }).map(function (i) {
                            var cond = {};
                            if (i.value === undefined) {
                                cond[i.operator.op] = '::P' + param_counter++;
                            }else {
                                cond[i.operator.op] = i.value;
                            }
                            return {
                                alias     : i.label,
                                path      : i.path[i.path.length - 1].classname + '-' + i.name,
                                field_doc : i.doc_text,
                                relation  : hex_md5(i.path_label),
                                column    : {
                                    colname         : i.name,
                                    transform       : i.transform.transform,
                                    transform_label : i.transform.label,
                                    aggregate       : 1
                                },
                                condition : cond // constructed above
                            }
                          }),
            display_cols: angular.copy( dgrid.allItems() ).map(strip_item),
            filter_cols : angular.copy( fgrid.allItems() ).map(strip_item)
        };

        function strip_item (i) {
            delete i.children;
            i.path.forEach(function(p){
                delete p.children;
                delete p.fields;
                delete p.links;
                delete p.struct.permacrud;
                delete p.struct.field_map;
                delete p.struct.fields;
            });
            return i;
        }

    }

    $scope.upgradeTemplate = function(template) {
        template.name(template.name() + ' (converted from XUL)');
        template.data.version = 5;

        var order_by;
        var rels = [];
        for (var key in template.data.rel_cache) {
            if (key == 'order_by') {
                order_by = template.data.rel_cache[key];
            } else {
                rels.push(template.data.rel_cache[key]);
            }
        }

        // preserve the old select order for the display cols
        var sel_order = {};
        template.data.select.map(function(val, idx) {
            // set key to unique value easily derived from relcache
            sel_order[val.relation + val.column.colname] = idx;
        });

        template.data['display_cols'] = [];
        template.data['filter_cols'] = [];

        function _convertPath(orig, rel) {
            var newPath = [];

            var table_path = rel.path.split(/\./);
            if (table_path.length > 1 || rel.path.indexOf('-') > -1) table_path.push( rel.idlclass );

            var prev_type = '';
            var prev_link = '';
            table_path.forEach(function(link) {
                var cls = link.split(/-/)[0];
                var fld = link.split(/-/)[1];
                var args = {
                    label : egCore.idl.classes[cls].label
                }
                if (prev_link != '') {
                    var link_parts = prev_link.split(/-/);
                    args['from'] = link_parts[0];
                    var join_parts = link_parts[1].split(/>/);
                    var prev_col = join_parts[0];
                    egCore.idl.classes[prev_link.split(/-/)[0]].fields.forEach(function(f) {
                        if (prev_col == f.name) {
                            args['link'] = f;
                        }
                    });
                    args['jtype'] = join_parts[1]; // frequently undefined
                }
                newPath.push(egCore.idl.classTree.buildNode(cls, args));
                prev_link = link;
            });
            return newPath;

        }

        function _buildCols(rel, tab_type, col_idx) {
            if (tab_type == 'dis_tab') {
                col_type = 'display_cols';
            } else {
                col_type = 'filter_cols';
            }

            for (var col in rel.fields[tab_type]) {
                var orig = rel.fields[tab_type][col];
                var col = {
                    name        : orig.colname,
                    path        : _convertPath(orig, rel),
                    label       : orig.alias,
                    datatype    : orig.datatype,
                    doc_text    : orig.field_doc,
                    transform   : {
                                    label     : orig.transform_label,
                                    transform : orig.transform,
                                    aggregate : (orig.aggregate == "undefined") ? undefined : orig.aggregate  // old structure sometimes has undefined as a quoted string
                                  },
                    path_label  : rel.label.replace('::', '->')
                };
                if (col_type == 'filter_cols') {
                    col['operator'] = {
                        op        : orig.op,
                        label     : orig.op_label
                    };
                    col['index'] = col_idx++;
                    if ('value' in orig.op_value) {
                        col['value'] = orig.op_value.value;
                    }
                } else { // display
                    col['index'] = sel_order[rel.alias + orig.colname];
                }

                template.data[col_type].push(col);
            }
        }

        rels.map(function(rel) {
            _buildCols(rel, 'dis_tab');
            _buildCols(rel, 'filter_tab', template.data.filter_cols.length);
            _buildCols(rel, 'aggfilter_tab', template.data.filter_cols.length);
        });

        template.data['display_cols'].sort(function(a, b){return a.index - b.index});
    }

    function loadTemplate () {
        if (!template_id) return;
        egCore.pcrud.retrieve( 'rt', template_id)
        .then( function(template) {
            template.data = angular.fromJson(template.data());
            if (template.data.version < 5) {
                $scope.upgradeTemplate(template);
            }

            $scope.templateName = template.name() + ' (clone)';
            $scope.templateDescription = template.description();
            $scope.templateDocURL = template.data.doc_url;

            $scope.changeCoreSource( template.data.core_class );

            egReportTemplateSvc.display_fields = template.data.display_cols;
            egReportTemplateSvc.filter_fields = template.data.filter_cols;

            $timeout(function(){
                dgrid.refresh();
                fgrid.refresh();
            });
        });

    }

    $scope.saveTemplate = function () {
        var tmpl = new egCore.idl.rt();
        tmpl.name( $scope.templateName );
        tmpl.description( $scope.templateDescription );
        tmpl.owner(egCore.auth.user().id());
        tmpl.folder(folder_id);
        tmpl.data(angular.toJson($scope.constructTemplate()));

        egConfirmDialog.open(tmpl.name(), egCore.strings.TEMPLATE_CONF_CONFIRM_SAVE,
            {ok : function() {
                return egCore.pcrud.create( tmpl )
                .then(
                    function() {
                        ngToast.create(egCore.strings.TEMPLATE_CONF_SUCCESS_SAVE);
                        return $timeout(
                            function(){
                                $window.location.href = egCore.env.basePath + 'reporter/legacy/main';
                            },
                            1000
                        );
                    },
                    function() {
                        ngToast.warning(egCore.strings.TEMPLATE_CONF_FAIL_SAVE);
                    }
                );
            }}
        );
    }

    $scope.addDisplayFields = function () {
        var t = $scope.selected_transform;
        if (!t) t = default_transform_obj;

        egReportTemplateSvc.addFields(
            'display_fields',
            $scope.selected_source_field_list, 
            t,
            $scope.currentPathLabel,
            $scope.currentPath
        );
        $scope.selected_transform = null;
        dgrid.refresh();
    }

    $scope.addFilterFields = function () {
        var t = $scope.selected_transform;
        if (!t) t = default_transform_obj;
        f = default_filter_obj;

        egReportTemplateSvc.addFields(
            'filter_fields',
            $scope.selected_source_field_list, 
            t,
            $scope.currentPathLabel,
            $scope.currentPath,
            f
        );
        $scope.selected_transform = null;
        fgrid.refresh();
    }

    $scope.moveDisplayFieldUp = function (items) {
        items.reverse().forEach(function(item) {
            egReportTemplateSvc.moveFieldUp('display_fields', item);
        });
        dgrid.refresh();
    }

    $scope.moveDisplayFieldDown = function (items) {
        items.forEach(function(item) {
            egReportTemplateSvc.moveFieldDown('display_fields', item);
        });
        dgrid.refresh();
    }

    $scope.removeDisplayField = function (items) {
        items.forEach(function(item) {egReportTemplateSvc.removeField('display_fields', item)});
        dgrid.refresh();
    }

    $scope.changeDisplayLabel = function (items) {
        items.forEach(function(item) {
            egPromptDialog.open(egCore.strings.TEMPLATE_CONF_PROMPT_CHANGE, item.label || '',
                {ok : function(value) {
                    if (value) egReportTemplateSvc.display_fields[item.index].label = value;
                }}
            );
        });
        dgrid.refresh();
    }

    $scope.changeDisplayFieldDoc = function (items) {
        items.forEach(function(item) {
            egPromptDialog.open(egCore.strings.TEMPLATE_FIELD_DOC_PROMPT_CHANGE, item.doc_text || '',
                {ok : function(value) {
                    if (value) egReportTemplateSvc.display_fields[item.index].doc_text = value;
                }}
            );
        });
        dgrid.refresh();
    }

    $scope.changeFilterFieldDoc = function (items) {
        items.forEach(function(item) {
            egPromptDialog.open(egCore.strings.TEMPLATE_FIELD_DOC_PROMPT_CHANGE, item.doc_text || '',
                {ok : function(value) {
                    if (value) egReportTemplateSvc.filter_fields[item.index].doc_text = value;
                }}
            );
        });
        fgrid.refresh();
    }

    $scope.changeFilterValue = function (items) {
        items.forEach(function(item) {
            var l = null;
            if (item.datatype == "bool") {
                var displayVal = typeof item.value === "undefined" ? egCore.strings.TEMPLATE_CONF_UNSET :
                                 item.value === 't'                ? egCore.strings.TEMPLATE_CONF_TRUE :
                                 item.value === 'f'                ? egCore.strings.TEMPLATE_CONF_FALSE :
                                 item.value.toString();
                egConfirmDialog.open(egCore.strings.TEMPLATE_CONF_DEFAULT, displayVal,
                    {ok : function() {
                        egReportTemplateSvc.filter_fields[item.index].value = 't';
                    },
                    cancel : function() {
                        egReportTemplateSvc.filter_fields[item.index].value = 'f';
                    }}, egCore.strings.TEMPLATE_CONF_TRUE, egCore.strings.TEMPLATE_CONF_FALSE
                );
            } else {
                egPromptDialog.open(egCore.strings.TEMPLATE_CONF_DEFAULT, item.value || '',
                    {ok : function(value) {
                        if (value) egReportTemplateSvc.updateFilterValue(item, value);
                    }}
                );
            }
        });
        fgrid.refresh();
    }

    $scope.changeTransform = function (items) {

        var f = items[0];

        var tlist = [];
        angular.forEach(egReportTemplateSvc.Transforms, function (o,n) {
            if ( o.datatype.indexOf(f.datatype) > -1) {
                if (tlist.indexOf(o.label) == -1) tlist.push( o.label );
            }
        });
        
        items.forEach(function(item) {
            egSelectDialog.open(
                egCore.strings.SELECT_TFORM, tlist, item.transform.label,
                {ok : function(value) {
                    if (value) {
                        var t = egReportTemplateSvc.getTransformByLabel(value);
                        item.transform = {
                            label     : value,
                            transform : t,
                            aggregate : egReportTemplateSvc.Transforms[t].aggregate ? true : false
                        };
                    }
                }}
            );
        });

        fgrid.refresh();
    }

    $scope.changeOperator = function (items) {

        var flist = [];
        Object.keys(egReportTemplateSvc.Filters).forEach(function(k){
            var v = egReportTemplateSvc.Filters[k];
            if (flist.indexOf(v.label) == -1) flist.push(v.label);
            if (v.labels && v.labels.length > 0) {
                v.labels.forEach(function(l) {
                    if (flist.indexOf(l) == -1) flist.push(l);
                })
            }
        });

        items.forEach(function(item) {
            var l = item.operator ? item.operator.label : '';
            egSelectDialog.open(
                egCore.strings.SELECT_OP, flist, l,
                {ok : function(value) {
                    if (value) {
                        var t = egReportTemplateSvc.getFilterByLabel(value);
                        item.operator = { label: value, op : t };

                        //Update the filter value based on the new operator, because
                        //  different operators treat the value differently
                        egReportTemplateSvc.updateFilterValue(item, egReportTemplateSvc.filter_fields[item.index].value);
                    }
                }}
            );
        });

        fgrid.refresh();
    }

    $scope.removeFilterValue = function (items) {
        items.forEach(function(item) {delete egReportTemplateSvc.filter_fields[item.index].value});
        fgrid.refresh();
    }

    $scope.removeFilterField = function (items) {
        items.forEach(function(item) {egReportTemplateSvc.removeField('filter_fields', item)});
        fgrid.refresh();
    }

    $scope.allSources = values(egCore.idl.classes).sort( function(a,b) {
        if (a.core && !b.core) return -1;
        if (b.core && !a.core) return 1;
        aname = a.label ? a.label : a.name;
        bname = b.label ? b.label : b.name;
        if (aname > bname) return 1;
        return -1;
    });

    $scope.class_tree = [];
    $scope.selected_source = null;
    $scope.selected_source_fields = [];
    $scope.selected_source_field_list = [];
    $scope.available_field_transforms = [];
    $scope.coreSource = null;
    $scope.coreSourceChosen = false;
    $scope.currentPathLabel = '';

    $scope.treeExpand = function (node, expanding) {
        if (expanding) node.children.map(egCore.idl.classTree.fleshNode);
    }

    $scope.filterFields = function (n) {
        return n.virtual ? false : true;
        // should we hide links?
        return n.datatype && n.datatype != 'link'
    }

    $scope.field_tree_opts = {
        multiSelection: true,
        equality      : function(node1, node2) {
            return node1.name == node2.name;
        }
    }

    $scope.field_transforms_tree_opts = {
        equality : function(node1, node2) {
            if (!node2) return false;
            return node1.transform == node2.transform;
        }
    }

    $scope.selectFields = function () {
        while ($scope.available_field_transforms.length) {
            $scope.available_field_transforms.pop();
        }

        angular.forEach( $scope.selected_source_field_list, function (f) {
            angular.forEach(egReportTemplateSvc.Transforms, function (o,n) {
                if ( o.datatype.indexOf(f.datatype) > -1) {
                    var include = true;

                    angular.forEach($scope.available_field_transforms, function (t) {
                        if (t.transform == n) include = false;
                    });

                    if (include) $scope.available_field_transforms.push({
                        transform : n,
                        label     : o.label,
                        aggregate : o.aggregate ? true : false
                    });
                }
            });
        });

    }

    $scope.selectSource = function (node, selected, $path) {

        while ($scope.selected_source_field_list.length) {
            $scope.selected_source_field_list.pop();
        }
        while ($scope.selected_source_fields.length) {
            $scope.selected_source_fields.pop();
        }

        if (selected) {
            $scope.currentPath = angular.copy( $path().reverse() );
            $scope.selected_source = node;
            $scope.currentPathLabel = $scope.currentPath.map(function(n,i){
                var l = n.label
                if (i && n.jtype) l += ' (' + n.jtype + ')';
                return l;
            }).join( ' -> ' );
            angular.forEach( node.fields, function (f) {
                $scope.selected_source_fields.push( f );
            });
        } else {
            $scope.currentPathLabel = '';
        }

        // console.log($scope.selected_source);
    }

    $scope.changeCoreSource = function (new_core) {
        console.log('changeCoreSource: '+new_core);
        function change_core () {
            if (new_core) $scope.coreSource = new_core;
            $scope.coreSourceChosen = true;

            $scope.class_tree.pop();
            $scope.class_tree.push(
                egCore.idl.classTree.setTop($scope.coreSource)
            );

            while ($scope.selected_source_fields.length) {
                $scope.selected_source_fields.pop();
            }

            while ($scope.available_field_transforms.length) {
                $scope.available_field_transforms.pop();
            }

            $scope.currentPathLabel = '';
        }

        if ($scope.coreSourceChosen) {
            egConfirmDialog.open(
                egCore.strings.FOLDERS_TEMPLATE,
                egCore.strings.SOURCE_SETUP_CONFIRM_EXIT,
                {ok : change_core}
            );
        } else {
            change_core();
        }
    }

    loadTemplate();
}])

;
