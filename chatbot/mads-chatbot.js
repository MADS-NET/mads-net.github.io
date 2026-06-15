const PAGEFIND_CANDIDATES = [
  "/pagefind/pagefind.js",
  new URL("pagefind/pagefind.js", window.location.href).href,
  new URL("../pagefind/pagefind.js", window.location.href).href,
];

const WEBLLM_IMPORT_URL = "https://esm.run/@mlc-ai/web-llm";
const MODEL_ID = "Qwen2.5-0.5B-Instruct-q4f16_1-MLC";
const MAX_RESULTS = 8;
const MAX_CONTEXT_DOCS = 6;
const MAX_DOC_CHARS = 1100;
const MAX_CONTEXT_CHARS = 8000;

const QUERY_EXPANSIONS = {
  arduino: "arduino serial analog source plugin ADC sensor",
  plugin: "plugin source sink filter C++ shared library agent",
  source: "source agent publisher data acquisition",
  analog: "analog ADC sensor Arduino serial",
};

const SPECIFIC_TERMS = new Set(["analog", "arduino"]);

const STOP_WORDS = new Set([
  "about",
  "after",
  "from",
  "how",
  "into",
  "mads",
  "read",
  "that",
  "the",
  "this",
  "use",
  "what",
  "when",
  "where",
  "which",
  "with",
]);

const state = {
  pagefind_promise: null,
  webllm_promise: null,
  engine_promise: null,
  local_model_accepted: false,
  is_busy: false,
};

function byId(id) {
  return document.getElementById(id);
}

function normalizeSpace(text) {
  return String(text || "").replace(/\s+/g, " ").trim();
}

function stripHtml(html) {
  const element = document.createElement("div");
  element.innerHTML = String(html || "");
  return normalizeSpace(element.textContent || "");
}

function clipText(text, max_chars) {
  const clean = normalizeSpace(text);
  if (clean.length <= max_chars) {
    return clean;
  }
  return `${clean.slice(0, Math.max(0, max_chars - 3)).trimEnd()}...`;
}

function normalizeUrl(url) {
  if (!url) {
    return "#";
  }
  if (/^https?:\/\//i.test(url)) {
    return url;
  }
  if (url.startsWith("/")) {
    return url;
  }
  return `/${url.replace(/^\.\//, "")}`;
}

function setStatus(text) {
  const status = byId("mads-chatbot-status");
  if (status) {
    status.textContent = text;
  }
}

function setBusy(is_busy) {
  state.is_busy = is_busy;
  const submit = byId("mads-chatbot-submit");
  const input = byId("mads-chatbot-input");
  if (submit) {
    submit.disabled = is_busy;
  }
  if (input) {
    input.disabled = is_busy;
  }
}

function scrollMessagesToBottom() {
  const messages = byId("mads-chatbot-messages");
  if (messages) {
    messages.scrollTop = messages.scrollHeight;
  }
}

function createElement(tag, class_name, text) {
  const element = document.createElement(tag);
  if (class_name) {
    element.className = class_name;
  }
  if (text !== undefined) {
    element.textContent = text;
  }
  return element;
}

function appendSources(container, docs, limit = MAX_CONTEXT_DOCS) {
  const list = createElement("ol", "mads-chatbot-source-list");
  docs.slice(0, limit).forEach((doc) => {
    const item = createElement("li", "mads-chatbot-source");
    const link = createElement("a", null, doc.title || doc.url);
    link.href = normalizeUrl(doc.url);
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    item.append(link);

    const excerpt = doc.excerpt || doc.content;
    if (excerpt) {
      item.append(createElement("p", null, clipText(excerpt, 260)));
    }
    list.append(item);
  });
  container.append(list);
}

function addMessage(role, text) {
  const messages = byId("mads-chatbot-messages");
  if (!messages) {
    return null;
  }

  const message = createElement(
    "div",
    `mads-chatbot-message mads-chatbot-message-${role}`,
  );
  const label = createElement(
    "span",
    "mads-chatbot-message-label",
    role === "user" ? "You" : "Assistant",
  );
  const bubble = createElement("div", "mads-chatbot-bubble");

  if (text) {
    bubble.append(createElement("div", "mads-chatbot-answer", text));
  }

  message.append(label, bubble);
  messages.append(message);
  scrollMessagesToBottom();
  return bubble;
}

function renderRetrievalMessage(docs, note) {
  const bubble = addMessage("assistant", note || "Relevant documentation:");
  if (!bubble) {
    return;
  }
  if (docs.length === 0) {
    bubble.append(
      createElement(
        "p",
        "mads-chatbot-note",
        "No matching documentation pages were found in the local search index.",
      ),
    );
    return;
  }
  appendSources(bubble, docs, MAX_RESULTS);
  scrollMessagesToBottom();
}

function renderGenerationOffer(question, docs) {
  const bubble = addMessage(
    "assistant",
    "I found relevant documentation. I can also synthesize an answer locally in your browser.",
  );
  if (!bubble) {
    return;
  }

  bubble.append(
    createElement(
      "p",
      "mads-chatbot-note",
      "First use may download a large model file. If loading fails, the retrieved documentation remains available.",
    ),
  );

  const button = createElement(
    "button",
    "mads-chatbot-local-button",
    "Generate local answer",
  );
  button.type = "button";
  button.addEventListener("click", async () => {
    state.local_model_accepted = true;
    button.disabled = true;
    await generateLocalAnswer(question, docs);
  });
  bubble.append(button);
  scrollMessagesToBottom();
}

function queryVariants(query) {
  const lower = query.toLowerCase();
  const words = lower.match(/[a-z0-9+.#_-]+/g) || [];
  const keywords = words.filter((word) => {
    return word.length > 2 && !STOP_WORDS.has(word);
  });
  const domain_terms = keywords.filter((word) => {
    return Object.prototype.hasOwnProperty.call(QUERY_EXPANSIONS, word);
  });
  const specific_terms = domain_terms.filter((word) => SPECIFIC_TERMS.has(word));
  const expansions = Object.entries(QUERY_EXPANSIONS)
    .filter(([term]) => lower.includes(term))
    .map(([, expansion]) => expansion);

  return [
    ...specific_terms,
    query,
    keywords.join(" "),
    ...expansions,
    ...domain_terms,
  ].filter((variant, index, variants) => {
    return variant && variants.indexOf(variant) === index;
  });
}

async function loadPagefind() {
  if (state.pagefind_promise) {
    return state.pagefind_promise;
  }

  state.pagefind_promise = (async () => {
    let last_error = null;
    for (const source of [...new Set(PAGEFIND_CANDIDATES)]) {
      try {
        const pagefind = await import(source);
        await pagefind.options({ excerptLength: 120 });
        return pagefind;
      } catch (error) {
        last_error = error;
      }
    }
    throw last_error || new Error("Pagefind could not be loaded.");
  })();

  return state.pagefind_promise;
}

async function retrieveDocs(pagefind, query, limit = MAX_RESULTS) {
  let raw_results = [];
  for (const variant of queryVariants(query)) {
    const search = await pagefind.search(variant);
    if (search.results.length === 0) {
      continue;
    }
    raw_results = await Promise.all(
      search.results.slice(0, limit).map((result) => result.data()),
    );
    break;
  }

  return raw_results.map((result) => {
    const excerpt = stripHtml(result.excerpt || "");
    const content = stripHtml(result.content || excerpt);
    return {
      title: normalizeSpace(result.meta?.title || result.url || "Untitled"),
      url: normalizeUrl(result.url),
      excerpt,
      content: content || excerpt,
    };
  });
}

function canUseLocalLLM() {
  return typeof navigator !== "undefined" && "gpu" in navigator;
}

async function loadWebLLM() {
  if (state.webllm_promise) {
    return state.webllm_promise;
  }
  state.webllm_promise = import(WEBLLM_IMPORT_URL);
  return state.webllm_promise;
}

async function getEngine(onProgress) {
  if (state.engine_promise) {
    return state.engine_promise;
  }

  state.engine_promise = (async () => {
    const { CreateMLCEngine } = await loadWebLLM();
    return CreateMLCEngine(MODEL_ID, {
      initProgressCallback: (progress) => {
        const percent =
          typeof progress.progress === "number"
            ? ` ${Math.round(progress.progress * 100)}%`
            : "";
        onProgress?.(progress.text || `Loading local model${percent}`);
      },
    });
  })();

  return state.engine_promise;
}

function buildContext(docs) {
  let total_chars = 0;
  const sections = [];

  docs.slice(0, MAX_CONTEXT_DOCS).forEach((doc, index) => {
    if (total_chars >= MAX_CONTEXT_CHARS) {
      return;
    }

    const remaining = MAX_CONTEXT_CHARS - total_chars;
    const body = clipText(doc.content || doc.excerpt, Math.min(MAX_DOC_CHARS, remaining));
    const section = [
      `SOURCE ${index + 1}`,
      `Title: ${doc.title}`,
      `URL: ${doc.url}`,
      "Excerpt:",
      body,
    ].join("\n");

    sections.push(section);
    total_chars += section.length;
  });

  return sections.join("\n\n");
}

function buildPrompt(question, docs) {
  return [
    "You are the MADS documentation assistant.",
    "Answer the user's question using only the documentation excerpts provided below.",
    "Do not invent APIs, file names, build flags, or code details that are not supported by the excerpts.",
    "If the excerpts are insufficient, say what is missing and list the most relevant source pages.",
    "For procedural questions, give a concise sequence of steps.",
    "When useful, include small code snippets, but only if they are directly supported by the excerpts.",
    'End with a "Sources" section containing the source titles and URLs used.',
    "",
    "Question:",
    question,
    "",
    "Documentation excerpts:",
    buildContext(docs),
  ].join("\n");
}

async function generateAnswer(prompt, onProgress) {
  const engine = await getEngine(onProgress);
  const response = await engine.chat.completions.create({
    messages: [
      {
        role: "system",
        content:
          "You answer MADS documentation questions using provided sources only.",
      },
      { role: "user", content: prompt },
    ],
    temperature: 0.1,
    max_tokens: 700,
  });

  return String(response.choices?.[0]?.message?.content || "").trim();
}

async function generateLocalAnswer(question, docs) {
  const bubble = addMessage("assistant", "Preparing local model...");
  if (!bubble) {
    return;
  }

  try {
    setBusy(true);
    setStatus(
      "This assistant can run a small language model locally in your browser. The first use may download a large model file.",
    );
    const prompt = buildPrompt(question, docs);
    const answer = await generateAnswer(prompt, (progress_text) => {
      setStatus(progress_text || "Loading local model...");
    });

    bubble.textContent = "";
    bubble.append(
      createElement(
        "div",
        "mads-chatbot-answer",
        answer || "The local model did not return an answer.",
      ),
    );
    appendSources(bubble, docs, MAX_CONTEXT_DOCS);
    setStatus("Answer generated locally from retrieved documentation.");
  } catch (error) {
    state.engine_promise = null;
    bubble.textContent = "";
    bubble.append(
      createElement(
        "div",
        "mads-chatbot-answer",
        "I could not run the local browser model in this browser. Here are the most relevant documentation pages:",
      ),
    );
    appendSources(bubble, docs, MAX_RESULTS);
    setStatus(`Local model unavailable: ${error.message || "unknown error"}`);
  } finally {
    setBusy(false);
    scrollMessagesToBottom();
  }
}

async function handleQuestion(question) {
  addMessage("user", question);
  setBusy(true);
  setStatus("Searching the documentation index...");

  try {
    const pagefind = await loadPagefind();
    const docs = await retrieveDocs(pagefind, question);

    if (docs.length === 0) {
      renderRetrievalMessage(docs);
      setStatus("No matching documentation pages found.");
      return;
    }

    if (!canUseLocalLLM()) {
      renderRetrievalMessage(
        docs,
        "I could not run a local browser model in this browser. Here are the most relevant documentation pages:",
      );
      setStatus("Showing search results because WebGPU is unavailable.");
      return;
    }

    renderRetrievalMessage(docs, "Retrieved documentation sources:");
    if (state.local_model_accepted) {
      await generateLocalAnswer(question, docs);
    } else {
      renderGenerationOffer(question, docs);
      setStatus("Search results are ready. Local generation is optional.");
    }
  } catch (error) {
    addMessage(
      "assistant",
      "I could not load the documentation search index. Build the site with Pagefind, then try again.",
    );
    setStatus(`Search unavailable: ${error.message || "unknown error"}`);
  } finally {
    setBusy(false);
  }
}

function setupChatbot() {
  const root = byId("mads-chatbot");
  const toggle = byId("mads-chatbot-toggle");
  const panel = byId("mads-chatbot-panel");
  const close = byId("mads-chatbot-close");
  const form = byId("mads-chatbot-form");
  const input = byId("mads-chatbot-input");

  if (!root || !toggle || !panel || !close || !form || !input) {
    return;
  }

  toggle.addEventListener("click", () => {
    panel.hidden = !panel.hidden;
    toggle.hidden = !panel.hidden;
    if (!panel.hidden) {
      input.focus();
    }
  });

  close.addEventListener("click", () => {
    panel.hidden = true;
    toggle.hidden = false;
    toggle.focus();
  });

  input.addEventListener("keydown", (event) => {
    if ((event.metaKey || event.ctrlKey) && event.key === "Enter") {
      form.requestSubmit();
    }
  });

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    if (state.is_busy) {
      return;
    }

    const question = input.value.trim();
    if (!question) {
      input.focus();
      return;
    }

    input.value = "";
    await handleQuestion(question);
    input.focus();
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", setupChatbot);
} else {
  setupChatbot();
}
