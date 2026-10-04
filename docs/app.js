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

  /* The hero command must be copyable immediately; only the decorative
     output lines wait for the typing animation to reveal them. */
  var heroCopyBtn = $(".term-line--cmd .term-copy");
  if (heroCopyBtn) heroCopyBtn.classList.add("is-visible");

  /* ---------- Compatible release for an explicitly selected macOS ---------- */
  function humanSize(bytes) {
    if (typeof bytes !== "number" || !isFinite(bytes) || bytes <= 0) return "\u2014";
    var units = ["B", "KB", "MB", "GB"], i = 0;
    while (bytes >= 1024 && i < units.length - 1) { bytes /= 1024; i++; }
    return bytes.toFixed(i > 1 ? 1 : 0) + " " + units[i];
  }
  function applyRelease(result) {
    var tag = result.tag, version = result.version, asset = result.asset;
    var set = function (id, text) { var el = document.getElementById(id); if (el) el.textContent = text; };
    set("releaseTag", tag);
    set("expectVersion", version);
    set("releaseSize", humanSize(asset.size));
    set("unzipCmd", "unzip -q " + asset.name + " -d /Applications");
    var unzipCopy = $("#unzipCopy");
    if (unzipCopy) { unzipCopy.setAttribute("data-copy", "unzip -q " + asset.name + " -d /Applications"); unzipCopy.disabled = false; }
    set("termOut1", "==> Downloading " + asset.name);
    set("termOut4", "✓ aerialdrop " + version + " is ready. Open it, drop in a video.");
    $$("[data-download]").forEach(function (el) {
      el.setAttribute("href", asset.url);
      el.removeAttribute("aria-disabled");
    });
    $$("[data-download-label]").forEach(function (el) { el.textContent = "Download AerialDrop " + tag; });
  }
  function clearRelease() {
    var set = function (id, value) { var el = document.getElementById(id); if (el) el.textContent = value; };
    set("releaseTag", "—");
    set("releaseSize", "Awaiting selection");
    set("expectVersion", "Resolve on this Mac");
    set("unzipCmd", "ZIP command available after release lookup");
    set("termOut1", "==> Selecting a compatible release");
    set("termOut4", "✓ Install the newest compatible release for your Mac.");
    var unzipCopy = $("#unzipCopy");
    if (unzipCopy) { unzipCopy.removeAttribute("data-copy"); unzipCopy.disabled = true; }
    $$("[data-download]").forEach(function (el) {
      el.removeAttribute("href");
      el.setAttribute("aria-disabled", "true");
    });
    $$("[data-download-label]").forEach(function (el) { el.textContent = "Download unavailable"; });
  }
  var macosSelect = $("#macosSelect"), customMacos = $("#customMacos"), releaseStatus = $("#releaseStatus");
  var customMacosLabel = $("#customMacosLabel");
  var retryRelease = $("#retryRelease"), lookupId = 0, dataPromise = null;
  function showStatus(message, retry) {
    if (releaseStatus) releaseStatus.textContent = message;
    if (retryRelease) retryRelease.hidden = !retry;
  }
  function selectedMacos() {
    if (!macosSelect || !macosSelect.value) return null;
    return macosSelect.value === "other" ? Number(customMacos.value) : Number(macosSelect.value);
  }
  function fetchWithTimeout(url, options) {
    if (!("AbortController" in window)) return fetch(url, options);
    var controller = new AbortController();
    var timer = setTimeout(function () { controller.abort(); }, 10000);
    return fetch(url, Object.assign({}, options, { signal: controller.signal }))
      .then(function (response) { clearTimeout(timer); return response; }, function (error) { clearTimeout(timer); throw error; });
  }
  function loadReleaseData() {
    if (!dataPromise) {
      dataPromise = Promise.all([
        fetchWithTimeout("release-compatibility.json").then(function (response) {
          if (!response.ok) throw new Error("compatibility policy HTTP " + response.status);
          return response.json();
        }),
        window.AerialDropCompatibility.loadCatalogue(fetchWithTimeout)
      ]).catch(function (error) { dataPromise = null; throw error; });
    }
    return dataPromise;
  }
  function updateRelease() {
    var current = ++lookupId;
    clearRelease();
    var macos = selectedMacos();
    if (macosSelect && macosSelect.value === "other") {
      customMacos.hidden = false;
      if (customMacosLabel) customMacosLabel.hidden = false;
    } else if (customMacos) {
      customMacos.hidden = true;
      if (customMacosLabel) customMacosLabel.hidden = true;
    }
    if (macos === null) { showStatus("Choose your Mac’s macOS major version to find its newest compatible release.", false); return; }
    if (!Number.isInteger(macos) || macos < 26 || macos > 999) {
      showStatus("Enter a macOS major version from 26 through 999.", false); return;
    }
    if (!window.fetch || !window.AerialDropCompatibility) {
      showStatus("Release lookup is unavailable. Run the install script on your Mac or check the official release notes.", false); return;
    }
    showStatus("Checking published releases for macOS " + macos + " on Apple Silicon…", false);
    loadReleaseData().then(function (data) {
      if (current !== lookupId) return;
      var result = window.AerialDropCompatibility.resolveRelease(data[0], data[1], macos, "arm64");
      applyRelease(result);
      showStatus("Newest compatible published release for macOS " + macos + " on Apple Silicon: " + result.tag + ".", false);
    }).catch(function (error) {
      if (current !== lookupId) return;
      var message = String(error && error.message || error);
      if (/no compatible published release/.test(message)) {
        showStatus("No compatible published release is available for macOS " + macos + " on Apple Silicon. Check the release notes or try the install script on this Mac.", false);
      } else {
        showStatus("Couldn’t verify compatible releases. Retry, use the install script on this Mac, or inspect the official releases page. Direct ZIP downloads are paused.", true);
      }
    });
  }
  if (macosSelect) {
    clearRelease();
    macosSelect.disabled = false;
    macosSelect.addEventListener("change", updateRelease);
    if (customMacos) customMacos.addEventListener("input", updateRelease);
    if (retryRelease) retryRelease.addEventListener("click", function () {
      dataPromise = null;
      updateRelease();
    });
    showStatus("Choose your Mac’s macOS major version to find its newest compatible release.", false);
  }

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
    if (playBtn) playBtn.addEventListener("click", function () {
      if (autoplay) { stopAutoplay(); return; }
      if (reduced) {
        /* Reduced Motion never autoplays; each press visibly advances one step. */
        go(current >= nodes.length - 1 ? 0 : current + 1);
        return;
      }
      startAutoplay();
    });
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
