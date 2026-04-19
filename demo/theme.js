(function () {
  const THEME_STORAGE_KEY = "crispybrain-demo-theme";
  const DEFAULT_THEME = "crispy";
  const SUPPORTED_THEMES = ["light", "dark", "crispy"];

  function normalizeTheme(value) {
    return SUPPORTED_THEMES.includes(value) ? value : DEFAULT_THEME;
  }

  function readStoredTheme() {
    try {
      return normalizeTheme(window.localStorage.getItem(THEME_STORAGE_KEY));
    } catch (_error) {
      return DEFAULT_THEME;
    }
  }

  function formatThemeLabel(themeName) {
    return themeName.charAt(0).toUpperCase() + themeName.slice(1);
  }

  function syncThemeControls(themeName, selectEl, badgeEl) {
    if (selectEl) {
      selectEl.value = themeName;
    }

    if (badgeEl) {
      badgeEl.textContent = formatThemeLabel(themeName);
    }
  }

  function applyTheme(themeName) {
    const normalizedTheme = normalizeTheme(themeName);
    document.documentElement.dataset.theme = normalizedTheme;

    try {
      window.localStorage.setItem(THEME_STORAGE_KEY, normalizedTheme);
    } catch (_error) {
      // Theme persistence is best-effort; the UI still works without it.
    }

    return normalizedTheme;
  }

  function initializeTheme() {
    return applyTheme(readStoredTheme());
  }

  function mountThemeControls(selectEl, badgeEl) {
    const activeTheme = normalizeTheme(document.documentElement.dataset.theme || readStoredTheme());
    syncThemeControls(activeTheme, selectEl, badgeEl);

    if (selectEl) {
      selectEl.addEventListener("change", (event) => {
        const nextTheme = applyTheme(event.target.value);
        syncThemeControls(nextTheme, selectEl, badgeEl);
      });
    }
  }

  window.CrispyBrainTheme = {
    THEME_STORAGE_KEY,
    DEFAULT_THEME,
    SUPPORTED_THEMES,
    normalizeTheme,
    readStoredTheme,
    applyTheme,
    initializeTheme,
    mountThemeControls,
    formatThemeLabel
  };

  initializeTheme();
})();
