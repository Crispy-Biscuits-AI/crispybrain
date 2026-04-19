const themeManager = window.CrispyBrainTheme;

const form = document.getElementById("demo-form");
const projectSlugInput = document.getElementById("project-slug");
const sessionIdInput = document.getElementById("session-id");
const questionInput = document.getElementById("question");
const submitButton = document.getElementById("submit-button");
const statusPill = document.getElementById("status-pill");
const themeSelect = document.getElementById("theme-select");
const themeBadge = document.getElementById("theme-badge");
const answerState = document.getElementById("answer-state");
const answerOutput = document.getElementById("answer-output");
const sourcesCount = document.getElementById("sources-count");
const sourcesOutput = document.getElementById("sources-output");
const debugOutput = document.getElementById("debug-output");

themeManager.mountThemeControls(themeSelect, themeBadge);

document.querySelectorAll(".sample-question").forEach((button) => {
  button.addEventListener("click", () => {
    questionInput.value = button.dataset.question || "";
    questionInput.focus();
  });
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const question = questionInput.value.trim();
  if (!question) {
    renderError({
      code: "INVALID_QUESTION",
      message: "Please enter a question before submitting the demo."
    });
    return;
  }

  setBusy(true);
  clearPanels();

  const payload = {
    question,
    project_slug: projectSlugInput.value.trim(),
    session_id: sessionIdInput.value.trim()
  };

  try {
    const response = await fetch("/api/demo/ask", {
      method: "POST",
      headers: {
        "Content-Type": "application/json"
      },
      body: JSON.stringify(payload)
    });

    const body = await response.json();

    if (!response.ok || body.ok !== true) {
      renderError(body.error || {
        code: "DEMO_REQUEST_FAILED",
        message: "CrispyBrain did not return a successful demo response."
      }, body);
      return;
    }

    renderSuccess(body);
  } catch (error) {
    renderError({
      code: "NETWORK_ERROR",
      message: "The local demo proxy could not be reached.",
      details: error instanceof Error ? error.message : String(error)
    });
  } finally {
    setBusy(false);
  }
});

function setBusy(isBusy) {
  submitButton.disabled = isBusy;
  statusPill.textContent = isBusy ? "Asking CrispyBrain..." : "Idle";
  statusPill.classList.toggle("busy", isBusy);
  statusPill.classList.remove("error");
  answerState.textContent = isBusy ? "Waiting for the demo response" : "Waiting for a question";
}

function clearPanels() {
  answerOutput.textContent = "Waiting for CrispyBrain...";
  sourcesCount.textContent = "0";
  sourcesOutput.innerHTML = '<p class="empty-state">Retrieved sources will appear here.</p>';
  debugOutput.innerHTML = '<p class="empty-state">The request state, workflow info, and errors will appear here.</p>';
}

function renderSuccess(body) {
  statusPill.textContent = "Answer ready";
  answerState.textContent = `Project ${body.project_slug || "alpha"}`;
  answerOutput.textContent = body.answer || "No answer text returned.";

  const sources = Array.isArray(body.sources) ? body.sources : [];
  sourcesCount.textContent = String(sources.length);
  sourcesOutput.innerHTML = "";

  if (sources.length === 0) {
    sourcesOutput.innerHTML = '<p class="empty-state">No sources were returned for this answer.</p>';
  } else {
    for (const source of sources) {
      const card = document.createElement("article");
      card.className = "source-card";
      card.innerHTML = `
        <h4>${escapeHtml(source.title || "Untitled source")}</h4>
        <p>${escapeHtml(source.snippet || "No snippet available.")}</p>
        <p class="source-meta">similarity: ${formatMaybeNumber(source.similarity)} · project: ${escapeHtml(source.project_slug || "general")}</p>
      `;
      sourcesOutput.appendChild(card);
    }
  }

  renderDebug(body.debug || {}, {
    question: body.question,
    project_slug: body.project_slug
  });
}

function renderError(error, body = {}) {
  statusPill.textContent = "Needs attention";
  statusPill.classList.add("error");
  answerState.textContent = "The demo path returned an error";
  answerOutput.textContent = body.answer || error.message || "The demo request failed.";

  const sources = Array.isArray(body.sources) ? body.sources : [];
  sourcesCount.textContent = String(sources.length);
  if (sources.length === 0) {
    sourcesOutput.innerHTML = '<p class="empty-state">No usable sources were returned for this request.</p>';
  }

  renderDebug(body.debug || {}, {
    error_code: error.code || "UNKNOWN_ERROR",
    error_message: error.message || "Unexpected demo error.",
    details: error.details || null,
    question: body.question || questionInput.value.trim() || null,
    project_slug: body.project_slug || projectSlugInput.value.trim() || "alpha"
  }, true);
}

function renderDebug(debug, extras = {}, isError = false) {
  const merged = { ...debug, ...extras };
  const entries = [
    ["workflow", merged.workflow || "crispybrain-demo"],
    ["upstream workflow", merged.upstream_workflow || "assistant"],
    ["teacher used", booleanLabel(merged.teacher_used)],
    ["retrieval count", valueOrDash(merged.retrieval_count)],
    ["project slug", merged.project_slug || projectSlugInput.value.trim() || "alpha"],
    ["session ID", merged.session_id || valueOrDash(sessionIdInput.value.trim())],
    ["trace stage", valueOrDash(merged.trace_stage)],
    ["proxy duration", merged.proxy_duration_ms ? `${merged.proxy_duration_ms} ms` : "—"],
    ["upstream status", valueOrDash(merged.upstream_status)],
    ["defaulted slug", booleanLabel(merged.defaulted_project_slug)]
  ];

  const wrapper = document.createElement("div");
  wrapper.className = `debug-card${isError ? " error-banner" : ""}`;

  const grid = document.createElement("div");
  grid.className = "debug-grid";

  for (const [label, value] of entries) {
    const cell = document.createElement("div");
    cell.innerHTML = `
      <div class="debug-key">${escapeHtml(label)}</div>
      <div class="debug-value">${escapeHtml(String(value))}</div>
    `;
    grid.appendChild(cell);
  }

  wrapper.appendChild(grid);

  if (merged.error_code || merged.error_message || merged.details) {
    const details = document.createElement("p");
    details.style.marginTop = "14px";
    details.textContent = [merged.error_code, merged.error_message, merged.details]
      .filter(Boolean)
      .join(" · ");
    wrapper.appendChild(details);
  }

  debugOutput.innerHTML = "";
  debugOutput.appendChild(wrapper);
}

function booleanLabel(value) {
  if (value === true) return "yes";
  if (value === false) return "no";
  return "—";
}

function valueOrDash(value) {
  if (value === undefined || value === null || value === "") return "—";
  return value;
}

function formatMaybeNumber(value) {
  return typeof value === "number" ? value.toFixed(3) : "—";
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}
