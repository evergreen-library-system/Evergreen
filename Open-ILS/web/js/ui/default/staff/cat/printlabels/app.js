/**
 * Vol/Copy Editor
 */

angular.module('egPrintLabels',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function ($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|mailto|blob):/); // grid export

    var resolver = {
        delay: ['egStartup', function (egStartup) { return egStartup.go(); }]
    };

    $routeProvider.when('/cat/printlabels/:dataKey', {
        templateUrl: './cat/printlabels/t_view',
        controller: 'LabelCtrl',
        resolve: resolver
    });

})

.factory('itemSvc',
       ['egCore',
function (egCore) {

    var service = {
        copies: [], // copy barcode search results
        index: 0 // search grid index
    };

    service.flesh = {
        flesh: 3,
        flesh_fields: {
            acp: ['call_number', 'location', 'status', 'location', 'floating', 'circ_modifier', 'age_protect', 'circ_lib'],
            acn: ['record', 'prefix', 'suffix', 'owning_lib'],
            bre: ['simple_record', 'creator', 'editor']
        },
        select: {
            // avoid fleshing MARC on the bre
            // note: don't add simple_record.. not sure why
            bre: ['id', 'tcn_value', 'creator', 'editor'],
        }
    }

    // resolved with the last received copy
    service.fetch = function (barcode, id, noListDupes) {
        var promise;

        if (barcode) {
            promise = egCore.pcrud.search('acp',
                { barcode: barcode, deleted: 'f' }, service.flesh);
        } else {
            promise = egCore.pcrud.retrieve('acp', id, service.flesh);
        }

        var lastRes;
        return promise.then(
            function () { return lastRes },
            null, // error

            // notify reads the stream of copies, one at a time.
            function (copy) {

                var flatCopy;
                if (noListDupes) {
                    // use the existing copy if possible
                    flatCopy = service.copies.filter(
                        function (c) { return c.id == copy.id() })[0];
                }

                if (!flatCopy) {
                    flatCopy = egCore.idl.toHash(copy, true);
                    flatCopy.index = service.index++;
                    service.copies.unshift(flatCopy);
                }

                return lastRes = {
                    copy: copy,
                    index: flatCopy.index
                }
            }
        );
    }

    return service;
}])

/**
 * Label controller!
 */
.controller('LabelCtrl',
       ['$scope', '$q', '$window', '$routeParams', '$location', '$timeout', 'egCore', 'egNet', 'ngToast', 'itemSvc', 'labelOutputRowsFilter',
function ($scope, $q, $window, $routeParams, $location, $timeout, egCore, egNet, ngToast, itemSvc, labelOutputRowsFilter) {

    var dataKey = $routeParams.dataKey;
    console.debug('dataKey: ' + dataKey);

    $scope.print = {
        template_name: 'item_label',
        template_output: '',
        template_context: 'default'
    };

    var toolbox_settings = {
        feed_option: {
            options: [
                { label: "Continuous", value: "continuous" },
                { label: "Sheet", value: "sheet" },
            ],
            selected: "continuous"
        },
        label_set: {
            margin_between: 0,
            size: 1
        },
        mode: {
            options: [
                { label: "Spine Label", value: "spine-only" },
                { label: "Pocket Label", value: "spine-pocket" }
            ],
            selected: "spine-pocket"
        },
        page: {
            column_class: ["spine", "pocket"],
            dimensions: {
                columns: 2,
                rows: 1
            },
            label: {
                gap: {
                    size: 0
                },
                set: {
                    size: 2
                }
            },
            margins: {
                top: { size: 0, label: "Top" },
                left: { size: 0, label: "Left" },
            },
            space_between_labels: {
                horizontal: { size: 0, label: "Horizontal" },
                vertical: { size: 0, label: "Vertical" }
            },
            start_position: {
                column: 1,
                row: 1
            }
        }
    };

    if (dataKey && dataKey.length > 0) {

        egNet.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            dataKey, 'print-labels-these-copies'
        ).then(function (data) {

            if (data) {

                $scope.preview_scope = {
                    'copies': []
                    , 'settings': {}
                    , 'toolbox_settings': JSON.parse(JSON.stringify(toolbox_settings))
                    , 'get_cn_for': function (copy) {
                        var key = $scope.rendered_cn_key_by_copy_id[copy.id];
                        if (key) {
                            var manual_cn = $scope.rendered_call_number_set[key];
                            if (manual_cn && manual_cn.value) {
                                return manual_cn.value;
                            } else {
                                return '..';
                            }
                        } else {
                            return '...';
                        }
                    }
                    , 'get_bib_for': function (copy) {
                        return $scope.record_details[copy['call_number.record.id']];
                    }
                    , 'get_cn_prefix': function (copy) {
                        return copy['call_number.prefix.label'];
                    }
                    , 'get_cn_suffix': function (copy) {
                        return copy['call_number.suffix.label'];
                    }
                    , 'get_location_prefix': function (copy) {
                        return copy['location.label_prefix'];
                    }
                    , 'get_location_suffix': function (copy) {
                        return copy['location.label_suffix'];
                    }
                    , 'get_cn_and_location_prefix': function (copy, separator) {
                        var acpl_prefix = copy['location.label_prefix'] || '';
                        var cn_prefix = copy['call_number.prefix.label'] || '';
                        var prefix = acpl_prefix + ' ' + cn_prefix;
                        prefix = prefix.trim();
                        if (separator && prefix != '') { prefix += separator; }
                        return prefix;
                    }
                    , 'get_cn_and_location_suffix': function (copy, separator) {
                        var acpl_suffix = copy['location.label_suffix'] || '';
                        var cn_suffix = copy['call_number.suffix.label'] || '';
                        var suffix = cn_suffix + ' ' + acpl_suffix;
                        suffix = suffix.trim();
                        if (separator && suffix != '') { suffix = separator + suffix; }
                        return suffix;
                    }
                    , 'valid_print_label_start_column': function () {
                        return !angular.isNumber(toolbox_settings.page.dimensions.columns) || !angular.isNumber(toolbox_settings.page.start_position.column) ? false : (toolbox_settings.page.start_position.column <= toolbox_settings.page.dimensions.columns);
                    }
                    , 'valid_print_label_start_row': function () {
                        return !angular.isNumber(toolbox_settings.page.dimensions.rows) || !angular.isNumber(toolbox_settings.page.start_position.row) ? false : (toolbox_settings.page.start_position.row <= toolbox_settings.page.dimensions.rows);
                    }
                };
                $scope.record_details = {};
                $scope.org_unit_settings = {};

                var promises = [];
                $scope.org_unit_setting_list = [
                     'webstaff.cat.label.font.family'
                    , 'webstaff.cat.label.font.size'
                    , 'webstaff.cat.label.font.weight'
                    , 'webstaff.cat.label.inline_css'
                    , 'webstaff.cat.label.left_label.height'
                    , 'webstaff.cat.label.left_label.left_margin'
                    , 'webstaff.cat.label.left_label.width'
                    , 'webstaff.cat.label.right_label.height'
                    , 'webstaff.cat.label.right_label.left_margin'
                    , 'webstaff.cat.label.right_label.width'
                    , 'webstaff.cat.label.call_number_wrap_filter_height'
                    , 'webstaff.cat.label.call_number_wrap_filter_width'
                ];

                promises.push(
                    egCore.pcrud.search('coust', { name: $scope.org_unit_setting_list }).then(
                         null
                        , null
                        , function (yaous) {
                            $scope.org_unit_settings[yaous.name()] = egCore.idl.toHash(yaous, true);
                        }
                    )
                );

                promises.push(
                    egCore.org.settings($scope.org_unit_setting_list).then(function (res) {
                        $scope.preview_scope.settings = res;
                        egCore.hatch.getItem('cat.printlabels.last_settings').then(function (last_settings) {
                            if (last_settings) {
                                for (s in last_settings) {
                                    $scope.preview_scope.settings[s] = last_settings[s];
                                }
                            }
                        });
                        egCore.hatch.getItem('cat.printlabels.last_toolbox_settings').then(function (last_toolbox_settings) {
                            if (last_toolbox_settings) {
                                $scope.preview_scope.toolbox_settings = JSON.parse(JSON.stringify(last_toolbox_settings));
                            }
                        });
                    })
                );

                angular.forEach(data.copies, function (copy) {
                    promises.push(
                        itemSvc.fetch(null, copy).then(function (res) {
                            var flat_copy = egCore.idl.toHash(res.copy, true);
                            $scope.preview_scope.copies.push(flat_copy);
                            $scope.record_details[flat_copy['call_number.record.id']] = 1;
                        })
                    )
                });

                $q.all(promises).then(function () {

                    var promises2 = [];
                    angular.forEach($scope.record_details, function (el, k, obj) {
                        promises2.push(
                            egNet.request(
                                'open-ils.search',
                                'open-ils.search.biblio.record.mods_slim.retrieve.authoritative',
                                k
                            ).then(function (data) {
                                obj[k] = egCore.idl.toHash(data, true);
                            })
                        );
                    });

                    $q.all(promises2).then(function () {
                        // today, staff, current_location, etc.
                        egCore.print.fleshPrintScope($scope.preview_scope);
                        $scope.template_changed(); // load the default
                        $scope.rebuild_cn_set();
                    });

                });
            } else {
                ngToast.danger(egCore.strings.KEY_EXPIRED);
            }

        });

    }

    $scope.checkForToolboxCustomizations = function (tText, redraw) {
        var re = /eg\_plt\_(\d+)/;
        redraw ? $scope.redraw_label_table() : false;
        return re.test(tText);
    }

    $scope.fetchTemplates = function (set_default) {
        return egCore.hatch.getItem('cat.printlabels.templates').then(function (t) {
            if (t) {
                $scope.templates = t;
                $scope.template_name_list = Object.keys(t);
                if (set_default) {
                    egCore.hatch.getItem('cat.printlabels.default_template').then(function (d) {
                        if ($scope.template_name_list.indexOf(d, 0) > -1) {
                            $scope.template_name = d;
                        }
                    });
                }
            }
        });
    }
    $scope.fetchTemplates(true);

    $scope.applyTemplate = function (n) {
        $scope.print.cn_template_content = $scope.templates[n].cn_content;
        $scope.print.template_content = $scope.templates[n].content;
        $scope.print.template_context = $scope.templates[n].context;
        for (var s in $scope.templates[n].settings) {
            $scope.preview_scope.settings[s] = $scope.templates[n].settings[s];
        }
        if ($scope.templates[n].toolbox_settings) {
            $scope.preview_scope.toolbox_settings = JSON.parse(JSON.stringify($scope.templates[n].toolbox_settings));
        }
        egCore.hatch.setItem('cat.printlabels.default_template', n);
        $scope.save_locally();
    }

    $scope.deleteTemplate = function (n) {
        if (n) {
            delete $scope.templates[n]
            $scope.template_name_list = Object.keys($scope.templates);
            $scope.template_name = '';
            egCore.hatch.setItem('cat.printlabels.templates', $scope.templates);
            $scope.fetchTemplates();
            ngToast.create(egCore.strings.PRINT_LABEL_TEMPLATE_SUCCESS_DELETE);
            egCore.hatch.getItem('cat.printlabels.default_template').then(function (d) {
                if (d && d == n) {
                    egCore.hatch.removeItem('cat.printlabels.default_template');
                }
            });
        }
    }

    $scope.saveTemplate = function (n) {
        if (n) {

            $scope.templates[n] = {
                content: $scope.print.template_content
                , context: $scope.print.template_context
                , cn_content: $scope.print.cn_template_content
                , settings: JSON.parse(JSON.stringify($scope.preview_scope.settings))
                , toolbox_settings: JSON.parse(JSON.stringify($scope.preview_scope.toolbox_settings))
            };
            $scope.template_name_list = Object.keys($scope.templates);

            egCore.hatch.setItem('cat.printlabels.templates', $scope.templates);
            $scope.fetchTemplates();

            $scope.dirty = false;
        } else {
            // save all templates, as we might do after an import
            egCore.hatch.setItem('cat.printlabels.templates', $scope.templates);
            $scope.fetchTemplates();
        }
        ngToast.create(egCore.strings.PRINT_LABEL_TEMPLATE_SUCCESS_SAVE);
    }

    $scope.templates = {};
    $scope.imported_templates = { data: '' };
    $scope.template_name = '';
    $scope.template_name_list = [];

    $scope.print_labels = function () {
        return egCore.print.print({
            context: $scope.print.template_context,
            template: $scope.print.template_name,
            scope: $scope.preview_scope,
        });
    }

    $scope.template_changed = function () {
        $scope.print.load_failed = false;
        egCore.print.getPrintTemplate('item_label')
        .then(
            function (html) {
                $scope.print.template_content = html;
                $scope.checkForToolboxCustomizations(html, true);
            },
            function () {
                $scope.print.template_content = '';
                $scope.print.load_failed = true;
            }
        );
        egCore.print.getPrintTemplateContext('item_label')
        .then(function (template_context) {
            $scope.print.template_context = template_context;
        });
        egCore.print.getPrintTemplate('item_label_cn')
        .then(
            function (html) {
                $scope.print.cn_template_content = html;
            },
            function () {
                $scope.print.cn_template_content = '';
                $scope.print.load_failed = true;
            }
        );
        egCore.hatch.getItem('cat.printlabels.last_settings').then(function (s) {
            if (s) {
                $scope.preview_scope.settings = JSON.parse(JSON.stringify(s));
            }
        });
        egCore.hatch.getItem('cat.printlabels.last_toolbox_settings').then(function (t) {
            if (t) {
                $scope.preview_scope.toolbox_settings = JSON.parse(JSON.stringify(t));
            }
        });

    }

    $scope.reset_to_default = function () {
        egCore.print.removePrintTemplate(
            'item_label'
        );
        egCore.print.removePrintTemplateContext(
            'item_label'
        );
        egCore.print.removePrintTemplate(
            'item_label_cn'
        );
        egCore.hatch.removeItem('cat.printlabels.last_settings');
        egCore.hatch.removeItem('cat.printlabels.last_toolbox_settings');
        for (s in $scope.preview_scope.settings) {
            $scope.preview_scope.settings[s] = undefined;
        }
        $scope.preview_scope.toolbox_settings = JSON.parse(JSON.stringify(toolbox_settings));

        egCore.org.settings($scope.org_unit_setting_list).then(function (res) {
            $scope.preview_scope.settings = res;
        });

        $scope.template_changed();
    }

    $scope.save_locally = function () {
        egCore.print.storePrintTemplate(
            'item_label',
            $scope.print.template_content
        );
        egCore.print.storePrintTemplateContext(
            'item_label',
            $scope.print.template_context
        );
        egCore.print.storePrintTemplate(
            'item_label_cn',
            $scope.print.cn_template_content
        );
        egCore.hatch.setItem('cat.printlabels.last_settings', JSON.parse(JSON.stringify($scope.preview_scope.settings)));
        egCore.hatch.setItem('cat.printlabels.last_toolbox_settings', JSON.parse(JSON.stringify($scope.preview_scope.toolbox_settings)));
    }

    $scope.imported_print_templates = { data: '' };
    $scope.$watch('imported_templates.data', function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            try {
                var data = JSON.parse(newVal);
                angular.forEach(data, function (el, k) {
                    $scope.templates[k] = {
                        content: el.content
                        , context: el.context
                        , cn_content: el.cn_content
                        , settings: JSON.parse(JSON.stringify(el.settings))
                    };
                    if (el.toolbox_settings) {
                        $scope.templates[k].toolbox_settings = JSON.parse(JSON.stringify(el.toolbox_settings));
                    }
                });
                $scope.saveTemplate();
                $scope.template_changed(); // refresh
                ngToast.create(egCore.strings.PRINT_TEMPLATES_SUCCESS_IMPORT);
            } catch (E) {
                ngToast.warning(egCore.strings.PRINT_TEMPLATES_FAIL_IMPORT);
            }
        }
    });

    $scope.rendered_call_number_set = {};
    $scope.rendered_cn_key_by_copy_id = {};
    $scope.rebuild_cn_set = function () {
        $timeout(function () {
            $scope.rendered_call_number_set = {};
            $scope.rendered_cn_key_by_copy_id = {};
            for (var i = 0; i < $scope.preview_scope.copies.length; i++) {
                var copy = $scope.preview_scope.copies[i];
                var rendered_cn = document.getElementById('cn_for_copy_' + copy.id);
                if (rendered_cn && rendered_cn.textContent) {
                    var key = rendered_cn.textContent;
                    if (typeof $scope.rendered_call_number_set[key] == 'undefined') {
                        $scope.rendered_call_number_set[key] = {
                            value: key
                        };
                    }
                    $scope.rendered_cn_key_by_copy_id[copy.id] = key;
                }
            }
            $scope.preview_scope.tickle = Date() + ' ' + Math.random();
        });
    }

    $scope.redraw_label_table = function () {
        if ($scope.print_label_form.$valid && $scope.print.template_content && $scope.preview_scope) {
            $scope.preview_scope.label_output_copies = labelOutputRowsFilter($scope.preview_scope.copies, $scope.preview_scope.toolbox_settings);
            var d = new Date().getTime().toString();
            var html = $scope.print.template_content;
            if ($scope.checkForToolboxCustomizations(html)) {
                html = html.replace(/eg\_plt\_\d+/, "eg_plt_" + d);
                $scope.print.template_content = html;
            } else {
                var table = "<table id=\"eg_plt_" + d + "_{{$index}}\" eg-print-label-table style=\"border-collapse: collapse; border: 0 solid transparent; border-spacing: 0; margin: {{$index === 0 ? toolbox_settings.page.margins.top.size : 0}} 0 0 0;\" class=\"custom-label-table{{$index % toolbox_settings.page.dimensions.rows === 0 && $index > 0 && toolbox_settings.feed_option.selected === 'sheet' ? ' page-break' : ''}}\" ng-init=\"parentIndex = $index\" ng-repeat=\"row in label_output_copies\">\n";
                table += "<tr>\n";
                table += "<td style=\"border: 0 solid transparent; padding: {{parentIndex % toolbox_settings.page.dimensions.rows === 0 && toolbox_settings.feed_option.selected === 'sheet' && parentIndex > 0 ? toolbox_settings.page.space_between_labels.vertical.size : parentIndex > 0 ? toolbox_settings.page.space_between_labels.vertical.size : 0}} 0 0 {{$index === 0 ? toolbox_settings.page.margins.left.size : col.styl ? col.styl : toolbox_settings.page.space_between_labels.horizontal.size}};\" ng-repeat=\"col in row.columns\">\n";
                table += "<pre class=\"{{col.cls}}\" style=\"border: none; margin-bottom: 0; margin-top: 0; overflow: hidden;\" ng-if=\"col.cls === 'spine'\">\n";
                table += "{{col.c ? get_cn_for(col.c) : ''}}";
                table += "</pre>\n";
                table += "<pre class=\"{{col.cls}}{{parentIndex % toolbox_settings.page.dimensions.rows === 0 && parentIndex > 0 && toolbox_settings.feed_option.selected === 'sheet' ? ' page-break' : ''}}\" style=\"border: none;  margin-bottom: 0; margin-top: 0; overflow: hidden;\" ng-if=\"col.cls === 'pocket'\">\n";
                table += "{{col.c ? col.c.barcode : ''}}\n";
                table += "{{col.c ? col.c['call_number.label'] : ''}}\n";
                table += "{{col.c ? get_bib_for(col.c).author : ''}}\n";
                table += "{{col.c ? (get_bib_for(col.c).title | wrap:28:'once':'  ') : ''}}\n";
                table += "</pre>\n";
                table += "</td>\n"
                table += "</tr>\n";
                table += "</table>";
                var comments = html.match(/\<\!\-\-(?:(?!\-\-\>)(?:.|\s))*\-\-\>\s*/g);
                html = html.replace(/\<\!\-\-(?:(?!\-\-\>)(?:.|\s))*\-\-\>\s*/g, '');
                var style = html.match(/\<style[^\>]*\>(?:(?!\<\/style\>)(?:.|\s))*\<\/style\>\s*/gi);
                var output = (comments ? comments.join("\n") : "") + (style ? style.join("\n") : "") + table;
                output = output.replace(/\n+/, "\n");
                $scope.print.template_content = output;
            }
        }
    }

    $scope.$watch('print.cn_template_content', function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_height']", function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_width']", function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watchGroup(['preview_scope.toolbox_settings.page.margins.top.size', 'preview_scope.toolbox_settings.page.margins.left.size', 'preview_scope.toolbox_settings.page.dimensions.rows', 'preview_scope.toolbox_settings.page.dimensions.columns', 'preview_scope.toolbox_settings.page.space_between_labels.horizontal.size', 'preview_scope.toolbox_settings.page.space_between_labels.vertical.size', 'preview_scope.toolbox_settings.page.start_position.row', 'preview_scope.toolbox_settings.page.start_position.column', 'preview_scope.toolbox_settings.page.label.gap.size'], function (newVal, oldVal) {
        if (newVal && newVal != oldVal && $scope.preview_scope.label_output_copies) {
            $scope.redraw_label_table();
        }
    });

    $scope.$watch("preview_scope.toolbox_settings.mode.selected", function (newVal, oldVal) {
        if (newVal && newVal != oldVal && $scope.preview_scope) {
            var ts_p = $scope.preview_scope.toolbox_settings.page;
            if (ts_p.label.set.size === 1) {
                if (newVal === "spine-pocket") {
                    ts_p.column_class = ["spine", "pocket"];
                    ts_p.label.set.size = 2;
                } else {
                    ts_p.column_class = ["spine"];
                }
            } else {
                if (newVal === "spine-only") {
                    for (var i = 0; i < ts_p.label.set.size; i++) {
                        ts_p.column_class[i] = "spine";
                    }
                } else {
                    ts_p.label.set.size === 2 ? ts_p.column_class = ["spine", "pocket"] : false;
                }
            }
            $scope.redraw_label_table();
        }
    });

    $scope.$watch("preview_scope.toolbox_settings.page.label.set.size", function (newVal, oldVal) {
        if (newVal && newVal != oldVal && oldVal) {
            var ts_p = $scope.preview_scope.toolbox_settings.page;
            if (angular.isNumber(newVal)) {
                while (ts_p.column_class.length > ts_p.label.set.size) {
                    ts_p.column_class.splice((ts_p.column_class.length - 1), 1);
                }
                while (ts_p.column_class.length < ts_p.label.set.size) {
                    ts_p.column_class.push("spine");
                }
            }
        }
    });

    $scope.$watch('print.cn_template_content', function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_height']", function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_width']", function (newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.current_tab = 'call_numbers';
    $scope.set_tab = function (tab) {
        $scope.current_tab = tab;
    }

}])

.directive("egPrintLabelColumnBounds", function () {
    return {
        link: function (scope, element, attr, ctrl) {
            function withinBounds(v) {
                scope.$watch("preview_scope.toolbox_settings.page.dimensions.columns", function (newVal, oldVal) {
                    ctrl.$setValidity("egWithinPrintColumnBounds", scope.preview_scope.valid_print_label_start_column())
                });
                return v;
            }
            ctrl.$parsers.push(withinBounds);
            ctrl.$formatters.push(withinBounds);
        },
        require: "ngModel"
    }
})

.directive("egPrintLabelRowBounds", function () {
    return {
        link: function (scope, element, attr, ctrl) {
            function withinBounds(v) {
                scope.$watch("preview_scope.toolbox_settings.page.dimensions.rows", function (newVal, oldVal) {
                    ctrl.$setValidity("egWithinPrintRowBounds", scope.preview_scope.valid_print_label_start_row());
                });
                return v;
            }
            ctrl.$parsers.push(withinBounds);
            ctrl.$formatters.push(withinBounds);
        },
        require: "ngModel"
    }
})

.directive("egPrintLabelValidCss", function () {
    return {
        require: "ngModel",
        link: function (scope, element, attr, ctrl) {
            function floatValidation(v) {
                ctrl.$setValidity("isFloat", v.toString().match(/^\-*(?:^0$|(?:\d+)(?:\.\d{1,})*([a-z]{2}))$/) ? true : false);
                return v;
            }
            ctrl.$parsers.push(floatValidation);
        }
    }
})

.directive("egPrintLabelValidInt", function () {
    return {
        require: "ngModel",
        link: function (scope, element, attr, ctrl) {
            function intValidation(v) {
                ctrl.$setValidity("isInteger", v.toString().match(/^\d+$/));
                return v;
            }
            ctrl.$parsers.push(intValidation);
        }
    }
})

.directive('egPrintTemplateOutput', ['$compile', function ($compile) {
    return function (scope, element, attrs) {
        scope.$watch(
            function (scope) {
                return scope.$eval(attrs.content);
            },
            function (value) {
                // create an isolate scope and copy the print context
                // data into the new scope.
                // TODO: see also print security concerns in egHatch
                var result = element.html(value);
                var context = scope.$eval(attrs.context);
                var print_scope = scope.$new(true);
                angular.forEach(context, function (val, key) {
                    print_scope[key] = val;
                })
                $compile(element.contents())(print_scope);
            }
        );
    };
}])

.filter('cn_wrap', function () {
    return function (input, w, h, wrap_type) {
        var names;
        var prefix = input[0];
        var callnum = input[1];
        var suffix = input[2];

        if (!w) { w = 8; }
        if (!h) { h = 9; }

        /* handle spine labels differently if using LC */
        if (wrap_type == 'lc' || wrap_type == 3) {
            /* Establish a pattern where every return value should be isolated on its own line 
               on the spine label: subclass letters, subclass numbers, cutter numbers, trailing stuff (date) */
            var patt1 = /^([A-Z]{1,3})\s*(\d+(?:\.\d+)?)\s*(\.[A-Z]\d*)\s*([A-Z]\d*)?\s*(\d\d\d\d(?:-\d\d\d\d)?)?\s*(.*)$/i;
            var result = callnum.match(patt1);
            if (result) {
                callnum = result.slice(1).join('\t');
            } else {
                callnum = callnum.split(/\s+/).join('\t');
            }

            /* If result is null, leave callnum alone. Can't parse this malformed call num */
        } else {
            callnum = callnum.split(/\s+/).join('\t');
        }

        if (prefix) {
            callnum = prefix + '\t' + callnum;
        }
        if (suffix) {
            callnum += '\t' + suffix;
        }

        /* At this point, the call number pieces are separated by tab characters.  This allows
        *  some space-containing constructs like "v. 1" to appear on one line
        */
        callnum = callnum.replace(/\t\t/g, '\t');  /* Squeeze out empties */
        names = callnum.split('\t');
        var j = 0; var tb = [];
        while (j < h) {

            /* spine */
            if (j < w) {

                var name = names.shift();
                if (name) {
                    name = String(name);

                    /* if the name is greater than the label width... */
                    if (name.length > w) {
                        /* then try to split it on periods */
                        var sname = name.split(/\./);
                        if (sname.length > 1) {
                            /* if we can, then put the periods back in on each splitted element */
                            if (name.match(/^\./)) sname[0] = '.' + sname[0];
                            for (var k = 1; k < sname.length; k++) sname[k] = '.' + sname[k];
                            /* and put all but the first one back into the names array */
                            names = sname.slice(1).concat(names);
                            /* if the name fragment is still greater than the label width... */
                            if (sname[0].length > w) {
                                /* then just truncate and throw the rest back into the names array */
                                tb[j] = sname[0].substr(0, w);
                                names = [sname[0].substr(w)].concat(names);
                            } else {
                                /* otherwise we're set */
                                tb[j] = sname[0];
                            }
                        } else {
                            /* if we can't split on periods, then just truncate and throw the rest back into the names array */
                            tb[j] = name.substr(0, w);
                            names = [name.substr(w)].concat(names);
                        }
                    } else {
                        /* otherwise we're set */
                        tb[j] = name;
                    }
                }
            }
            j++;
        }
        return tb.join('\n');
    }
})

.filter("columnRowRange", function () {
    return function (i) {
        var res = [];
        for (var j = 0; j < i; j++) {
            res.push(j);
        }
        return res;
    }
})

//Accepts $scope.preview_scope.copies and $scope.preview_scope.toolbox_settings as its parameters.
.filter("labelOutputRows", function () {
    return function (copies, settings) {
        var cols = [], rows = [];
        for (var j = 0; j < (settings.page.start_position.row - 1) ; j++) {
            cols = [];
            for (var k = 0; k < settings.page.dimensions.columns; k++) {
                cols.push({ c: null, index: k, cls: getPrintLabelOutputClass(k, settings), styl: getPrintLabelStyle(k, settings) });
            }
            rows.push({ columns: cols });
        }
        cols = [];
        for (var j = 0; j < (settings.page.start_position.column - 1) ; j++) {
            cols.push({ c: null, index: j, cls: getPrintLabelOutputClass(j, settings), styl: getPrintLabelStyle(j, settings) });
        }
        var m = cols.length;
        for (var j = 0; j < copies.length; j++) {
            for (var n = 0; n < settings.page.label.set.size; n++) {
                if (m < settings.page.dimensions.columns) {
                    cols.push({ c: copies[j], index: cols.length, cls: getPrintLabelOutputClass(m, settings), styl: getPrintLabelStyle(m, settings) });
                    m += 1;
                }
                if (m === settings.page.dimensions.columns) {
                    m = 0;
                    rows.push({ columns: cols });
                    cols = [];
                    n = settings.page.label.set.size;
                }
            }
        }
        cols.length > 0 ? rows.push({ columns: cols }) : false;
        if (rows.length > 0) {
            while ((rows[(rows.length - 1)].columns.length) < settings.page.dimensions.columns) {
                rows[(rows.length - 1)].columns.push({ c: null, index: rows[(rows.length - 1)].columns.length, cls: getPrintLabelOutputClass(rows[(rows.length - 1)].columns.length, settings), styl: getPrintLabelStyle(rows[(rows.length - 1)].columns.length, settings) });
            }
        }
        return rows;
    }
})

.filter('wrap', function () {
    return function (input, w, wrap_type, indent) {
        var output;

        if (!w) return input;
        if (!indent) indent = '';

        function wrap_on_space(
                text,
                length,
                wrap_just_once,
                if_cant_wrap_then_truncate,
                idx
        ) {
            if (idx > 10) {
                console.log('possible infinite recursion, aborting');
                return '';
            }
            if (String(text).length <= length) {
                return text;
            } else {
                var truncated_text = String(text).substr(0, length);
                var pivot_pos = truncated_text.lastIndexOf(' ');
                var left_chunk = text.substr(0, pivot_pos).replace(/\s*$/, '');
                var right_chunk = String(text).substr(pivot_pos + 1);

                var wrapped_line;
                if (left_chunk.length == 0) {
                    if (if_cant_wrap_then_truncate) {
                        wrapped_line = truncated_text;
                    } else {
                        wrapped_line = text;
                    }
                } else {
                    wrapped_line =
                        left_chunk + '\n'
                        + indent + (
                            wrap_just_once
                            ? right_chunk
                            : (
                                right_chunk.length > length
                                ? wrap_on_space(
                                    right_chunk,
                                    length,
                                    false,
                                    if_cant_wrap_then_truncate,
                                    idx + 1)
                                : right_chunk
                            )
                        )
                    ;
                }
                return wrapped_line;
            }
        }

        switch (wrap_type) {
            case 'once':
                output = wrap_on_space(input, w, true, false, 0);
                break;
            default:
                output = wrap_on_space(input, w, false, false, 0);
                break;
        }

        return output;
    }
});

function getPrintLabelOutputClass(index, settings) {
    return settings.page.column_class[index % settings.page.label.set.size];
}

function getPrintLabelStyle(index, settings) {
    return index > 0 && (index % settings.page.label.set.size === 0) ? settings.page.label.gap.size : "";
}