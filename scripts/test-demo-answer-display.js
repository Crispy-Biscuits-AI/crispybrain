#!/usr/bin/env node

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "..");
const appPath = path.join(repoRoot, "demo", "app.js");
const indexPath = path.join(repoRoot, "demo", "index.html");
const appSource = fs.readFileSync(appPath, "utf8");
const indexSource = fs.readFileSync(indexPath, "utf8");

function extractFunction(name) {
  const start = appSource.indexOf(`function ${name}`);
  assert.notEqual(start, -1, `Missing function ${name}`);

  let index = appSource.indexOf("{", appSource.indexOf(")", start));
  let depth = 0;
  for (; index < appSource.length; index += 1) {
    const char = appSource[index];
    if (char === "{") depth += 1;
    if (char === "}") depth -= 1;
    if (depth === 0) return appSource.slice(start, index + 1);
  }

  throw new Error(`Could not extract function ${name}`);
}

const functionNames = [
  "normalizeProjectOptions",
  "renderProjectOptions",
  "getProjectDisplayName",
  "getSelectedProjectDisplayName",
  "updateProjectContext",
  "deriveAnswerPresentation",
  "splitCaveatSentences",
  "splitSentences",
  "normalizeDirectAnswerText",
  "buildUnsupportedDetailAnswer",
  "describeUnsupportedQuestionClaim",
  "canonicalizeAnswerTerms",
  "collectCanonicalSourceTexts",
  "extractCanonicalTerms",
  "replaceCanonicalTerm",
  "splitAnswerParagraphs",
  "splitDirectAnswerParagraph",
  "looksLikeAnswerCaveat",
  "normalizeCaveatLead",
  "buildUncertaintyText",
  "cleanText",
  "uniqueTexts",
  "asObject",
];

const sandbox = {};
vm.createContext(sandbox);
vm.runInContext(
  `${functionNames.map(extractFunction).join("\n\n")}
  this.normalizeProjectOptions = normalizeProjectOptions;
  this.renderProjectOptions = renderProjectOptions;
  this.getProjectDisplayName = getProjectDisplayName;
  this.deriveAnswerPresentation = deriveAnswerPresentation;
  this.buildUncertaintyText = buildUncertaintyText;`,
  sandbox,
  { filename: appPath },
);

function makeSelect() {
  const select = {
    children: [],
    value: "",
    appendChild(option) {
      this.children.push(option);
      if (option.selected) this.value = option.value;
    },
  };

  Object.defineProperty(select, "innerHTML", {
    get() {
      return "";
    },
    set() {
      this.children = [];
      this.value = "";
    },
  });

  return select;
}

sandbox.document = {
  createElement(tagName) {
    assert.equal(tagName, "option");
    return {
      value: "",
      textContent: "",
      selected: false,
    };
  },
};
sandbox.projectSlugSelect = makeSelect();
sandbox.deleteProjectSelect = makeSelect();
sandbox.availableProjects = [];
sandbox.availableProjectOptions = [];
sandbox.projectListUnavailable = false;
sandbox.projectsLoading = false;
sandbox.answerState = { textContent: "Ready for a query" };
sandbox.projectCount = { textContent: "" };
sandbox.activeProjectPill = { textContent: "" };
sandbox.queryContextBadge = { textContent: "" };
sandbox.queryContextNote = { textContent: "" };
sandbox.resetPanels = () => {};
sandbox.renderNoProjectsState = () => {};
sandbox.updateProjectContext = sandbox.updateProjectContext;

const selectorOptions = sandbox.normalizeProjectOptions({
  projects: ["star-wars-2", "alpha"],
  project_options: [
    { project_slug: "star-wars-2", display_name: "Star Wars" },
    { project_slug: "alpha", display_name: "alpha" },
  ],
});
sandbox.renderProjectOptions(selectorOptions, "alpha", "star-wars-2");
assert.equal(sandbox.projectSlugSelect.value, "star-wars-2");
assert.equal(sandbox.projectSlugSelect.children[0].value, "star-wars-2");
assert.equal(sandbox.projectSlugSelect.children[0].textContent, "Star Wars");
assert.equal(sandbox.deleteProjectSelect.children[0].textContent, "Star Wars");
assert.equal(sandbox.getProjectDisplayName("star-wars-2"), "Star Wars");
assert.equal(sandbox.activeProjectPill.textContent, "Star Wars");

const starWarsSources = [
  {
    title: "star-wars-notes.md",
    filename: "star-wars-notes.md",
    snippet: "Anakin Skywalker became Darth Vader.",
    preview: "Anakin Skywalker became Darth Vader.",
  },
];

const directPresentation = sandbox.deriveAnswerPresentation(
  {
    answer_mode: "direct",
    query: "Who is Darth Vader?",
    answer: "Available project memory is limited, but it supports these points: darth vader is anakin skywalker, a central character in Star Wars.",
  },
  starWarsSources,
);

assert.match(directPresentation.answerText, /\bDarth Vader\b/);
assert.match(directPresentation.answerText, /\bAnakin Skywalker\b/);
assert.doesNotMatch(directPresentation.answerText, /\bdarth vader\b/);
assert.doesNotMatch(directPresentation.answerText, /\banakin skywalker\b/);

const unsupportedPresentation = sandbox.deriveAnswerPresentation(
  {
    answer_mode: "direct",
    query: "Is Darth Vader’s cape pink?",
    answer: [
      "Project memory provides only partial information here, mainly about question answer seed facts, darth vader and anakin skywalker, and relationships and themes.",
      "Early development is only partially documented in the retrieved notes.",
      "from project memory.",
    ].join("\n\n"),
  },
  starWarsSources,
);

assert.equal(
  unsupportedPresentation.answerText,
  "Project memory does not mention Darth Vader's cape being pink.",
);
assert.doesNotMatch(unsupportedPresentation.answerText, /provides only partial information/i);
assert.doesNotMatch(unsupportedPresentation.answerText, /retrieved memory context/i);
assert.doesNotMatch(unsupportedPresentation.answerText, /available project memory is limited/i);

const uncertaintyText = sandbox.buildUncertaintyText(
  "weak",
  { note: "Retrieved memory was partial, so details outside the source are treated as unverified." },
  unsupportedPresentation,
);
assert.match(uncertaintyText, /partial information/i);
assert.match(uncertaintyText, /Retrieved memory was partial/i);

for (const requiredId of [
  "project-slug",
  "create-project-button",
  "delete-project-button",
  "trace-drawer",
  "sources-output",
  "footer-version",
]) {
  assert.match(indexSource, new RegExp(`id="${requiredId}"|class="${requiredId}"`), `Missing UI hook ${requiredId}`);
}

for (const requiredFunction of [
  "renderProjectOptions",
  "createProject",
  "renderTrace",
  "renderSources",
  "generateMarkdownExport",
]) {
  assert.match(appSource, new RegExp(`function ${requiredFunction}\\b`), `Missing function ${requiredFunction}`);
}

console.log("PASS: demo answer display keeps direct answers clean and preserves proper-name capitalization");
