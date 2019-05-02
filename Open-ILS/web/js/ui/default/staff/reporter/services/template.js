/**
 * Report templates
 */

angular.module('egReportMod', ['egCoreMod', 'ui.bootstrap'])
.factory('egReportTemplateSvc',

       ['$uibModal','$q','egCore','egConfirmDialog','egAlertDialog',
function($uibModal , $q , egCore , egConfirmDialog , egAlertDialog) {

    //dojo.requireLocalization("openils.reports", "reports");
    //var egCore.strings = dojo.i18n.getLocalization("openils.reports", "reports");

    var OILS_RPT_DTYPE_ARRAY = 'array';
    var OILS_RPT_DTYPE_STRING = 'text';
    var OILS_RPT_DTYPE_MONEY = 'money';
    var OILS_RPT_DTYPE_BOOL = 'bool';
    var OILS_RPT_DTYPE_INT = 'int';
    var OILS_RPT_DTYPE_ID = 'id';
    var OILS_RPT_DTYPE_OU = 'org_unit';
    var OILS_RPT_DTYPE_FLOAT = 'float';
    var OILS_RPT_DTYPE_TIMESTAMP = 'timestamp';
    var OILS_RPT_DTYPE_INTERVAL = 'interval';
    var OILS_RPT_DTYPE_LINK = 'link';
    var OILS_RPT_DTYPE_NONE = '';
    var OILS_RPT_DTYPE_NULL = null;
    var OILS_RPT_DTYPE_UNDEF;
    
    var OILS_RPT_DTYPE_ALL = [
    	OILS_RPT_DTYPE_STRING,
    	OILS_RPT_DTYPE_MONEY,
    	OILS_RPT_DTYPE_INT,
    	OILS_RPT_DTYPE_ID,
    	OILS_RPT_DTYPE_FLOAT,
    	OILS_RPT_DTYPE_TIMESTAMP,
    	OILS_RPT_DTYPE_BOOL,
    	OILS_RPT_DTYPE_OU,
    	OILS_RPT_DTYPE_NONE,
    	OILS_RPT_DTYPE_NULL,
    	OILS_RPT_DTYPE_UNDEF,
    	OILS_RPT_DTYPE_INTERVAL,
    	OILS_RPT_DTYPE_LINK
    ];
    var OILS_RPT_DTYPE_NOT_ID = [OILS_RPT_DTYPE_STRING,OILS_RPT_DTYPE_MONEY,OILS_RPT_DTYPE_INT,OILS_RPT_DTYPE_FLOAT,OILS_RPT_DTYPE_TIMESTAMP];
    var OILS_RPT_DTYPE_NOT_BOOL = [OILS_RPT_DTYPE_STRING,OILS_RPT_DTYPE_MONEY,OILS_RPT_DTYPE_INT,OILS_RPT_DTYPE_FLOAT,OILS_RPT_DTYPE_TIMESTAMP,OILS_RPT_DTYPE_ID,OILS_RPT_DTYPE_OU,OILS_RPT_DTYPE_LINK];

    var service = {
        display_fields : [],
        filter_fields  : [],

        Filters : {
        	'=' : {
        		label : egCore.strings.OPERATORS_EQUALS
        	},
        
        	'like' : {
        		label : egCore.strings.OPERATORS_LIKE
        	}, 
        
        	ilike : {
        		label : egCore.strings.OPERATORS_ILIKE
        	},
        
        	'>' : {
        		label : egCore.strings.OPERATORS_GREATER_THAN,
        		labels : { timestamp : egCore.strings.OPERATORS_GT_TIME }
        	},
        
        	'>=' : {
        		label : egCore.strings.OPERATORS_GT_EQUAL,
        		labels : { timestamp : egCore.strings.OPERATORS_GTE_TIME }
        	}, 
        
        
        	'<' : {
        		label : egCore.strings.OPERATORS_LESS_THAN,
        		labels : { timestamp : egCore.strings.OPERATORS_LT_TIME }
        	}, 
        
        	'<=' : {
        		label : egCore.strings.OPERATORS_LT_EQUAL, 
        		labels : { timestamp : egCore.strings.OPERATORS_LTE_TIME }
        	},
        
        	'in' : {
        		label : egCore.strings.OPERATORS_IN_LIST
        	},
        
        	'not in' : {
        		label : egCore.strings.OPERATORS_NOT_IN_LIST
        	},
        
        	'between' : {
        		label : egCore.strings.OPERATORS_BETWEEN
        	},
        
        	'not between' : {
        		label : egCore.strings.OPERATORS_NOT_BETWEEN
        	},
        
        	'is' : {
        		label : egCore.strings.OPERATORS_IS_NULL
        	},
        
        	'is not' : {
        		label : egCore.strings.OPERATORS_IS_NOT_NULL
        	},
        
        	'is blank' : {
        		label : egCore.strings.OPERATORS_NULL_BLANK
        	},
        
        	'is not blank' : {
        		label : egCore.strings.OPERATORS_NOT_NULL_BLANK
        	},
        
        	'= any' : {
        		labels : { 'array' : egCore.strings.OPERATORS_EQ_ANY }
        	},
        
        	'<> any' : {
        		labels : { 'array' : egCore.strings.OPERATORS_NE_ANY }
        	}
        },

        Transforms : {
           Bare : {
                datatype : OILS_RPT_DTYPE_ALL,
                label : egCore.strings.TRANSFORMS_BARE
            },
        
            first : {
                datatype : OILS_RPT_DTYPE_NOT_ID,
                label : egCore.strings.TRANSFORMS_FIRST
            },
        
            last : {
                datatype : OILS_RPT_DTYPE_NOT_ID,
                label : egCore.strings.TRANSFORMS_LAST
            },
        
            count : {
                datatype : OILS_RPT_DTYPE_NOT_BOOL,
                aggregate : true,
                label :  egCore.strings.TRANSFORMS_COUNT
            },
        
            count_distinct : {
                datatype : OILS_RPT_DTYPE_NOT_BOOL,
                aggregate : true,
                label : egCore.strings.TRANSFORMS_COUNT_DISTINCT
            },
        
            min : {
                datatype : OILS_RPT_DTYPE_NOT_ID,
                aggregate : true,
                label : egCore.strings.TRANSFORMS_MIN
            },
        
            max : {
                datatype : OILS_RPT_DTYPE_NOT_ID,
                aggregate : true,
                label : egCore.strings.TRANSFORMS_MAX
            },
        
            /* string transforms ------------------------- */
        
            substring : {
                datatype : [ OILS_RPT_DTYPE_STRING ],
                params : 2,
                label : egCore.strings.TRANSFORMS_SUBSTRING
            },
        
            lower : {
                datatype : [ OILS_RPT_DTYPE_STRING ],
                label : egCore.strings.TRANSFORMS_LOWER
            },
        
            upper : {
                datatype : [ OILS_RPT_DTYPE_STRING ],
                label : egCore.strings.TRANSFORMS_UPPER
            },
        
            first5 : {
                datatype : [ OILS_RPT_DTYPE_STRING ],
                label : egCore.strings.TRANSFORMS_FIRST5
            },
        
                first_word : {
                        datatype : [OILS_RPT_DTYPE_STRING, 'text'],
                        label : egCore.strings.TRANSFORMS_FIRST_WORD
                },
        
            /* timestamp transforms ----------------------- */
            dow : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_DOW,
                cal_format : '%w',
                regex : /^[0-6]$/
            },
            dom : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_DOM,
                cal_format : '%e',
                regex : /^[0-9]{1,2}$/
            },
        
            doy : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_DOY,
                cal_format : '%j',
                regex : /^[0-9]{1,3}$/
            },
        
            woy : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_WOY,
                cal_format : '%U',
                regex : /^[0-9]{1,2}$/
            },
        
            moy : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_MOY,
                cal_format : '%m',
                regex : /^\d{1,2}$/
            },
        
            qoy : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_QOY,
                regex : /^[1234]$/
            }, 
        
            hod : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_HOD,
                cal_format : '%H',
                regex : /^\d{1,2}$/
            }, 
        
            date : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_DATE,
                regex : /^\d{4}-\d{2}-\d{2}$/,
                hint  : 'YYYY-MM-DD',
                cal_format : '%Y-%m-%d',
                input_size : 10
            },
        
            month_trunc : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_MONTH_TRUNC,
                regex : /^\d{4}-\d{2}$/,
                hint  : 'YYYY-MM',
                cal_format : '%Y-%m',
                input_size : 7
            },
        
            year_trunc : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_YEAR_TRUNC,
                regex : /^\d{4}$/,
                hint  : 'YYYY',
                cal_format : '%Y',
                input_size : 4
            },
        
            hour_trunc : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_HOUR_TRUNC,
                regex : /^\d{2}$/,
                hint  : 'HH',
                cal_format : '%Y-%m-$d %H',
                input_size : 2
            },
        
            day_name : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                cal_format : '%A',
                label : egCore.strings.TRANSFORMS_DAY_NAME
            }, 
        
            month_name : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                cal_format : '%B',
                label : egCore.strings.TRANSFORMS_MONTH_NAME
            },
            age : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_AGE
            },
        
            months_ago : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_MONTHS_AGO
            },
        
            quarters_ago : {
                datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
                label : egCore.strings.TRANSFORMS_QUARTERS_AGO
            },
        
            /* int  / float transforms ----------------------------------- */
            sum : {
                datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT, OILS_RPT_DTYPE_MONEY ],
                label : egCore.strings.TRANSFORMS_SUM,
                aggregate : true
            }, 
        
            average : {
                datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT, OILS_RPT_DTYPE_MONEY ],
                label : egCore.strings.TRANSFORMS_AVERAGE,
                aggregate : true
            },
        
            round : {
                datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
                label : egCore.strings.TRANSFORMS_ROUND,
            },
        
            'int' : {
                datatype : [ OILS_RPT_DTYPE_FLOAT ],
                label : egCore.strings.TRANSFORMS_INT
            }
        }
    };

    service.addFields = function (type, fields, transform, source_label, source_path, op) {
        fields.forEach(function(f) {
            var l = f.label ? f.label : f.name;
            var new_field = angular.extend(
                {},
                f,
                { index : service[type].length,
                  label : l,
                  path  : source_path,
                  path_label : source_label,
                  operator   : op,
                  transform  : transform,
                  doc_text   : ''
                }
            );

            var add = true;
            service[type].forEach(function(e) {
                if (e.name == new_field.name && e.path == new_field.path) add = false;
            });
            if (add) service[type].push(new_field);
        });
    }

    service.moveFieldUp = function (type, field) {
        var new_list = [];
        while (service[type].length) {
            var f = service[type].pop();
            if (field.index == f.index && f.index > 0)
                new_list.unshift(f,service[type].pop());
            else
                new_list.unshift(f);
        }
        new_list.forEach(function(f) {
            service[type].push(angular.extend(f, { index : service[type].length}));
        });
    }

    service.moveFieldDown = function (type, field) {
        var new_list = [];
        var start_len = service[type].length - 1;
        while (service[type].length) {
            var f = service[type].shift();
            if (field.index == f.index && f.index < start_len)
                new_list.push(service[type].shift(),f);
            else
                new_list.push(f);
        }
        new_list.forEach(function(f) {
            service[type].push(angular.extend(f, { index : service[type].length}));
        });
    }

    service.updateFilterValue = function(item, value) {
        switch (item.operator.op) {
            case 'between':
            case 'not between':
            case 'not in':
            case 'in':
                //if value isn't an array yet, split into an array for
                //  operators that need it
                if (typeof value === 'string') {
                    value = value.split(/\s*,\s*/);
                }
                break;

            default:
                //if value was split but shouldn't be, then convert back to
                //  comma-separated string
                if (Array.isArray(value)) {
                    value = value.toString();
                }
        }

        service.filter_fields[item.index].value = value;
    }

    service.removeField = function (type, field) {
        var new_list = [];
        while (service[type].length) {
            var f = service[type].shift();
            if (field.index != f.index ) new_list.push(f);
        }
        new_list.forEach(function(f) {
            service[type].push(angular.extend(f, { index : service[type].length}));
        });
    }

    service.getTransformByLabel = function (l) {
        for( var key in service.Transforms ) {
            var t = service.Transforms[key];
            if (l == t.label) return key;
            if (angular.isArray(t.labels) && t.labels.indexOf(l) > -1) return key;
        }
        return null;
    }

    service.getFilterByLabel = function (l) {
        for( var key in service.Filters ) {
            var t = service.Filters[key];
            if (l == t.label) return key;
            if (angular.isArray(t.labels) && t.labels.indexOf(l) > -1) return key;
        }
        return null;
    }

    service.getTransforms = function (args) {
        var dtype = args.datatype;
        var agg = args.aggregate;
        var nonagg = args.non_aggregate;
        var label = args.label;
    
        var tforms = [];
    
        for( var key in service.Transforms ) {
            var obj = service.Transforms[key];
            if( agg && !nonagg && !obj.aggregate ) continue;
            if( !agg && nonagg && obj.aggregate ) continue;
            if( !dtype && obj.datatype.length > 0 ) continue;
            if( dtype && obj.datatype.length > 0 && transformIsForDatatype(key,dtype).length == 0 ) continue;
            tforms.push(key);
        }
    
        return tforms;
    }


    service.transformIsForDatatype = function (tform, dtype) {
        var obj = service.Transforms[tform];
        return obj.datateype.filter(function(d) { return (d == dtype) })[0];
    }

    return service;
}])
;

