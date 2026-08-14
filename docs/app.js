/* AerialDrop landing page — interactivity (vanilla JS, no dependencies) */
(function () {
  "use strict";

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };

  /* ---------- Theme ---------- */
  var themeToggle = $("#themeToggle");
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    var meta = $('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "light" ? "#eef2f9" : "#05070d");
    if (themeToggle) themeToggle.setAttribute("aria-pressed", theme === "light" ? "true" : "false");
    try { localStorage.setItem("ad-theme", theme); } catch (e) {}
  }
  if (themeToggle) {
    themeToggle.addEventListener("click", function () {
      var current = document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark";
      applyTheme(current === "light" ? "dark" : "light");
    });
    applyTheme(document.documentElement.getAttribute("data-theme") === "light" ? "light" : "dark");
  }

  /* ---------- Mobile nav ---------- */
  var navToggle = $("#navToggle"), navLinks = $("#navLinks");
  if (navToggle && navLinks) {
    navToggle.addEventListener("click", function () {
      var open = navLinks.classList.toggle("open");
      navToggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
    $$("a", navLinks).forEach(function (a) {
      a.addEventListener("click", function () {
        navLinks.classList.remove("open");
        navToggle.setAttribute("aria-expanded", "false");
      });
    });
  }

  /* ---------- Active nav link while scrolling ---------- */
  var navAnchors = {};
  $$(".nav__links a[href^='#']").forEach(function (a) { navAnchors[a.getAttribute("href").slice(1)] = a; });
  var sectionIds = Object.keys(navAnchors);
  if (sectionIds.length && "IntersectionObserver" in window) {
    var ioNav = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          Object.keys(navAnchors).forEach(function (id) {
            navAnchors[id].classList.toggle("is-active", id === entry.target.id);
          });
        }
      });
    }, { rootMargin: "-40% 0px -55% 0px" });
    sectionIds.forEach(function (id) {
      var el = document.getElementById(id);
      if (el) ioNav.observe(el);
    });
  }

  /* ---------- Latest release (GitHub API, graceful fallback) ---------- */
  function humanSize(bytes) {
    if (typeof bytes !== "number" || !isFinite(bytes) || bytes <= 0) return "—";
    var units = ["B", "KB", "MB", "GB"], i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return bytes.toFixed(i > 1 ? 1 : 0) + " " + units[i];
  }
  function fetchRelease() {
    var url = "https://api.github.com/repos/YapWH1208/AerialDrop/releases/latest";
    var controller = ("AbortController" in window) ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, 6000) : null;
    fetch(url, controller ? { signal: controller.signal, headers: { Accept: "application/vnd.github+json" } } : {})
      .then(function (res) { if (!res.ok) throw new Error("HTTP " + res.status); return res.json(); })
      .then(function (rel) {
        var tag = rel.tag_name || "latest";
        var asset = (rel.assets || []).filter(function (a) { return /macOS/i.test(a.name) && /\.zip$/i.test(a.name); })[0];
        var downloadUrl = asset ? asset.browser_download_url : null;
        var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
        set("releaseTag", tag);
        if (rel.published_at) {
          var d = new Date(rel.published_at);
          if (!isNaN(d.getTime())) {
            set("releaseDate", d.toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" }));
          }
        }
        set("releaseSize", humanSize(asset && asset.size));
        if (downloadUrl) {
          ["releaseBtn", "downloadBtn", "ctaDownloadBtn", "releaseTabBtn"].forEach(function (id) {
            var el = document.getElementById(id);
            if (el) el.setAttribute("href", downloadUrl);
          });
          var label = "Get AerialDrop " + tag;
          var lbl = $("#releaseBtnLabel"); if (lbl) lbl.textContent = label;
          var dl = $("#downloadBtnLabel"); if (dl) dl.textContent = "Download " + tag;
        }
      })
      .catch(function () {
        var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
        set("releaseDate", "unavailable offline");
        set("releaseSize", "—");
      })
      .then(function () { if (timer) clearTimeout(timer); });
  }
  if (window.fetch) fetchRelease();

  /* ---------- Copy to clipboard ---------- */
  function copyText(text, btn) {
    function done() {
      if (!btn) return;
      var original = btn.textContent;
      btn.textContent = "Copied ✓";
      btn.classList.add("is-copied");
      setTimeout(function () { btn.textContent = original; btn.classList.remove("is-copied"); }, 1600);
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(done, function () { legacyCopy(text); done(); });
    } else { legacyCopy(text); done(); }
  }
  function legacyCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed"; ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta);
  }
  $$(".code-block__copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var code = btn.closest(".code-block");
      var text = code ? code.querySelector("code").innerText : btn.getAttribute("data-copy") || "";
      copyText(text, btn);
    });
  });
  $$(".copy-line").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy") || "";
      if (!text) {
        var code = btn.querySelector("code");
        text = code ? code.innerText : "";
      }
      copyText(text.replace(/\\n/g, "\n"), btn);
    });
  });

  /* ---------- Install tabs ---------- */
  var tabList = $("#installTabs");
  if (tabList) {
    var tabs = $$(".tab", tabList), panels = $$(".tab-panel", tabList);
    function selectTab(tab) {
      tabs.forEach(function (t) {
        var on = t === tab;
        t.classList.toggle("is-active", on);
        t.setAttribute("aria-selected", on ? "true" : "false");
        t.setAttribute("tabindex", on ? "0" : "-1");
      });
      panels.forEach(function (p) {
        var on = p.id === tab.getAttribute("data-tab");
        p.classList.toggle("is-active", on);
        p.hidden = !on;
      });
    }
    tabs.forEach(function (tab) {
      tab.addEventListener("click", function () { selectTab(tab); });
      tab.addEventListener("keydown", function (e) {
        var idx = tabs.indexOf(tab);
        if (e.key === "ArrowRight" || e.key === "ArrowDown") { e.preventDefault(); selectTab(tabs[(idx + 1) % tabs.length]); tabs[(idx + 1) % tabs.length].focus(); }
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") { e.preventDefault(); selectTab(tabs[(idx - 1 + tabs.length) % tabs.length]); tabs[(idx - 1 + tabs.length) % tabs.length].focus(); }
      });
    });
  }

  /* ---------- Pipeline stepper ---------- */
  var stepperEl = $("#stepper");
  if (stepperEl) {
    var nodes = $$(".stepper__node", stepperEl);
    var panelsEl = $$(".step-panel");
    var progress = $("#stepProgress"), status = $("#stepStatus");
    var prevBtn = $("#stepPrev"), nextBtn = $("#stepNext"), playBtn = $("#stepPlay");
    var titles = nodes.map(function (n) { return n.textContent.trim().replace(/^\d+/, "").trim(); });
    var current = 0, autoplay = false, timer = null, STEP_MS = 3400;
    var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

    function render() {
      nodes.forEach(function (n, i) {
        var li = n.parentElement;
        li.classList.toggle("is-active", i === current);
        li.classList.toggle("is-done", i < current);
        if (i === current) n.setAttribute("aria-current", "step"); else n.removeAttribute("aria-current");
      });
      panelsEl.forEach(function (p, i) { p.classList.toggle("is-active", i === current); p.hidden = i !== current; });
      if (progress) progress.style.width = ((current + 1) / nodes.length * 100) + "%";
      if (status) status.textContent = "Step " + (current + 1) + " of " + nodes.length + " · " + titles[current];
      if (prevBtn) prevBtn.disabled = current === 0;
      if (nextBtn) nextBtn.disabled = current === nodes.length - 1;
    }
    function go(i) {
      current = Math.max(0, Math.min(nodes.length - 1, i));
      render();
    }
    function stopAutoplay() {
      autoplay = false;
      if (timer) { clearInterval(timer); timer = null; }
      if (playBtn) { playBtn.textContent = "Play"; playBtn.setAttribute("aria-pressed", "false"); }
    }
    function startAutoplay() {
      if (reduced) { playBtn.textContent = "Play"; playBtn.setAttribute("aria-pressed", "false"); return; }
      autoplay = true;
      playBtn.textContent = "Pause"; playBtn.setAttribute("aria-pressed", "true");
      timer = setInterval(function () {
        if (current >= nodes.length - 1) { go(0); } else { go(current + 1); }
      }, STEP_MS);
    }
    nodes.forEach(function (n, i) {
      n.addEventListener("click", function () { stopAutoplay(); go(i); });
    });
    if (prevBtn) prevBtn.addEventListener("click", function () { stopAutoplay(); go(current - 1); });
    if (nextBtn) nextBtn.addEventListener("click", function () { stopAutoplay(); go(current + 1); });
    if (playBtn) playBtn.addEventListener("click", function () { autoplay ? stopAutoplay() : startAutoplay(); });
    if (document.addEventListener) {
      document.addEventListener("visibilitychange", function () { if (document.hidden) stopAutoplay(); });
    }
    render();
  }

  /* ---------- OS compatibility check ---------- */
  var osEl = $("#osCheck");
  if (osEl) {
    var ua = navigator.userAgent || "";
    var mac = /Macintosh|Mac OS X/i.test(ua) && !/iPhone|iPad|iPod/i.test(ua);
    var text;
    if (mac) {
      text = '<span class="ok">✓ macOS detected</span> — you\'re on the right platform. AerialDrop needs macOS 26 (Tahoe) or later: check <em>System Settings → About</em>.';
    } else if (/iPhone|iPad|iPod/i.test(ua)) {
      text = '<span class="warn">iOS detected</span> — AerialDrop is a macOS app and needs a Mac running Tahoe 26 or later.';
    } else {
      text = '<span class="warn">Not macOS?</span> AerialDrop runs on Macs with macOS 26 (Tahoe) or later — this page can\'t verify your OS from the browser.';
    }
    osEl.innerHTML = text;
  }

  /* ---------- Scroll reveal ---------- */
  var revealEls = $$(".reveal");
  if (revealEls.length && "IntersectionObserver" in window && !(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches)) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
      });
    }, { threshold: 0.12, rootMargin: "0px 0px -6% 0px" });
    revealEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.forEach(function (el) { el.classList.add("in"); });
  }

  /* ---------- Footer year ---------- */
  var yearEl = $("#year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();
