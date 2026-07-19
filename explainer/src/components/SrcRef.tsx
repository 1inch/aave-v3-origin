const REPO_BASE = "https://github.com/aave-dao/aave-v3-origin/blob/main/";

/**
 * Renders repository source references as deep links to GitHub.
 * Pass repo-relative paths like 'src/contracts/protocol/pool/Pool.sol'.
 * Trailing free-text annotations can be given via `note`.
 */
export function SrcRef({ paths, note }: { paths: string[]; note?: string }) {
  return (
    <div className="src-ref">
      {paths.map((p, i) => (
        <span key={p}>
          {i > 0 && " · "}
          <a href={`${REPO_BASE}${p}`} target="_blank" rel="noreferrer">
            {p}
          </a>
        </span>
      ))}
      {note && <span> · {note}</span>}
    </div>
  );
}
