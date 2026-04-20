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
}

function renderSuccess(body, meta = {}) {
  const selectedSources = normalizeSources(body.selected_sources || body.sources);
  const retrievedCandidates = normalizeSources(body.retrieved_candidates);
  answerOutput.textContent = body.answer || "No answer text returned.";
  answerState.textContent = buildAnswerState(body, selectedSources);

  updateSourceLabels(selectedSources.length);
  renderExplanation(body, selectedSources, retrievedCandidates);
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
  renderExplanation({ ...body, error }, selectedSources, retrievedCandidates);
  renderSourceSummary({ ...body, error }, selectedSources, retrievedCandidates);
  renderSources(selectedSources);
  renderTrace({ ...body, error }, meta, selectedSources, retrievedCandidates);
}

function renderExplanation(body, selectedSources, retrievedCandidates, options = {}) {
  const grounding = asObject(body.grounding);
  const error = asObject(body.error);
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

  const uncertaintyText = buildUncertaintyText(status, grounding);
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

function buildUncertaintyText(status, grounding) {
  if (status !== "weak") return "";

  const note = cleanText(grounding.note);
  const prefix = "Some aspects of this answer are uncertain or not fully documented.";
  return note ? `${prefix} ${note}` : prefix;
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
