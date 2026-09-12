// language switch (ko / en), remembered in localStorage; highlights the current page in the menu
(function () {
  var saved = null;
  try { saved = localStorage.getItem("lang"); } catch (e) {}
  var lang = saved || ((navigator.language || "ko").toLowerCase().indexOf("ko") === 0 ? "ko" : "en");
  document.documentElement.setAttribute("lang", lang);
  function apply() {
    var b = document.getElementById("langbtn");
    if (b) b.textContent = document.documentElement.getAttribute("lang") === "ko" ? "English" : "한국어";
  }
  window.toggleLang = function () {
    var next = document.documentElement.getAttribute("lang") === "ko" ? "en" : "ko";
    document.documentElement.setAttribute("lang", next);
    try { localStorage.setItem("lang", next); } catch (e) {}
    apply();
  };
  document.addEventListener("DOMContentLoaded", function () {
    apply();
    var here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll("nav.menu a").forEach(function (a) {
      if (a.getAttribute("href") === here) a.classList.add("active");
    });
  });
})();


// ---- live server status (index page). The relay answers /status and /ping over HTTPS via Caddy.
var STATUS_URL = 'https://relay.seibucup.online';
function srvText(id, ko, en) { var e = document.getElementById(id); if (e) e.innerHTML = '<span class="ko">' + ko + '</span><span class="en">' + en + '</span>'; }
function srvSet(id, v) { var e = document.getElementById(id); if (e) e.textContent = v; }
async function refreshStatus() {
  var box = document.getElementById('srv'); if (!box) return;
  try {
    var ctl = new AbortController(); var tm = setTimeout(function () { ctl.abort(); }, 5000);
    var r = await fetch(STATUS_URL + '/status', { cache: 'no-store', signal: ctl.signal });
    var j = await r.json(); clearTimeout(tm);
    // ping: measured on an already-open connection, best of 3 short requests
    var best = 9999;
    for (var i = 0; i < 3; i++) {
      var t0 = performance.now();
      await fetch(STATUS_URL + '/ping', { cache: 'no-store' });
      best = Math.min(best, performance.now() - t0);
    }
    box.dataset.state = 'online';
    srvText('srv-state', '온라인', 'ONLINE');
    srvSet('srv-ping', Math.round(best));
    srvSet('srv-users', j.users); srvSet('srv-rooms', j.rooms); srvSet('srv-players', j.players); srvSet('srv-playing', j.playing);
    var note = document.getElementById('srv-note'); if (note) note.textContent = '';
  } catch (e) {
    box.dataset.state = 'offline';
    srvText('srv-state', '오프라인', 'OFFLINE');
    ['srv-ping', 'srv-users', 'srv-rooms', 'srv-players', 'srv-playing'].forEach(function (id) { srvSet(id, '-'); });
    srvText('srv-note', '서버에 연결할 수 없습니다. 점검 중이거나 아직 열리지 않았습니다.', 'Cannot reach the server - it may be down for maintenance or not open yet.');
  }
}
document.addEventListener('DOMContentLoaded', function () {
  if (!document.getElementById('srv')) return;
  refreshStatus();
  setInterval(function () { if (!document.hidden) refreshStatus(); }, 15000);
  document.addEventListener('visibilitychange', function () { if (!document.hidden) refreshStatus(); });
});
