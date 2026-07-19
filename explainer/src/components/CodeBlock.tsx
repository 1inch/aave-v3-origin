import type { ReactNode } from "react";

type Token = { text: string; cls?: string };

const RULES: { re: RegExp; cls: string }[] = [
  { re: /^(?:\/\/[^\n]*|\/\*[\s\S]*?\*\/)/, cls: "tok-com" },
  { re: /^(?:'(?:[^'\\\n]|\\.)*'|"(?:[^"\\\n]|\\.)*")/, cls: "tok-str" },
  {
    re: /^\b(?:function|returns?|internal|external|public|private|pure|view|storage|memory|calldata|require|revert|emit|if|else|for|while|do|struct|mapping|contract|library|interface|abstract|import|from|using|constant|immutable|new|delete|is|override|virtual|constructor|modifier|event|error|indexed|payable|unchecked|assembly|try|catch|type|const|let|var|export|default|return|extends|implements|async|await|true|false)\b/,
    cls: "tok-kw",
  },
  {
    re: /^\b(?:uint\d*|int\d*|address|bool|bytes\d*|string|number|boolean|void|DataTypes|ReserveData|EModeCategory)\b/,
    cls: "tok-type",
  },
  {
    re: /^(?:\b0x[0-9a-fA-F_]+\b|\b\d[\d_]*(?:\.\d[\d_]*)?(?:e\d+)?\b)/,
    cls: "tok-num",
  },
  { re: /^\b[A-Za-z_]\w*(?=\s*\()/, cls: "tok-fn" },
  { re: /^(?:=>|->|[+\-*/%=<>!&|^~?:]+)/, cls: "tok-op" },
];

function tokenize(code: string): Token[] {
  const tokens: Token[] = [];
  let rest = code;
  let plain = "";
  const flush = () => {
    if (plain) {
      tokens.push({ text: plain });
      plain = "";
    }
  };
  while (rest.length > 0) {
    let matched = false;
    for (const rule of RULES) {
      const m = rule.re.exec(rest);
      if (m && m[0].length > 0) {
        flush();
        tokens.push({ text: m[0], cls: rule.cls });
        rest = rest.slice(m[0].length);
        matched = true;
        break;
      }
    }
    if (!matched) {
      plain += rest[0];
      rest = rest.slice(1);
    }
  }
  flush();
  return tokens;
}

export function CodeBlock({ title, code }: { title?: string; code: string }) {
  const tokens = tokenize(code.trim());
  const nodes: ReactNode[] = tokens.map((t, i) =>
    t.cls ? (
      <span key={i} className={t.cls}>
        {t.text}
      </span>
    ) : (
      <span key={i}>{t.text}</span>
    )
  );
  return (
    <div className="codeblock">
      {title ? <div className="codeblock-bar">{title}</div> : null}
      <pre>
        <code>{nodes}</code>
      </pre>
    </div>
  );
}
