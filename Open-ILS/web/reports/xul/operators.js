dojo.requireLocalization("openils.reports", "reports");

var rpt_strings = dojo.i18n.getLocalization("openils.reports", "reports");

var OILS_RPT_FILTERS = {
	'=' : {
		label : rpt_strings.OPERATORS_EQUALS
	},

	'like' : {
		label : rpt_strings.OPERATORS_LIKE
	}, 

	ilike : {
		label : rpt_strings.OPERATORS_ILIKE
	},

	'>' : {
		label : rpt_strings.OPERATORS_GREATER_THAN,
		labels : { timestamp : rpt_strings.OPERATORS_GT_TIME }
	},

	'>=' : {
		label : rpt_strings.OPERATORS_GT_EQUAL,
		labels : { timestamp : rpt_strings.OPERATORS_GTE_TIME }
	}, 


	'<' : {
		label : rpt_strings.OPERATORS_LESS_THAN,
		labels : { timestamp : rpt_strings.OPERATORS_LT_TIME }
	}, 

	'<=' : {
		label : rpt_strings.OPERATORS_LT_EQUAL, 
		labels : { timestamp : rpt_strings.OPERATORS_LTE_TIME }
	},

	'in' : {
		label : rpt_strings.OPERATORS_IN_LIST
	},

	'not in' : {
		label : rpt_strings.OPERATORS_NOT_IN_LIST
	},

	'between' : {
		label : rpt_strings.OPERATORS_BETWEEN
	},

	'not between' : {
		label : rpt_strings.OPERATORS_NOT_BETWEEN
	},

	'is' : {
		label : rpt_strings.OPERATORS_IS_NULL
	},

	'is not' : {
		label : rpt_strings.OPERATORS_IS_NOT_NULL
	},

	'is blank' : {
		label : rpt_strings.OPERATORS_NULL_BLANK
	},

	'is not blank' : {
		label : rpt_strings.OPERATORS_NOT_NULL_BLANK
	}
}

