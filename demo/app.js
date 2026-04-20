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
const sourcesOutput = document.getElementById("sources-output");

const traceFields = {
  elapsed: document.getElementById("trace-elapsed"),
  inputTokens: document.getElementById("trace-input-tokens"),
  outputTokens: document.getElementById("trace-output-tokens"),
  sourceCount: document.getElementById("trace-source-count"),
  topScore: document.getElementById("trace-top-score"),
  grounding: document.getElementById("trace-grounding"),
  mode: document.getElementById("trace-mode"),
  answerMode: document.getElementById("trace-answer-mode"),
  stage: document.getElementById("trace-stage"),
};

let sourcesOpen = false;
let traceOpen = false;

themeManager.mountThemeControls(themeSelect, themeBadge);
setSourcesOpen(false);
setTraceOpen(false);
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
  renderSources([]);
  renderTrace({}, { elapsedMs: null });

  if (!statusPill.classList.contains("busy")) {
    answerState.textContent = "Ready for a query";
    answerOutput.textContent = "Query memory to see an answer here.";
  }
}

function renderSuccess(body, meta = {}) {
  const sources = normalizeSources(body.sources);
  answerOutput.textContent = body.answer || "No answer text returned.";
  answerState.textContent = buildAnswerState(body, sources);

  updateSourceLabels(sources.length);
  renderSources(sources);
  renderTrace(body, meta);
}

function renderError(error, body = {}, meta = {}) {
  const sources = normalizeSources(body.sources);
  answerState.textContent = "Request could not be completed";
  answerOutput.textContent = body.answer || error.message || "The memory query failed.";

  updateSourceLabels(sources.length);
  renderSources(sources);
  renderTrace({ ...body, error }, meta);
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

    const meta = document.createElement("p");
    meta.className = "source-meta";
    const parts = [];

    if (typeof source.score === "number") {
      parts.push(`score ${source.score.toFixed(3)}`);
    }

    if (source.identifier) {
      parts.push(source.identifier);
    }

    meta.textContent = parts.join(" · ") || "Supporting memory";
    card.appendChild(meta);

    sourcesOutput.appendChild(card);
  }
}

function renderTrace(body, meta = {}) {
  const sources = normalizeSources(body.sources);
  const retrieval = asObject(body.retrieval);
  const grounding = asObject(body.grounding);
  const trace = asObject(body.trace);
  const debug = asObject(body.debug);
  const error = asObject(body.error);

  setTraceField("elapsed", formatMilliseconds(firstNumber(
    debug.proxy_duration_ms,
    trace.proxy_duration_ms,
    meta.elapsedMs,
  )));
  setTraceField("inputTokens", formatTokenCount(firstNumber(
    body.usage?.input_tokens,
    body.usage?.prompt_tokens,
    trace.input_tokens,
    debug.input_tokens,
  )));
  setTraceField("outputTokens", formatTokenCount(firstNumber(
    body.usage?.output_tokens,
    body.usage?.completion_tokens,
    trace.output_tokens,
    debug.output_tokens,
  )));
  setTraceField("sourceCount", formatPlain(firstNumber(
    retrieval.memory_count,
    grounding.supporting_source_count,
    sources.length,
  )));
  setTraceField("topScore", formatScore(firstNumber(
    retrieval.strongest_similarity,
    sources[0]?.score,
  )));
  setTraceField("grounding", formatPlain(
    grounding.status || error.code || "—"
  ));
  setTraceField("mode", determineRetrievalMode(body, sources));
  setTraceField("answerMode", formatPlain(body.answer_mode));
  setTraceField("stage", formatPlain(
    trace.stage || debug.trace_stage || debug.workflow || "—"
  ));
}

function setTraceField(key, value) {
  traceFields[key].textContent = value;
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
      title: cleanText(record.title) || cleanText(record.source) || "Untitled source",
      snippet: cleanText(record.snippet) || cleanText(record.content),
      score: firstNumber(record.similarity, record.score),
      identifier: presentValue(record.project_slug, record.id),
    };
  });
}

function determineRetrievalMode(body, sources) {
  const retrieval = asObject(body.retrieval);
  const trace = asObject(body.trace);
  const rankingMode = cleanText(trace.ranking_mode)?.toLowerCase();
  const strategy = cleanText(retrieval.strategy)?.toLowerCase();

  if (trace.lexical_fallback_used === true) return "keyword";
  if (rankingMode && /anchor|lexical|keyword/.test(rankingMode)) return "keyword";
  if ((retrieval.empty === true || sources.length === 0) && body.answer_mode === "insufficient") return "fallback";
  if (typeof retrieval.strongest_similarity === "number") return "semantic";
  if (rankingMode === "semantic") return "semantic";
  if (strategy && /semantic|project-first|scope|all-memories|general/.test(strategy)) return "semantic";

  return "—";
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
