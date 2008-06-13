
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

