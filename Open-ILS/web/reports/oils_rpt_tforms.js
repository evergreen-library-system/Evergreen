
var OILS_RPT_TRANSFORMS = {
	Bare : {
		label : 'Raw Data'
	},

	first : {
		label : 'First Value'
	},

	last : {
		label : 'Last Value'
	},

	count : {
		aggregate : true,
		label :  'Count'
	},

	count_distinct : {
		aggregate : true,
		label : 'Count Distinct'
	},

	min : {
		aggregate : true,
		label : 'Min'
	},

	max : {
		aggregate : true,
		label : 'Max'
	},

	/* string transforms ------------------------- */

	substring : {
		datatype : OILS_RPT_DTYPE_STRING,
		label : 'Substring'
	},

	lower : {
		datatype : OILS_RPT_DTYPE_STRING,
		label : 'Lower case'
	},

	upper : {
		datatype : OILS_RPT_DTYPE_STRING,
		label : 'Upper case'
	},

	/* timestamp transforms ----------------------- */
	dow : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Day of Week',
		regex : /^[0-6]$/
	},
	dom : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Day of Month',
		regex : /^[0-9]{1,2}$/
	},

	doy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Day of Year',
		regex : /^[0-9]{1,3}$/
	},

	woy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Week of Year',
		regex : /^[0-9]{1,2}$/
	},

	moy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Month of Year',
		regex : /^\d{1,2}$/
	},

	qoy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Quarter of Year',
		regex : /^[1234]$/
	}, 

	hod : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Hour of day',
		regex : /^\d{1,2}$/
	}, 

	date : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Date',
		regex : /^\d{4}-\d{2}-\d{2}$/,
		hint  : 'YYYY-MM-DD',
		cal_format : '%Y-%m-%d',
		input_size : 10
	},

	month_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Year + Month',
		regex : /^\d{4}-\d{2}$/,
		hint  : 'YYYY-MM',
		cal_format : '%Y-%m',
		input_size : 7
	},

	year_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Year',
		regex : /^\d{4}$/,
		hint  : 'YYYY',
		cal_format : '%Y',
		input_size : 4
	},

	hour_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Hour',
		regex : /^\d{2}$/,
		hint  : 'HH',
		cal_format : '%H',
		input_size : 2
	},

	day_name : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Day Name'
	}, 

	month_name : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Month Name'
	},
	age : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Age'
	},

	/*
	relative_year : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Relative year'
	},

	relative_month : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Relative month'
	},

	relative_week : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Relative week'
	},

	relative_date : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Relative date'
	},
	*/

	/* exists?
	days_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Days ago'
	}
	*/

	months_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Months ago'
	},

	quarters_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Quarters ago'
	},


	/* exists?
	years_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : 'Years ago'
	},
	*/


	/* int  / float transforms ----------------------------------- */
	sum : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : 'Sum',
		aggregate : true
	}, 

	average : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : 'Average',
		aggregate : true
	},

	round : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : 'Round',
	},

	'int' : {
		datatype : OILS_RPT_DTYPE_FLOAT,
		label : 'Drop trailing decimals'
	}
}


function oilsRptGetTforms(args) {
	var dtype = args.datatype;
	var agg = args.aggregate;
	var tforms = OILS_RPT_TRANSFORMS;
	var nonagg = args.non_aggregate;

	var keys = oilsRptObjectKeys(OILS_RPT_TRANSFORMS);
	var tforms = [];

	_debug('getting tform '+dtype+' : ' + agg + ' : ' + nonagg);

	for( var i = 0; i < keys.length; i++ ) {
		var key = keys[i];
		var obj = OILS_RPT_TRANSFORMS[key];
		if( dtype && !oilsRptTformIsDtype(key,dtype) ) continue;
		if( agg && !nonagg && !obj.aggregate ) continue;
		if( !agg && nonagg && obj.aggregate ) continue;
		tforms.push(key);
	}

	return tforms;
}


function oilsRptTformIsDtype(tform, dtype) {
	var obj = OILS_RPT_TRANSFORMS[tform];
	if( typeof obj.datatype == 'string' )
		return (obj.datatype == dtype);
	return !obj.datatype || grep(obj.datatype, function(d) { return (d == dtype) });
}




/* builds a new transform picker */
function oilsRptTformPicker(args) {
	this.node = args.node;
	this.selector = elem('select');
	this.tforms = oilsRptGetTforms(args);
	for( var i = 0; i < this.tforms.length; i++ ) 
		this.addOpt(this.tforms[i]);
	appendClear(this.node, this.selector);
}

oilsRptTformPicker.prototype.addOpt = function(key) {
	var tform = OILS_RPT_TRANSFORMS[key];		
	var obj = this;
	insertSelectorVal(this.selector, -1, tform.label, key);
}

oilsRptTformPicker.prototype.getSelected = function(key) {
	return getSelectorVal(this.selector);
}



