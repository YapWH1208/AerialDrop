/* AerialDrop landing page — interactivity (vanilla JS, no dependencies) */
(function () {
  "use strict";

  var $ = function (sel, root) { return (root || document).querySelector(sel); };
  var $$ = function (sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); };
  var reduced = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  /* ---------- Theme ---------- */
  var themeToggle = $("#themeToggle");
  function applyTheme(theme) {
    document.documentElement.setAttribute("data-theme", theme);
    var meta = $('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", theme === "light" ? "#f3f6f9" : "#070b10");
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

  /* ---------- Clipboard helpers ---------- */
  function legacyCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.style.position = "fixed";
    ta.style.opacity = "0";
    document.body.appendChild(ta);
    ta.select();
    var ok = false;
    try { ok = document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta);
    return ok;
  }
  function copyText(text, btn, doneText) {
    function flash(label, cls) {
      if (!btn) return;
      var original = btn.textContent;
      btn.textContent = label;
      btn.classList.add(cls);
      setTimeout(function () {
        btn.textContent = original;
        btn.classList.remove(cls);
      }, 1600);
    }
    var okLabel = doneText || "Copied \u2713";
    function tryLegacy() {
      if (legacyCopy(text)) {
        flash(okLabel, "is-copied");
      } else {
        flash("Copy failed", "is-failed");
      }
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(
        function () { flash(okLabel, "is-copied"); },
        tryLegacy
      );
    } else {
      tryLegacy();
    }
  }
  function commandFor(btn) {
    var attr = btn.getAttribute("data-copy");
    if (attr) return attr.replace(/\\n/g, "\n");
    var code = btn.parentElement ? btn.parentElement.querySelector("code") : null;
    return code ? code.innerText : "";
  }
  $$(".cmd__copy, .term-copy").forEach(function (btn) {
    btn.addEventListener("click", function () {
      copyText(commandFor(btn), btn);
    });
  });
  $$(".term-line--cmd").forEach(function (line) {
    line.addEventListener("click", function (e) {
      if (e.target.closest(".term-copy")) return;
      var btn = line.querySelector(".term-copy");
      if (btn) copyText(commandFor(btn), btn);
    });
  });

  /* ---------- Latest release (GitHub API, graceful fallback) ---------- */
  function humanSize(bytes) {
    if (typeof bytes !== "number" || !isFinite(bytes) || bytes <= 0) return "\u2014";
    var units = ["B", "KB", "MB", "GB"], i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return bytes.toFixed(i > 1 ? 1 : 0) + " " + units[i];
  }
  function applyRelease(tag, downloadUrl) {
    var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
    set("releaseTag", tag);
    set("expectVersion", tag.replace(/^v/, ""));
    var version = tag.replace(/^v/, "");
    var zipName = "AerialDrop-" + version + "-macOS.zip";
    var unzipCmd = $("#unzipCmd");
    if (unzipCmd) unzipCmd.textContent = "unzip -q " + zipName + " -d /Applications";
    var unzipCopy = $("#unzipCopy");
    if (unzipCopy) unzipCopy.setAttribute("data-copy", "unzip -q " + zipName + " -d /Applications");
    var out1 = $("#termOut1");
    if (out1) out1.innerHTML = '<span class="term-ok">==&gt;</span> Downloading ' + zipName;
    var out4 = $("#termOut4");
    if (out4) out4.innerHTML = '<span class="term-check">\u2713</span> aerialdrop ' + version + " is ready. Open it, drop in a video.";
    if (downloadUrl) {
      $$("[data-download]").forEach(function (el) { el.setAttribute("href", downloadUrl); });
      $$("[data-download-label]").forEach(function (el) { el.textContent = "Download AerialDrop " + tag; });
    }
  }
  function fetchRelease() {
    var url = "https://api.github.com/repos/YapWH1208/AerialDrop/releases/latest";
    var controller = ("AbortController" in window) ? new AbortController() : null;
    var timer = controller ? setTimeout(function () { controller.abort(); }, 6000) : null;
    fetch(url, controller ? { signal: controller.signal, headers: { Accept: "application/vnd.github+json" } } : {})
      .then(function (res) { if (!res.ok) throw new Error("HTTP " + res.status); return res.json(); })
      .then(function (rel) {
        var tag = rel.tag_name || "v1.1.3";
        var asset = (rel.assets || []).filter(function (a) { return /macOS/i.test(a.name) && /\.zip$/i.test(a.name); })[0];
        var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
        set("releaseSize", humanSize(asset && asset.size));
        applyRelease(tag, asset && asset.browser_download_url);
      })
      .catch(function () {
        var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
        set("releaseSize", "unavailable offline");
        applyRelease("v1.1.3", null);
      })
      .then(function () { if (timer) clearTimeout(timer); });
  }
  if (window.fetch) fetchRelease();

  /* ---------- Hero terminal typing ---------- */
  var termCmd = $("#termCmd");
  if (termCmd) {
    var cmdText = termCmd.getAttribute("data-text") ||
      "brew install --cask yapwh1208/tap/aerialdrop";
    var termOuts = ["termOut1", "termOut2", "termOut3", "termOut4", "termCursor"].map(function (id) {
      return document.getElementById(id);
    });
    var started = false, typing = false, step = 0, charIndex = 0;

    function typeStep() {
      if (charIndex < cmdText.length) {
        termCmd.textContent = cmdText.slice(0, charIndex + 1);
        charIndex++;
        setTimeout(typeStep, 26);
      } else {
        typing = false;
        setTimeout(function () { revealNext(); }, 550);
      }
    }
    function revealNext() {
      if (step < termOuts.length) {
        var el = termOuts[step];
        if (el) el.classList.remove("is-hidden");
        step++;
        setTimeout(revealNext, step === termOuts.length ? 900 : 620);
      } else {
        var copyBtn = document.querySelector(".term-line--cmd .term-copy");
        if (copyBtn) copyBtn.classList.add("is-visible");
      }
    }
    function startTerminal() {
      if (started) return;
      started = true;
      if (reduced) {
        termCmd.textContent = cmdText;
        termOuts.forEach(function (el) { if (el) el.classList.remove("is-hidden"); });
        var copyBtn2 = document.querySelector(".term-line--cmd .term-copy");
        if (copyBtn2) copyBtn2.classList.add("is-visible");
        return;
      }
      typing = true;
      setTimeout(typeStep, 700);
    }
    if ("IntersectionObserver" in window) {
      var ioTerm = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.isIntersecting) {
            startTerminal();
            ioTerm.disconnect();
          }
        });
      }, { threshold: 0.3 });
      var termBody = $("#termBody");
      if (termBody) ioTerm.observe(termBody);
    } else {
      startTerminal();
    }
  }

  /* ---------- Install method tabs ---------- */
  var installer = $("#installer");
  if (installer) {
    var methods = $$(".method", installer);
    var panels = $$(".panel", installer);
    function selectMethod(method) {
      methods.forEach(function (m) {
        var on = m === method;
        m.classList.toggle("is-active", on);
        m.setAttribute("aria-selected", on ? "true" : "false");
        m.setAttribute("tabindex", on ? "0" : "-1");
      });
      panels.forEach(function (p) {
        var on = p.id === method.getAttribute("data-tab");
        p.classList.toggle("is-active", on);
        p.hidden = !on;
      });
    }
    methods.forEach(function (method) {
      method.addEventListener("click", function () { selectMethod(method); });
      method.addEventListener("keydown", function (e) {
        var idx = methods.indexOf(method);
        if (e.key === "ArrowRight" || e.key === "ArrowDown") {
          e.preventDefault();
          selectMethod(methods[(idx + 1) % methods.length]);
          methods[(idx + 1) % methods.length].focus();
        }
        if (e.key === "ArrowLeft" || e.key === "ArrowUp") {
          e.preventDefault();
          selectMethod(methods[(idx - 1 + methods.length) % methods.length]);
          methods[(idx - 1 + methods.length) % methods.length].focus();
        }
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

    function render() {
      nodes.forEach(function (n, i) {
        var li = n.parentElement;
        li.classList.toggle("is-active", i === current);
        li.classList.toggle("is-done", i < current);
        if (i === current) n.setAttribute("aria-current", "step"); else n.removeAttribute("aria-current");
      });
      panelsEl.forEach(function (p, i) { p.classList.toggle("is-active", i === current); p.hidden = i !== current; });
      if (progress) progress.style.width = ((current + 1) / nodes.length * 100) + "%";
      if (status) status.textContent = "Step " + (current + 1) + " of " + nodes.length + " \u00b7 " + titles[current];
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
      if (reduced) return;
      autoplay = true;
      playBtn.textContent = "Pause";
      playBtn.setAttribute("aria-pressed", "true");
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

  /* ---------- First-run checklist (persisted) ---------- */
  var checkBoxes = $$("#checklistBox .check input[type='checkbox']");
  if (checkBoxes.length) {
    var KEY = "ad-checklist-v1";
    var countEl = $("#checkCount"), doneEl = $("#checkDone"), resetBtn = $("#checkReset");
    var barEl = $("#checkProgress");
    var saved = null;
    try { saved = JSON.parse(localStorage.getItem(KEY) || "null"); } catch (e) {}
    function renderChecklist() {
      var done = 0;
      checkBoxes.forEach(function (box) {
        var li = box.closest(".check");
        if (box.checked) {
          done++;
          if (li) li.classList.add("is-done");
        } else if (li) {
          li.classList.remove("is-done");
        }
      });
      if (countEl) countEl.textContent = done + " of " + checkBoxes.length + " done";
      if (barEl) barEl.style.width = (done / checkBoxes.length * 100) + "%";
      if (doneEl) doneEl.classList.toggle("is-hidden", done < checkBoxes.length);
    }
    checkBoxes.forEach(function (box, i) {
      if (saved && saved[i]) box.checked = true;
      box.addEventListener("change", function () {
        var values = checkBoxes.map(function (b) { return b.checked; });
        try { localStorage.setItem(KEY, JSON.stringify(values)); } catch (e) {}
        renderChecklist();
      });
    });
    if (resetBtn) {
      resetBtn.addEventListener("click", function () {
        checkBoxes.forEach(function (box) { box.checked = false; });
        try { localStorage.removeItem(KEY); } catch (e) {}
        renderChecklist();
      });
    }
    renderChecklist();
  }

  /* ---------- OS compatibility check ---------- */
  var osEl = $("#osCheck");
  if (osEl) {
    var ua = navigator.userAgent || "";
    var mac = /Macintosh|Mac OS X/i.test(ua) && !/iPhone|iPad|iPod/i.test(ua);
    if (mac) {
      osEl.innerHTML = '<span class="ok">\u2713 macOS detected</span> \u2014 need macOS 26 (Tahoe) or later';
    } else if (/iPhone|iPad|iPod/i.test(ua)) {
      osEl.innerHTML = '<span class="warn">iOS detected</span> \u2014 AerialDrop is a macOS app';
    } else {
      osEl.innerHTML = '<span class="warn">Not macOS?</span> \u2014 AerialDrop runs on macOS 26+';
    }
  }

  /* ---------- Scroll reveal ---------- */
  var revealEls = $$(".reveal");
  if (revealEls.length && "IntersectionObserver" in window && !reduced) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in");
          io.unobserve(entry.target);
        }
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
