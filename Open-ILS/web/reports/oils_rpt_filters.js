dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

var OILS_RPT_FILTERS = {
	'=' : {
		label : rpt_strings.FILTERS_LABEL_EQUALS
	},

	'like' : {
		label : rpt_strings.FILTERS_LABEL_LIKE
	}, 

	ilike : {
		label : rpt_strings.FILTERS_LABEL_ILIKE
	},

	'>' : {
		label : rpt_strings.FILTERS_LABEL_GREATER_THAN,
		labels : { timestamp : rpt_strings.FILTERS_LABEL_GT_TIME }
	},

	'>=' : {
		label : rpt_strings.FILTERS_LABEL_GT_EQUAL,
		labels : { timestamp : rpt_strings.FILTERS_LABEL_GTE_TIME }
	}, 


	'<' : {
		label : rpt_strings.FILTERS_LABEL_LESS_THAN,
		labels : { timestamp : rpt_strings.FILTERS_LABEL_LT_TIME }
	}, 

	'<=' : {
		label : rpt_strings.FILTERS_LABEL_LT_EQUAL,
		labels : { timestamp : rpt_strings.FILTERS_LABEL_LSE_TIME }
	},

	'in' : {
		label : rpt_strings.FILTERS_LABEL_IN
	},

	'not in' : {
		label : rpt_strings.FILTERS_LABEL_NOT_IN
	},

	'between' : {
		label : rpt_strings.FILTERS_LABEL_BETWEEN
	},

	'not between' : {
		label : rpt_strings.FILTERS_LABEL_NOT_BETWEEN
	},

	'is' : {
		label : rpt_strings.FILTERS_LABEL_NULL
	},

	'is not' : {
		label : rpt_strings.FILTERS_LABEL_NOT_NULL
    },

    'is blank' : {
        label : rpt_strings.FILTERS_LABEL_NULL_BLANK
    },

    'is not blank' : {
        label : rpt_strings.FILTERS_LABEL_NOT_NULL_BLANK
	}
}


function oilsRptFilterPicker(args) {
	this.node = args.node;
	this.dtype = args.datatype;
	this.selector = elem('select');
	for( var key in OILS_RPT_FILTERS ) 
		this.addOpt(key, key == args.select );
	appendClear(this.node, this.selector);
}


oilsRptFilterPicker.prototype.addOpt = function(key, select) {
	var filter = OILS_RPT_FILTERS[key];
	var label = filter.label;
	var opt = insertSelectorVal( this.selector, -1, label, key);
	if( select ) opt.selected = true;
	if( filter.labels && filter.labels[this.dtype] ) 
		insertSelectorVal( this.selector, -1, filter.labels[this.dtype], key);
}

oilsRptFilterPicker.prototype.getSelected = function() {
	return getSelectorVal(this.selector);
}




