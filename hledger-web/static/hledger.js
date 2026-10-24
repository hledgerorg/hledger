/* hledger web ui javascript */

//----------------------------------------------------------------------
// STARTUP

document.addEventListener('DOMContentLoaded', function() {

  // First, so that nothing below can stop it.
  browsePingInit();

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

  // Fold tree-mode report tables (see reportTreeInit below). The
  // sidebar's tree is folded earlier, inline right after its markup
  // (default-layout.hamlet), so it never paints unfolded.
  reportTreeInit();

  // Shift-clicking in the years row selects a range of years, and in
  // the account type and commodity rows, several of them.
  yearsRangeInit();
  typesMultiInit();
  commoditiesMultiInit();

  // The controls and commodity disclosures save their state, and control
  // clicks save the page's scroll position.
  controlsInit();

  // The key hints, if they are on (the . key).
  keyHintsShow();

  // The hideemptyaccts cookie was replaced by the empty parameter;
  // clear it from browsers that still carry it. Older versions set it
  // with a one-year max-age, so this can safely be removed after
  // 2028-01-01.
  if (document.cookie.indexOf('hideemptyaccts=') >= 0) {
    document.cookie = 'hideemptyaccts=; path=/; max-age=0';
  }

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
    // Escape closes an open dialog, even from one of its fields. Done here
    // rather than left to the browser, so that the key is marked handled;
    // otherwise Safari in full screen also takes it as leaving full screen.
    var opendialog = document.querySelector('dialog[open]');
    if (opendialog && e.key === 'Escape') {
      opendialog.close();
      e.preventDefault();
      return;
    }
    if (e.target.closest('input, textarea, select')) { return; }
    // The help keys toggle the help, so they close it too; while a dialog
    // is open the other keys do nothing.
    var help = document.getElementById('helpmodal');
    if (help && help.open && (e.key === 'h' || e.key === '?')) {
      helpToggle();
      e.preventDefault();
      return;
    }
    if (document.querySelector('dialog[open]')) { return; }
    if (gomenuOpen()) {
      // After g, a page's key goes there; escape or any other key closes the menu.
      if (e.key.length > 1 && e.key !== 'Escape') { return; }
      gomenuChoose(e.key);
      e.preventDefault();
      return;
    }
    var k = keymapFind(e.key);
    if (!k || k.run(keyTarget(k), e.key) === false) { return; }
    e.preventDefault();
  });
  // Escape leaves the search field, keeping what was typed, so that the
  // keyboard shortcuts and scrolling work again.
  var searchfield = document.querySelector('#searchform input[name=q]');
  if (searchfield) {
    searchfield.addEventListener('keydown', function(e) {
      if (e.key === 'Escape') { focusPage(); e.preventDefault(); }
    });
  }
  var fullwindowexit = document.getElementById('fullwindow-exit');
  if (fullwindowexit) { fullwindowexit.addEventListener('click', fullWindowToggle); }
  // A click elsewhere closes the g key's menu, as escape does.
  document.addEventListener('click', function(e) {
    if (gomenuOpen() && !e.target.closest('#gomenu')) { gomenuHide(); }
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

  entryTooltipInit();
  registerChartInit();
  chartWidthRecord();
  var resizing;
  window.addEventListener('resize', function() {
    clearTimeout(resizing);
    resizing = setTimeout(chartWidthRecord, 250);
  });

  // Unless something has focus already: a long page can be clicked or
  // tabbed in before it has finished loading.
  if (!document.activeElement || document.activeElement === document.body) { focusPage(); }
});

// Focus the main content, so that the arrow keys, space and page up/down
// scroll it. On wider screens it scrolls by itself, not the window, and
// browsers send those keys to the window until something in it has focus,
// so a page could not be scrolled from the keyboard before a click.
function focusPage() {
  var main = document.getElementById('main-content');
  if (main) { main.focus({ preventScroll: true }); }
}

//----------------------------------------------------------------------
// KEYS

// The keyboard shortcuts, as a table, which the key handler and the key
// hints (the . key) both read, so that a hint shows only where its key
// acts. Each entry has its keys, the first being the one hinted, and what
// they do; when they stand for a control on the page, how to find it: a
// selector, or a function returning the element (nothing when this page
// has none). The action is given that element and the key pressed, and
// returns false when the key was not for it, leaving the key to the
// browser. The hints go on that element, unless the entry says where
// (keyHints). The keys are cased as hledger-ui's.
// In full window mode, s, o and / leave it, showing what they ask for.
var keymap = [
  { keys: ['?', 'h'], at: '#searchform [data-target="#helpmodal"]', run: helpToggle },
  // The report links carry the keys that go to them after g, as the g
  // menu's links do, both from the server's report menu (App.reportMenu).
  // hledger.css draws their hints from those, so that they are there at
  // first paint: added here, after a long page has loaded, they would
  // make the row wrap a moment after it appeared, moving the page down.
  { keys: ['g'], run: gomenuShow, hints: function() { return []; } },
  { keys: ['s'], at: '#sidebar-menu',
    run: function() { if (fullWindowLeave()) { sidebarShow(); } else { sidebarToggle(); } } },
  { keys: ['o'], at: '#main-content details.report-controls > summary',
    run: function() { if (fullWindowLeave()) { controlsShow(); } else { controlsToggle(); } } },
  { keys: ['a', 'n'], at: '#addformlink', run: function() { addformShow(); } },
  { keys: ['f'], at: '#fullwindow-exit', run: fullWindowToggle },
  { keys: ['/'], at: '#searchform input[name=q]', run: function() { fullWindowLeave(); focusSearch(); } },
  { keys: ['.'], run: keyHintsToggle },
  { keys: ['z'], at: '.zero-balances a:not(.current)', run: linkFollow },
  { keys: ['t'], at: rowLink('accounts', -1),        run: linkToggle },
  { keys: ['H'], at: rowLink('accum', 1),            run: linkToggle },
  { keys: ['L'], at: rowLink('lots', 1),             run: linkToggle },
  { keys: ['V'], at: rowLink('amounts', -1),         run: linkToggle },
  { keys: ['B'], at: rowLink('amounts', 1),          run: linkToggle },
  { keys: ['R'], at: rowLink('postings', 1),         run: linkToggle },
  { keys: ['U'], at: rowLink('status', 1),           run: linkToggle },
  { keys: ['P'], at: rowLink('status', 2),           run: linkToggle },
  { keys: ['C'], at: rowLink('status', 3),           run: linkToggle },
  { keys: ['S'], at: rowLink('sort', 1),             run: linkToggle },
  // The Extra columns links each toggle their own column.
  { keys: ['T'], at: rowLink('columns', 0),          run: linkFollow },
  { keys: ['A'], at: rowLink('columns', 1),          run: linkFollow },
  { keys: ['Y'], at: rowLink('interval', 1),         run: linkToggle },
  { keys: ['Q'], at: rowLink('interval', 2),         run: linkToggle },
  { keys: ['M'], at: rowLink('interval', 3),         run: linkToggle },
  { keys: ['W'], at: rowLink('interval', 4),         run: linkToggle },
  { keys: ['D'], at: rowLink('interval', 5),         run: linkToggle },
  // The depth keys are hinted by the Depth row's label: its links are
  // digits already, and - and + step from whichever is current.
  { keys: '0123456789'.split(''), at: rowLink('depth', -1), run: depthSet, hints: depthHint('0-9') },
  { keys: ['-', '_'], at: depthStep(-1),             run: linkFollow, hints: depthHint('-') },
  { keys: ['+', '='], at: depthStep(1),              run: linkFollow, hints: depthHint('+') },
  // With nothing else to cancel, escape leaves full window mode.
  { keys: ['Escape'], run: function() { return fullWindowLeave(); } },
];

function keymapFind(key) {
  return keymap.find(function(k) { return k.keys.indexOf(key) >= 0; });
}

// The element a keymap entry stands for on this page, if any.
function keyTarget(k) {
  if (!k.at) { return null; }
  return typeof k.at === 'string' ? document.querySelector(k.at) : k.at();
}

// A keymap entry's hints on this page: each an element, the text to show,
// and whether it goes after the element's content rather than before.
function keyHints(k) {
  if (k.hints) { return k.hints(k); }
  var el = keyTarget(k);
  return el ? [[el, k.keys[0], false]] : [];
}

// A depth key's hint, after the Depth row's label, while the key has a
// link to go to.
function depthHint(text) {
  return function(k) {
    var label = document.querySelector('#main-content .depth .row-label');
    return label && keyTarget(k) ? [[label, text, true]] : [];
  };
}

// The . key shows or hides a small badge on each control, naming its key.
// The setting is kept in local storage, for this hledger-web (scheme, host
// and port), and the body's keyhints class restored from it before the
// page paints (default-layout-wrapper.hamlet); keyHintsShow then adds the
// badges. hledger.css hides them on touch screens, which have no keys.
function keyHintsToggle() {
  var on = document.body.classList.toggle('keyhints');
  try {
    if (on) { localStorage.setItem('keyhints', '1'); } else { localStorage.removeItem('keyhints'); }
  } catch (e) {}
  keyHintsShow();
}

function keyHintsShow() {
  var on = document.body.classList.contains('keyhints');
  document.querySelectorAll('kbd.keyhint').forEach(function(b) { b.remove(); });
  if (!on) { return; }
  keymap.forEach(function(k) {
    keyHints(k).forEach(function(h) {
      var el = h[0];
      var badge = document.createElement('kbd');
      badge.className = 'keyhint';
      badge.setAttribute('aria-hidden', 'true');
      badge.textContent = h[1];
      // A field can't hold it, so it goes beside the field.
      if (el.matches('input')) { el.before(badge); }
      else if (h[2]) { el.append(badge); }
      else { el.prepend(badge); }
    });
  });
}

// A finder for the link at idx (negative counts from the end) in a row of
// control links. Each row builder says which position its keys rely on
// (Widget.Common).
function rowLink(rowCls, idx) {
  return function() {
    var links = document.querySelectorAll('#main-content .' + rowCls + ' a');
    return links[idx < 0 ? links.length + idx : idx];
  };
}

function linkFollow(a) {
  if (a) { location.href = a.href; }
}

// hledger-ui's toggling keys, on a row of control links: follow the link,
// or when it is already current, the row's first link, which shows the
// default.
function linkToggle(a) {
  if (!a) { return; }
  location.href = (a.classList.contains('current') ? a.closest('.report-links').querySelector('a') : a).href;
}

// A finder for the Depth link the - and + keys go to: the one delta
// steps from the current one, through 0, 1, ... the deepest (no limit),
// stopping at either end.
function depthStep(delta) {
  return function() {
    var links = Array.prototype.slice.call(document.querySelectorAll('#main-content .depth a'));
    var cur = links.findIndex(function(a) { return a.classList.contains('current'); });
    return cur >= 0 ? links[cur + delta] : undefined;
  };
}

// The digit keys set the depth limit, like hledger-ui's: the Depth row's
// last link, the deepest, carries the page's url without a depth limit,
// which the depth parameter adds.
function depthSet(deepest, n) {
  if (!deepest) { return false; }
  var url = new URL(deepest.href);
  url.searchParams.set('depth', n);
  location.href = url.href;
}

// The entry targeted by the url hash is marked by a :target rule in
// hledger.css, which needs no javascript. A hash can be anything, eg an
// old bookmark's numeric row id, so location.hash must not be passed to
// querySelector.

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

// Focus the search field ready for another query term: rather than
// selecting the search, put the cursor at its end, after a space.
function focusSearch() {
  var q = document.querySelector('#searchform input[name=q]');
  if (!q) { return; }
  if (q.value && !/\s$/.test(q.value)) { q.value += ' '; }
  q.focus();
  q.setSelectionRange(q.value.length, q.value.length);
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
  // The placeholder templates come from the page, in its language.
  var postings = addform.querySelector('.account-postings');
  account.placeholder = (postings.dataset.accountPlaceholder || 'Account {n}').replace('{n}', num);
  amount.placeholder = (postings.dataset.amountPlaceholder || 'Amount {n}').replace('{n}', num);

  addform.querySelector('.account-postings').appendChild(newrow);
}

//----------------------------------------------------------------------
// SIDEBAR

// The g key's menu (default-layout.hamlet): it lists the pages, each with
// the key that goes to it, keyed by page rather than position, so that
// reordering the menu keeps the keys.
function gomenuOpen() {
  var menu = document.getElementById('gomenu');
  return !!menu && !menu.hidden;
}

function gomenuShow() {
  var menu = document.getElementById('gomenu');
  if (menu) { menu.hidden = false; }
}

function gomenuHide() {
  var menu = document.getElementById('gomenu');
  if (menu) { menu.hidden = true; }
}

function gomenuChoose(key) {
  var target = Array.prototype.find.call(
    document.querySelectorAll('#gomenu a[data-gokey]'),
    function (a) { return a.getAttribute('data-gokey') === key; });
  gomenuHide();
  if (target) { location.href = target.href; }
}

// A shift-click on a link in the years, account type, or commodity rows is
// always handled here, never by the browser, whose own shift-click opens a
// new window, or in Safari adds to the Reading List. compose(link) returns
// the url combining the clicked link with the row's selection, or null to
// follow the link as a plain click would.
function shiftClickRow(row, compose) {
  row.addEventListener('click', function (ev) {
    if (!ev.shiftKey) { return; }
    var a = ev.target.closest('a');
    if (!a) { return; }
    ev.preventDefault();
    location.href = compose(a) || a.href;
  });
}

// Shift-clicking a year in the years row extends the selection: from the
// years marked current (a plain click's single year, or an earlier range)
// to the clicked one, as an end-exclusive date:FIRST..LAST+1 search term,
// which the row marks year by year. With no year marked (All current), a
// shift-click selects the clicked year like a plain click.
function yearsRangeInit() {
  document.querySelectorAll('p.years').forEach(function (row) {
    shiftClickRow(row, function (a) {
      var clicked = parseInt(a.textContent, 10);
      if (isNaN(clicked)) { return null; }  // the All link
      var years = [clicked];
      document.querySelectorAll('p.years a.current').forEach(function (c) {
        var y = parseInt(c.textContent, 10);
        if (!isNaN(y)) { years.push(y); }
      });
      if (years.length < 2) { return null; }  // nothing to extend from
      var lo = Math.min.apply(null, years);
      var hi = Math.max.apply(null, years);
      // the clicked link's url, with every date: term (a hand-typed
      // search may hold several) replaced by the range
      var url = new URL(a.href);
      var q = (url.searchParams.get('q') || '').replace(/\s*\bdate:\S+/g, '').trim();
      url.searchParams.set('q', (q ? q + ' ' : '') + 'date:' + lo + '..' + (hi + 1));
      return url.toString();
    });
  });
}

// Shift-clicking in the account type row adds the clicked type to the
// selected ones, or removes it, as a single type:AL.. search term; the
// row marks each selected type (see Widget.Common.typeLinks).
function typesMultiInit() {
  document.querySelectorAll('div.types').forEach(function (box) {
    shiftClickRow(box, function (a) {
      var typeOf = function (link) {
        var m = (new URL(link.href).searchParams.get('q') || '').match(/type:(\w+)/);
        return m && m[1].toUpperCase();
      };
      var clicked = typeOf(a);
      if (!clicked) { return null; }  // the All link
      var letters = [];
      box.querySelectorAll('a.current').forEach(function (c) {
        var t = typeOf(c);
        if (t && letters.indexOf(t) < 0) { letters.push(t); }
      });
      var i = letters.indexOf(clicked);
      if (i >= 0) { letters.splice(i, 1); } else { letters.push(clicked); }
      var url = new URL(a.href);
      // drop every type: term (a hand-typed search may hold several),
      // then append the one composed term
      var q = (url.searchParams.get('q') || '').replace(/\s*\btype:\w+/g, '').trim();
      if (letters.length) { q = (q ? q + ' ' : '') + 'type:' + letters.sort().join(''); }
      if (q) { url.searchParams.set('q', q); } else { url.searchParams.delete('q'); }
      return url.toString();
    });
  });
}

// Shift-clicking in the commodity row adds the clicked commodity to the
// selected ones, or removes it, as a single cur:A|B search term. The
// links carry their regex-escaped patterns, and the row the search's
// other terms, as data attributes (Widget.Common.commodityLinks), so no
// query parsing happens here and any symbol works, spaces included: a
// composed term containing one is quoted whole.
function commoditiesMultiInit() {
  document.querySelectorAll('div.commodities').forEach(function (box) {
    shiftClickRow(box, function (a) {
      var clicked = a.getAttribute('data-cur');
      if (!clicked) { return null; }  // the All link
      var pats = [];
      box.querySelectorAll('a.current[data-cur]').forEach(function (c) {
        pats.push(c.getAttribute('data-cur'));
      });
      var i = pats.indexOf(clicked);
      if (i >= 0) { pats.splice(i, 1); } else { pats.push(clicked); }
      var q = box.getAttribute('data-rest') || '';
      if (pats.length) {
        var term = 'cur:' + pats.join('|');
        if (/\s/.test(term)) { term = '"' + term + '"'; }
        q = (q + ' ' + term).trim();
      }
      var url = new URL(a.href);
      if (q) { url.searchParams.set('q', q); } else { url.searchParams.delete('q'); }
      return url.toString();
    });
  });
}

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
  chartWidthRecord();
}

function fullWindowOn() {
  return document.body.classList.contains('fullwindow');
}

function fullWindowToggle() {
  // Full window mode hides all but the report's heading and data
  // (hledger.css). It is remembered for this tab, and each page restores
  // it before painting (default-layout-wrapper.hamlet). Session storage,
  // not a cookie like the sidebar's, since the server needn't know it, and
  // that is kept per tab and per hledger-web automatically.
  var on = document.body.classList.toggle('fullwindow');
  try {
    if (on) { sessionStorage.setItem('fullwindow', '1'); } else { sessionStorage.removeItem('fullwindow'); }
  } catch (e) {}
  chartWidthRecord();
}

function fullWindowLeave() {
  // Leave full window mode, saying whether it was on.
  if (!fullWindowOn()) { return false; }
  fullWindowToggle();
  return true;
}

function sidebarShow() {
  var sidebar = document.getElementById('sidebar-menu');
  if (sidebar && sidebar.classList.contains('col-any-0')) { sidebarToggle(); }
}

// Tree-mode report rows carry indent-N classes, their indent, and
// depth-N classes, their account's depth (and the table the depth
// limit to fold to initially, if any; a row starts open when its
// account is above the limit). Give each group a caret that opens or
// closes its rows in place, leaving the page's URL alone.
function reportTreeInit() {
  document.querySelectorAll('.report-table table').forEach(function(table) {
    var fold = parseInt(table.getAttribute('data-depth-fold') || '', 10);
    table.querySelectorAll('tbody').forEach(function(tbody) {
      var rows = [];
      tbody.querySelectorAll('tr').forEach(function(tr) {
        var td = tr.querySelector('td.account');
        var m = td && td.className.match(/\bindent-(\d+)\b/);
        var d = td && td.className.match(/\bdepth-(\d+)\b/);
        if (m) { rows.push({tr: tr, td: td, indent: +m[1], depth: d ? +d[1] : NaN, expanded: true, parent: false}); }
      });
      rows.forEach(function(r, i) {
        r.parent = i + 1 < rows.length && rows[i + 1].indent > r.indent;
        if (!isNaN(fold)) { r.expanded = r.depth < fold; }
        var caret = document.createElement('span');
        caret.className = 'tree-caret';
        r.td.insertBefore(caret, r.td.firstChild);
        if (r.parent) {
          caret.addEventListener('click', function() { r.expanded = !r.expanded; apply(); });
        }
      });
      function apply() {
        // a row shows when every ancestor is open; the stack holds the
        // open flags of the current row's ancestors
        var stack = [];
        rows.forEach(function(r) {
          while (stack.length > r.indent) { stack.pop(); }
          r.tr.classList.toggle('tree-fold-hide', !stack.every(function(open) { return open; }));
          r.td.querySelector('.tree-caret').textContent = r.parent ? (r.expanded ? '\u25be' : '\u25b8') : '';
          stack.push(r.expanded);
        });
      }
      if (rows.length) { apply(); }
    });
  });
}

// The report controls disclosure, and the commodity filter's collapsed
// list inside it, remember their state in cookies (showcontrols,
// showcommodities), which the server reads to render the next page the
// way this one was left — nothing moves after paint. The commodity
// list's scroll position is remembered per tab, and clicking a control
// link saves the page's scroll position, which the inline script in
// default-layout.hamlet restores on the next page before it paints.
function controlsInit() {
  var d = document.querySelector('#main-content details.report-controls');
  if (!d) { return; }
  d.addEventListener('toggle', function () {
    setCookie('showcontrols', d.open ? '1' : '0');
  });
  var cd = d.querySelector('div.commodities details');
  if (cd) {
    cd.addEventListener('toggle', function () {
      setCookie('showcommodities', cd.open ? '1' : '0');
    });
    var cl = cd.querySelector('.report-links');
    if (cl) {
      try {
        var ct = parseInt(sessionStorage.getItem('commodityScrollTop'), 10);
        if (!isNaN(ct)) { cl.scrollTop = ct; }
      } catch (e) {}
      cl.addEventListener('scroll', function () {
        try { sessionStorage.setItem('commodityScrollTop', cl.scrollTop); } catch (e) {}
      });
    }
  }
  document.addEventListener('click', function (ev) {
    var a = ev.target.closest('a');
    if (!a || !a.closest('details.report-controls')) { return; }
    try { sessionStorage.setItem('pageScrollTop', document.documentElement.scrollTop); } catch (e) {}
  });
}

// The c key opens and closes the disclosure like a click on its
// summary; controlsInit's toggle listener saves the choice either way.
function controlsToggle() {
  var d = document.querySelector('#main-content details.report-controls');
  if (d) { d.open = !d.open; }
}

function controlsShow() {
  var d = document.querySelector('#main-content details.report-controls');
  if (d) { d.open = true; }
}

// The sidebar's account tree is folded by an inline script right after its
// markup in default-layout.hamlet, like its scroll restore and for the same
// reason: run from this file it would fold only at DOMContentLoaded, after
// the browser has painted the tree in full, a visible jump.

// The UI state cookies' names end with the server's port, so that several
// hledger-webs on one host keep their own (App.uiCookie).
function uiCookieName(name) {
  return name + (document.hledgerWebCookieSuffix || '');
}

function setCookie(name, value) {
  document.cookie = uiCookieName(name) + '=' + value + '; path=/; max-age=31536000; samesite=lax';
}

function getCookie(name) {
  return document.cookie.split('; ').reduce(function(found, c) {
    var parts = c.split('=');
    return parts[0] === uiCookieName(name) ? parts.slice(1).join('=') : found;
  }, undefined);
}

//----------------------------------------------------------------------
// ENTRY TOOLTIP
//
// Hovering a transaction in the journal or a register shows its journal
// entry, the way a browser shows a title attribute, but in a fixed-width
// font so that the amounts line up as they do in the journal. The rows carry
// the entry in a data-entry attribute; in a title attribute the browser would
// draw it itself, in a proportional font and wrapped at its own narrow width.
// As with titles, the innermost one applies: over an account link, the
// link's title (the full account name) shows instead.

function entryTooltipInit() {
  if (!document.querySelector('[data-entry]')) { return; }
  var tip = document.createElement('div');
  tip.className = 'entry-tooltip';
  tip.setAttribute('aria-hidden', 'true');
  tip.hidden = true;
  document.body.appendChild(tip);

  var row = null;         // the element with an entry under the pointer
  var timer = null;       // set while waiting to show its entry
  var clicked = false;    // set by a click, until the pointer leaves the row
  var x, y;               // the pointer position, where the entry appears

  function show() {
    timer = null;
    entryTooltipFill(tip, row.getAttribute('data-entry'));
    entryTooltipPlace(tip, x, y);
  }
  function hide() {
    clearTimeout(timer);
    timer = null;
    tip.hidden = true;
  }

  // Mouse only. A touch has no hover, and changing the page when a touch
  // arrives over a link makes iOS treat the first tap as a hover, so the link
  // would take two taps.
  function track(e) {
    if (e.pointerType !== 'mouse') { return; }
    x = e.clientX;
    y = e.clientY;
    var el = e.target.closest('[title], [data-entry]');
    var over = el && el.hasAttribute('data-entry') ? el : null;
    if (over !== row) {
      // Moving on to the next entry while one is showing shows the next at
      // once, as with browser tooltips; otherwise it appears after a pause.
      var showing = !tip.hidden;
      hide();
      row = over;
      clicked = false;
      if (row) {
        if (showing) { show(); } else { timer = setTimeout(show, 500); }
      }
    } else if (row && tip.hidden && !timer && !clicked) {
      // Still over the row after a scroll or a key press hid it.
      timer = setTimeout(show, 500);
    }
  }
  document.addEventListener('pointerover', track);
  document.addEventListener('pointermove', track);

  // Also like a browser tooltip, it goes away when the pointer leaves the
  // window, and on a click, a key press or a scroll. After a click it stays
  // away until the pointer leaves the row, so as not to cover a selection
  // being made. Scroll events don't bubble, and the main pane scrolls by
  // itself, hence the capture.
  document.addEventListener('pointerout', function(e) {
    if (!e.relatedTarget) { hide(); row = null; }
  });
  document.addEventListener('pointerdown', function() {
    hide();
    clicked = true;
  });
  document.addEventListener('keydown', hide);
  document.addEventListener('scroll', hide, true);
  window.addEventListener('blur', hide);
}

// Put an entry's lines in the tooltip.
function entryTooltipFill(tip, entry) {
  tip.textContent = '';
  entry.replace(/\s+$/, '').split('\n').forEach(function(line) {
    var div = document.createElement('div');
    // Set as text, so that journal content cannot be parsed as markup.
    div.textContent = line;
    // A line too long for the window wraps, and its continuation is indented
    // past the line's own indentation, so the entry keeps its shape.
    var indent = (line.match(/^ */)[0].length + 2) + 'ch';
    div.style.paddingLeft = indent;
    div.style.textIndent = '-' + indent;
    tip.appendChild(div);
  });
}

// Show the tooltip below the pointer, or above it if there is no room below,
// and keep it within the window.
function entryTooltipPlace(tip, x, y) {
  var margin = 8;
  var vw = document.documentElement.clientWidth;
  var vh = document.documentElement.clientHeight;
  tip.style.maxWidth = (vw - 2 * margin) + 'px';
  tip.style.maxHeight = (vh - 2 * margin) + 'px';
  tip.style.left = '0';
  tip.style.top = '0';
  tip.hidden = false;
  var w = tip.offsetWidth;
  var h = tip.offsetHeight;
  var top = y + 20;  // clear of the pointer's arrow
  if (top + h > vh - margin) { top = y - margin - h; }
  if (top < margin) { top = vh - margin - h; }
  tip.style.left = Math.max(margin, Math.min(x, vw - margin - w)) + 'px';
  tip.style.top = top + 'px';
  // An entry taller than the window is cut off; the css marks the cut.
  tip.classList.toggle('clipped', tip.scrollHeight > tip.clientHeight);
}

//----------------------------------------------------------------------
// REGISTER CHART
//
// The register page's balance chart is SVG, drawn by the server (see
// registerChartHtml and chart.hamlet), its points linking to their rows. Here,
// dragging across one of its plots shows the register for the dates dragged
// across. Each plot carries its date scale, on a transparent rect.plot under
// it: its first and last dates (data-d0, data-d1) and their x positions
// (data-x0, data-x1), between which dates are spaced evenly. The chart carries
// this register's url without its date terms (data-baselink).

// Keep the width of the page's main column in the chartwidth cookie, for
// the server to draw the register chart that wide (registerChartHtml): a
// chart drawn wider than its column is shrunk to fit, its text with it.
// Measured on every page, so that it is known before a register is shown.
function chartWidthRecord() {
  var main = document.getElementById('main-content');
  if (!main) { return; }
  var style = getComputedStyle(main);
  var w = Math.floor(main.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight));
  if (w > 0 && String(w) !== getCookie('chartwidth')) { setCookie('chartwidth', w); }
}

// Let the register chart's plots, if this page has any, be dragged across.
function registerChartInit() {
  document.querySelectorAll('.register-chart[data-baselink] svg').forEach(function(svg) {
    var plots = Array.prototype.slice.call(svg.querySelectorAll('rect.plot[data-d0]'));
    if (!plots.length) { return; }
    var drag = null;       // the drag in progress: its plot, where it started, and its selection
    var dragged = false;   // was the last press a drag, rather than a click ?
    // The pointer's position in the chart's own coordinates, whatever size
    // the page draws it at.
    var point = function(ev) {
      return new DOMPoint(ev.clientX, ev.clientY).matrixTransform(svg.getScreenCTM().inverse());
    };
    svg.addEventListener('pointerdown', function(ev) {
      dragged = false;
      if (ev.button !== 0) { return; }
      var p = point(ev);
      var plot = plots.find(function(pl) {
        var r = registerChartPlotBox(pl);
        return p.x >= r.x && p.x <= r.x + r.width && p.y >= r.y && p.y <= r.y + r.height;
      });
      if (!plot) { return; }
      drag = { plot: plot, x: p.x, selection: null };
      // no text selection, and no dragging away the link of a point pressed on
      ev.preventDefault();
    });
    svg.addEventListener('dragstart', function(ev) { ev.preventDefault(); });
    svg.addEventListener('pointermove', function(ev) {
      if (!drag) { return; }
      var x = registerChartClamp(drag.plot, point(ev).x);
      if (!drag.selection) {
        // a click may wobble a little before it is a drag
        if (Math.abs(x - drag.x) < 4) { return; }
        // From here on the pointer is the drag's, wherever it goes. (Not
        // before: a click would then land on the chart, not a point's link.)
        svg.setPointerCapture(ev.pointerId);
        var r = registerChartPlotBox(drag.plot);
        drag.selection = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
        drag.selection.setAttribute('class', 'selection');
        drag.selection.setAttribute('y', r.y);
        drag.selection.setAttribute('height', r.height);
        svg.appendChild(drag.selection);
      }
      drag.selection.setAttribute('x', Math.min(x, drag.x));
      drag.selection.setAttribute('width', Math.abs(x - drag.x));
    });
    svg.addEventListener('pointerup', function(ev) {
      var d = drag;
      drag = null;
      if (!d || !d.selection) { return; }
      dragged = true;
      registerChartSelect(svg, d.plot, d.x, registerChartClamp(d.plot, point(ev).x));
    });
    svg.addEventListener('pointercancel', function() {
      if (drag && drag.selection) { drag.selection.remove(); }
      drag = null;
    });
    // A drag ending on a point is not a click on its link.
    svg.addEventListener('click', function(ev) {
      if (dragged) { ev.preventDefault(); }
      dragged = false;
    }, true);
  });
}

// The position and size of a plot, in the chart's coordinates.
function registerChartPlotBox(plot) {
  return { x: +plot.getAttribute('x'), y: +plot.getAttribute('y'),
           width: +plot.getAttribute('width'), height: +plot.getAttribute('height') };
}

// An x position kept within a plot.
function registerChartClamp(plot, x) {
  var r = registerChartPlotBox(plot);
  return Math.max(r.x, Math.min(r.x + r.width, x));
}

// Show the register for the dates between two x positions on a plot, by
// reloading it with a date: query for them.
function registerChartSelect(svg, plot, xa, xb) {
  var DAY = 24 * 60 * 60 * 1000;
  // dates as YYYY-MM-DD are read, and written, as UTC
  var d0 = Date.parse(plot.getAttribute('data-d0')), d1 = Date.parse(plot.getAttribute('data-d1'));
  var x0 = +plot.getAttribute('data-x0'), x1 = +plot.getAttribute('data-x1');
  var span = Math.round((d1 - d0) / DAY);
  // the day nearest an x position, within the plot's dates
  var day = function(x) {
    var k = x1 > x0 ? Math.round((x - x0) / (x1 - x0) * span) : 0;
    return d0 + Math.max(0, Math.min(span, k)) * DAY;
  };
  var iso = function(t) { return new Date(t).toISOString().slice(0, 10); };
  // as a date: term reads it: YYYY-MM-DD..YYYY-MM-DD, the end exclusive
  var range = iso(day(Math.min(xa, xb))) + '..' + iso(day(Math.max(xa, xb)) + DAY);
  var url = new URL(svg.closest('.register-chart').getAttribute('data-baselink'), document.baseURI);
  var q = url.searchParams.get('q');
  url.searchParams.set('q', (q ? q + ' ' : '') + 'date:' + range);
  document.location = url.href;
}

//----------------------------------------------------------------------
// BROWSE MODE

// In the default --serve-browse mode the server exits once no browser
// window has shown it for fifteen minutes (serveAndBrowse in Main.hs). It
// knows a window is open because the page pings it: on load, every 30
// seconds, and whenever the page is shown again. Browsers run the timers of
// background tabs less often, so the pings from a hidden page can be minutes
// apart; the ping on showing makes up for that as soon as the page is seen.
// Pages are marked for this by defaultLayout in browse mode only; the server
// answers /_ping in that mode only. The ping goes to the page's own origin,
// whatever address the browser reached us at (the policy allows requests to
// our origin only), under the base url's path, in case a proxy in front of
// us expects one.
//
// A ping that can't reach the server means it has stopped, so the page shows
// the #server-stopped notice, and hides it again if a later ping gets through
// (eg after the server was restarted on the same address).
function browsePingInit() {
  if (!document.body.hasAttribute('data-browse-mode')) { return; }
  var base = new URL(document.hledgerWebBaseurl, document.baseURI);
  var url = base.pathname.replace(/\/$/, '') + '/_ping';
  var notice = document.getElementById('server-stopped');
  var ping = function() {
    fetch(url, { cache: 'no-store' }).then(
      function() { if (notice) { notice.hidden = true; } },
      function() { if (notice) { notice.hidden = false; } });
  };
  ping();
  setInterval(ping, 30000);
  document.addEventListener('visibilitychange', function() {
    if (document.visibilityState === 'visible') { ping(); }
  });
  // A page restored from the back/forward cache didn't run meanwhile.
  window.addEventListener('pageshow', function(e) {
    if (e.persisted) { ping(); }
  });
}
