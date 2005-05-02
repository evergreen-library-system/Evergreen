/* detect my browser */

var isMac
var NS;
var NS4;
var NS6;
var IE;
var IE4;
var IE4mac;
var IE4plus;
var IE5;
var IE5plus;
var IE6;
var IEMajor;
var ver4;

function detect_browser() {       

	isMac = (navigator.appVersion.indexOf("Mac")!=-1) ? true : false;
	NS = (navigator.appName == "Netscape") ? true : false;
	NS4 = (document.layers) ? true : false;
	IE = (navigator.appName == "Microsoft Internet Explorer") ? true : false;
	IEmac = ((document.all)&&(isMac)) ? true : false;
	IE4plus = (document.all) ? true : false;
	IE4 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 4.")!=-1)) ? true : false;
	IE5 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 5.")!=-1)) ? true : false;
	IE6 = ((document.all)&&(navigator.appVersion.indexOf("MSIE 6.")!=-1)) ? true : false;
	ver4 = (NS4 || IE4plus) ? true : false;
	NS6 = (!document.layers) && (navigator.userAgent.indexOf('Netscape')!=-1)?true:false;

	IE5plus = IE5 || IE6;
	IEMajor = 0;

	if (IE4plus) {
		var start = navigator.appVersion.indexOf("MSIE");
		var end = navigator.appVersion.indexOf(".",start);
		IEMajor = parseInt(navigator.appVersion.substring(start+5,end));
		IE5plus = (IEMajor>=5) ? true : false;
	}
}

detect_browser();

