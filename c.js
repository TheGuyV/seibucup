
var DATA = /(^|\.)seibucup\.online$/.test(location.hostname) ? "" : "https://seibucup.online/";
var STATUS_GIST = "71310b8cdc6416102908f77204291333";
var COUNTRY = [["이탈리아", "Italy"], ["스페인", "Spain"], ["네덜란드", "Holland"], ["잉글랜드", "England"], ["미국", "USA"], ["한국", "Korea"],
  ["프랑스", "France"], ["브라질", "Brazil"], ["아르헨티나", "Argentina"], ["독일", "Germany"], ["일본", "Japan"], ["GOD", "GOD"]];
var PAGES = [["index", "홈", "Home"], ["download", "다운로드", "Download"], ["ranking", "순위", "Rankings"], ["results", "경기 기록", "Results"], ["guide", "안내", "Guide"], ["dashboard", "내 기록", "My page"]];

function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
function $(id) { return document.getElementById(id); }
function getJSON(name) { return fetch(DATA + name + "?" + Date.now(), { cache: "no-store" }).then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); }); }

var LANG = "ko";
try { var sv = localStorage.getItem("lang"); LANG = sv ? (sv === "en" ? "en" : "ko") : ((navigator.language || "ko").toLowerCase().indexOf("ko") === 0 ? "ko" : "en"); } catch (e) {}
document.documentElement.lang = LANG;
function L(ko, en) { return LANG === "en" ? en : ko; }
function B(ko, en) { return '<span class="ko">' + ko + '</span><span class="en">' + en + "</span>"; }
var langHooks = [];
function setLang(l) {
  LANG = l; document.documentElement.lang = l;
  try { localStorage.setItem("lang", l); } catch (e) {}
  langHooks.forEach(function (f) { f(); });
}

(function shell() {
  var here = (location.pathname.split("/").pop() || "index.html").replace(".html", "") || "index";
  var nav = PAGES.map(function (p) { return '<a href="' + p[0] + '.html"' + (p[0] === here ? ' aria-current="page"' : "") + ">" + B(p[1], p[2]) + "</a>"; }).join("");
  document.body.insertAdjacentHTML("afterbegin",
    '<header><div class="wrap"><a class="logo" href="index.html">SEIBU CUP</a><nav aria-label="menu">' + nav +
    '<button type="button" class="langbtn" id="langBtn">' + B("English", "한국어") + "</button></nav></div></header>");
  document.body.insertAdjacentHTML("beforeend",
    '<footer class="wrap"><p>' + B("원작사와 관계없는 비공식 팬 프로젝트예요.", "An unofficial fan project, not related to the original publisher.") + "<br>Seibu Cup Soccer © 1992 Seibu Kaihatsu.</p><p>" +
    '<a href="donate.html">' + B("응원", "Support") + '</a><a href="license.html">' + B("라이선스", "License") + '</a><a href="privacy.html">' + B("개인정보", "Privacy") + "</a>" +
    '<a href="https://cafe.naver.com/seibucup">' + B("네이버 카페", "Naver Cafe") + "</a>" +
    '<button type="button" class="theme" id="themeBtn"></button></p>' +
    '<p class="fam">' + B("패밀리 사이트", "Family sites") + ': <a href="https://twc98.seibucup.online/">' + B("테크모 월드컵 98", "Tecmo World Cup \'98") + '</a>' +
    '<a href="https://rg2.seibucup.online/">' + B("런앤건2", "Run and Gun 2") + '</a><a href="https://tekkentag.seibucup.online/">' + B("철권 태그", "Tekken Tag") + '</a>' +
    '<a href="https://sf2.seibucup.online/">' + B("스트리트 파이터 II", "Street Fighter II") + '</a></p></footer>');
  $("langBtn").onclick = function () { setLang(LANG === "en" ? "ko" : "en"); };
  var modes = ["auto", "light", "dark"], m = "auto";
  var names = { auto: ["자동", "auto"], light: ["밝게", "light"], dark: ["어둡게", "dark"] };
  try { m = localStorage.getItem("siteC.theme") || "auto"; } catch (e) {}
  function apply() {
    if (m === "auto") document.documentElement.removeAttribute("data-theme"); else document.documentElement.setAttribute("data-theme", m);
    $("themeBtn").textContent = L("화면: ", "Theme: ") + L(names[m][0], names[m][1]);
  }
  apply(); langHooks.push(apply);
  $("themeBtn").onclick = function () { m = modes[(modes.indexOf(m) + 1) % 3]; try { localStorage.setItem("siteC.theme", m); } catch (e) {} apply(); };
})();

function loadStatus(cb) {
  fetch("https://api.github.com/gists/" + STATUS_GIST).then(function (r) { if (!r.ok) throw 0; return r.json(); })
    .then(function (g) { cb(JSON.parse(g.files["status.json"].content)); }).catch(function () { cb(null); });
}

function teamName(i) { var n = COUNTRY[Number(i)]; return n ? L(n[0], n[1]) : L("클럽", "Club"); }
function kind(r) {
  if (r.type === "2v2") return "2v2";
  if (r.turbo || r.mq === "turbo") return "turbo";
  if (r.ranked) return "club";
  return "1v1";
}
var KIND = { "2v2": ["2:2", "2 vs 2"], turbo: ["터보", "Turbo"], club: ["클럽 매치", "Club match"], "1v1": ["1:1", "1 vs 1"] };
function matchRow(r) {
  var n = r.nicks || [];
  var left = n.filter(function (x, i) { return x && i % 2 === 0; }).join(" · "), right = n.filter(function (x, i) { return x && i % 2 === 1; }).join(" · ");
  var tn = r.tnames || {};
  function side(i) { var c = tn[n[i]]; return c && c[0] ? c[0] : teamName(r.teams && r.teams[i]); }
  var k = KIND[kind(r)];
  return '<div class="mt"><span>' + esc(side(0)) + '<span class="n">' + esc(left) + '</span></span>' +
    '<span class="sc">' + Number(r.score[0]) + " : " + Number(r.score[1]) + '</span>' +
    '<span class="r">' + esc(side(1)) + '<span class="n">' + esc(right) + '</span></span>' +
    '<span class="k">' + esc(L(k[0], k[1])) + " · " + esc((r.when || "").slice(5)) + "</span></div>";
}

(function hit() {
  try {
    if (!/(^|\.)seibucup\.online$/.test(location.hostname) || navigator.doNotTrack === "1" || navigator.globalPrivacyControl) return;
    var ref = "";
    if (document.referrer) { try { var ru = new URL(document.referrer); ref = ru.host === location.host ? ru.origin + ru.pathname : ru.origin; } catch (e) {} }
    var u = "https://play.seibucup.online/hit?p=" + encodeURIComponent(location.pathname) + "&r=" + encodeURIComponent(ref) + "&w=" + (screen.width || 0) + "&l=" + LANG;
    if (navigator.sendBeacon) navigator.sendBeacon(u); else fetch(u, { method: "POST", mode: "no-cors", keepalive: true }).catch(function () {});
  } catch (e) {}
})();

if ("serviceWorker" in navigator) { try { navigator.serviceWorker.register("sw.js", { updateViaCache: "none" }).catch(function () {}); } catch (e) {} }
