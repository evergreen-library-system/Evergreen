attachEvt('common', 'run', insertTip);

var user_tips = [
	'Click on a folder icon in the sidebar to access related quick searches',
	"If you don't find what you want try expanding your search using the range selector at the right of the search bar"
];

function insertTip () {
	var tip_div = document.getElementById('tips');
	if (tip_div)
		tip_div.appendChild( text( user_tips[ Math.floor(Math.random() * user_tips.length) ] ) );
}

