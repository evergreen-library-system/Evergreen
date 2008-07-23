var OILS_RPT_FILTERS = {
	'=' : {
		label : 'Equals',
	},

	'like' : {
		label : 'Contains Matching substring',
	}, 

	ilike : {
		label : 'Contains Matching substring (ignore case)',
	},

	'>' : {
		label : 'Greater than',
		labels : { timestamp : 'After (Date/Time)' }
	},

	'>=' : {
		label : 'Greater than or equal to',
		labels : { timestamp : 'On or After (Date/Time)' }
	}, 


	'<' : {
		label : 'Less than',
		labels : { timestamp : 'Before (Date/Time)' }
	}, 

	'<=' : {
		label : 'Less than or equal to', 
		labels : { timestamp : 'On or Before (Date/Time)' }
	},

	'in' : {
		label : 'In list',
	},

	'not in' : {
		label : 'Not in list',
	},

	'between' : {
		label : 'Between',
	},

	'not between' : {
		label : 'Not between',
	},

	'is' : {
		label : 'Is NULL'
	},

	'is not' : {
		label : 'Is not NULL'
    },

    'is blank' : {
        label : 'Is NULL or Blank'
    },

    'is not blank' : {
        label : 'Is not NULL or Blank'
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




