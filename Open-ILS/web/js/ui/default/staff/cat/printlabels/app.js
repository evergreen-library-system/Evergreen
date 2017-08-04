/**
 * Vol/Copy Editor
 */

angular.module('egPrintLabels',
    ['ngRoute', 'ui.bootstrap', 'egCoreMod', 'egUiMod', 'egGridMod'])

.config(function($routeProvider, $locationProvider, $compileProvider) {
    $locationProvider.html5Mode(true);
    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|blob):/); // grid export

    var resolver = {
        delay : ['egStartup', function(egStartup) { return egStartup.go(); }]
    };

    $routeProvider.when('/cat/printlabels/:dataKey', {
        templateUrl: './cat/printlabels/t_view',
        controller: 'LabelCtrl',
        resolve : resolver
    });

})

.factory('itemSvc', 
       ['egCore',
function(egCore) {

    var service = {
        copies : [], // copy barcode search results
        index : 0 // search grid index
    };

    service.flesh = {   
        flesh : 3, 
        flesh_fields : {
            acp : ['call_number','location','status','location','floating','circ_modifier','age_protect'],
            acn : ['record','prefix','suffix'],
            bre : ['simple_record','creator','editor']
        },
        select : { 
            // avoid fleshing MARC on the bre
            // note: don't add simple_record.. not sure why
            bre : ['id','tcn_value','creator','editor'],
        } 
    }

    // resolved with the last received copy
    service.fetch = function(barcode, id, noListDupes) {
        var promise;

        if (barcode) {
            promise = egCore.pcrud.search('acp', 
                {barcode : barcode, deleted : 'f'}, service.flesh);
        } else {
            promise = egCore.pcrud.retrieve('acp', id, service.flesh);
        }

        var lastRes;
        return promise.then(
            function() {return lastRes},
            null, // error

            // notify reads the stream of copies, one at a time.
            function(copy) {

                var flatCopy;
                if (noListDupes) {
                    // use the existing copy if possible
                    flatCopy = service.copies.filter(
                        function(c) {return c.id == copy.id()})[0];
                }

                if (!flatCopy) {
                    flatCopy = egCore.idl.toHash(copy, true);
                    flatCopy.index = service.index++;
                    service.copies.unshift(flatCopy);
                }

                return lastRes = {
                    copy : copy, 
                    index : flatCopy.index
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
       ['$scope','$q','$window','$routeParams','$location','$timeout','egCore','egNet','ngToast','itemSvc',
function($scope , $q , $window , $routeParams , $location , $timeout , egCore , egNet , ngToast , itemSvc ) {

    var dataKey = $routeParams.dataKey;
    console.debug('dataKey: ' + dataKey);

    $scope.print = {
        template_name : 'item_label',
        template_output : '',
        template_context : 'default'
    };


    if (dataKey && dataKey.length > 0) {

        egNet.request(
            'open-ils.actor',
            'open-ils.actor.anon_cache.get_value',
            dataKey, 'print-labels-these-copies'
        ).then(function (data) {

            if (data) {

                $scope.preview_scope = {
                     'copies' : []
                    ,'settings' : {}
                    ,'get_cn_for' : function(copy) {
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
                    ,'get_bib_for' : function(copy) {
                        return $scope.record_details[copy['call_number.record.id']];
                    }
                    ,'get_cn_prefix' : function(copy) {
                        return copy['call_number.prefix.label'];
                    }
                    ,'get_cn_suffix' : function(copy) {
                        return copy['call_number.suffix.label'];
                    }
                    ,'get_location_prefix' : function(copy) {
                        return copy['location.label_prefix'];
                    }
                    ,'get_location_suffix' : function(copy) {
                        return copy['location.label_suffix'];
                    }
                    ,'get_cn_and_location_prefix' : function(copy,separator) {
                        var acpl_prefix = copy['location.label_prefix'] || '';
                        var cn_prefix = copy['call_number.prefix.label'] || '';
                        var prefix = acpl_prefix + ' ' + cn_prefix;
                        prefix = prefix.trim();
                        if (separator && prefix != '') { prefix += separator; }
                        return prefix;
                    }
                    ,'get_cn_and_location_suffix' : function(copy,separator) {
                        var acpl_suffix = copy['location.label_suffix'] || '';
                        var cn_suffix = copy['call_number.suffix.label'] || '';
                        var suffix = cn_suffix + ' ' + acpl_suffix;
                        suffix = suffix.trim();
                        if (separator && suffix != '') { suffix = separator + suffix; }
                        return suffix;
                    }
                };
                $scope.record_details = {};
                $scope.org_unit_settings = {};

                var promises = [];
                $scope.org_unit_setting_list = [
                     'webstaff.cat.label.font.family'
                    ,'webstaff.cat.label.font.size'
                    ,'webstaff.cat.label.font.weight'
                    ,'webstaff.cat.label.inline_css'
                    ,'webstaff.cat.label.left_label.height'
                    ,'webstaff.cat.label.left_label.left_margin'
                    ,'webstaff.cat.label.left_label.width'
                    ,'webstaff.cat.label.right_label.height'
                    ,'webstaff.cat.label.right_label.left_margin'
                    ,'webstaff.cat.label.right_label.width'
                    ,'webstaff.cat.label.call_number_wrap_filter_height'
                    ,'webstaff.cat.label.call_number_wrap_filter_width'
                ];

                promises.push(
                    egCore.pcrud.search('coust',{name:$scope.org_unit_setting_list}).then(
                         null
                        ,null
                        ,function(yaous) {
                            $scope.org_unit_settings[yaous.name()] = egCore.idl.toHash(yaous, true);
                        }
                    )
                );

                promises.push(
                    egCore.org.settings($scope.org_unit_setting_list).then(function(res) {
                        $scope.preview_scope.settings = res;
                        egCore.hatch.getItem('cat.printlabels.last_settings').then(function(last_settings) {
                            if (last_settings) {
                                for (s in last_settings) {
                                    $scope.preview_scope.settings[s] = last_settings[s];
                                }
                            }
                        });
                    })
                );

                angular.forEach(data.copies, function(copy) {
                    promises.push(
                        itemSvc.fetch(null,copy).then(function(res) {
                            var flat_copy = egCore.idl.toHash(res.copy, true);
                            $scope.preview_scope.copies.push(flat_copy);
                            $scope.record_details[ flat_copy['call_number.record.id'] ] = 1;
                        })
                    )
                });

                $q.all(promises).then(function() {

                    var promises2 = [];
                    angular.forEach($scope.record_details, function(el,k,obj) {
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

                    $q.all(promises2).then(function() {
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

    $scope.fetchTemplates = function (set_default) {
        return egCore.hatch.getItem('cat.printlabels.templates').then(function(t) {
            if (t) {
                $scope.templates = t;
                $scope.template_name_list = Object.keys(t);
                if (set_default) {
                    egCore.hatch.getItem('cat.printlabels.default_template').then(function(d) {
                        if ($scope.template_name_list.indexOf(d,0) > -1) {
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
            egCore.hatch.getItem('cat.printlabels.default_template').then(function(d) {
                if (d && d == n) {
                    egCore.hatch.removeItem('cat.printlabels.default_template');
                }
            });
        }
    }

    $scope.saveTemplate = function (n) {
        if (n) {

            $scope.templates[n] = {
                 content : $scope.print.template_content
                ,context : $scope.print.template_context
                ,cn_content : $scope.print.cn_template_content
                ,settings : $scope.preview_scope.settings
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
    $scope.imported_templates = { data : '' };
    $scope.template_name = '';
    $scope.template_name_list = [];

    $scope.print_labels = function() {
        return egCore.print.print({
            context : $scope.print.template_context,
            template : $scope.print.template_name,
            scope : $scope.preview_scope,
        });
    }

    $scope.template_changed = function() {
        $scope.print.load_failed = false;
        egCore.print.getPrintTemplate('item_label')
        .then(
            function(html) { 
                $scope.print.template_content = html;
            },
            function() {
                $scope.print.template_content = '';
                $scope.print.load_failed = true;
            }
        );
        egCore.print.getPrintTemplateContext('item_label')
        .then(function(template_context) {
            $scope.print.template_context = template_context;
        });
        egCore.print.getPrintTemplate('item_label_cn')
        .then(
            function(html) {
                $scope.print.cn_template_content = html;
            },
            function() {
                $scope.print.cn_template_content = '';
                $scope.print.load_failed = true;
            }
        );
        egCore.hatch.getItem('cat.printlabels.last_settings').then(function(s) {
            if (s) {
                $scope.preview_scope.settings = s;
            }
        });

    }

    $scope.reset_to_default = function() {
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
        for (s in $scope.preview_scope.settings) {
            $scope.preview_scope.settings[s] = undefined;
        }
        $scope.preview_scope.settings = {};
        egCore.org.settings($scope.org_unit_setting_list).then(function(res) {
            $scope.preview_scope.settings = res;
        });

        $scope.template_changed();
    }

    $scope.save_locally = function() {
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
        egCore.hatch.setItem('cat.printlabels.last_settings', $scope.preview_scope.settings);
    }

    $scope.imported_print_templates = { data : '' };
    $scope.$watch('imported_templates.data', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            try {
                var data = JSON.parse(newVal);
                angular.forEach(data, function(el,k) {
                    $scope.templates[k] = {
                         content : el.content
                        ,context : el.context
                        ,cn_content : el.cn_content
                        ,settings : el.settings
                    };
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
    $scope.rebuild_cn_set = function() {
        $timeout(function(){
            $scope.rendered_call_number_set = {};
            $scope.rendered_cn_key_by_copy_id = {};
            for (var i = 0; i < $scope.preview_scope.copies.length; i++) {
                var copy = $scope.preview_scope.copies[i];
                var rendered_cn = document.getElementById('cn_for_copy_'+copy.id);
                if (rendered_cn && rendered_cn.textContent) {
                    var key = rendered_cn.textContent;
                    if (typeof $scope.rendered_call_number_set[key] == 'undefined') {
                        $scope.rendered_call_number_set[key] = {
                            value : key
                        };
                    }
                    $scope.rendered_cn_key_by_copy_id[copy.id] = key;
                }
            }
            $scope.preview_scope.tickle = Date() + ' ' + Math.random();
        });
    }

    $scope.$watch('print.cn_template_content', function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_height']", function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.$watch("preview_scope.settings['webstaff.cat.label.call_number_wrap_filter_width']", function(newVal, oldVal) {
        if (newVal && newVal != oldVal) {
            $scope.rebuild_cn_set();
        }
    });

    $scope.current_tab = 'call_numbers';
    $scope.set_tab = function(tab) {
        $scope.current_tab = tab;
    }

}])

// 
.directive('egPrintTemplateOutput', ['$compile',function($compile) {
    return function(scope, element, attrs) {
        scope.$watch(
            function(scope) {
                return scope.$eval(attrs.content);
            },
            function(value) {
                // create an isolate scope and copy the print context
                // data into the new scope.
                // TODO: see also print security concerns in egHatch
                var result = element.html(value);
                var context = scope.$eval(attrs.context);
                var print_scope = scope.$new(true);
                angular.forEach(context, function(val, key) {
                    print_scope[key] = val;
                })
                $compile(element.contents())(print_scope);
            }
        );
    };
}])

.filter('cn_wrap', function() {
    return function(input, w, h, wrap_type) {
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
        callnum = callnum.replace(/\t\t/g,'\t');  /* Squeeze out empties */ 
        names = callnum.split('\t');
        var j = 0; var tb = [];
        while (j < h) {
            
            /* spine */
            if (j < w) {

                var name = names.shift();
                if (name) {
                    name = String( name );

                    /* if the name is greater than the label width... */
                    if (name.length > w) {
                        /* then try to split it on periods */
                        var sname = name.split(/\./);
                        if (sname.length > 1) {
                            /* if we can, then put the periods back in on each splitted element */
                            if (name.match(/^\./)) sname[0] = '.' + sname[0];
                            for (var k = 1; k < sname.length; k++) sname[k] = '.' + sname[k];
                            /* and put all but the first one back into the names array */
                            names = sname.slice(1).concat( names );
                            /* if the name fragment is still greater than the label width... */
                            if (sname[0].length > w) {
                                /* then just truncate and throw the rest back into the names array */
                                tb[j] = sname[0].substr(0,w);
                                names = [ sname[0].substr(w) ].concat( names );
                            } else {
                                /* otherwise we're set */
                                tb[j] = sname[0];
                            }
                        } else {
                            /* if we can't split on periods, then just truncate and throw the rest back into the names array */
                            tb[j] = name.substr(0,w);
                            names = [ name.substr(w) ].concat( names );
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

.filter('wrap', function() {
    return function(input, w, wrap_type, indent) {
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
            if (idx>10) {
                console.log('possible infinite recursion, aborting');
                return '';
            }
            if (String(text).length <= length) {
                return text;
            } else {
                var truncated_text = String(text).substr(0,length);
                var pivot_pos = truncated_text.lastIndexOf(' ');
                var left_chunk = text.substr(0,pivot_pos).replace(/\s*$/,'');
                var right_chunk = String(text).substr(pivot_pos+1);

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
                                    idx+1)
                                : right_chunk
                            )
                        )
                    ;
                }
                return wrapped_line;
            }
        }

        switch(wrap_type) {
            case 'once':
                output = wrap_on_space(input,w,true,false,0);
            break;
            default:
                output = wrap_on_space(input,w,false,false,0);
            break;
        }

        return output;
    }
})

