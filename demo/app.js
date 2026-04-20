const themeManager = window.CrispyBrainTheme;

const form = document.getElementById("memory-form");
const projectSlugInput = document.getElementById("project-slug");
const sessionIdInput = document.getElementById("session-id");
const questionInput = document.getElementById("question");
const submitButton = document.getElementById("submit-button");
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
const answerOutput = document.getElementById("answer-output");
const sourceSummary = document.getElementById("source-summary");
const sourcesOutput = document.getElementById("sources-output");
const traceNote = document.getElementById("trace-note");

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

themeManager.mountThemeControls(themeSelect, themeBadge);
setSourcesOpen(true);
setTraceOpen(true);
resetPanels();

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

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const question = questionInput.value.trim();
  if (!question) {
    renderError({
      code: "INVALID_QUESTION",
      message: "Enter a query before running retrieval.",
    });
    return;
  }

  setBusy(true);
  resetPanels();

  const payload = {
    question,
    project_slug: projectSlugInput.value.trim(),
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
      }, body, { elapsedMs });
      return;
    }

    renderSuccess(body, { elapsedMs });
  } catch (error) {
    renderError({
      code: "NETWORK_ERROR",
      message: "The local memory proxy could not be reached.",
      details: error instanceof Error ? error.message : String(error),
    }, {}, {
      elapsedMs: Math.round(performance.now() - requestStarted),
    });
  } finally {
    setBusy(false);
  }
});

function setBusy(isBusy) {
  submitButton.disabled = isBusy;
  submitButton.textContent = isBusy ? "Running..." : "Run query";
  statusPill.textContent = isBusy ? "running" : "idle";
  statusPill.classList.toggle("busy", isBusy);

  if (isBusy) {
    answerState.textContent = "Retrieving memory…";
    answerOutput.textContent = "Searching stored memory and assembling a response…";
  }
}

function resetPanels() {
  updateSourceLabels(0);
  renderSourceSummary({}, [], []);
  renderSources([]);
  renderTrace({}, { elapsedMs: null }, [], []);

  if (!statusPill.classList.contains("busy")) {
    answerState.textContent = "Ready for a query";
    answerOutput.textContent = "Query memory to see an answer here.";
  }
}

function renderSuccess(body, meta = {}) {
  const selectedSources = normalizeSources(body.selected_sources || body.sources);
  const retrievedCandidates = normalizeSources(body.retrieved_candidates);
  answerOutput.textContent = body.answer || "No answer text returned.";
  answerState.textContent = buildAnswerState(body, selectedSources);

  updateSourceLabels(selectedSources.length);
  renderSourceSummary(body, selectedSources, retrievedCandidates);
  renderSources(selectedSources);
  renderTrace(body, meta, selectedSources, retrievedCandidates);
}

function renderError(error, body = {}, meta = {}) {
  const selectedSources = normalizeSources(body.selected_sources || body.sources);
  const retrievedCandidates = normalizeSources(body.retrieved_candidates);
  answerState.textContent = "Request could not be completed";
  answerOutput.textContent = body.answer || error.message || "The memory query failed.";

  updateSourceLabels(selectedSources.length);
  renderSourceSummary({ ...body, error }, selectedSources, retrievedCandidates);
  renderSources(selectedSources);
  renderTrace({ ...body, error }, meta, selectedSources, retrievedCandidates);
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

    const title = document.createElement("h3");
    title.textContent = source.title || "Untitled source";
    card.appendChild(title);

    const snippet = document.createElement("p");
    snippet.textContent = source.snippet || "No preview available.";
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

    if (typeof source.score === "number") {
      parts.push(`score ${source.score.toFixed(3)}`);
    }

    if (source.reviewStatus) parts.push(source.reviewStatus);
    if (source.sourceQuality) parts.push(`quality ${source.sourceQuality}`);
    if (source.sourceIndependence) parts.push(source.sourceIndependence);
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

  if (typeof grounding.note === "string" && grounding.note.trim() !== "") {
    return grounding.note.trim();
  }

  if (sources.length > 0) {
    return "Source-backed response";
  }

  if (body.answer_mode === "insufficient") {
    return "No strong supporting memory was retrieved";
  }

  return "Response ready";
}

function normalizeSources(value) {
  if (!Array.isArray(value)) return [];

  return value.map((source) => {
    const record = asObject(source);
    return {
      title: cleanText(record.title) || cleanText(record.source_label) || cleanText(record.source) || "Untitled source",
      snippet: cleanText(record.snippet) || cleanText(record.content),
      score: firstNumber(record.similarity, record.score, record.retrieval_score),
      identifier: presentValue(
        cleanText(record.filename),
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
