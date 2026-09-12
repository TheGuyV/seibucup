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

