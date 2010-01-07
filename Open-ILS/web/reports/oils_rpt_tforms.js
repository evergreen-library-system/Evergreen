dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");


var OILS_RPT_TRANSFORMS = {
	Bare : {
		label : rpt_strings.TFORMS_LABEL_RAW_DATA
	},

	first : {
		label : rpt_strings.TFORMS_LABEL_FIRST
	},

	last : {
		label : rpt_strings.TFORMS_LABEL_LAST
	},

	count : {
		aggregate : true,
		label :  rpt_strings.TFORMS_LABEL_COUNT
	},

	count_distinct : {
		aggregate : true,
		label : rpt_strings.TFORMS_LABEL_COUNT_DISTINCT
	},

	min : {
		aggregate : true,
		label : rpt_strings.TFORMS_LABEL_MIN
	},

	max : {
		aggregate : true,
		label : rpt_strings.TFORMS_LABEL_MAX
	},

	/* string transforms ------------------------- */

   /* XXX not supported yet
	substring : {
		datatype : OILS_RPT_DTYPE_STRING,
		label : 'Substring'
	},
   */

	lower : {
		datatype : [OILS_RPT_DTYPE_STRING, 'text'],
		label : rpt_strings.TFORMS_LABEL_LOWER
	},

	upper : {
		datatype : [OILS_RPT_DTYPE_STRING, 'text'],
		label : rpt_strings.TFORMS_LABEL_UPPER
	},

	first5 : {
		datatype : [OILS_RPT_DTYPE_STRING, 'text'],
		label : rpt_strings.TFORMS_LABEL_FIRST5
	},

	first_word : {
		datatype : [OILS_RPT_DTYPE_STRING, 'text'],
		label : rpt_strings.TFORMS_LABEL_FIRST_WORD
	},

	/* timestamp transforms ----------------------- */
	dow : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_DOW,
		regex : /^[0-6]$/
	},
	dom : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_DOM,
		regex : /^[0-9]{1,2}$/
	},

	doy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_DOY,
		regex : /^[0-9]{1,3}$/
	},

	woy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_WOY,
		regex : /^[0-9]{1,2}$/
	},

	moy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_MOY,
		regex : /^\d{1,2}$/
	},

	qoy : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_QOY,
		regex : /^[1234]$/
	}, 

	hod : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_HOD,
		regex : /^\d{1,2}$/
	}, 

	date : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_DATE,
		regex : /^\d{4}-\d{2}-\d{2}$/,
		hint  : 'YYYY-MM-DD',
		cal_format : '%Y-%m-%d',
		input_size : 10
	},

	month_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_MONTH_TRUNC,
		regex : /^\d{4}-\d{2}$/,
		hint  : 'YYYY-MM',
		cal_format : '%Y-%m',
		input_size : 7
	},

	year_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_YEAR_TRUNC,
		regex : /^\d{4}$/,
		hint  : 'YYYY',
		cal_format : '%Y',
		input_size : 4
	},

	hour_trunc : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_HOUR_TRUNC,
		regex : /^\d{2}$/,
		hint  : 'HH',
		cal_format : '%H',
		input_size : 2
	},

	day_name : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_DAY_NAME
	}, 

	month_name : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_MONTH_NAME
	},
	age : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_AGE
	},

	months_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_MONTHS_AGO
	},

	quarters_ago : {
		datatype : OILS_RPT_DTYPE_TIMESTAMP,
		label : rpt_strings.TFORMS_LABEL_QUARTERS_AGO
	},

	/* int  / float transforms ----------------------------------- */
	sum : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : rpt_strings.TFORMS_LABEL_SUM,
		aggregate : true
	}, 

	average : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : rpt_strings.TFORMS_LABEL_AVERAGE,
		aggregate : true
	},

	round : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : rpt_strings.TFORMS_LABEL_ROUND,
	},

	'int' : {
		datatype : OILS_RPT_DTYPE_FLOAT,
		label : rpt_strings.TFORMS_LABEL_INT
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
		this.addOpt(this.tforms[i], this.tforms[i] == args.select );
	appendClear(this.node, this.selector);
}

oilsRptTformPicker.prototype.addOpt = function(key, select) {
	var tform = OILS_RPT_TRANSFORMS[key];		
	var obj = this;
	var opt = insertSelectorVal(this.selector, -1, tform.label, key);
	if( select ) opt.selected = true;
}

oilsRptTformPicker.prototype.getSelected = function(key) {
	return getSelectorVal(this.selector);
}



