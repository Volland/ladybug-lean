// Small enhancements: theme toggle, copy buttons, and a tiny highlighter for
// Lean and Cypher snippets. The pages read fine without any of it.
(function () {
  const root = document.documentElement;
  try {
    const saved = localStorage.getItem("theme");
    if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  } catch (_) {}

  document.addEventListener("DOMContentLoaded", () => {
    const toggle = document.querySelector(".theme-toggle");
    if (toggle) {
      toggle.addEventListener("click", () => {
        const dark = root.dataset.theme
          ? root.dataset.theme === "dark"
          : window.matchMedia("(prefers-color-scheme: dark)").matches;
        root.dataset.theme = dark ? "light" : "dark";
        try { localStorage.setItem("theme", root.dataset.theme); } catch (_) {}
      });
    }

    const leanKw = /\b(def|structure|where|deriving|let|do|return|fun|match|with|if|then|else|for|in|open|namespace|end|import|example|theorem|instance|node_table|rel_table|query|stmt|cypher(?=%)|variable|private|partial|require|from|package|lean_lib|lean_exe)\b/g;
    const cypherKw = /\b(MATCH|OPTIONAL|WHERE|RETURN|WITH|ORDER|BY|DESC|ASC|LIMIT|SKIP|CREATE|MERGE|SET|DELETE|DETACH|UNWIND|AS|AND|OR|XOR|NOT|IS|NULL|IN|STARTS|ENDS|CONTAINS|CALL|YIELD|UNION|ALL|EXISTS|COUNT|SHORTEST|DISTINCT|NODE|REL|TABLE|PRIMARY|KEY|FROM|TO)\b/g;
    const types = /\b(Int64|Int32|Int|Nat|String|Bool|Float|Float32|Option|Array|List|Unit|IO|Query|Statement|Expr|Schema|Timestamp|Date|Embedding|MemM|LbugM|MonadGraph|Path|Value|Error|Except)\b/g;

    const escape = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

    document.querySelectorAll("pre > code").forEach((code) => {
      const lang = code.className || "";
      if (lang.includes("plain")) return;
      const src = code.textContent;
      // Tokenize strings and comments first so keywords inside them stay plain.
      const parts = src.split(/("(?:[^"\\]|\\.)*"|--[^\n]*|\/\/[^\n]*|\/-[\s\S]*?-\/)/g);
      code.innerHTML = parts.map((p, i) => {
        if (i % 2 === 1) {
          const cls = p.startsWith('"') ? "str" : "com";
          return `<span class="${cls}">${escape(p)}</span>`;
        }
        let h = escape(p);
        h = h.replace(/\b(\d+(?:\.\d+)?)\b/g, '<span class="num">$1</span>');
        h = h.replace(types, '<span class="ty">$1</span>');
        h = h.replace(lang.includes("cypher") ? cypherKw : leanKw, '<span class="kw">$1</span>');
        if (!lang.includes("cypher")) h = h.replace(cypherKw, '<span class="kw">$1</span>');
        return h;
      }).join("");
    });

    document.querySelectorAll("pre").forEach((pre) => {
      if (pre.dataset.nocopy !== undefined) return;
      const btn = document.createElement("button");
      btn.className = "copy";
      btn.type = "button";
      btn.textContent = "copy";
      btn.addEventListener("click", async () => {
        try {
          await navigator.clipboard.writeText(pre.querySelector("code").textContent);
          btn.textContent = "copied";
          setTimeout(() => (btn.textContent = "copy"), 1400);
        } catch (_) {
          btn.textContent = "select";
        }
      });
      pre.appendChild(btn);
    });
  });
})();
