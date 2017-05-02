;(function () {
  var GBisbns = [];
  var GBPBadgelink;
  var GBPreviewLink = '';
  var GBPreviewShowing = false;
  var lang = 'en';
  if (document.documentElement.lang) {
    lang = document.documentElement.lang.substr(0,2) || 'en';
  }
  var head = document.getElementsByTagName('head')[0];

/**
 * This function is the call-back function for the JSON scripts which
 * executes a Google book search response.
 *
 * @param {JSON} GBPBookInfo is the JSON object pulled from the Google books service.
 */
  function GBPreviewCallback (GBPBookInfo) {
    if (GBPBookInfo.totalItems < 1) {
      return;
    }

    var accessInfo = GBPBookInfo.items[0].accessInfo;
    if (!accessInfo) {
      return;
    }

    if (accessInfo.embeddable) {
      GBPreviewLink = GBPBookInfo.items[0].volumeInfo.previewLink;
      if (!GBPreviewLink) {
        return;
      }
      if (document.location.protocol === 'https:') {
        GBPreviewLink = GBPreviewLink.replace(/^http:/, 'https:');
      }
      var gbsrc = '//www.google.com/books/jsapi.js';
      if (!head.querySelector('script[src="' + gbsrc + '"]')) {
        var GBjsapi = document.createElement('script');
        GBjsapi.src = gbsrc;
        head.appendChild(GBjsapi);
      }
    /* Add a button below the book cover image to load the preview. */
      var GBPBadge = document.createElement('img');
      GBPBadge.id = 'gbpbadge';
      GBPBadge.src = 'https://www.google.com/intl/' + lang + '/googlebooks/images/gbs_preview_button1.gif';
      GBPBadge.title = document.getElementById('rdetail_title').innerHTML;
      GBPBadge.style.border = 0;
      GBPBadge.style.margin = '0.5em 0 0 0';
      GBPBadgelink = document.createElement('a');
      GBPBadgelink.id = 'gbpbadge_link';
      GBPBadgelink.addEventListener('click', GBDisplayPreview);
      GBExtrasActivate(true);
      GBPBadgelink.appendChild(GBPBadge);
      document.getElementById('rdetail_title_div').appendChild(GBPBadgelink);
      document.getElementById('gbp_extra').style.display = 'block';
    }
  }

  function GBPViewerLoadCallback () {
    var GBPViewer = new google.books.DefaultViewer(document.getElementById('rdetail_preview_div'));
    GBPViewer.load(GBPreviewLink);
    GBPViewer.resize();
    GBPBadgelink = document.getElementById('gbpbadge_link');
    GBPBadgelink.removeEventListener('click', GBDisplayPreview);
    GBPBadgelink.addEventListener('click', GBShowHidePreview);
  }

  function GBExtrasActivate (init) {
    var extras = document.getElementById('gbp_extra_links').getElementsByTagName('a');
    for (var i = 0; i < extras.length; i++) {
      if (init) {
        extras[i].addEventListener('click', GBDisplayPreview);
      } else {
        extras[i].removeEventListener('click', GBDisplayPreview);
        extras[i].addEventListener('click', GBShowHidePreview);
      }
    }
  }

/**
 *  This is called when the user clicks on the 'Preview' link.  We assume
 *  a preview is available from Google if this link was made visible.
 */
  function GBDisplayPreview () {
    var GBPreviewPane = document.getElementById('rdetail_preview_div');
    if (GBPreviewPane === null || typeof GBPreviewPane.loaded === 'undefined' || GBPreviewPane.loaded === 'false') {
      GBPreviewPane = document.createElement('div');
      GBPreviewPane.id = 'rdetail_preview_div';
      GBPreviewPane.style.height = document.documentElement.clientHeight + 'px';
      GBPreviewPane.style.width = document.documentElement.clientWidth + 'px';
      GBPreviewPane.style.display = 'block';
      var GBClear = document.createElement('div');
      GBClear.style.padding = '1em';
      document.getElementById('gbp_extra_container').appendChild(GBPreviewPane);
      document.getElementById('gbp_extra_container').appendChild(GBClear);
      google.books.load({'language': lang});
      window.setTimeout(GBPViewerLoadCallback, 750);
      GBPreviewPane.loaded = 'true';
    }
    GBShowHidePreview();
    document.location.hash = '#gbp_extra';
  }

  function GBShowHidePreview () {
    if (!GBPreviewShowing) {
      document.getElementById('gbp_extra_container').style.display = 'inherit';
      document.getElementById('gbp_arrow_link').style.display = 'none';
      document.getElementById('gbp_arrow_down_link').style.display = 'inline';
      GBPreviewShowing = true;
      document.location.hash = '#gbp_extra';
    } else { // button can open, but shouldn't close
      document.getElementById('gbp_extra_container').style.display = 'none';
      document.getElementById('gbp_arrow_link').style.display = 'inline';
      document.getElementById('gbp_arrow_down_link').style.display = 'none';
      GBPreviewShowing = false;
      document.location.hash = 'rdetail_title';
    }
  }

  function GBLoader () {
    var spans = document.body.querySelectorAll('li.rdetail_isbns span.rdetail_value');
    for (var i = 0; i < spans.length; i++) {
      var prop = spans[i].getAttribute('property');
      if (!prop) {
        continue;
      }
      var isbn = spans[i].textContent || spans[i].innerText
      if (!isbn) {
        continue;
      }
      isbn = isbn.toString().replace(/^\s+/, '');
      var idx = isbn.indexOf(' ');
      if (idx > -1) {
        isbn = isbn.substring(0, idx);
      }
      isbn = isbn.toString().replace(/-/g, '');
      if (!isbn) {
        continue;
      }
      GBisbns.push(isbn);
    }

    if (GBisbns.length) {
      var req = new window.XMLHttpRequest();
      var qisbn = encodeURIComponent('isbn:' + GBisbns[0]);
      req.open('GET', 'https://www.googleapis.com/books/v1/volumes?q=' + qisbn + '&prettyPrint=false');
      if (req.responseType && (req.responseType = 'json')) {
        req.onload = function (evt) {
          var result = req.response;
          if (result) {
            GBPreviewCallback(result);
          }
        }
      } else {
      // IE 10/11
        req.onload = function (evt) {
          var result = JSON.parse(req.responseText);
          if (result) {
            GBPreviewCallback(result);
          }
        }
      }
      req.send();
    }
  };

  // Skips IE9
  if (window.addEventListener && !window.XDomainRequest) {
    window.addEventListener('load', GBLoader, false);
  }
})()
