/* hledger web ui javascript */

//----------------------------------------------------------------------
// STARTUP

document.addEventListener('DOMContentLoaded', function() {

  // Open and close the dialogs. The data-toggle/data-target/data-dismiss
  // attributes in the templates are the hooks.
  document.querySelectorAll('[data-toggle="modal"]').forEach(function(el) {
    el.addEventListener('click', function(e) {
      e.preventDefault();
      var d = document.querySelector(el.getAttribute('data-target'));
      if (!d) { return; }
      if (d.id === 'addmodal') { addformShow(); } else { d.showModal(); }
    });
  });
  document.querySelectorAll('[data-dismiss="modal"]').forEach(function(el) {
    el.addEventListener('click', function() {
      var d = el.closest('dialog');
      if (d) { d.close(); }
    });
  });
  // Clicking the backdrop closes a modal dialog. With showModal() a click on
  // the backdrop is reported as a click on the dialog element itself.
  document.querySelectorAll('dialog').forEach(function(d) {
    d.addEventListener('click', function(e) {
      if (e.target === d) { d.close(); }
    });
  });

  // Typing in the last amount field adds another posting row. Delegating from
  // the form means the handler does not have to be moved as rows come and go.
  var addform = document.getElementById('addform');
  if (addform) {
    addform.addEventListener('keypress', function(e) {
      if (!e.target.classList.contains('amount-input')) { return; }
      var amounts = addform.querySelectorAll('.amount-input');
      if (e.target === amounts[amounts.length - 1]) { addformAddPosting(); }
    });
  }

  // The date field is a text input, so hledger's smart dates ("today", "2/15")
  // keep working. The button beside it opens the browser's own calendar, via
  // the hidden date input, and what you pick is written back as an iso date.
  var datebutton = document.getElementById('datebutton');
  var datepicked = document.getElementById('datepicked');
  if (datebutton && datepicked) {
    datebutton.addEventListener('click', function() {
      var datefield = document.querySelector('#addform input[name=date]');
      datepicked.value = /^\d{4}-\d{2}-\d{2}$/.test(datefield.value) ? datefield.value : isoDate();
      if (datepicked.showPicker) { datepicked.showPicker(); }
    });
    datepicked.addEventListener('change', function() {
      var datefield = document.querySelector('#addform input[name=date]');
      if (datepicked.value) { datefield.value = datepicked.value; }
    });
  }

  // Keyboard shortcuts. Not while typing in a field, or the search box would
  // toggle the sidebar and open the add form as you spell "assets".
  document.addEventListener('keydown', function(e) {
    if (e.ctrlKey || e.metaKey || e.altKey) { return; }
    if (e.target.closest('input, textarea, select')) { return; }
    if (document.querySelector('dialog[open]')) { return; }
    switch (e.key) {
      case 'h': case '?': helpToggle();                                     break;
      case 'j': location.href = document.hledgerWebBaseurl + '/journal';     break;
      case 's': sidebarToggle();                                            break;
      case 'e': emptyAccountsToggle();                                      break;
      case 'a': case 'n': addformShow();                                    break;
      case 'f': focusSearch();                                              break;
      default: return;
    }
    e.preventDefault();
  });

  // Name the chosen file beside the upload button. Set as text, so a file whose
  // name contains markup is shown, not parsed.
  var fileinput = document.getElementById('file');
  if (fileinput) {
    fileinput.addEventListener('change', function() {
      var info = document.getElementById('file-info');
      if (info) {
        info.textContent = fileinput.files[0] ? fileinput.files[0].name : '';
      }
    });
  }

  document.querySelectorAll('[data-toggle="offcanvas"]').forEach(function(el) {
    el.addEventListener('click', function() {
      var row = document.querySelector('.row-offcanvas');
      if (row) { row.classList.toggle('active'); }
    });
  });

  registerChartInit();
});

// The entry targeted by the url hash is marked by a :target rule in
// hledger.css, which needs no javascript. Note that register rows have
// numeric ids, so location.hash must not be passed to querySelector.

// The account sidebar's scroll position is preserved across page navigations
// by an inline script right after the sidebar's markup in
// default-layout.hamlet. It must run during page parse, not from this file:
// this script loads at the end of the body and DOMContentLoaded fires only
// once the whole document is parsed, while the browser paints the sidebar
// (at scroll position 0) much earlier when a long journal or register
// follows it, which made the sidebar visibly jump on page load.

//----------------------------------------------------------------------
// ADD FORM

function addformShow(showmsg) {
  var d = document.getElementById('addmodal');
  if (!d || d.open) { return; }  // showModal() throws if already open
  addformReset(typeof showmsg !== 'undefined' ? showmsg : false);
  d.showModal();
  addformFocus();
}

function helpToggle() {
  var d = document.getElementById('helpmodal');
  if (!d) { return; }
  if (d.open) {
    d.close();
  } else {
    d.showModal();
    // showModal() focuses the first focusable element, which here is the
    // close button; focus the dialog itself so it opens without a focus ring.
    d.focus();
  }
}

// Make sure the add form is empty and clean and has the default number of rows.
function addformReset(showmsg) {
  var addform = document.getElementById('addform');
  if (!addform) { return; }
  if (!showmsg) {
    var msg = document.getElementById('message');
    if (msg) { msg.innerHTML = ''; }
  }
  addform.querySelectorAll('.account-group.added-row').forEach(function(el) {
    el.remove();
  });
  addform.reset();
}

// Pre-fill today's date and focus the description field in the add form.
function addformFocus() {
  var addform = document.getElementById('addform');
  if (!addform) { return; }
  addform.querySelector('input[name=date]').value = isoDate();
  // Deferred, so the field is focusable: http://stackoverflow.com/a/7046837
  setTimeout(function() {
    addform.querySelector('input[name=description]').focus();
  }, 0);
}

function isoDate() {
  return new Date().toLocaleDateString("sv");  // https://stackoverflow.com/a/58633651/84401
}

function focusSearch() {
  var q = document.querySelector('#searchform input');
  if (q) { q.focus(); }
}

// Insert another posting row in the add form.
function addformAddPosting() {
  var addform = document.getElementById('addform');
  if (!addform) { return; }
  var groups = addform.querySelectorAll('.account-group');
  var newrow = groups[groups.length - 1].cloneNode(true);
  newrow.classList.add('added-row');
  var num = groups.length + 1;

  // The cloned row may carry error styling from a previous failed submit.
  newrow.querySelectorAll('.has-error').forEach(function(el) { el.classList.remove('has-error'); });
  newrow.querySelectorAll('.error-block').forEach(function(el) { el.remove(); });

  var account = newrow.querySelector('input[name=account]');
  var amount = newrow.querySelector('input[name=amount]');
  account.value = '';
  amount.value = '';
  account.placeholder = 'Account ' + num;
  amount.placeholder = 'Amount ' + num;

  addform.querySelector('.account-postings').appendChild(newrow);
}

//----------------------------------------------------------------------
// SIDEBAR

function sidebarToggle() {
  var sidebar = document.getElementById('sidebar-menu');
  var main = document.getElementById('main-content');
  var spacer = document.getElementById('spacer');
  [sidebar, spacer].forEach(function(el) {
    if (el) { el.classList.toggle('col-md-4'); el.classList.toggle('col-sm-4'); el.classList.toggle('col-any-0'); }
  });
  if (main) {
    main.classList.toggle('col-md-8'); main.classList.toggle('col-sm-8');
    main.classList.toggle('col-md-12'); main.classList.toggle('col-sm-12');
  }
  // The server reads this cookie, so the next page renders the way we left it.
  setCookie('showsidebar', sidebar && sidebar.classList.contains('col-any-0') ? '0' : '1');
}

function emptyAccountsToggle() {
  document.querySelectorAll('.acct.empty').forEach(function(el) {
    el.parentNode.classList.toggle('hide');
  });
  setCookie('hideemptyaccts', getCookie('hideemptyaccts') === '1' ? '0' : '1');
}

function setCookie(name, value) {
  document.cookie = name + '=' + value + '; path=/; max-age=31536000; samesite=lax';
}

function getCookie(name) {
  return document.cookie.split('; ').reduce(function(found, c) {
    var parts = c.split('=');
    return parts[0] === name ? parts.slice(1).join('=') : found;
  }, undefined);
}

//----------------------------------------------------------------------
// REGISTER CHART
//
// The register page's balance chart, drawn with flot. chart.hamlet renders
// only the markup, with the data as JSON on #register-chart, so that pages
// carry no inline scripts beyond the nonced ones (#2703). flot needs jquery,
// so this section uses it too.

// Draw the register chart, if this page has one.
function registerChartInit() {
  var $chartdiv = $('#register-chart');
  // flot needs a container with a size, so do nothing while it is hidden.
  if (!$chartdiv.length || !$chartdiv.is(':visible')) { return; }
  var $label = $('#register-chart-label');
  $label.text($chartdiv.attr('data-title'));
  var commodities = JSON.parse($chartdiv.attr('data-series'));
  // Each commodity is drawn as two flot series over the same points: a
  // stepped line for the running balance, and one clickable, hoverable point
  // per transaction. A point is [timestamp, balance, amount text, balance
  // text, transaction text, transaction index]: flot reads the first two,
  // the tooltip and click handlers the rest.
  var series = [];
  commodities.forEach(function(c, i) {
    series.push({
      data: c.points, label: c.label, color: i,
      lines: { show: true, steps: true }, points: { show: false },
      clickable: false, hoverable: false,
    });
    series.push({
      data: c.points, color: i,
      lines: { show: false }, points: { show: true },
    });
  });
  var plot = registerChart($chartdiv, series);
  registerChartLegend($label, plot);
  $chartdiv.bind('plotclick', registerChartClick);
  $chartdiv.bind('plotselected', registerChartSelect);
}

function registerChart($container, series) {
  // https://github.com/flot/flot/blob/master/API.md
  return $container.plot(
    series,
    {
      xaxis: {
        mode: "time",
        timeformat: "%Y/%m/%d",
      },
      selection: {
        mode: "x"
      },
      // flot's legend is built from inline style attributes, which the
      // Content-Security-Policy blocks; registerChartLegend draws ours.
      legend: {
        show: false
      },
      grid: {
        markings: function () {
          var now = Date.now();
          return [
            {
              xaxis: { to: now }, // past
              yaxis: { to: 0 },   // <0
              color: '#ffdddd',
            },
            {
              xaxis: { from: now }, // future
              yaxis: { from: 0 },   // >0
              color: '#e0e0e0',
            },
            {
              xaxis: { from: now }, // future
              yaxis: { to: 0 },     // <0
              color: '#e8c8c8',
            },
            {
              yaxis: { from: 0, to: 0 }, // =0
              color: '#bb0000',
              lineWidth:1
            },
          ];
        },
        hoverable: true,
        autoHighlight: true,
        clickable: true,
      },
      // https://github.com/krzysu/flot.tooltip
      tooltip: true,
      tooltipOpts: {
        xDateFormat: "%Y/%m/%d",
        content:
          function(label, x, y, flotitem) {
            var data = flotitem.series.data[flotitem.dataIndex];
            // The plugin renders this as html. Build it from text nodes and
            // let the browser serialize it, so the journal text cannot be
            // parsed as markup.
            return $('<div>')
              .append(document.createTextNode(data[3] + " balance on %x after " + data[2] + " posted by transaction:"))
              .append($('<pre>').text(data[4]))
              .html();
          },
        onHover: function(flotitem, $tooltipel) {
          $tooltipel.css('border-color', flotitem.series.color);
        },
      },
    }
  ).data("plot");
}

// Add the legend to the label line: a color swatch and the commodity for
// each balance line.
function registerChartLegend($label, plot) {
  plot.getData().forEach(function(s) {
    if (typeof s.label !== 'string') { return; }
    var $swatch = $('<span class="legend-swatch">').css('background-color', s.color);
    $('<span class="legend-item">').append($swatch, document.createTextNode(s.label)).appendTo($label);
  });
}

// Handle a click on a chart point: scroll to that transaction's row.
function registerChartClick(ev, pos, item) {
  if (!item) { return; }
  var id = String(item.series.data[item.dataIndex][5]);
  var target = document.getElementById(id);
  if (target) {
    window.location.hash = '#' + id;
    $('html, body').animate({ scrollTop: $(target).offset().top }, 1000);
  }
}

// Handle a selection (zoom) on the chart: reload with a date: query for
// the selected range.
function registerChartSelect(ev, ranges) {
  // Reconstruct from/to dates carefully based on the selected x-values.
  // Those x values are unix timestamps (milliseconds since epoch) enclosing the data points' timestamps.
  // Those are generated by dayToUtcNoonTimestamp, and are UTC times representing the transaction dates.
  var from = new Date(ranges.xaxis.from);
  var fromy = from.getUTCFullYear();
  var fromm = from.getUTCMonth() + 1;
  var fromd = from.getUTCDate();
  var to = new Date(ranges.xaxis.to + 1 * 24 * 60 * 60 * 1000);
  var toy = to.getUTCFullYear();
  var tom = to.getUTCMonth() + 1;
  var tod = to.getUTCDate();

  var range = fromy + "/" + fromm + "/" + fromd + "-" + toy + "/" + tom + "/" + tod;
  // The base link is this register's url without its date terms; add ours.
  var url = new URL($('#register-chart').attr('data-baselink'), document.baseURI);
  var q = url.searchParams.get('q');
  url.searchParams.set('q', (q ? q + ' ' : '') + 'date:' + range);
  document.location = url.href;
}
