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
var OILS_RPT_DTYPE_NOT_BOOL = [OILS_RPT_DTYPE_STRING,OILS_RPT_DTYPE_MONEY,OILS_RPT_DTYPE_INT,OILS_RPT_DTYPE_FLOAT,OILS_RPT_DTYPE_TIMESTAMP,OILS_RPT_DTYPE_ID];

var OILS_RPT_TRANSFORMS = {
	Bare : {
		datatype : OILS_RPT_DTYPE_ALL,
		label : 'Raw Data'
	},

	first : {
		datatype : OILS_RPT_DTYPE_NOT_ID,
		label : 'First Value'
	},

	last : {
		datatype : OILS_RPT_DTYPE_NOT_ID,
		label : 'Last Value'
	},

	count : {
		datatype : OILS_RPT_DTYPE_NOT_BOOL,
		aggregate : true,
		label :  'Count'
	},

	count_distinct : {
		datatype : OILS_RPT_DTYPE_NOT_BOOL,
		aggregate : true,
		label : 'Count Distinct'
	},

	min : {
		datatype : OILS_RPT_DTYPE_NOT_ID,
		aggregate : true,
		label : 'Min'
	},

	max : {
		datatype : OILS_RPT_DTYPE_NOT_ID,
		aggregate : true,
		label : 'Max'
	},

	/* string transforms ------------------------- */

	substring : {
		datatype : [ OILS_RPT_DTYPE_STRING ],
		params : 2,
		label : 'Substring'
	},

	lower : {
		datatype : [ OILS_RPT_DTYPE_STRING ],
		label : 'Lower case'
	},

	upper : {
		datatype : [ OILS_RPT_DTYPE_STRING ],
		label : 'Upper case'
	},

	firt5 : {
		datatype : [ OILS_RPT_DTYPE_STRING ],
		label : 'First 5 characters (for US ZIP code)'
	},

	/* timestamp transforms ----------------------- */
	dow : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Day of Week',
		cal_format : '%w',
		regex : /^[0-6]$/
	},
	dom : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Day of Month',
		cal_format : '%e',
		regex : /^[0-9]{1,2}$/
	},

	doy : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Day of Year',
		cal_format : '%j',
		regex : /^[0-9]{1,3}$/
	},

	woy : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Week of Year',
		cal_format : '%U',
		regex : /^[0-9]{1,2}$/
	},

	moy : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Month of Year',
		cal_format : '%m',
		regex : /^\d{1,2}$/
	},

	qoy : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Quarter of Year',
		regex : /^[1234]$/
	}, 

	hod : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Hour of day',
		cal_format : '%H',
		regex : /^\d{1,2}$/
	}, 

	date : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Date',
		regex : /^\d{4}-\d{2}-\d{2}$/,
		hint  : 'YYYY-MM-DD',
		cal_format : '%Y-%m-%d',
		input_size : 10
	},

	month_trunc : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Year + Month',
		regex : /^\d{4}-\d{2}$/,
		hint  : 'YYYY-MM',
		cal_format : '%Y-%m',
		input_size : 7
	},

	year_trunc : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Year',
		regex : /^\d{4}$/,
		hint  : 'YYYY',
		cal_format : '%Y',
		input_size : 4
	},

	hour_trunc : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Hour',
		regex : /^\d{2}$/,
		hint  : 'HH',
		cal_format : '%Y-%m-$d %H',
		input_size : 2
	},

	day_name : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		cal_format : '%A',
		label : 'Day Name'
	}, 

	month_name : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		cal_format : '%B',
		label : 'Month Name'
	},
	age : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Age'
	},

	months_ago : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Months ago'
	},

	quarters_ago : {
		datatype : [ OILS_RPT_DTYPE_TIMESTAMP ],
		label : 'Quarters ago'
	},

	/* int  / float transforms ----------------------------------- */
	sum : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT, OILS_RPT_DTYPE_MONEY ],
		label : 'Sum',
		aggregate : true
	}, 

	average : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT, OILS_RPT_DTYPE_MONEY ],
		label : 'Average',
		aggregate : true
	},

	round : {
		datatype : [ OILS_RPT_DTYPE_INT, OILS_RPT_DTYPE_FLOAT ],
		label : 'Round',
	},

	'int' : {
		datatype : [ OILS_RPT_DTYPE_FLOAT ],
		label : 'Drop trailing decimals'
	}
}

function getTransforms(args) {
	var dtype = args.datatype;
	var agg = args.aggregate;
	var tforms = OILS_RPT_TRANSFORMS;
	var nonagg = args.non_aggregate;

	var keys = getKeys(OILS_RPT_TRANSFORMS)
	var tforms = [];

	for( var i = 0; i < keys.length; i++ ) {
		var key = keys[i];
		var obj = OILS_RPT_TRANSFORMS[key];
		if( agg && !nonagg && !obj.aggregate ) continue;
		if( !agg && nonagg && obj.aggregate ) continue;
		if( !dtype && obj.datatype.length > 0 ) continue;
		if( dtype && obj.datatype.length > 0 && transformIsForDatatype(key,dtype).length == 0 ) continue;
		tforms.push(key);
	}

	return tforms;
}


function transformIsForDatatype(tform, dtype) {
	var obj = OILS_RPT_TRANSFORMS[tform];
	return grep(function(d) { return (d == dtype) }, obj.datatype);
}


