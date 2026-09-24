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
  // phones / tablets: say up front that the game itself runs on a Windows PC (this site is only the guide there)
  function isMobile() {
    var ua = navigator.userAgent || "";
    if (/Android|iPhone|iPad|iPod|Mobile|Windows Phone/i.test(ua)) return true;
    return (navigator.maxTouchPoints || 0) > 1 && Math.min(screen.width, screen.height) < 900;   // iPadOS in desktop mode
  }
  function pcNote() {
    var hidden = false;
    try { hidden = sessionStorage.getItem("pcnote") === "1"; } catch (e) {}
    if (hidden || !isMobile()) return;
    var d = document.createElement("div");
    d.className = "pcnote";
    d.innerHTML = '<span class="ko">이 게임은 <strong>Windows PC</strong>에서 작동합니다. 휴대폰·태블릿에서는 안내만 볼 수 있으니, 런처는 PC에서 내려받아 주세요.</span>' +
                  '<span class="en">This game runs on a <strong>Windows PC</strong>. On a phone or tablet you can only read the guide - download the launcher on your PC.</span>' +
                  '<button type="button" class="pcnote-x" aria-label="close">×</button>';
    d.querySelector(".pcnote-x").onclick = function () {
      d.parentNode.removeChild(d);
      try { sessionStorage.setItem("pcnote", "1"); } catch (e) {}
    };
    document.body.insertBefore(d, document.body.firstChild);
  }
  // the download page's version number comes from version.json, which every release rewrites,
  // so it can never quietly fall behind the actual build
  function showVersion() {
    var els = document.querySelectorAll("#dlver, #dlver2");
    if (!els.length || !window.fetch) return;
    fetch("version.json", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (v) {
      if (!v || !v.version) return;
      for (var i = 0; i < els.length; i++) els[i].textContent = v.version;
    }).catch(function () {});
  }
  // The relay's status beside the logo: "● 서버 정상 · 접속 N명 · 방 M개" (2026-09-24). The relay keeps a secret
  // GitHub gist's status.json up to date (when the counts change, and every 5 minutes anyway); a status older
  // than 12 minutes means the relay has gone quiet. No port on the relay PC is involved. Read through the API
  // (fresh to the minute; 60 calls an hour per visitor), shared between pages for a minute.
  var STATUS_GIST = "71310b8cdc6416102908f77204291333";   // the gist the live relay made (its status_gist.txt)
  var STALE_S = 12 * 60;
  function statusPill() {
    var brand = document.querySelector("header.top .brand");
    if (!STATUS_GIST || !brand || !window.fetch) return null;
    var el = document.createElement("span");
    el.className = "srv"; el.hidden = true; el.setAttribute("role", "status");
    brand.parentNode.insertBefore(el, brand.nextSibling);
    return el;
  }
  function renderStatus(el, d) {
    if (!el) return;
    if (!d) { el.hidden = true; return; }
    var age = Date.now() / 1000 - (d.t || 0), state, ko, en;
    if (d.up === false) { state = "down"; ko = "서버 꺼짐"; en = "Server down"; }
    else if (age > STALE_S) { state = "down"; ko = "서버 응답 없음"; en = "Server not responding"; }
    else {
      state = "up";
      ko = "서버 정상 · 접속 " + (d.users || 0) + "명 · 방 " + (d.rooms || 0) + "개" + (d.playing ? " · 경기 중 " + d.playing : "");
      en = "Server up · " + (d.users || 0) + " online · " + (d.rooms || 0) + " room" + (d.rooms === 1 ? "" : "s") + (d.playing ? " · " + d.playing + " playing" : "");
    }
    var at = new Date((d.t || 0) * 1000), hm = ("0" + at.getHours()).slice(-2) + ":" + ("0" + at.getMinutes()).slice(-2);
    el.className = "srv " + state;
    el.title = (document.documentElement.getAttribute("lang") === "ko" ? "마지막 확인 " : "Last heard ") + hm;
    el.innerHTML = '<i></i><span class="ko">' + ko + '</span><span class="en">' + en + '</span>';
    el.hidden = false;
  }
  window.seibuStatus = renderStatus;    // (for checking the look by hand)
  function loadStatus(el) {
    var cached = null;
    try { cached = JSON.parse(sessionStorage.getItem("srv") || "null"); } catch (e) {}
    if (cached && Date.now() - cached.at < 60000) { renderStatus(el, cached.d); return; }
    fetch("https://api.github.com/gists/" + STATUS_GIST).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.json();
    }).then(function (g) {
      var d = JSON.parse(g.files["status.json"].content);
      try { sessionStorage.setItem("srv", JSON.stringify({ at: Date.now(), d: d })); } catch (e) {}
      renderStatus(el, d);
    }).catch(function () { if (!cached) renderStatus(el, null); });   // (rate-limited or offline: keep what we had)
  }
  function startStatus() {
    var el = statusPill();
    if (!el) return;
    loadStatus(el);
    setInterval(function () { if (!document.hidden) loadStatus(el); }, 90000);
  }
  // sw.js: the site is always fetched afresh, never from the browser's cache (see there). The
  // worker script itself is checked against the server on every visit too (updateViaCache).
  if ("serviceWorker" in navigator) {
    try { navigator.serviceWorker.register("sw.js", { updateViaCache: "none" }).catch(function () {}); } catch (e) {}
  }
  document.addEventListener("DOMContentLoaded", function () {
    apply();
    pcNote();
    showVersion();
    startStatus();
    var here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll("nav.menu a").forEach(function (a) {
      if (a.getAttribute("href") === here) a.classList.add("active");
    });
  });
})();

