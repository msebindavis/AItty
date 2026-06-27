// AItty marketing site — vanilla JS, no deps.
// Handles: mobile nav toggle, scroll-spy active link, screenshot lightbox.

(function () {
  "use strict";

  // ---------- Mobile nav toggle ----------
  var toggle = document.getElementById("navToggle");
  var menu = document.getElementById("mobileMenu");
  if (toggle && menu) {
    toggle.addEventListener("click", function () {
      var open = menu.classList.toggle("open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    // Close menu when a link is tapped
    menu.querySelectorAll("a").forEach(function (a) {
      a.addEventListener("click", function () {
        menu.classList.remove("open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  // ---------- Scroll-spy: highlight active nav link ----------
  var navLinks = Array.prototype.slice.call(document.querySelectorAll(".nav-links a"));
  var sections = navLinks
    .map(function (a) { return document.querySelector(a.getAttribute("href")); })
    .filter(Boolean);

  if (sections.length && "IntersectionObserver" in window) {
    var byId = {};
    navLinks.forEach(function (a) { byId[a.getAttribute("href").slice(1)] = a; });

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          navLinks.forEach(function (a) { a.classList.remove("active"); });
          var link = byId[entry.target.id];
          if (link) link.classList.add("active");
        }
      });
    }, { rootMargin: "-45% 0px -50% 0px", threshold: 0 });

    sections.forEach(function (s) { observer.observe(s); });
  }

  // ---------- Screenshot lightbox ----------
  var shots = Array.prototype.slice.call(document.querySelectorAll(".shot"));
  var lb = document.getElementById("lightbox");
  var lbImg = document.getElementById("lightboxImg");
  var lbClose = document.getElementById("lightboxClose");

  function openLightbox(src, alt) {
    if (!lb || !lbImg) return;
    lbImg.src = src;
    lbImg.alt = alt || "Screenshot enlarged";
    lb.classList.add("open");
    lb.setAttribute("aria-hidden", "false");
    document.body.style.overflow = "hidden";
  }
  function closeLightbox() {
    if (!lb) return;
    lb.classList.remove("open");
    lb.setAttribute("aria-hidden", "true");
    document.body.style.overflow = "";
    // Clear src after fade to avoid a flash of the previous image next open
    setTimeout(function () { if (lbImg && !lb.classList.contains("open")) lbImg.src = ""; }, 200);
  }

  shots.forEach(function (btn) {
    btn.addEventListener("click", function () {
      var img = btn.querySelector("img");
      openLightbox(btn.getAttribute("data-src") || (img && img.src), img && img.alt);
    });
  });
  if (lbClose) lbClose.addEventListener("click", closeLightbox);
  if (lb) lb.addEventListener("click", function (e) { if (e.target === lb) closeLightbox(); });
  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape" && lb && lb.classList.contains("open")) closeLightbox();
  });
})();