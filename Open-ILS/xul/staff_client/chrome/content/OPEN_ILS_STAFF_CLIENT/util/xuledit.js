// From Ted's Mozilla page: http://ted.mielczarek.org/code/mozilla/index.html 
// Modified by Jason for Evergreen to push in the main (auth) window reference
var old = '';
var timeout = -1;
var xwin = null;
var newwin = false;

function init()
{
  if(xwin)  // for some reason onload gets called when the browser refreshes???
    return;

  update();
  document.getElementById('ta').select();
}

function openwin()
{
  toggleBrowser(false);
  xwin = window.open('about:blank', 'xulwin', 'chrome,all,resizable=yes,width=400,height=400');
  newwin = true;
  update();
}

function toggleBrowser(show)
{
  document.getElementById("split").collapsed = !show;
  document.getElementById("content").collapsed = !show;
  document.getElementById("open").collapsed = !show;
}

function update()
{
  var textarea = document.getElementById("ta");

  // either this is the first time, or
  // they closed the window
  if(xwin == null || (xwin instanceof Window && xwin.document == null)) {
    toggleBrowser(true);
    xwin = document.getElementById("content");
    newwin = true;
  }

  if (old != textarea.value || newwin) {
    old = textarea.value;
    newwin = false;
    var dataURI = "data:application/vnd.mozilla.xul+xml," + encodeURIComponent(old);
    if(xwin instanceof Window)
      xwin.document.location = dataURI;
    else
      xwin.setAttribute("src",dataURI);
  }

  timeout = window.setTimeout(update, 500);
}

function resetTimeout()
{
  if(timeout != -1)
    window.clearTimeout(timeout);

  timeout = window.setTimeout(update, 500);
}
