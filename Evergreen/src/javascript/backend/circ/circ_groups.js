/* ---------------------------------------------------------------------
	Set up the limits for the various profiles (aka permission groups).
	Values of -1 mean there is no limit 

	maxItemsOut			- the maximum number of items the user can have out
	fineThreshold		- the fine threshold. 
	overdueThreshold	- the overdue items threshold.
	maxHolds				- The maximum number of holds the user can have

	A user exceeds the fineThreshold and/or overdueThreshold if they are 
	equal to or exceed the threshold
	--------------------------------------------------------------------- */

var GROUP_CONFIG = {

	'Patron' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'Class' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: 15
	},

	'Friend'	: {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'NonResident' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'OutOfState' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'Outreach' : {
		maxItemsOut			: -1,
		fineThreshold		: -1,
		overdueThreshold	: -1,
		maxHolds				: 15
	},


	'Restricted' : {
		maxItemsOut			: 2,
		fineThreshold		: 0.01,
		overdueThreshold	: 1,
		maxHolds				: 5
	},

	'Temp' : {
		maxItemsOut			: 5,
		fineThreshold		: .01,
		overdueThreshold	: 1,
		maxHolds				: 5
	},

	'TempRes6' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'tempRes12' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: -1
	},

	'Trustee' : {
		maxItemsOut			: 50,
		fineThreshold		: 10,
		overdueThreshold	: 10,
		maxHolds				: 10
	},


	'Vendor' : {
		maxItemsOut			: 0,
		fineThreshold		: 0.01,
		overdueThreshold	: 1,
		maxHolds				: 0
	},

	'Staff' : {
		maxItemsOut			: 50,
		fineThreshold		: -1,
		overdueThreshold	: -1,
		maxHolds				: -1 
	},

};





