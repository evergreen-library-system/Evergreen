<script language="javascript">

function field_add_remove (x) {
	var field = x.name;
	if (x.checked)
		Widget.Select.addOption('output_order',field, outputs[field]);
	else
		Widget.Select.removeOption('output_order',field);
	return true;
}


if ( typeof Widget == "undefined" ) Widget = {};

if ( typeof Widget.Select == "undefined" ) Widget.Select = {};

Widget.Select.VERSION = '0.01';


Widget.Select.selectAll = function (source){
	if (typeof(source) != 'object') source = document.getElementById(source);
	var l = source.options.length;
    for (var j=0; j<l; j++){
    	source.options[j].selected = true;
    }
}


Widget.Select.selectNone = function(source){
	if (typeof(source) != 'object') source = document.getElementById(source);
	var l = source.options.length;
    for (var j=0; j<l; j++){
    	source.options[j].selected = false;
    }
}


Widget.Select.invertSelection = function(source){
	if (typeof(source) != 'object') source = document.getElementById(source);
	var l = source.options.length;
    for (var j=0; j<l; j++){
    	source.options[j].selected = ! source.options[j].selected;
    }
}

Widget.Select._moveOption = function(e, source, s_idx, target){
			var opt = new Option(
				e.text, e.value);
			opt.selected = e.selected;
			target.options[target.options.length] = opt;
			source.options[s_idx] = null;
}


Widget.Select.moveSelectedOptionsUp = function(source){
	if (typeof(source) != 'object') source = document.getElementById(source);
	var l = source.options.length;
    for (var j=0; j<l; j++){
	
		var e = source.options[0];
		if (e.selected){
			Widget.Select._moveOption(e, source, 0, source, l);
			continue;
		}
		
	
		while (j<l-1){
			var f= source.options[1];
			if (!f.selected) break;
			Widget.Select._moveOption(f, source, 1, source, l);
			j++;
		}
	
		Widget.Select._moveOption(e, source, 0, source, l);
	}
			
}


Widget.Select.moveSelectedOptionsDown = function(source){
	if (typeof(source) != 'object') source = document.getElementById(source);
	var l = source.options.length;
    var skip=0;
    for (var j=0; j<l; j++){
		var e = source.options[0];
		if (skip == 0){
			if (e.selected){
				for (var i=1;i<l-j; i++){
					var f = source.options[i];
					if (! f.selected){
						Widget.Select._moveOption(f, source, i, source, l);
						j++;
						break;
					}
					skip++;
					
				}
				
			}
		}else{
			skip--;
		}	
		
		Widget.Select._moveOption(e, source, 0, source, l);
		
	}
			
}



Widget.Select.moveSelectedOptionsTo = function(source, target){
	if (typeof(source) != 'object') source = document.getElementById(source);
	if (typeof(target) != 'object') target = document.getElementById(target);
	for (var i=0; i<source.options.length; i++){
		var e = source.options[i];
		if(e.selected){
			Widget.Select._moveOption(e,source, i, target, target.options.length);
			i--;
		}
	}
}






Widget.Select.addOption = function (target,val,l) {
	if (typeof(target) != 'object') target = document.getElementById(target);
	target.options[target.options.length] = new Option( l, val );
}

Widget.Select.removeOption = function (target, val) {
	if (typeof(target) != 'object') target = document.getElementById(target);
	var l = target.options.length;
	for ( var i = 0; i<l; i++) {
		if (target.options[i].value == val) {
			target.options[i] = null;
			break;
		}
	}
}



</script>
