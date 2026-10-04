/* Browser and Node implementation of Scripts/release_compatibility.py's contract. */
(function (root, factory) {
  var api = factory();
  if (typeof module === "object" && module.exports) module.exports = api;
  root.AerialDropCompatibility = api;
})(typeof window === "object" ? window : globalThis, function () {
  "use strict";

  var baseUrl = "https://github.com/YapWH1208/AerialDrop/releases/download";
  var apiUrl = "https://api.github.com/repos/YapWH1208/AerialDrop/releases";
  var versionPattern = /^(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$/;

  function fail(message) { throw new Error(message); }
  function versionKey(value) {
    var match = typeof value === "string" ? versionPattern.exec(value) : null;
    if (!match || match[0].length !== value.length) fail("invalid stable version");
    return value.split(".").map(Number);
  }
  function major(value) {
    if (!Number.isInteger(value) || value < 26 || value > 999) fail("macOS major must be 26 through 999");
    return value;
  }
  function archValid(value) { return value === "arm64" || value === "x86_64"; }
  function exactKeys(value, keys) {
    return value && typeof value === "object" && !Array.isArray(value) &&
      Object.keys(value).sort().join("|") === keys.slice().sort().join("|");
  }
  function validatePolicy(policy) {
    if (!exactKeys(policy, ["schema_version", "releases"]) || policy.schema_version !== 1 ||
        !Number.isInteger(policy.schema_version) || !Array.isArray(policy.releases) || !policy.releases.length) {
      fail("invalid compatibility policy schema");
    }
    var seen = new Set();
    policy.releases.forEach(function (record) {
      if (!exactKeys(record, ["version", "min_macos", "max_macos", "architectures"])) fail("invalid compatibility record");
      versionKey(record.version);
      if (seen.has(record.version)) fail("duplicate compatibility version");
      seen.add(record.version);
      major(record.min_macos);
      if (record.max_macos !== null && major(record.max_macos) < record.min_macos) fail("invalid macOS range");
      if (!Array.isArray(record.architectures) || !record.architectures.length ||
          record.architectures.some(function (arch) { return !archValid(arch); }) ||
          new Set(record.architectures).size !== record.architectures.length) fail("invalid architectures");
    });
    return policy;
  }
  function compatible(record, macos, arch) {
    major(macos);
    if (!archValid(arch)) fail("unsupported architecture");
    return record.min_macos <= macos && (record.max_macos === null || macos <= record.max_macos) &&
      record.architectures.indexOf(arch) !== -1;
  }
  function validatedAsset(release, version) {
    if (!Array.isArray(release.assets)) return null;
    var name = "AerialDrop-" + version + "-macOS.zip";
    var matches = release.assets.filter(function (asset) {
      return asset && typeof asset === "object" && !Array.isArray(asset) && asset.name === name;
    });
    if (matches.length !== 1) return null;
    var asset = matches[0];
    var url = baseUrl + "/v" + version + "/" + name;
    if (typeof asset.digest !== "string" || asset.digest.length !== 71 ||
        !/^sha256:[0-9a-fA-F]{64}$/.test(asset.digest) ||
        !Number.isInteger(asset.size) || asset.size <= 0 || asset.browser_download_url !== url) return null;
    return { name: name, url: url, sha256: asset.digest.slice(7).toLowerCase(), size: asset.size };
  }
  function compareVersions(a, b) {
    var left = versionKey(a), right = versionKey(b);
    for (var i = 0; i < 3; i++) if (left[i] !== right[i]) return left[i] - right[i];
    return 0;
  }
  function resolveRelease(policy, catalogue, macos, arch, version) {
    validatePolicy(policy);
    major(macos);
    if (!archValid(arch)) fail("unsupported architecture");
    if (version !== undefined && version !== null) versionKey(version);
    if (!Array.isArray(catalogue)) fail("release catalogue must be an array");
    var declarations = new Map(policy.releases.map(function (record) { return [record.version, record]; }));
    if (version && !declarations.has(version)) fail("version is not declared");
    if (version && !compatible(declarations.get(version), macos, arch)) fail("pinned version is incompatible");
    var seen = new Set(), candidates = [];
    catalogue.forEach(function (release) {
      if (!release || typeof release !== "object" || Array.isArray(release)) fail("malformed release catalogue entry");
      var tag = release.tag_name;
      if (typeof tag !== "string") fail("release catalogue entry has no tag_name");
      if (seen.has(tag)) fail("duplicate release catalogue tag");
      seen.add(tag);
      if (!tag.startsWith("v")) return;
      var candidateVersion = tag.slice(1);
      try { versionKey(candidateVersion); } catch (error) { return; }
      var record = declarations.get(candidateVersion);
      if (!record || (version && candidateVersion !== version) || release.draft !== false ||
          release.prerelease !== false || typeof release.published_at !== "string" || !release.published_at ||
          !compatible(record, macos, arch)) return;
      var asset = validatedAsset(release, candidateVersion);
      if (asset) candidates.push({ version: candidateVersion, tag: tag, asset: asset });
    });
    if (!candidates.length) fail("no compatible published release for macOS " + macos + " on " + arch);
    candidates.sort(function (a, b) { return compareVersions(b.version, a.version); });
    return candidates[0];
  }
  function loadCatalogue(fetcher) {
    var catalogue = [];
    function page(number) {
      if (number > 100) fail("release catalogue exceeds 100 pages");
      return fetcher(apiUrl + "?per_page=100&page=" + number, { headers: { Accept: "application/vnd.github+json" } })
        .then(function (response) {
          if (!response.ok) fail("GitHub HTTP " + response.status);
          return response.json();
        }).then(function (releases) {
          if (!Array.isArray(releases)) fail("invalid GitHub release response");
          if (releases.length > 100) fail("invalid GitHub release page length");
          catalogue.push.apply(catalogue, releases);
          return releases.length === 100 ? page(number + 1) : catalogue;
        });
    }
    return page(1);
  }
  return { validatePolicy: validatePolicy, resolveRelease: resolveRelease, loadCatalogue: loadCatalogue };
});
