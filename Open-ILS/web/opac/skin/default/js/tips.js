attachEvt('result', 'allRecordsReceived', insertTip);

/*
var user_tips = [
	'Click on a folder icon in the sidebar to access related quick searches',
	"If you don't find what you want try expanding your search using the range selector at the right of the search bar"
];
*/

function insertTip () {
	var tip_div = document.getElementById('tips');
	if (tip_div) {
		var tips = tip_div.getElementsByTagName('div')[0].getElementsByTagName('span');
		var index = Math.floor(Math.random() * tips.length);
		tip_div.appendChild( tips[index] );
		removeCSSClass(tip_div, 'hide_me');
	}
}

