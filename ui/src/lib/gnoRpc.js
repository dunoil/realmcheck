// gnoRpc.js: read-only HTTP helpers for a Gno.land testnet.
//
// Endpoints are configurable through Vite env vars so the local
// end-to-end harness can point the UI at a local gnodev chain:
//   VITE_GNO_RPC            (default https://rpc.onyx.testnets.gno.land)
//   VITE_GNOWEB             (default https://onyx.testnets.gno.land)
//   VITE_REALMCHECK_REALM   (default gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck)
// In plain node (smoke tests) import.meta.env is undefined, so the
// same names are read from process.env there, then the Onyx defaults.
//
// Verified live 27 Nov 2026 against https://rpc.onyx.testnets.gno.land:
// - abci_query with path "vm/qfile" and data 0x<hex of file path> returns
//   the file listing for a directory, or the file source for a file.
//   The result is in result.response.ResponseBase.Data (base64), and an
//   error is in result.response.ResponseBase.Error.
// - abci_query with path "vm/qeval" and data 0x<hex of expression>
//   returns the printed value in the same Data field.
// The gno.land docs call the RPC a Tendermint RPC; the data parameter
// must be 0x-prefixed hex. A missing 0x prefix fails with
// "illegal base64 data".

const _viteEnv =
  typeof import.meta !== "undefined" && import.meta.env
    ? import.meta.env
    : {};
const _nodeEnv =
  typeof process !== "undefined" && process.env ? process.env : {};

function envVar(name, fallback) {
  const v = _viteEnv[name] !== undefined ? _viteEnv[name] : _nodeEnv[name];
  return v !== undefined && v !== "" ? v : fallback;
}

// Configurable endpoints. ONYX_RPC and ONYX_GNOWEB stay as aliases so
// existing imports keep working; new code should use GNO_RPC and
// GNO_GNOWEB.
export const GNO_RPC = envVar(
  "VITE_GNO_RPC",
  "https://rpc.onyx.testnets.gno.land",
);
export const GNO_GNOWEB = envVar(
  "VITE_GNOWEB",
  "https://onyx.testnets.gno.land",
);
export const REALMCHECK_REALM = envVar(
  "VITE_REALMCHECK_REALM",
  "gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/realmcheck",
);

export const ONYX_RPC = GNO_RPC;
export const ONYX_GNOWEB = GNO_GNOWEB;

function hexEncode(str) {
  return [...new TextEncoder().encode(str)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function base64Decode(b64) {
  const bin = atob(b64);
  const bytes = Uint8Array.from(bin, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

// abciQuery runs one read-only ABCI query and returns the decoded Data
// string. It throws on HTTP errors and on chain errors.
export async function abciQuery(path, data) {
  const url =
    `${GNO_RPC}/abci_query?path=${encodeURIComponent(JSON.stringify(path))}` +
    `&data=0x${hexEncode(data)}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`RPC HTTP ${res.status} for ${path}`);
  const json = await res.json();
  const base = json?.result?.response?.ResponseBase;
  if (!base) throw new Error(`Unexpected RPC response shape for ${path}`);
  if (base.Error) {
    const log = base.Log || "";
    const short = log.split("\n").find((l) => l.includes("package") || l.includes("file"));
    throw new Error(
      `Chain error (${base.Error["@type"] || "unknown"}): ${short || log.slice(0, 160)}`,
    );
  }
  return base.Data ? base64Decode(base.Data) : "";
}

// qfile returns the file listing for a directory path, or the file
// source for a file path.
export async function qfile(filepath) {
  return abciQuery("vm/qfile", filepath);
}

// qeval evaluates a read-only expression and returns its printed value.
export async function qeval(expr) {
  return abciQuery("vm/qeval", expr);
}

// fetchRealmFiles lists the .gno files of a realm and fetches each one.
// Returns [{ name, source }]. Throws when the realm does not exist.
// Test files (*_test.gno) are skipped: test code legitimately calls
// realms without guards and ignores return values, so auditing it
// only produces noise (on gno.land/r/sys/params, 15 of 18 findings
// came from test files alone).
export async function fetchRealmFiles(realmPath) {
  const listing = await qfile(realmPath);
  const names = listing
    .split("\n")
    .map((s) => s.trim())
    .filter((n) => n.endsWith(".gno") && !n.endsWith("_test.gno"));
  if (names.length === 0) {
    throw new Error(`No .gno files found in ${realmPath}`);
  }
  const files = [];
  for (const name of names) {
    const source = await qfile(`${realmPath}/${name}`);
    files.push({ name, source });
  }
  return files;
}

export async function sha256Hex(str) {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(str),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// The source hash identifies the exact bytes audited. It must match the
// hash stored on-chain by SubmitReport: sha256 of the single audited
// file, or of the raw sources concatenated for a multi-file realm. Do NOT
// hash the display string (filename headers): the live view then shows a
// different hash from the stored report for the same source (seen 27 Nov
// 2026: live 3499e691... vs stored f8616d8b... for vulnmint).
export async function sourceHashFor(files) {
  return sha256Hex(files.map((f) => f.source).join(""));
}

// encodeFindings renders findings in the SubmitReport encoding:
// one finding per line, RULEID|Severity|Line|Title|Description|SourceLine.
export function encodeFindings(findings) {
  return findings
    .map((f) =>
      [f.ruleID, f.severity, f.line, f.title, f.description, f.sourceLine].join("|"),
    )
    .join("\n");
}

// decodeFindings parses the SubmitReport encoding back into findings.
export function decodeFindings(encoded) {
  const trimmed = (encoded || "").trim();
  if (trimmed === "") return [];
  const out = [];
  for (const line of trimmed.split("\n")) {
    const parts = line.split("|");
    if (parts.length !== 6) continue;
    const lineNo = parseInt(parts[2], 10);
    if (!lineNo || lineNo < 1) continue;
    out.push({
      ruleID: parts[0].trim(),
      severity: parts[1].trim(),
      title: parts[3].trim(),
      description: parts[4].trim(),
      file: "",
      line: lineNo,
      sourceLine: parts[5].trim(),
    });
  }
  return out;
}

// parsePrintedString extracts the string value from a qeval printed
// string, for example ("hello\nworld" string). The printer uses
// Go-style escapes, which JSON.parse accepts for the ASCII content
// RealmCheck stores. Falls back to a manual unescape when parsing fails.
export function parsePrintedString(text) {
  if (!text) return "";
  const m = text.match(/\("((?:\\.|[^"\\])*)" string\)/);
  if (!m) return "";
  try {
    return JSON.parse(`"${m[1]}"`);
  } catch {
    return m[1]
      .replace(/\\n/g, "\n")
      .replace(/\\t/g, "\t")
      .replace(/\\"/g, '"')
      .replace(/\\\\/g, "\\");
  }
}

// parsePrintedReport parses the printed GetReport / LatestReport value
// returned by vm/qeval, for example:
// (struct{(1 int),("gno.land/r/..." string),("f861..." string),(75 int),
// ("g1..." string),(3 int64),(slice[ref(...)] ...)} ...)
// (true bool)
// Returns { id, realmPath, sourceHash, score, auditor, height } or null
// when the second value is false (no report).
export function parsePrintedReport(text) {
  if (!text || text.includes("(false bool)")) return null;
  const strings = [...text.matchAll(/\("([^"]*)" string\)/g)].map((m) => m[1]);
  const ints = [...text.matchAll(/\((\d+) int\)/g)].map((m) => parseInt(m[1], 10));
  const int64s = [...text.matchAll(/\((\d+) int64\)/g)].map((m) => parseInt(m[1], 10));
  if (strings.length < 3 || ints.length < 2) return null;
  return {
    id: ints[0],
    realmPath: strings[0],
    sourceHash: strings[1],
    score: ints[1],
    auditor: strings[2],
    height: int64s.length > 0 ? int64s[0] : 0,
  };
}

// buildSubmitCommand renders the exact gnokey command that stores a
// report on chain. Gas scales with the finding count (measured on a
// local dev chain, 27 Nov 2026: 1 finding used 8,904,806 gas,
// 3 findings 20.4M, 4 findings 26.3M). Use gas-wanted 10,000,000 plus
// 7,000,000 per finding, and a fee of gas-wanted divided by 500 (twice
// the chain minimum of 1 ugnot per 1000 gas).
export function buildSubmitCommand({ realmPath, sourceHash, score, findings }) {
  const encoded = encodeFindings(findings);
  const gasWanted = 10000000 + 7000000 * findings.length;
  const gasFee = gasWanted / 500;
  const esc = (s) => `'${String(s).replace(/'/g, `'\\''`)}'`;
  return [
    "gnokey maketx call \\",
    `  -pkgpath ${JSON.stringify(REALMCHECK_REALM)} -func "SubmitReport" \\`,
    `  -args ${JSON.stringify(realmPath)} \\`,
    `  -args ${JSON.stringify(sourceHash)} \\`,
    `  -args ${JSON.stringify(String(score))} \\`,
    `  -args ${esc(encoded)} \\`,
    `  -gas-fee ${gasFee}ugnot -gas-wanted ${gasWanted} -chainid onyx-1 \\`,
    `  -remote ${GNO_RPC}:443 <your-key-name>`,
  ].join("\n");
}

export function gnowebUrl(realmPath) {
  return `${GNO_GNOWEB}/${realmPath.replace(/^gno\.land\//, "")}`;
}
