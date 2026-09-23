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
  // sw.js: the site is always fetched afresh, never from the browser's cache (see there). The
  // worker script itself is checked against the server on every visit too (updateViaCache).
  if ("serviceWorker" in navigator) {
    try { navigator.serviceWorker.register("sw.js", { updateViaCache: "none" }).catch(function () {}); } catch (e) {}
  }
  document.addEventListener("DOMContentLoaded", function () {
    apply();
    pcNote();
    showVersion();
    var here = location.pathname.split("/").pop() || "index.html";
    document.querySelectorAll("nav.menu a").forEach(function (a) {
      if (a.getAttribute("href") === here) a.classList.add("active");
    });
  });
})();

