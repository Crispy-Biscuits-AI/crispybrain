const themeManager = window.CrispyBrainTheme;

const form = document.getElementById("memory-form");
const projectSlugSelect = document.getElementById("project-slug");
const deleteProjectSelect = document.getElementById("delete-project-slug");
const createProjectInput = document.getElementById("create-project-slug");
const sessionIdInput = document.getElementById("session-id");
const questionInput = document.getElementById("question");
const createProjectButton = document.getElementById("create-project-button");
const submitButton = document.getElementById("submit-button");
const deleteProjectButton = document.getElementById("delete-project-button");
const projectFeedback = document.getElementById("project-feedback");
const projectCount = document.getElementById("project-count");
const activeProjectPill = document.getElementById("active-project-pill");
const queryContextBadge = document.getElementById("query-context-badge");
const queryContextNote = document.getElementById("query-context-note");
const statusPill = document.getElementById("status-pill");
const themeSelect = document.getElementById("theme-select");
const themeBadge = document.getElementById("theme-badge");
const resultsLayout = document.getElementById("results-layout");
const sourcesPanel = document.getElementById("sources-panel");
const sourcesToggle = document.getElementById("sources-toggle");
const sourcesBadge = document.getElementById("sources-badge");
const sourceToggleButtons = document.querySelectorAll("[data-toggle-sources]");
const traceDrawer = document.getElementById("trace-drawer");
const traceToggleButtons = document.querySelectorAll("[data-toggle-trace]");
const answerState = document.getElementById("answer-state");
const explanationSummary = document.getElementById("explanation-summary");
const confidenceIndicator = document.getElementById("confidence-indicator");
const explanationSourceCount = document.getElementById("explanation-source-count");
const explanationGroundingStatus = document.getElementById("explanation-grounding-status");
const explanationDetail = document.getElementById("explanation-detail");
const explanationUncertainty = document.getElementById("explanation-uncertainty");
const answerOutput = document.getElementById("answer-output");
const sourceSummary = document.getElementById("source-summary");
const sourcesOutput = document.getElementById("sources-output");
const traceNote = document.getElementById("trace-note");
const exportFullButton = document.getElementById("export-md-full");
const exportSocialButton = document.getElementById("export-md-social");
const exportStatus = document.getElementById("export-status");

const traceFields = {
  elapsed: document.getElementById("trace-elapsed"),
  inputTokens: document.getElementById("trace-input-tokens"),
  outputTokens: document.getElementById("trace-output-tokens"),
  sourceCount: document.getElementById("trace-source-count"),
  selectedCount: document.getElementById("trace-selected-count"),
  candidateCount: document.getElementById("trace-candidate-count"),
  topScore: document.getElementById("trace-top-score"),
  grounding: document.getElementById("trace-grounding"),
  mode: document.getElementById("trace-mode"),
  answerMode: document.getElementById("trace-answer-mode"),
  fallback: document.getElementById("trace-fallback"),
  memoryState: document.getElementById("trace-memory-state"),
  projectSlug: document.getElementById("trace-project-slug"),
  stage: document.getElementById("trace-stage"),
};

let sourcesOpen = true;
let traceOpen = true;
let queryBusy = false;
let projectActionBusy = false;
let projectsLoading = false;
let projectListUnavailable = false;
let projectActionMode = "";
let availableProjects = [];
let exportStatusTimer = null;

themeManager.mountThemeControls(themeSelect, themeBadge);
setSourcesOpen(true);
setTraceOpen(true);
resetPanels();
updateProjectContext();
loadProjectOptions();

for (const button of sourceToggleButtons) {
  button.addEventListener("click", () => {
    setSourcesOpen(!sourcesOpen);
  });
}

for (const button of traceToggleButtons) {
  button.addEventListener("click", () => {
    setTraceOpen(!traceOpen);
  });
}

exportFullButton.addEventListener("click", () => {
  void handleMarkdownExport("full");
});

exportSocialButton.addEventListener("click", () => {
  void handleMarkdownExport("social");
});

projectSlugSelect.addEventListener("change", () => {
  clearProjectFeedback();
  updateProjectContext();
  syncProjectControls();
});

deleteProjectSelect.addEventListener("change", () => {
  clearProjectFeedback();
  syncProjectControls();
});

createProjectInput.addEventListener("input", () => {
  clearProjectFeedback();
  syncProjectControls();
});

questionInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter" || event.shiftKey || event.altKey || event.metaKey || event.ctrlKey) {
    return;
  }

  event.preventDefault();
  if (!submitButton.disabled) {
    form.requestSubmit();
  }
});

createProjectInput.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") {
    return;
  }

  event.preventDefault();
  if (!createProjectButton.disabled) {
    createProject();
  }
});

createProjectButton.addEventListener("click", () => {
  createProject();
});

deleteProjectButton.addEventListener("click", async () => {
  const projectSlug = deleteProjectSelect.value.trim();
  if (!projectSlug) {
    renderNoProjectsState();
    return;
  }

  clearProjectFeedback();
  const confirmed = window.confirm(`Delete project "${projectSlug}" and remove its inbox folder?`);
  if (!confirmed) {
    return;
  }

  setProjectActionBusy(true, "deleting project", "deleting");
  try {
    const response = await fetch(`/api/projects/${encodeURIComponent(projectSlug)}`, {
      method: "DELETE",
      headers: {
        Accept: "application/json",
      },
      cache: "no-store",
    });
    const body = await response.json();

    if (!response.ok || body.ok !== true || !Array.isArray(body.projects)) {
      renderError(body.error || {
        code: "PROJECT_DELETE_FAILED",
        message: "CrispyBrain could not delete the selected project.",
      }, body);
      return;
    }

    renderProjectOptions(body.projects, body.default_project_slug);
    resetPanels();

    if (availableProjects.length === 0) {
      renderNoProjectsState(`Deleted project "${projectSlug}". No inbox projects remain.`);
      return;
    }

    answerState.textContent = "Project deleted";
    answerOutput.textContent = `Deleted project "${projectSlug}". Switched to "${projectSlugSelect.value.trim()}".`;
    syncProjectControls();
  } catch (error) {
    renderError({
      code: "PROJECT_DELETE_FAILED",
      message: "CrispyBrain could not delete the selected project.",
      details: error instanceof Error ? error.message : String(error),
    });
  } finally {
    setProjectActionBusy(false);
  }
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const projectSlug = projectSlugSelect.value.trim();
  const question = questionInput.value.trim();
  if (!question) {
    renderError({
      code: "INVALID_QUESTION",
      message: "Enter a query before running retrieval.",
    });
    return;
  }

  if (!projectSlug) {
    renderNoProjectsState();
    return;
  }

  setBusy(true);
  resetPanels();
  setRenderedQuestion(question);

  const payload = {
    question,
    project_slug: projectSlug,
    session_id: sessionIdInput.value.trim(),
  };

  const requestStarted = performance.now();

  try {
    const response = await fetch("/api/demo/ask", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const body = await response.json();
    const elapsedMs = Math.round(performance.now() - requestStarted);

    if (!response.ok || body.ok !== true) {
      renderError(body.error || {
        code: "REQUEST_FAILED",
        message: "The memory query did not complete successfully.",
      }, body, { elapsedMs, question });
      return;
    }

    renderSuccess(body, { elapsedMs, question });
  } catch (error) {
    renderError({
      code: "NETWORK_ERROR",
      message: "The local memory proxy could not be reached.",
      details: error instanceof Error ? error.message : String(error),
    }, {}, {
      elapsedMs: Math.round(performance.now() - requestStarted),
      question,
    });
  } finally {
    setBusy(false);
  }
});

async function createProject() {
  const desiredProjectSlug = createProjectInput.value.trim();
  if (!desiredProjectSlug) {
    setProjectFeedback("Enter a project slug before creating a project.", true);
    return;
  }

  clearProjectFeedback();
  setProjectActionBusy(true, "creating project", "creating");

  try {
    const response = await fetch("/api/projects", {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
      },
      cache: "no-store",
      body: JSON.stringify({
        project_slug: desiredProjectSlug,
      }),
    });
    const body = await response.json();

    if (!response.ok || body.ok !== true || typeof body.created_project_slug !== "string") {
      setProjectFeedback(
        body?.error?.message || "CrispyBrain could not create that inbox project.",
        true,
      );
      return;
    }

    createProjectInput.value = "";
    await loadProjectOptions(body.created_project_slug);
    if (!availableProjects.includes(body.created_project_slug) || projectSlugSelect.value.trim() !== body.created_project_slug) {
      setProjectFeedback("Project created, but CrispyBrain could not refresh the selector safely.", true);
      return;
    }

    clearProjectFeedback();
    resetPanels();
    answerState.textContent = "Project created";
    answerOutput.textContent = `Created project "${body.created_project_slug}" and selected it for retrieval.`;
    syncProjectControls();
    questionInput.focus();
  } catch (error) {
    setProjectFeedback(
      error instanceof Error
        ? `CrispyBrain could not create that inbox project. ${error.message}`
        : "CrispyBrain could not create that inbox project.",
      true,
    );
  } finally {
    setProjectActionBusy(false);
  }
}

async function loadProjectOptions(preferredProjectSlug = "") {
  projectsLoading = true;
  projectListUnavailable = false;
  updateProjectContext();
  syncProjectControls();

  try {
    const response = await fetch("/api/projects", {
      headers: {
        Accept: "application/json",
      },
      cache: "no-store",
    });
    const body = await response.json();

    if (!response.ok || !Array.isArray(body.projects)) {
      throw new Error("Project list request did not return a valid payload.");
    }

    renderProjectOptions(body.projects, body.default_project_slug, preferredProjectSlug);
  } catch (error) {
    renderProjectLoadFailure(error);
  } finally {
    projectsLoading = false;
    updateProjectContext();
    syncProjectControls();
  }
}

function renderProjectOptions(projects, defaultProjectSlug, preferredProjectSlug = "") {
  const currentValue = projectSlugSelect.value.trim();
  const currentDeleteValue = deleteProjectSelect.value.trim();
  const selectedValue = projects.includes(preferredProjectSlug)
    ? preferredProjectSlug
    : (projects.includes(currentValue)
      ? currentValue
      : (projects.includes(defaultProjectSlug) ? defaultProjectSlug : (projects[0] || "")));
  const selectedDeleteValue = projects.includes(currentDeleteValue)
    ? currentDeleteValue
    : (projects.includes(preferredProjectSlug)
      ? preferredProjectSlug
      : selectedValue);

  availableProjects = [...projects];
  projectListUnavailable = false;
  projectSlugSelect.innerHTML = "";
  deleteProjectSelect.innerHTML = "";

  if (projects.length === 0) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "No inbox projects found";
    option.selected = true;
    projectSlugSelect.appendChild(option);

    const deleteOption = document.createElement("option");
    deleteOption.value = "";
    deleteOption.textContent = "No inbox projects found";
    deleteOption.selected = true;
    deleteProjectSelect.appendChild(deleteOption);

    updateProjectContext();
    renderNoProjectsState();
    return;
  }

  for (const project of projects) {
    const option = document.createElement("option");
    option.value = project;
    option.textContent = project;
    option.selected = project === selectedValue;
    projectSlugSelect.appendChild(option);

    const deleteOption = document.createElement("option");
    deleteOption.value = project;
    deleteOption.textContent = project;
    deleteOption.selected = project === selectedDeleteValue;
    deleteProjectSelect.appendChild(deleteOption);
  }

  if (answerState.textContent === "No projects available" || answerState.textContent === "Project list unavailable") {
    resetPanels();
  }

  updateProjectContext();
}

function renderProjectLoadFailure(error) {
  availableProjects = [];
  projectListUnavailable = true;
  projectSlugSelect.innerHTML = "";
  deleteProjectSelect.innerHTML = "";
  setRenderedQuestion("");
  clearExportStatus();

  const option = document.createElement("option");
  option.value = "";
  option.textContent = "Projects unavailable";
  option.selected = true;
  projectSlugSelect.appendChild(option);

  const deleteOption = document.createElement("option");
  deleteOption.value = "";
  deleteOption.textContent = "Projects unavailable";
  deleteOption.selected = true;
  deleteProjectSelect.appendChild(deleteOption);

  updateProjectContext();
  answerState.textContent = "Project list unavailable";
  answerOutput.textContent = "CrispyBrain could not load inbox projects from /api/projects.";
  syncProjectControls();
  console.error("Failed to load inbox projects for CrispyBrain demo:", error);
}

function renderNoProjectsState(message = "No inbox projects are available.") {
  setRenderedQuestion("");
  clearExportStatus();
  updateProjectContext();
  answerState.textContent = "No projects available";
  answerOutput.textContent = `${message} Create a project above to enable retrieval from inbox/.`;
  syncProjectControls();
}

function setBusy(isBusy) {
  queryBusy = isBusy;
  submitButton.textContent = isBusy ? "Running..." : "Run query";
  if (!projectActionBusy) {
    statusPill.textContent = isBusy ? "running" : "idle";
    statusPill.classList.toggle("busy", isBusy);
  }
  syncProjectControls();

  if (isBusy) {
    clearExportStatus();
    answerState.textContent = "Retrieving memory…";
    answerOutput.textContent = "Searching stored memory and assembling a response…";
  }
}

function setProjectActionBusy(isBusy, statusText = "idle", actionMode = "") {
  projectActionBusy = isBusy;
  projectActionMode = isBusy ? actionMode : "";
  createProjectButton.textContent = projectActionMode === "creating" ? "Creating..." : "Create Project";
  deleteProjectButton.textContent = projectActionMode === "deleting" ? "Deleting..." : "Delete Project";
  if (isBusy) {
    statusPill.textContent = statusText;
    statusPill.classList.add("busy");
  } else if (!queryBusy) {
    statusPill.textContent = "idle";
    statusPill.classList.remove("busy");
  }
  syncProjectControls();
}

function syncProjectControls() {
  const hasProjects = availableProjects.length > 0;
  const hasProjectSelection = Boolean(projectSlugSelect.value.trim());
  const hasDeleteSelection = Boolean(deleteProjectSelect.value.trim());
  const hasCreateInput = Boolean(createProjectInput.value.trim());
  const controlsBusy = queryBusy || projectActionBusy || projectsLoading;
  const canExport = canExportRenderedAnswer();

  projectSlugSelect.disabled = controlsBusy || !hasProjects;
  deleteProjectSelect.disabled = controlsBusy || !hasProjects;
  createProjectInput.disabled = controlsBusy;
  createProjectButton.disabled = controlsBusy || !hasCreateInput;
  questionInput.disabled = controlsBusy || !hasProjectSelection;
  submitButton.disabled = controlsBusy || !hasProjectSelection;
  deleteProjectButton.disabled = controlsBusy || !hasDeleteSelection;
  exportFullButton.disabled = controlsBusy || !canExport;
  exportSocialButton.disabled = controlsBusy || !canExport;
}

function setProjectFeedback(message, isError = false) {
  const trimmedMessage = typeof message === "string" ? message.trim() : "";
  projectFeedback.textContent = trimmedMessage;
  projectFeedback.hidden = trimmedMessage === "";
  projectFeedback.classList.toggle("is-error", isError && trimmedMessage !== "");
}

function clearProjectFeedback() {
  setProjectFeedback("");
}

function updateProjectContext() {
  const selectedProject = projectSlugSelect.value.trim();

  if (projectsLoading) {
    projectCount.textContent = "Loading projects…";
    activeProjectPill.textContent = "Loading projects…";
    queryContextBadge.textContent = "Loading projects…";
    queryContextNote.textContent = "Loading available inbox projects for retrieval.";
    return;
  }

  if (projectListUnavailable) {
    projectCount.textContent = "Projects unavailable";
    activeProjectPill.textContent = "Projects unavailable";
    queryContextBadge.textContent = "Reload projects";
    queryContextNote.textContent = "CrispyBrain could not load inbox projects from /api/projects.";
    return;
  }

  projectCount.textContent = availableProjects.length === 0
    ? "No projects yet"
    : `${availableProjects.length} ${availableProjects.length === 1 ? "project" : "projects"}`;

  if (availableProjects.length === 0) {
    activeProjectPill.textContent = "Create a project";
    queryContextBadge.textContent = "No active project";
    queryContextNote.textContent = "Create a project to enable retrieval from inbox/.";
    return;
  }

  if (!selectedProject) {
    activeProjectPill.textContent = "Select a project";
    queryContextBadge.textContent = "Select a project";
    queryContextNote.textContent = "Choose which inbox project CrispyBrain should query.";
    return;
  }

  activeProjectPill.textContent = selectedProject;
  queryContextBadge.textContent = selectedProject;
  queryContextNote.textContent = `This query will run against "${selectedProject}".`;
}

function resetPanels() {
  clearExportStatus();
  if (!queryBusy) {
    setRenderedQuestion("");
  }
  updateSourceLabels(0);
  renderExplanation({}, [], [], {
    isBusy: statusPill.classList.contains("busy"),
  });
  renderSourceSummary({}, [], []);
  renderSources([]);
  renderTrace({}, { elapsedMs: null }, [], []);

  if (!statusPill.classList.contains("busy")) {
    answerState.textContent = "Ready for a query";
    answerOutput.textContent = "Query memory to see an answer here.";
  }

  syncProjectControls();
}

function renderSuccess(body, meta = {}) {
  const selectedSources = normalizeSources(body.selected_sources || body.sources);
  const retrievedCandidates = normalizeSources(body.retrieved_candidates);
  const presentation = deriveAnswerPresentation(body, selectedSources);
  if (typeof meta.question === "string") {
    setRenderedQuestion(meta.question);
  }
  answerOutput.textContent = presentation.answerText || "No answer text returned.";
  answerState.textContent = buildAnswerState(body, selectedSources);

  updateSourceLabels(selectedSources.length);
  renderExplanation(body, selectedSources, retrievedCandidates, { presentation });
  renderSourceSummary(body, selectedSources, retrievedCandidates);
  renderSources(selectedSources);
  renderTrace(body, meta, selectedSources, retrievedCandidates);
  syncProjectControls();
}

function renderError(error, body = {}, meta = {}) {
  const selectedSources = normalizeSources(body.selected_sources || body.sources);
  const retrievedCandidates = normalizeSources(body.retrieved_candidates);
  const presentation = deriveAnswerPresentation(body, selectedSources);
  setRenderedQuestion(typeof meta.question === "string" ? meta.question : "");
  answerState.textContent = "Request could not be completed";
  answerOutput.textContent = presentation.answerText || body.answer || error.message || "The memory query failed.";

  updateSourceLabels(selectedSources.length);
  renderExplanation({ ...body, error }, selectedSources, retrievedCandidates, { presentation });
  renderSourceSummary({ ...body, error }, selectedSources, retrievedCandidates);
  renderSources(selectedSources);
  renderTrace({ ...body, error }, meta, selectedSources, retrievedCandidates);
  syncProjectControls();
}

async function handleMarkdownExport(mode) {
  const exportData = extractRenderedContentFromDom();
  if (!isRenderableExportData(exportData)) {
    showExportStatus("Run a query before exporting.", true);
    syncProjectControls();
    return;
  }

  const markdown = generateMarkdownExport(mode, exportData);
  if (!markdown) {
    showExportStatus("Markdown export is not available right now.", true);
    return;
  }

  const copied = await copyTextToClipboard(markdown);
  if (!copied) {
    showExportStatus("CrispyBrain could not copy the markdown.", true);
    return;
  }

  showExportStatus(mode === "full" ? "Copied full markdown." : "Copied social markdown.");
}

function setRenderedQuestion(questionText) {
  resultsLayout.dataset.renderedQuestion = normalizeExportBlock(questionText);
}

function extractRenderedContentFromDom() {
  return {
    questionText: normalizeExportBlock(resultsLayout.dataset.renderedQuestion || ""),
    answerText: normalizeExportBlock(answerOutput.textContent),
    whyThisAnswer: extractRenderedWhyThisAnswer(),
    sources: extractRenderedSources(),
    trace: extractRenderedTraceLines(),
  };
}

function extractRenderedWhyThisAnswer() {
  return {
    bullets: uniqueTexts([
      explanationSummary.textContent,
      explanationDetail.textContent,
      explanationUncertainty.hidden ? "" : explanationUncertainty.textContent,
    ]).map((line) => collapseExportLine(line)).filter(Boolean),
  };
}

function extractRenderedSources() {
  return Array.from(sourcesOutput.querySelectorAll(".source-card"))
    .map((card) => {
      const title = collapseExportLine(card.querySelector("h3")?.textContent || "");
      const chunkLabel = collapseExportLine(card.querySelector(".source-card-header .source-badge")?.textContent || "");
      const preview = collapseExportLine(card.querySelector(".source-preview")?.textContent || "");
      const pathLabel = collapseExportLine(card.querySelector(".source-path")?.textContent || "");
      const meta = collapseExportLine(card.querySelector(".source-meta")?.textContent || "");
      const segments = [];

      if (title) {
        segments.push(chunkLabel ? `${title} (${chunkLabel})` : title);
      }
      if (preview) segments.push(preview);
      if (pathLabel && pathLabel !== title) segments.push(pathLabel);
      if (meta && meta !== "Supporting memory") segments.push(meta);

      return segments.join(" — ");
    })
    .filter(Boolean);
}

function extractRenderedTraceLines() {
  const traceLines = Array.from(traceDrawer.querySelectorAll(".trace-row"))
    .map((row) => {
      const label = collapseExportLine(row.querySelector("dt")?.textContent || "");
      const value = collapseExportLine(row.querySelector("dd")?.textContent || "");
      if (!label || !value || value === "—") {
        return "";
      }

      return `${label}: ${value}`;
    })
    .filter(Boolean);

  const noteText = collapseExportLine(traceNote.textContent);
  if (noteText && noteText !== "No grounding note yet.") {
    traceLines.push(`Grounding note: ${noteText}`);
  }

  return traceLines;
}

function canExportRenderedAnswer() {
  return isRenderableExportData(extractRenderedContentFromDom());
}

function isRenderableExportData(exportData) {
  if (!exportData.questionText || !exportData.answerText) {
    return false;
  }

  return ![
    "Query memory to see an answer here.",
    "Searching stored memory and assembling a response…",
  ].includes(exportData.answerText);
}

function generateMarkdownExport(mode, data) {
  if (mode === "social") {
    return [
      `❓ ${data.questionText}`,
      "",
      `✅ ${data.answerText}`,
      "",
      "🧠 Source: CrispyBrain (local AI memory)",
    ].join("\n").trim();
  }

  const lines = [
    "# 🧠 CrispyBrain Q&A",
    "",
    "## ❓ Question",
    data.questionText,
    "",
    "## ✅ Answer",
    data.answerText,
  ];

  if (data.whyThisAnswer.bullets.length > 0) {
    lines.push("", "## 🧩 Why This Answer");
    for (const line of data.whyThisAnswer.bullets) {
      lines.push(`- ${line}`);
    }
  }

  if (data.sources.length > 0) {
    lines.push("", "## 📚 Sources");
    for (const source of data.sources) {
      lines.push(`- ${source}`);
    }
  }

  if (data.trace.length > 0) {
    lines.push("", "## 🔍 Trace (Optional)");
    for (const traceLine of data.trace) {
      lines.push(`- ${traceLine}`);
    }
  }

  lines.push("", "---", "Shared via **CrispyBrain (local-first AI memory system)**");
  return lines.join("\n").trim();
}

async function copyTextToClipboard(text) {
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch (error) {
      console.warn("navigator.clipboard.writeText failed, falling back to execCommand:", error);
    }
  }

  const fallback = document.createElement("textarea");
  fallback.value = text;
  fallback.setAttribute("readonly", "");
  fallback.style.position = "fixed";
  fallback.style.opacity = "0";
  fallback.style.pointerEvents = "none";
  document.body.appendChild(fallback);
  fallback.select();
  fallback.setSelectionRange(0, fallback.value.length);

  let copied = false;
  try {
    copied = document.execCommand("copy");
  } catch (error) {
    console.warn("Clipboard fallback failed:", error);
  } finally {
    fallback.remove();
  }

  return copied;
}

function showExportStatus(message, isError = false) {
  window.clearTimeout(exportStatusTimer);
  exportStatus.textContent = collapseExportLine(message);
  exportStatus.classList.toggle("is-error", isError);
  exportStatusTimer = window.setTimeout(() => {
    clearExportStatus();
  }, 2200);
}

function clearExportStatus() {
  window.clearTimeout(exportStatusTimer);
  exportStatusTimer = null;
  exportStatus.textContent = "";
  exportStatus.classList.remove("is-error");
}

function normalizeExportBlock(value) {
  if (typeof value !== "string") {
    return "";
  }

  return value
    .replace(/\r\n/g, "\n")
    .replace(/\u00a0/g, " ")
    .split("\n")
    .map((line) => line.replace(/[ \t]+/g, " ").trim())
    .join("\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function collapseExportLine(value) {
  return normalizeExportBlock(value).replace(/\n+/g, " ").trim();
}

function renderExplanation(body, selectedSources, retrievedCandidates, options = {}) {
  const grounding = asObject(body.grounding);
  const error = asObject(body.error);
  const presentation = asObject(options.presentation);
  const sourceCount = selectedSources.length;
  const candidateCount = retrievedCandidates.length;
  const isBusy = options.isBusy === true;
  const status = deriveGroundingStatus(body, grounding, error);
  const confidence = determineConfidence(status, error, isBusy);

  explanationSummary.textContent = buildExplanationSummary(status, sourceCount, isBusy, error);
  explanationDetail.textContent = buildExplanationDetail(body, status, sourceCount, candidateCount, isBusy, error);
  explanationSourceCount.textContent = `${sourceCount} ${sourceCount === 1 ? "source" : "sources"} used`;
  explanationGroundingStatus.textContent = status === "idle"
    ? "Grounding unavailable"
    : `Grounding ${status}`;
  confidenceIndicator.textContent = confidence.label;
  confidenceIndicator.className = `confidence-pill ${confidence.className}`;

  const uncertaintyText = buildUncertaintyText(status, grounding, presentation);
  if (uncertaintyText) {
    explanationUncertainty.hidden = false;
    explanationUncertainty.textContent = uncertaintyText;
    return;
  }

  explanationUncertainty.hidden = true;
  explanationUncertainty.textContent = "";
}

function renderSourceSummary(body, selectedSources, retrievedCandidates) {
  sourceSummary.innerHTML = "";

  const grounding = asObject(body.grounding);
  const trace = asObject(body.trace);
  const noteText = cleanText(grounding.note)
    || (body.answer_mode === "insufficient" ? "No strong supporting memory was retrieved." : "");
  const summaryItems = [
    ["Project", cleanText(body.project_slug) || cleanText(trace.project_slug)],
    ["Answer mode", cleanText(body.answer_mode)],
    ["Grounding", cleanText(grounding.status)],
    ["Selected", selectedSources.length > 0 ? String(selectedSources.length) : ""],
    ["Candidates", retrievedCandidates.length > 0 ? String(retrievedCandidates.length) : ""],
  ].filter(([, value]) => value);

  if (summaryItems.length === 0 && !noteText) {
    sourceSummary.innerHTML = '<p class="empty-state">No supporting trace summary yet.</p>';
    return;
  }

  const card = document.createElement("div");
  card.className = "source-summary-card";

  if (summaryItems.length > 0) {
    const list = document.createElement("dl");
    list.className = "summary-list";

    for (const [label, value] of summaryItems) {
      const row = document.createElement("div");
      const term = document.createElement("dt");
      term.textContent = label;
      const detail = document.createElement("dd");
      detail.textContent = value;
      row.appendChild(term);
      row.appendChild(detail);
      list.appendChild(row);
    }

    card.appendChild(list);
  }

  if (noteText) {
    const note = document.createElement("p");
    note.className = "summary-note";
    note.textContent = noteText;
    card.appendChild(note);
  }

  sourceSummary.appendChild(card);
}

function renderSources(sources) {
  sourcesOutput.innerHTML = "";

  if (sources.length === 0) {
    sourcesOutput.innerHTML = '<p class="empty-state">No supporting memory found.</p>';
    return;
  }

  for (const source of sources) {
    const card = document.createElement("article");
    card.className = "source-card";

    const header = document.createElement("div");
    header.className = "source-card-header";

    const title = document.createElement("h3");
    title.textContent = source.filename || source.title || "Untitled source";
    header.appendChild(title);

    if (source.chunkLabel) {
      const chunk = document.createElement("span");
      chunk.className = "source-badge";
      chunk.textContent = source.chunkLabel;
      header.appendChild(chunk);
    }

    card.appendChild(header);

    const badges = document.createElement("div");
    badges.className = "source-badges";

    if (typeof source.score === "number") {
      const relevance = document.createElement("span");
      relevance.className = "source-badge";
      relevance.textContent = `Relevance ${source.score.toFixed(3)}`;
      badges.appendChild(relevance);
    }

    if (source.reviewStatus) {
      const review = document.createElement("span");
      review.className = "source-badge";
      review.textContent = source.reviewStatus;
      badges.appendChild(review);
    }

    if (source.sourceQuality) {
      const quality = document.createElement("span");
      quality.className = "source-badge";
      quality.textContent = `Quality ${source.sourceQuality}`;
      badges.appendChild(quality);
    }

    if (source.sourceIndependence) {
      const independence = document.createElement("span");
      independence.className = "source-badge";
      independence.textContent = source.sourceIndependence;
      badges.appendChild(independence);
    }

    if (badges.childElementCount > 0) {
      card.appendChild(badges);
    }

    const snippet = document.createElement("p");
    snippet.className = "source-preview";
    snippet.textContent = source.preview ? `"${source.preview}"` : "No preview available.";
    card.appendChild(snippet);

    if (source.pathLabel) {
      const path = document.createElement("p");
      path.className = "source-path";
      path.textContent = source.pathLabel;
      card.appendChild(path);
    }

    const meta = document.createElement("p");
    meta.className = "source-meta";
    const parts = [];

    if (source.projectSlug) parts.push(`project ${source.projectSlug}`);
    if (source.identifier) parts.push(source.identifier);

    meta.textContent = parts.join(" · ") || "Supporting memory";
    card.appendChild(meta);

    sourcesOutput.appendChild(card);
  }
}

function renderTrace(body, meta = {}, selectedSources = [], retrievedCandidates = []) {
  const retrieval = asObject(body.retrieval);
  const grounding = asObject(body.grounding);
  const trace = asObject(body.trace);
  const debug = asObject(body.debug);
  const error = asObject(body.error);
  const usage = extractUsage(body, trace, debug);
  const elapsed = determineElapsedMs(trace, debug, meta);

  setTraceField("elapsed", formatMilliseconds(elapsed));
  setTraceField("inputTokens", formatTokenCount(usage.inputTokens));
  setTraceField("outputTokens", formatTokenCount(usage.outputTokens));
  setTraceField("sourceCount", formatPlain(firstNumber(
    selectedSources.length,
    grounding.supporting_source_count,
    debug.supporting_source_count,
    retrieval.memory_count,
    debug.retrieval_count,
  )));
  setTraceField("selectedCount", formatPlain(firstNumber(
    selectedSources.length,
    grounding.supporting_source_count,
  )));
  setTraceField("candidateCount", formatPlain(firstNumber(
    retrievedCandidates.length,
    body.filtered_candidate_count,
  )));
  setTraceField("topScore", formatScore(firstNumber(
    strongestSourceScore(selectedSources),
    retrieval.strongest_similarity,
    grounding.strongest_similarity,
  )));
  setTraceField("grounding", formatPlain(
    grounding.status || error.code || "—"
  ));
  setTraceField("mode", determineRetrievalMode(body));
  setTraceField("answerMode", formatPlain(body.answer_mode));
  setTraceField("fallback", determineFallbackState(body));
  setTraceField("memoryState", determineMemoryState(body, selectedSources));
  setTraceField("projectSlug", formatPlain(
    cleanText(body.project_slug) || cleanText(trace.project_slug)
  ));
  setTraceField("stage", formatPlain(
    trace.stage || debug.trace_stage || debug.workflow || "—"
  ));
  setTraceNote(
    cleanText(grounding.note)
      || cleanText(error.message)
      || "No grounding note yet.",
    grounding.weak_grounding === true || body.answer_mode === "insufficient",
  );
}

function setTraceField(key, value) {
  traceFields[key].textContent = value;
}

function setTraceNote(value, isWarning) {
  traceNote.textContent = value;
  traceNote.classList.toggle("is-warning", isWarning === true);
}

function updateSourceLabels(count) {
  const amount = `${count} ${count === 1 ? "source" : "sources"} used`;
  sourcesToggle.textContent = `Sources (${count})`;
  sourcesBadge.textContent = amount;
}

function setSourcesOpen(isOpen) {
  sourcesOpen = isOpen;
  resultsLayout.classList.toggle("sources-open", isOpen);
  sourcesPanel.setAttribute("aria-hidden", String(!isOpen));

  for (const button of sourceToggleButtons) {
    button.setAttribute("aria-expanded", String(isOpen));
  }
}

function setTraceOpen(isOpen) {
  traceOpen = isOpen;
  traceDrawer.classList.toggle("trace-open", isOpen);
  traceDrawer.setAttribute("aria-hidden", String(!isOpen));

  for (const button of traceToggleButtons) {
    button.setAttribute("aria-expanded", String(isOpen));
  }
}

function buildAnswerState(body, sources) {
  const grounding = asObject(body.grounding);

  if (body.answer_mode === "direct" && sources.length > 0) {
    return "Direct answer";
  }

  if (sources.length > 0) {
    return "Source-backed response";
  }

  if (typeof grounding.note === "string" && grounding.note.trim() !== "") {
    return grounding.note.trim();
  }

  if (body.answer_mode === "insufficient") {
    return "No strong supporting memory was retrieved";
  }

  return "Response ready";
}

function deriveAnswerPresentation(body, selectedSources = []) {
  const rawAnswer = cleanText(body.answer);
  if (!rawAnswer) {
    return {
      answerText: "",
      caveatText: "",
    };
  }

  if (body.answer_mode !== "direct") {
    return {
      answerText: canonicalizeAnswerTerms(rawAnswer, body, selectedSources),
      caveatText: "",
    };
  }

  const paragraphs = splitAnswerParagraphs(rawAnswer);
  const answerParagraphs = [];
  const caveatParagraphs = [];

  for (const [index, paragraph] of paragraphs.entries()) {
    if (index === 0) {
      const splitParagraph = splitDirectAnswerParagraph(paragraph);
      if (splitParagraph !== null) {
        if (splitParagraph.answerText) answerParagraphs.push(splitParagraph.answerText);
        if (splitParagraph.caveatText) caveatParagraphs.push(splitParagraph.caveatText);
        continue;
      }
    }

    const sentenceSplit = splitCaveatSentences(paragraph);
    if (sentenceSplit !== null) {
      if (sentenceSplit.answerText) answerParagraphs.push(sentenceSplit.answerText);
      if (sentenceSplit.caveatText) caveatParagraphs.push(sentenceSplit.caveatText);
      continue;
    }

    if (looksLikeAnswerCaveat(paragraph)) {
      caveatParagraphs.push(paragraph);
      continue;
    }

    answerParagraphs.push(paragraph);
  }

  const fallbackAnswer = answerParagraphs.join("\n\n").trim()
    || buildUnsupportedDetailAnswer(body)
    || rawAnswer;
  const answerText = canonicalizeAnswerTerms(
    normalizeDirectAnswerText(fallbackAnswer),
    body,
    selectedSources,
  );
  const caveatText = canonicalizeAnswerTerms(
    uniqueTexts(caveatParagraphs).join(" ").trim(),
    body,
    selectedSources,
  );

  return {
    answerText,
    caveatText,
  };
}

function splitCaveatSentences(paragraph) {
  const sentences = splitSentences(paragraph);
  if (sentences.length < 2 || !looksLikeAnswerCaveat(sentences[0])) {
    return null;
  }

  const answerSentences = [];
  const caveatSentences = [];
  let answerStarted = false;

  for (const sentence of sentences) {
    if (!answerStarted && looksLikeAnswerCaveat(sentence)) {
      caveatSentences.push(sentence);
      continue;
    }

    answerStarted = true;
    answerSentences.push(sentence);
  }

  return {
    answerText: answerSentences.join(" ").trim(),
    caveatText: caveatSentences.join(" ").trim(),
  };
}

function splitSentences(text) {
  return cleanText(text)
    .split(/(?<=[.!?])\s+/)
    .map((sentence) => sentence.trim())
    .filter(Boolean);
}

function normalizeDirectAnswerText(text) {
  return cleanText(text)
    .replace(
      /^there is no mention of (.+?) in (?:the )?(?:retrieved memory context|available project memory|project memory)\.?$/i,
      "Project memory does not mention $1.",
    )
    .replace(
      /^no mention of (.+?) appears in (?:the )?(?:retrieved memory context|available project memory|project memory)\.?$/i,
      "Project memory does not mention $1.",
    )
    .trim();
}

function buildUnsupportedDetailAnswer(body) {
  const question = cleanText(body.query) || cleanText(body.question);
  const claim = describeUnsupportedQuestionClaim(question);
  if (!claim) return "";
  return `Project memory does not mention ${claim}.`;
}

function describeUnsupportedQuestionClaim(question) {
  const normalized = cleanText(question)
    .replace(/[\u2018\u2019]/g, "'")
    .replace(/[?]+$/g, "")
    .trim();
  const match = normalized.match(/^(?:is|are|was|were)\s+(.+)$/i);
  if (!match) return "";

  const words = match[1].trim().split(/\s+/).filter(Boolean);
  if (words.length < 3) return `that ${match[1].trim()}`;

  const predicate = words.pop();
  return `${words.join(" ")} being ${predicate}`;
}

function canonicalizeAnswerTerms(text, body = {}, selectedSources = []) {
  const sourceTexts = collectCanonicalSourceTexts(body, selectedSources);
  const canonicalTerms = extractCanonicalTerms(sourceTexts);
  let result = cleanText(text);

  for (const term of canonicalTerms) {
    result = replaceCanonicalTerm(result, term);
  }

  return result;
}

function collectCanonicalSourceTexts(body, selectedSources) {
  const texts = [
    cleanText(body.query),
    cleanText(body.question),
    cleanText(body.answer),
  ];

  for (const source of selectedSources) {
    const record = asObject(source);
    texts.push(
      cleanText(record.title),
      cleanText(record.filename),
      cleanText(record.snippet),
      cleanText(record.content),
      cleanText(record.preview),
    );
  }

  return texts.filter(Boolean);
}

function extractCanonicalTerms(texts) {
  const terms = [];
  const seen = new Set();
  const candidatePattern = /\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)+\b/g;
  const ignored = new Set(["Project Memory", "Crispy Brain"]);

  for (const text of texts) {
    for (const match of text.matchAll(candidatePattern)) {
      const term = match[0].trim();
      const key = term.toLowerCase();
      if (ignored.has(term) || seen.has(key)) continue;
      seen.add(key);
      terms.push(term);
    }
  }

  return terms.sort((a, b) => b.length - a.length);
}

function replaceCanonicalTerm(text, term) {
  const escaped = term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const pattern = new RegExp("\\b" + escaped.replace(/\s+/g, "\\s+") + "\\b", "gi");
  return text.replace(pattern, term);
}

function splitAnswerParagraphs(answerText) {
  return answerText
    .split(/\n\s*\n/g)
    .map((paragraph) => paragraph.trim())
    .filter(Boolean);
}

function splitDirectAnswerParagraph(paragraph) {
  const colonIndex = paragraph.indexOf(":");
  if (colonIndex <= 0 || colonIndex >= paragraph.length - 1) {
    return null;
  }

  const lead = paragraph.slice(0, colonIndex).trim();
  const tail = paragraph.slice(colonIndex + 1).trim();

  if (!lead || !tail || !looksLikeAnswerCaveat(lead)) {
    return null;
  }

  return {
    caveatText: normalizeCaveatLead(lead),
    answerText: tail,
  };
}

function looksLikeAnswerCaveat(text) {
  const value = cleanText(text).toLowerCase();
  if (!value) return false;

  return [
    /^available project memory is limited\b/,
    /^based on available project memory\b/,
    /^project memory is limited\b/,
    /^project memory provides only partial information\b/,
    /^the evidence is limited\b/,
    /^from project memory\b/,
    /^however, (?:the )?available information is limited\b/,
    /^grounding is weak\b/,
    /^early development is only partially documented\b/,
    /^anything beyond .* cannot be verified\b/,
    /^i do not have enough stored memory\b/,
    /^no strong supporting memory was retrieved\b/,
    /^some aspects of this answer are uncertain\b/,
    /^some details may be incomplete\b/,
    /^this answer is based on limited evidence\b/,
    /^this answer is based on project memory\b/,
  ].some((pattern) => pattern.test(value));
}

function normalizeCaveatLead(text) {
  const normalized = cleanText(text)
    .replace(/,?\s*but it supports these points$/i, "")
    .replace(/,?\s*but$/i, "")
    .trim();

  if (!normalized) return "";
  return /[.!?]$/.test(normalized) ? normalized : `${normalized}.`;
}

function normalizeSources(value) {
  if (!Array.isArray(value)) return [];

  return value.map((source) => {
    const record = asObject(source);
    const label = cleanText(record.source_label) || cleanText(record.title) || cleanText(record.source);
    return {
      title: cleanText(record.title) || label || "Untitled source",
      filename: cleanText(record.filename) || extractFilenameFromLabel(label) || "Untitled source",
      chunkLabel: buildChunkLabel(record, label),
      snippet: cleanText(record.snippet) || cleanText(record.content),
      preview: buildSnippetPreview(cleanText(record.snippet) || cleanText(record.content)),
      score: firstNumber(record.retrieval_score, record.similarity, record.score),
      identifier: presentValue(
        cleanText(record.source_type),
        firstNumber(record.memory_id, record.id),
      ),
      pathLabel: cleanText(record.filepath) || cleanText(record.filename),
      projectSlug: cleanText(record.project_slug),
      reviewStatus: cleanText(record.review_status),
      sourceQuality: cleanText(record.source_quality),
      sourceIndependence: cleanText(record.source_independence),
    };
  });
}

function determineRetrievalMode(body) {
  const retrieval = asObject(body.retrieval);
  const trace = asObject(body.trace);
  const rankingMode = cleanText(trace.ranking_mode)?.toLowerCase();
  const strategy = cleanText(retrieval.strategy)?.toLowerCase();

  if (rankingMode) return rankingMode;
  if (strategy && /anchor/.test(strategy)) return "anchor";
  if (strategy && /lexical|keyword/.test(strategy)) return "keyword";
  if (strategy && /semantic|project-first|scope|all-memories|general/.test(strategy)) return "semantic";

  return "—";
}

function determineFallbackState(body) {
  const retrieval = asObject(body.retrieval);
  const trace = asObject(body.trace);

  if (trace.lexical_fallback_used === true) return "yes";
  if (trace.lexical_fallback_used === false) return "no";
  if (retrieval.empty === true && body.answer_mode === "insufficient") return "yes";

  return "—";
}

function determineMemoryState(body, sources) {
  const retrieval = asObject(body.retrieval);
  const grounding = asObject(body.grounding);

  if (body.answer_mode === "conflict" || body.conflict_flag === true) return "conflict";
  if (grounding.status === "grounded") return "hit";
  if (grounding.status === "weak") return sources.length > 0 ? "weak hit" : "weak";
  if (grounding.status === "none") return "miss";
  if (sources.length > 0) return "hit";
  if (retrieval.empty === true) return "miss";

  return "—";
}

function deriveGroundingStatus(body, grounding, error) {
  if (grounding.status) return grounding.status;
  if (body.answer_mode === "insufficient") return "none";
  if (error.code) return "error";
  return "idle";
}

function determineConfidence(status, error, isBusy) {
  if (isBusy) {
    return {
      label: "Checking evidence",
      className: "is-busy",
    };
  }

  if (status === "grounded") {
    return {
      label: "High confidence",
      className: "is-grounded",
    };
  }

  if (status === "weak") {
    return {
      label: "Limited confidence",
      className: "is-weak",
    };
  }

  if (status === "none") {
    return {
      label: "No evidence",
      className: "is-none",
    };
  }

  if (error.code) {
    return {
      label: "Unavailable",
      className: "is-error",
    };
  }

  return {
    label: "Awaiting query",
    className: "is-idle",
  };
}

function buildExplanationSummary(status, sourceCount, isBusy, error) {
  if (isBusy) {
    return "Searching stored memory for supporting evidence.";
  }

  if (status === "grounded") {
    return `This answer is based on ${formatSourceCount(sourceCount, "relevant project memory source")}.`;
  }

  if (status === "weak") {
    if (sourceCount > 0) {
      return `This answer is based on limited evidence from ${formatSourceCount(sourceCount, "project memory source")}. Some details may be incomplete.`;
    }

    return "This answer is based on limited evidence from project memory. Some details may be incomplete.";
  }

  if (status === "none") {
    return "No supporting project memory was retrieved for this answer.";
  }

  if (error.code) {
    return "The request did not complete, so the evidence summary is unavailable.";
  }

  return "Run a query to see how CrispyBrain grounded the answer.";
}

function buildExplanationDetail(body, status, sourceCount, candidateCount, isBusy, error) {
  if (isBusy) {
    return "This layer explains what sources were used, how strong the evidence is, and where uncertainty remains.";
  }

  if (error.code) {
    return cleanText(error.message) || "The explanation layer could not inspect supporting evidence because the request failed.";
  }

  if (body.answer_mode === "conflict" || body.conflict_flag === true) {
    return "The visible sources disagree, so CrispyBrain surfaced that conflict instead of guessing at a single answer.";
  }

  if (status === "grounded") {
    if (candidateCount > sourceCount && sourceCount > 0) {
      return `CrispyBrain selected ${formatSourceCount(sourceCount, "source")} from ${formatSourceCount(candidateCount, "retrieved candidate")} and answered from the strongest matching project memory.`;
    }

    return "CrispyBrain answered directly from the strongest matching project memory it retrieved.";
  }

  if (status === "weak") {
    if (candidateCount > 0 && sourceCount > 0) {
      return `CrispyBrain found related project memory and selected ${formatSourceCount(sourceCount, "source")}, but the support still looks partial, borderline, or correlated.`;
    }

    return "CrispyBrain found some related memory, but the visible support is still limited.";
  }

  if (status === "none") {
    return "CrispyBrain fell back because it could not find visible project memory strong enough to support a grounded answer.";
  }

  return "This layer explains what sources were used, how strong the evidence is, and where uncertainty remains.";
}

function buildUncertaintyText(status, grounding, presentation = {}) {
  const noteParts = [];
  const caveatText = cleanText(presentation.caveatText);
  const note = cleanText(grounding.note);

  if (status === "weak") {
    noteParts.push("Some aspects of this answer are uncertain or not fully documented.");
  }

  if (caveatText) {
    noteParts.push(caveatText);
  }

  if (note) {
    noteParts.push(note);
  }

  return uniqueTexts(noteParts).join(" ");
}

function formatSourceCount(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function determineElapsedMs(trace, debug, meta) {
  const directValue = firstNumber(
    debug.proxy_duration_ms,
    trace.proxy_duration_ms,
    meta.elapsedMs,
  );

  if (typeof directValue === "number") {
    return directValue;
  }

  const stageHistory = Array.isArray(trace.stage_history) ? trace.stage_history : [];
  if (stageHistory.length >= 2) {
    const startedAt = Date.parse(stageHistory[0].timestamp || "");
    const lastStage = stageHistory[stageHistory.length - 1] || {};
    const endedAt = Date.parse(lastStage.timestamp || "");

    if (Number.isFinite(startedAt) && Number.isFinite(endedAt) && endedAt >= startedAt) {
      return endedAt - startedAt;
    }
  }

  return null;
}

function extractUsage(body, trace, debug) {
  return {
    inputTokens: firstNumber(
      body.usage?.input_tokens,
      body.usage?.prompt_tokens,
      body.usage?.inputTokens,
      trace.input_tokens,
      trace.prompt_tokens,
      debug.input_tokens,
      debug.prompt_tokens,
    ),
    outputTokens: firstNumber(
      body.usage?.output_tokens,
      body.usage?.completion_tokens,
      body.usage?.outputTokens,
      trace.output_tokens,
      trace.completion_tokens,
      debug.output_tokens,
      debug.completion_tokens,
    ),
  };
}

function strongestSourceScore(sources) {
  let topScore = null;

  for (const source of sources) {
    if (typeof source.score === "number" && (topScore === null || source.score > topScore)) {
      topScore = source.score;
    }
  }

  return topScore;
}

function asObject(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function cleanText(value) {
  return typeof value === "string" && value.trim() !== "" ? value.trim() : "";
}

function uniqueTexts(values) {
  const result = [];
  const seen = new Set();

  for (const value of values) {
    const cleaned = cleanText(value);
    if (!cleaned) continue;

    const key = cleaned.toLowerCase();
    if (seen.has(key)) continue;

    seen.add(key);
    result.push(cleaned);
  }

  return result;
}

function firstNumber(...values) {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }

    if (typeof value === "string" && value.trim() !== "") {
      const parsed = Number(value);
      if (Number.isFinite(parsed)) {
        return parsed;
      }
    }
  }

  return null;
}

function presentValue(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim() !== "") {
      return value.trim();
    }

    if (typeof value === "number" && Number.isFinite(value)) {
      return String(value);
    }
  }

  return "";
}

function extractFilenameFromLabel(label) {
  if (!label) return "";

  return label.split("::")[0]?.trim() || label;
}

function buildChunkLabel(record, label) {
  const chunkIndex = firstNumber(record.chunk_index, record.chunkIndex);
  const totalChunks = firstNumber(record.total_chunks, record.totalChunks);

  if (typeof chunkIndex === "number") {
    const chunkText = `chunk ${String(Math.round(chunkIndex)).padStart(2, "0")}`;
    if (typeof totalChunks === "number" && totalChunks > 1) {
      return `${chunkText} of ${String(Math.round(totalChunks)).padStart(2, "0")}`;
    }

    return chunkText;
  }

  const chunkMatch = label.match(/chunk\s+\d+/i);
  return chunkMatch ? chunkMatch[0].toLowerCase() : "";
}

function buildSnippetPreview(text) {
  if (!text) return "";

  const collapsed = text.replace(/\s+/g, " ").trim();
  if (collapsed.length <= 120) return collapsed;
  return `${collapsed.slice(0, 117).trimEnd()}...`;
}

function formatMilliseconds(value) {
  return typeof value === "number" ? `${Math.round(value)} ms` : "—";
}

function formatTokenCount(value) {
  return typeof value === "number" ? String(Math.round(value)) : "—";
}

function formatScore(value) {
  return typeof value === "number" ? value.toFixed(3) : "—";
}

function formatPlain(value) {
  if (value === undefined || value === null || value === "") return "—";
  return String(value);
}
