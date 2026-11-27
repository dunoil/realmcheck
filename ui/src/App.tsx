import { useEffect, useRef, useState } from "react";
import {
  RULES,
  auditFiles,
  score as auditScore,
  type Finding,
} from "./lib/audit.js";
import { explainRule, extractEnclosingFunction } from "./lib/explain.js";
import {
  ADENA_EXTENSION_URL,
  ADENA_INSTALL_URL,
  connectAdena,
  isAdenaInstalled,
  shortAddress,
  submitReportWithAdena,
} from "./lib/adena.js";
import {
  GNO_GNOWEB,
  REALMCHECK_REALM,
  buildSubmitCommand,
  decodeFindings,
  fetchRealmFiles,
  gnowebUrl,
  parsePrintedReport,
  parsePrintedString,
  qeval,
  sha256Hex,
  type StoredReport,
} from "./lib/gnoRpc.js";
import "./index.css";

const SEVERITY_STYLE: Record<string, { badge: string; label: string }> = {
  critical: {
    badge: "bg-red-500/15 text-red-300 ring-red-500/40",
    label: "Critical",
  },
  high: {
    badge: "bg-orange-500/15 text-orange-300 ring-orange-500/40",
    label: "High",
  },
  medium: {
    badge: "bg-yellow-500/15 text-yellow-300 ring-yellow-500/40",
    label: "Medium",
  },
  low: {
    badge: "bg-zinc-500/15 text-zinc-300 ring-zinc-500/40",
    label: "Low",
  },
};

const SEVERITY_ORDER = ["critical", "high", "medium", "low"];

interface DemoRealm {
  name: string;
  realmPath: string;
  vulnerability: string;
  files: string[];
  expectedFindings: {
    line: number;
    ruleID: string;
    severity: string;
    title: string;
    file: string;
  }[];
  expectedScore: number;
}

interface DemoManifest {
  generatedAt: string;
  note: string;
  realms: DemoRealm[];
}

function scoreColor(s: number): string {
  if (s >= 90) return "text-emerald-400";
  if (s >= 70) return "text-amber-400";
  return "text-red-400";
}

function scoreLabel(s: number): string {
  if (s >= 90) return "Clean: no known risky shapes found.";
  if (s >= 70) return "Review advised: some risky shapes found.";
  return "High risk: review carefully before calling this realm.";
}

function ScoreRing({ value }: { value: number }) {
  const r = 52;
  const c = 2 * Math.PI * r;
  const offset = c - (value / 100) * c;
  const color =
    value >= 90 ? "#34d399" : value >= 70 ? "#fbbf24" : "#f87171";
  return (
    <div className="relative h-36 w-36 shrink-0">
      <svg viewBox="0 0 120 120" className="h-36 w-36 -rotate-90">
        <circle
          cx="60"
          cy="60"
          r={r}
          fill="none"
          stroke="#27272a"
          strokeWidth="10"
        />
        <circle
          cx="60"
          cy="60"
          r={r}
          fill="none"
          stroke={color}
          strokeWidth="10"
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={offset}
        />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center">
        <span className={`text-4xl font-bold ${scoreColor(value)}`}>
          {value}
        </span>
        <span className="text-xs text-zinc-400">/ 100</span>
      </div>
    </div>
  );
}

function FindingCard({
  finding,
  source,
}: {
  finding: Finding;
  source?: string;
}) {
  const [open, setOpen] = useState(false);
  const meta = SEVERITY_STYLE[finding.severity] || SEVERITY_STYLE.low;
  const explanation = explainRule(finding.ruleID);
  const fn = source ? extractEnclosingFunction(source, finding.line) : null;
  return (
    <article className="rounded-xl border border-zinc-800 bg-zinc-900/60 p-4">
      <div className="flex flex-wrap items-center gap-2">
        <span
          className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ${meta.badge}`}
        >
          {finding.ruleID} · {meta.label}
        </span>
        <h3 className="text-sm font-semibold text-zinc-100">
          {finding.title}
        </h3>
      </div>
      <p className="mt-2 text-sm leading-relaxed text-zinc-300">
        {finding.description}
      </p>
      <div className="mt-3 rounded-lg bg-zinc-950 px-3 py-2 font-mono text-xs text-zinc-300">
        <span className="text-zinc-500">
          {finding.file ? `${finding.file}:` : ""}
          {finding.line}
        </span>{" "}
        {finding.sourceLine}
      </div>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="mt-3 rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-emerald-300 hover:bg-zinc-800"
      >
        {open ? "Hide explanation" : "Explain this function"}
      </button>
      {open && (
        <div className="mt-3 space-y-3 rounded-lg border border-zinc-800 bg-zinc-950/60 p-3">
          {fn ? (
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                Enclosing function:{" "}
                <span className="font-mono normal-case text-zinc-200">
                  {fn.name}
                </span>{" "}
                (lines {fn.startLine} to {fn.endLine})
              </p>
              <div className="mt-2 overflow-x-auto rounded-lg bg-zinc-950 ring-1 ring-zinc-800">
                <div className="min-w-max py-2 font-mono text-xs leading-relaxed">
                  {fn.lines.map((l) => (
                    <div
                      key={l.number}
                      className={
                        l.isFinding
                          ? "flex bg-emerald-500/15 px-3 ring-1 ring-inset ring-emerald-500/40"
                          : "flex px-3"
                      }
                    >
                      <span className="w-8 shrink-0 select-none pr-3 text-right text-zinc-600">
                        {l.number}
                      </span>
                      <span
                        className={
                          l.isFinding ? "text-emerald-200" : "text-zinc-300"
                        }
                      >
                        {l.text === "" ? " " : l.text}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
              <p className="mt-1 text-xs text-zinc-500">
                Highlighted line is the finding line.
              </p>
            </div>
          ) : (
            <p className="text-xs leading-relaxed text-zinc-500">
              The full source is not available for this finding, so the
              enclosing function cannot be shown here. Audit the realm live
              to see it in context.
            </p>
          )}
          <div className="space-y-2 text-sm leading-relaxed text-zinc-300">
            <p>
              <span className="font-semibold text-zinc-100">
                Why this is risky:{" "}
              </span>
              {explanation.risk}
            </p>
            <p>
              <span className="font-semibold text-zinc-100">
                What an attacker could do:{" "}
              </span>
              {explanation.attacker}
            </p>
            <p>
              <span className="font-semibold text-zinc-100">
                What to check before calling this realm:{" "}
              </span>
              {explanation.check}
            </p>
            <p>
              <span className="font-semibold text-zinc-100">
                Fix pattern:{" "}
              </span>
              {explanation.fix}
            </p>
          </div>
        </div>
      )}
    </article>
  );
}

function FindingsList({
  findings,
  files,
}: {
  findings: Finding[];
  files?: { name: string; source: string }[];
}) {
  if (findings.length === 0) {
    return (
      <div className="rounded-xl border border-emerald-500/30 bg-emerald-500/10 p-5 text-center">
        <p className="text-lg font-semibold text-emerald-300">
          No findings. No known risky shapes in this source.
        </p>
        <p className="mt-1 text-sm text-zinc-400">
          A clean result means no known shape was found, not that the realm
          is safe. Always review the source yourself before sending funds.
        </p>
      </div>
    );
  }
  const counts = SEVERITY_ORDER.map(
    (sev) => `${findings.filter((f) => f.severity === sev).length} ${sev}`,
  )
    .filter((s) => !s.startsWith("0 "))
    .join(" · ");
  const sourceByFile = new Map(
    (files || []).map((f) => [f.name, f.source]),
  );
  return (
    <div>
      <p className="mb-3 text-sm text-zinc-400">
        {findings.length} finding{findings.length === 1 ? "" : "s"}: {counts}
      </p>
      <div className="space-y-3">
        {[...findings]
          .sort(
            (a, b) =>
              SEVERITY_ORDER.indexOf(a.severity) -
                SEVERITY_ORDER.indexOf(b.severity) ||
              a.line - b.line,
          )
          .map((f, i) => (
            <FindingCard
              key={`${f.ruleID}-${f.file}-${f.line}-${i}`}
              finding={f}
              source={f.file ? sourceByFile.get(f.file) : undefined}
            />
          ))}
      </div>
    </div>
  );
}

type Phase = "idle" | "fetching" | "auditing" | "done" | "error";

export default function App() {
  const [realmPath, setRealmPath] = useState("gno.land/r/gov/dao");
  const [phase, setPhase] = useState<Phase>("idle");
  const [status, setStatus] = useState("");
  const [error, setError] = useState("");
  const [files, setFiles] = useState<{ name: string; source: string }[]>([]);
  const [findings, setFindings] = useState<Finding[]>([]);
  const [sourceHash, setSourceHash] = useState("");
  const [demoName, setDemoName] = useState<string | null>(null);
  const [demoManifest, setDemoManifest] = useState<DemoManifest | null>(null);
  const [demoError, setDemoError] = useState("");
  const [demoRunning, setDemoRunning] = useState<string | null>(null);
  // True when a demo report was audited from the bundled sources
  // because the live fetch from Onyx failed. The report then says so.
  const [demoLiveFallback, setDemoLiveFallback] = useState(false);
  const [showSave, setShowSave] = useState(false);
  const [copied, setCopied] = useState(false);
  const [linkCopied, setLinkCopied] = useState(false);
  type AdenaStatus =
    | "idle"
    | "not-installed"
    | "connecting"
    | "connected"
    | "signing"
    | "signed"
    | "error";
  const [adenaStatus, setAdenaStatus] = useState<AdenaStatus>("idle");
  const [adenaAddress, setAdenaAddress] = useState("");
  const [adenaTxHash, setAdenaTxHash] = useState("");
  const [adenaTxHeight, setAdenaTxHeight] = useState<number | null>(null);
  const [adenaError, setAdenaError] = useState("");
  const [adenaTxCopied, setAdenaTxCopied] = useState(false);
  const [stored, setStored] = useState<{
    report: StoredReport;
    findings: Finding[];
  } | null>(null);
  const [storedLoading, setStoredLoading] = useState(false);
  const [storedError, setStoredError] = useState("");
  const autoRanRef = useRef(false);

  const currentScore = auditScore(findings);

  function reportLink(): string {
    const base = `${window.location.origin}${window.location.pathname}`;
    if (demoName) return `${base}?demo=${encodeURIComponent(demoName)}`;
    return `${base}?realm=${encodeURIComponent(realmPath.trim())}`;
  }

  function copyText(text: string, done: () => void) {
    const finish = () => {
      done();
      window.setTimeout(() => {
        setCopied(false);
        setLinkCopied(false);
      }, 2000);
    };
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(finish).catch(() => {
        setCopied(false);
        setLinkCopied(false);
      });
      return;
    }
    const area = document.createElement("textarea");
    area.value = text;
    document.body.appendChild(area);
    area.select();
    try {
      document.execCommand("copy");
      finish();
    } catch {
      setCopied(false);
      setLinkCopied(false);
    }
    document.body.removeChild(area);
  }

  function scrollToReport() {
    document
      .getElementById("report")
      ?.scrollIntoView({ behavior: "smooth", block: "start" });
  }

  async function runAudit(path: string) {
    const clean = path.trim();
    if (!clean.startsWith("gno.land/")) {
      setError(
        "Realm path must start with gno.land/, for example gno.land/r/sys/params.",
      );
      setPhase("error");
      return;
    }
    setError("");
    setStored(null);
    setShowSave(false);
    setAdenaStatus("idle");
    setAdenaAddress("");
    setAdenaTxHash("");
    setAdenaTxHeight(null);
    setAdenaError("");
    setCopied(false);
    setLinkCopied(false);
    setDemoName(null);
    setDemoLiveFallback(false);
    setPhase("fetching");
    setStatus(`Fetching source for ${clean} from the configured network...`);
    try {
      const fetched = await fetchRealmFiles(clean);
      setFiles(fetched);
      setPhase("auditing");
      setStatus(
        `Auditing ${fetched.length} source file${fetched.length === 1 ? "" : "s"} with rules RC-01 to RC-08...`,
      );
      const found = auditFiles(fetched);
      const combined = fetched
        .map((f) => `===== ${f.name} =====\n${f.source}`)
        .join("\n");
      const hash = await sha256Hex(combined);
      setFindings(found);
      setSourceHash(hash);
      setPhase("done");
      setStatus("");
      window.history.replaceState(
        null,
        "",
        `?realm=${encodeURIComponent(clean)}`,
      );
      scrollToReport();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPhase("error");
    }
  }

  async function runDemoAudit(demo: DemoRealm) {
    setError("");
    setStored(null);
    setShowSave(false);
    setAdenaStatus("idle");
    setAdenaAddress("");
    setAdenaTxHash("");
    setAdenaTxHeight(null);
    setAdenaError("");
    setCopied(false);
    setLinkCopied(false);
    setDemoRunning(demo.name);
    setDemoLiveFallback(false);
    setPhase("fetching");
    setStatus(`Fetching the live source for ${demo.name} from Onyx...`);
    try {
      // Live first: fetch the deployed source from the chain, the same
      // path the search box uses. The bundled sources are only a
      // fallback when the live fetch fails, and the report then says so
      // instead of silently serving the bundled copy.
      let fetched: { name: string; source: string }[];
      try {
        fetched = await fetchRealmFiles(demo.realmPath);
      } catch (liveErr) {
        const base = import.meta.env.BASE_URL;
        const bundled: { name: string; source: string }[] = [];
        for (const file of demo.files) {
          const res = await fetch(
            `${base}demo-sources/${demo.name}/${encodeURIComponent(file)}`,
          );
          if (!res.ok) {
            throw new Error(
              `Live fetch failed (${liveErr instanceof Error ? liveErr.message : String(liveErr)}), and the bundled demo source ${file} could not be loaded either (HTTP ${res.status}).`,
            );
          }
          bundled.push({ name: file, source: await res.text() });
        }
        fetched = bundled;
        setDemoLiveFallback(true);
      }
      setFiles(fetched);
      setRealmPath(demo.realmPath);
      setPhase("auditing");
      setStatus(
        `Auditing ${fetched.length} source file${fetched.length === 1 ? "" : "s"} with rules RC-01 to RC-08...`,
      );
      const found = auditFiles(fetched);
      const combined = fetched
        .map((f) => `===== ${f.name} =====\n${f.source}`)
        .join("\n");
      const hash = await sha256Hex(combined);
      setFindings(found);
      setSourceHash(hash);
      setDemoName(demo.name);
      setPhase("done");
      setStatus("");
      window.history.replaceState(
        null,
        "",
        `?demo=${encodeURIComponent(demo.name)}`,
      );
      scrollToReport();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPhase("error");
    } finally {
      setDemoRunning(null);
    }
  }

  // Deep links: ?realm=gno.land/r/... auto-runs a live audit on load,
  // ?demo=<name> auto-runs a live audit of the demo realm (bundled
  // sources are the fallback when the live fetch fails). The demo
  // manifest is fetched first so a ?demo= link can resolve its files.
  useEffect(() => {
    let cancelled = false;
    async function init() {
      let manifest: DemoManifest | null = null;
      try {
        const res = await fetch(
          `${import.meta.env.BASE_URL}demo-sources/manifest.json`,
        );
        if (res.ok) {
          manifest = (await res.json()) as DemoManifest;
          if (!cancelled) setDemoManifest(manifest);
        } else if (!cancelled) {
          setDemoError(
            `Demo list unavailable (HTTP ${res.status}). The demo cards need the next build.`,
          );
        }
      } catch {
        if (!cancelled) {
          setDemoError(
            "Demo list could not be loaded. The demo cards need the next build.",
          );
        }
      }
      if (cancelled || autoRanRef.current) return;
      autoRanRef.current = true;
      const params = new URLSearchParams(window.location.search);
      const demoParam = params.get("demo");
      const realmParam = params.get("realm");
      if (demoParam && manifest) {
        const demo = manifest.realms.find((r) => r.name === demoParam);
        if (demo) {
          void runDemoAudit(demo);
          return;
        }
      }
      if (realmParam && realmParam.startsWith("gno.land/")) {
        setRealmPath(realmParam);
        void runAudit(realmParam);
      }
    }
    void init();
    return () => {
      cancelled = true;
    };
    // Runs once on mount. runAudit and runDemoAudit are stable enough
    // for this one-shot deep link: they only use setters and imports.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // When the save panel opens, check whether the Adena extension is
  // present, so the panel can show the install prompt instead of a dead
  // button. The check re-runs if the extension appears while the panel
  // is open (for example after the user installs it and returns).
  useEffect(() => {
    if (!showSave) return;
    if (!isAdenaInstalled()) {
      setAdenaStatus((s) => (s === "idle" ? "not-installed" : s));
    } else {
      setAdenaStatus((s) => (s === "not-installed" ? "idle" : s));
    }
  }, [showSave]);

  async function handleConnectAdena() {
    setAdenaError("");
    setAdenaStatus("connecting");
    try {
      const account = await connectAdena();
      setAdenaAddress(account.address);
      setAdenaStatus("connected");
    } catch (e) {
      setAdenaError(e instanceof Error ? e.message : String(e));
      setAdenaStatus("error");
    }
  }

  async function handleSignWithAdena() {
    if (!adenaAddress) return;
    setAdenaError("");
    setAdenaStatus("signing");
    try {
      const result = await submitReportWithAdena({
        address: adenaAddress,
        realmPath: realmPath.trim(),
        sourceHash,
        score: currentScore,
        findings,
      });
      setAdenaTxHash(result.hash);
      setAdenaTxHeight(result.height);
      setAdenaStatus("signed");
    } catch (e) {
      setAdenaError(e instanceof Error ? e.message : String(e));
      setAdenaStatus("error");
    }
  }

  async function loadStored(path: string) {
    const clean = path.trim();
    setStoredLoading(true);
    setStoredError("");
    setStored(null);
    try {
      const printed = await qeval(
        `${REALMCHECK_REALM}.LatestReport(${JSON.stringify(clean)})`,
      );
      const report = parsePrintedReport(printed);
      if (!report) {
        setStoredError(
          `No stored report found for ${clean} yet. Audit it first, then save the report on chain.`,
        );
        return;
      }
      const raw = await qeval(
        `${REALMCHECK_REALM}.ReportFindings(${report.id})`,
      );
      const decoded = decodeFindings(parsePrintedString(raw));
      setStored({ report, findings: decoded });
    } catch (e) {
      setStoredError(e instanceof Error ? e.message : String(e));
    } finally {
      setStoredLoading(false);
    }
  }

  const submitCommand =
    phase === "done"
      ? buildSubmitCommand({
          realmPath: realmPath.trim(),
          sourceHash,
          score: currentScore,
          findings,
        })
      : "";

  return (
    <div className="min-h-screen bg-zinc-950 text-zinc-100">
      <header className="border-b border-zinc-800">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-3 px-4 py-4">
          <a href={window.location.pathname} className="text-lg font-bold tracking-tight">
            RealmCheck
          </a>
          <div className="flex flex-wrap items-center gap-2">
            <span className="rounded-full bg-emerald-500/15 px-3 py-1 text-xs font-semibold text-emerald-300 ring-1 ring-emerald-500/40">
              Onyx testnet · onyx-1
            </span>
            <a
              className="rounded-full bg-zinc-800 px-3 py-1 text-xs font-semibold text-zinc-200 ring-1 ring-zinc-700 hover:bg-zinc-700"
              href="https://github.com/dunoil/realmcheck"
              target="_blank"
              rel="noreferrer"
            >
              GitHub
            </a>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-5xl px-4 py-8">
        <section className="rounded-2xl border border-zinc-800 bg-gradient-to-b from-zinc-900/70 to-zinc-900/30 p-5 sm:p-8">
          <p className="text-xs font-semibold uppercase tracking-widest text-emerald-400">
            Gnome Tavern Hackathon · Gno.land
          </p>
          <h1 className="mt-3 text-3xl font-bold leading-tight tracking-tight sm:text-4xl">
            Read the source before you trust the realm.
          </h1>
          <p className="mt-3 max-w-3xl text-base leading-relaxed text-zinc-300">
            RealmCheck audits any Gno.land realm before you call it. Paste a
            realm path and get a risk score with findings that cite the exact
            source lines, plus a plain-English explanation of each finding
            and the fix pattern.
          </p>
          <p className="mt-3 max-w-3xl text-sm leading-relaxed text-zinc-400">
            Source-on-chain auditing only works on Gno.land: every realm's
            source lives on the chain itself and is readable by anyone, so
            the audit runs against exactly what is deployed. There is no
            bytecode to decompile and no off-chain repository that might
            differ from the deployed code. If the source is on the chain,
            anyone can verify it. If it is not, there is nothing to verify.
          </p>
          <div className="mt-5 flex flex-wrap gap-2">
            {RULES.map((r) => (
              <span
                key={r.id}
                className="rounded-full bg-zinc-800 px-2.5 py-1 font-mono text-xs text-zinc-200 ring-1 ring-zinc-700"
                title={r.name}
              >
                {r.id}
              </span>
            ))}
            <span className="rounded-full bg-emerald-500/15 px-2.5 py-1 text-xs font-semibold text-emerald-300 ring-1 ring-emerald-500/40">
              8 deterministic rules, no LLM in the score
            </span>
          </div>
          <dl className="mt-6 grid grid-cols-1 gap-3 sm:grid-cols-3">
            <div className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
              <dt className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                Score
              </dt>
              <dd className="mt-1 text-sm text-zinc-200">
                100 minus severity weights: critical 25, high 15, medium 8,
                low 3.
              </dd>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
              <dt className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                Source
              </dt>
              <dd className="mt-1 text-sm text-zinc-200">
                Fetched live from the chain with vm/qfile, one file at a
                time. No source ever leaves your browser except the report
                you choose to save.
              </dd>
            </div>
            <div className="rounded-xl border border-zinc-800 bg-zinc-950/60 p-3">
              <dt className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                Reports
              </dt>
              <dd className="mt-1 text-sm text-zinc-200">
                Save a report on chain with its source hash, so anyone can
                re-run the audit and compare.
              </dd>
            </div>
          </dl>
        </section>

        <section className="mt-6 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <label
            htmlFor="realm-path"
            className="text-sm font-semibold text-zinc-200"
          >
            Realm path
          </label>
          <div className="mt-2 flex flex-col gap-2 sm:flex-row">
            <input
              id="realm-path"
              value={realmPath}
              onChange={(e) => setRealmPath(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") void runAudit(realmPath);
              }}
              placeholder="gno.land/r/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/vulnmint"
              spellCheck={false}
              className="min-w-0 flex-1 rounded-lg border border-zinc-700 bg-zinc-950 px-3 py-2.5 font-mono text-sm text-zinc-100 outline-none focus:border-emerald-500"
            />
            <button
              type="button"
              onClick={() => void runAudit(realmPath)}
              disabled={phase === "fetching" || phase === "auditing"}
              className="rounded-lg bg-emerald-500 px-5 py-2.5 text-sm font-bold text-zinc-950 hover:bg-emerald-400 disabled:opacity-50"
            >
              {phase === "fetching" || phase === "auditing"
                ? "Auditing..."
                : "Audit realm"}
            </button>
            <button
              type="button"
              onClick={() => void loadStored(realmPath)}
              disabled={storedLoading}
              className="rounded-lg border border-zinc-700 bg-zinc-900 px-4 py-2.5 text-sm font-semibold text-zinc-200 hover:bg-zinc-800 disabled:opacity-50"
            >
              {storedLoading ? "Loading..." : "View stored report"}
            </button>
          </div>
          <p className="mt-3 text-xs leading-relaxed text-zinc-500">
            Try an example that exists on Onyx today:{" "}
            <button
              type="button"
              className="font-mono text-emerald-400 underline underline-offset-2"
              onClick={() => {
                setRealmPath("gno.land/r/gov/dao");
                void runAudit("gno.land/r/gov/dao");
              }}
            >
              gno.land/r/gov/dao
            </button>{" "}
            or{" "}
            <button
              type="button"
              className="font-mono text-emerald-400 underline underline-offset-2"
              onClick={() => {
                setRealmPath("gno.land/r/sys/params");
                void runAudit("gno.land/r/sys/params");
              }}
            >
              gno.land/r/sys/params
            </button>
            . Scores change as the rules improve, so run the audit to see
            the current result. The five deliberately vulnerable demo realms
            below are live on Onyx at the paths shown.
          </p>
          {(phase === "fetching" || phase === "auditing") && (
            <p className="mt-3 text-sm text-zinc-300" role="status">
              {status}
            </p>
          )}
          {phase === "error" && (
            <div
              className="mt-3 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-300"
              role="alert"
            >
              Audit failed: {error}
            </div>
          )}
        </section>

        {phase === "done" && (
          <section id="report" className="mt-6 scroll-mt-4">
            {demoName && demoLiveFallback && (
              <p className="mb-3 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                Live fetch failed for the {demoName} realm, so this report
                shows the bundled copy: the scores below come from the
                source bundled with this page, not from the chain.
              </p>
            )}
            <div className="flex flex-col gap-5 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5 sm:flex-row sm:items-center">
              <ScoreRing value={currentScore} />
              <div className="min-w-0 flex-1">
                <h2 className="break-all font-mono text-base font-semibold text-zinc-100">
                  {realmPath.trim()}
                </h2>
                <p className="mt-1 text-sm text-zinc-300">
                  {scoreLabel(currentScore)}
                </p>
                <p className="mt-2 text-xs text-zinc-500">
                  {files.length} source file{files.length === 1 ? "" : "s"}{" "}
                  audited ({files.map((f) => f.name).join(", ")}) ·{" "}
                  {findings.length} finding{findings.length === 1 ? "" : "s"}{" "}
                  · source SHA-256{" "}
                  <span className="font-mono text-zinc-400">
                    {sourceHash.slice(0, 16)}...
                  </span>
                </p>
                <div className="mt-3 flex flex-wrap gap-2">
                  <a
                    className="rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                    href={gnowebUrl(realmPath.trim())}
                    target="_blank"
                    rel="noreferrer"
                  >
                    View realm on gnoweb
                  </a>
                  <button
                    type="button"
                    onClick={() =>
                      copyText(reportLink(), () => setLinkCopied(true))
                    }
                    className="rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                  >
                    {linkCopied ? "Link copied" : "Copy link to this report"}
                  </button>
                  <button
                    type="button"
                    onClick={() => setShowSave((v) => !v)}
                    className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-bold text-zinc-950 hover:bg-emerald-400"
                  >
                    {showSave
                      ? "Hide save options"
                      : "Save this report on chain"}
                  </button>
                </div>
              </div>
            </div>

            {showSave && (
              <div className="mt-4 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
                <h3 className="text-sm font-semibold text-zinc-100">
                  Save this report on chain
                </h3>
                <p className="mt-1 text-sm leading-relaxed text-zinc-400">
                  The report is stored in the RealmCheck report realm (
                  <span className="font-mono">{REALMCHECK_REALM}</span>),
                  so anyone can load it later with "View stored report". The
                  stored source hash lets anyone re-run the audit and compare.
                </p>
                <p className="mt-3 text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  Option 1: gnokey (works today)
                </p>
                <pre className="mt-2 overflow-x-auto rounded-lg bg-zinc-950 p-3 font-mono text-xs leading-relaxed text-zinc-300">
                  {submitCommand}
                </pre>
                <button
                  type="button"
                  onClick={() =>
                    copyText(submitCommand, () => setCopied(true))
                  }
                  className="mt-2 rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                >
                  {copied ? "Copied" : "Copy command"}
                </button>
                <p className="mt-4 text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  Option 2: Adena wallet
                </p>
                {adenaStatus === "not-installed" && (
                  <div className="mt-2 rounded-lg border border-amber-500/40 bg-amber-500/10 px-3 py-2 text-sm text-amber-200">
                    <p>
                      Adena is not installed in this browser, so signing
                      from the page is unavailable. Install it, then reopen
                      this panel.
                    </p>
                    <p className="mt-2 flex flex-wrap gap-2">
                      <a
                        className="rounded-lg bg-amber-500 px-3 py-1.5 text-xs font-bold text-zinc-950 hover:bg-amber-400"
                        href={ADENA_INSTALL_URL}
                        target="_blank"
                        rel="noreferrer"
                      >
                        Get Adena at adena.app
                      </a>
                      <a
                        className="rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                        href={ADENA_EXTENSION_URL}
                        target="_blank"
                        rel="noreferrer"
                      >
                        Chrome Web Store page
                      </a>
                    </p>
                    <p className="mt-2 text-xs text-amber-200/80">
                      Until then, use the gnokey command above with a funded
                      Onyx key.
                    </p>
                  </div>
                )}
                {(adenaStatus === "idle" || adenaStatus === "error") && (
                  <div className="mt-2">
                    <button
                      type="button"
                      onClick={() => void handleConnectAdena()}
                      className="rounded-lg bg-emerald-500 px-4 py-2 text-sm font-bold text-zinc-950 hover:bg-emerald-400"
                    >
                      Connect Adena to sign
                    </button>
                    <p className="mt-2 text-xs text-zinc-500">
                      Adena asks you to approve the connection, switches to
                      the Onyx testnet if needed (adding it from this
                      page's settings when it is missing), and then signs
                      the report. Nothing is sent until you approve the
                      transaction in the extension.
                    </p>
                  </div>
                )}
                {adenaStatus === "connecting" && (
                  <p className="mt-2 text-sm text-zinc-300" role="status">
                    Connecting to Adena... approve the connection in the
                    extension window.
                  </p>
                )}
                {adenaStatus === "connected" && (
                  <div className="mt-2">
                    <p className="text-sm text-zinc-300">
                      Connected as{" "}
                      <span className="font-mono text-zinc-100">
                        {shortAddress(adenaAddress)}
                      </span>{" "}
                      <span className="break-all font-mono text-xs text-zinc-500">
                        ({adenaAddress})
                      </span>
                    </p>
                    <button
                      type="button"
                      onClick={() => void handleSignWithAdena()}
                      className="mt-2 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-bold text-zinc-950 hover:bg-emerald-400"
                    >
                      Sign and save this report
                    </button>
                    <p className="mt-2 text-xs text-zinc-500">
                      The transaction calls SubmitReport on{" "}
                      <span className="font-mono">{REALMCHECK_REALM}</span>{" "}
                      with this report's score and findings. Adena shows
                      the gas and the call before you approve it.
                    </p>
                  </div>
                )}
                {adenaStatus === "signing" && (
                  <p className="mt-2 text-sm text-zinc-300" role="status">
                    Waiting for your approval in Adena... review the
                    SubmitReport call and confirm it to save the report.
                  </p>
                )}
                {adenaStatus === "signed" && (
                  <div className="mt-2 rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-200">
                    <p>
                      Report signed and sent. Transaction hash:
                    </p>
                    <p className="mt-1 break-all font-mono text-xs text-emerald-100">
                      {adenaTxHash}
                    </p>
                    {adenaTxHeight !== null && (
                      <p className="mt-1 text-xs text-emerald-200/80">
                        Included at height {adenaTxHeight}.
                      </p>
                    )}
                    <p className="mt-2 flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() =>
                          copyText(adenaTxHash, () => setAdenaTxCopied(true))
                        }
                        className="rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                      >
                        {adenaTxCopied ? "Hash copied" : "Copy transaction hash"}
                      </button>
                      <button
                        type="button"
                        onClick={() => void loadStored(realmPath.trim())}
                        className="rounded-lg bg-emerald-500 px-3 py-1.5 text-xs font-bold text-zinc-950 hover:bg-emerald-400"
                      >
                        Load the stored report
                      </button>
                    </p>
                  </div>
                )}
                {adenaStatus === "error" && adenaError && (
                  <div
                    className="mt-2 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-300"
                    role="alert"
                  >
                    {adenaError} You can try connecting again, or use the
                    gnokey command above instead.
                  </div>
                )}
              </div>
            )}

            <div className="mt-6">
              <h2 className="mb-3 text-lg font-bold">Findings</h2>
              <FindingsList findings={findings} files={files} />
            </div>
          </section>
        )}

        {(stored || storedError) && (
          <section className="mt-6 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
            <h2 className="text-lg font-bold">Stored report</h2>
            {storedError && (
              <p className="mt-2 text-sm text-red-300" role="alert">
                {storedError}
              </p>
            )}
            {stored && (
              <div className="mt-3">
                <div className="flex flex-col gap-5 sm:flex-row sm:items-center">
                  <ScoreRing value={stored.report.score} />
                  <div className="min-w-0 flex-1">
                    <h3 className="break-all font-mono text-base font-semibold text-zinc-100">
                      {stored.report.realmPath}
                    </h3>
                    <p className="mt-1 text-sm text-zinc-300">
                      {scoreLabel(stored.report.score)}
                    </p>
                    <p className="mt-2 text-xs text-zinc-500">
                      Report #{stored.report.id} · stored at height{" "}
                      {stored.report.height} · auditor{" "}
                      <span className="font-mono break-all text-zinc-400">
                        {stored.report.auditor}
                      </span>{" "}
                      · source SHA-256{" "}
                      <span className="font-mono text-zinc-400">
                        {stored.report.sourceHash.slice(0, 16)}...
                      </span>
                    </p>
                    <a
                      className="mt-3 inline-block rounded-lg border border-zinc-700 bg-zinc-900 px-3 py-1.5 text-xs font-semibold text-zinc-200 hover:bg-zinc-800"
                      href={gnowebUrl(REALMCHECK_REALM)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      View report realm on gnoweb
                    </a>
                  </div>
                </div>
                <div className="mt-6">
                  <FindingsList findings={stored.findings} />
                </div>
              </div>
            )}
          </section>
        )}

        <section className="mt-10">
          <div className="flex flex-wrap items-baseline justify-between gap-2">
            <h2 className="text-lg font-bold">Try the demo realms</h2>
            <span className="rounded-full bg-emerald-500/15 px-2.5 py-0.5 text-xs font-semibold text-emerald-300 ring-1 ring-emerald-500/40">
              Live on Onyx
            </span>
          </div>
          <p className="mt-2 max-w-3xl text-sm leading-relaxed text-zinc-400">
            Five deliberately vulnerable realms, built to prove the rules
            work. Each audit fetches the live source from Onyx and runs the
            rules in your browser. Expected findings and scores come from
            the rule set at build time and move with it.
          </p>
          {demoError && (
            <p className="mt-3 rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-300" role="alert">
              {demoError}
            </p>
          )}
          {!demoManifest && !demoError && (
            <p className="mt-3 text-sm text-zinc-400" role="status">
              Loading demo realms...
            </p>
          )}
          {demoManifest && (
            <div className="mt-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {demoManifest.realms.map((demo) => (
                <article
                  key={demo.name}
                  className="flex flex-col rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4"
                >
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <h3 className="font-mono text-sm font-bold text-zinc-100">
                      {demo.name}
                    </h3>
                    <span className="rounded-full bg-zinc-800 px-2 py-0.5 text-xs font-semibold text-zinc-300 ring-1 ring-zinc-700">
                      Expected {demo.expectedScore}/100
                    </span>
                  </div>
                  <p className="mt-1 break-all font-mono text-xs text-zinc-500">
                    {demo.realmPath}
                  </p>
                  <p className="mt-2 flex-1 text-sm leading-relaxed text-zinc-300">
                    {demo.vulnerability}
                  </p>
                  <ul className="mt-3 space-y-1">
                    {demo.expectedFindings.map((f) => {
                      const style =
                        SEVERITY_STYLE[f.severity] || SEVERITY_STYLE.low;
                      return (
                        <li
                          key={`${f.ruleID}-${f.line}`}
                          className="flex flex-wrap items-center gap-2 text-xs"
                        >
                          <span
                            className={`rounded-full px-2 py-0.5 font-semibold ring-1 ${style.badge}`}
                          >
                            {f.ruleID} · {style.label}
                          </span>
                          <span className="text-zinc-400">
                            {f.title} · line {f.line}
                          </span>
                        </li>
                      );
                    })}
                  </ul>
                  <button
                    type="button"
                    onClick={() => void runDemoAudit(demo)}
                    disabled={
                      demoRunning !== null ||
                      phase === "fetching" ||
                      phase === "auditing"
                    }
                    className="mt-4 rounded-lg bg-emerald-500 px-4 py-2 text-sm font-bold text-zinc-950 hover:bg-emerald-400 disabled:opacity-50"
                  >
                    {demoRunning === demo.name
                      ? "Auditing..."
                      : `Audit ${demo.name}`}
                  </button>
                </article>
              ))}
            </div>
          )}
        </section>

        <section className="mt-10">
          <h2 className="text-lg font-bold">The eight rules</h2>
          <p className="mt-2 max-w-3xl text-sm leading-relaxed text-zinc-400">
            Every rule is deterministic: the same source always produces the
            same findings and the same score. The same rules run on chain as
            the{" "}
            <span className="font-mono text-zinc-100">
              gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules
            </span>{" "}
            package, so any project can import them.
          </p>
          <div className="mt-4 grid gap-3 sm:grid-cols-2">
            {RULES.map((rule) => {
              const style =
                SEVERITY_STYLE[rule.severity] || SEVERITY_STYLE.low;
              return (
                <article
                  key={rule.id}
                  className="rounded-2xl border border-zinc-800 bg-zinc-900/40 p-4"
                >
                  <div className="flex flex-wrap items-center gap-2">
                    <span className="rounded-full bg-zinc-800 px-2.5 py-0.5 font-mono text-xs font-bold text-zinc-100 ring-1 ring-zinc-700">
                      {rule.id}
                    </span>
                    <span
                      className={`rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ${style.badge}`}
                    >
                      {style.label}
                    </span>
                  </div>
                  <h3 className="mt-2 text-sm font-semibold text-zinc-100">
                    {rule.name}
                  </h3>
                  <p className="mt-1 text-sm leading-relaxed text-zinc-400">
                    {rule.description}
                  </p>
                </article>
              );
            })}
          </div>
        </section>

        <section className="mt-10 rounded-2xl border border-zinc-800 bg-zinc-900/40 p-5">
          <h2 className="text-lg font-bold">How it works</h2>
          <ol className="mt-3 list-decimal space-y-2 pl-5 text-sm leading-relaxed text-zinc-300">
            <li>
              The UI fetches the realm source live from the configured
              network with the{" "}
              <span className="font-mono text-zinc-100">vm/qfile</span>{" "}
              query, one file at a time. No source ever leaves your browser
              except the report you choose to save.
            </li>
            <li>
              Eight deterministic rules (RC-01 to RC-08) scan the source: no
              caller guard, unrestricted mint, admin backdoor, unbounded
              storage, funds without a check, weak randomness, unchecked
              cross-realm calls, and unguarded state mutation. The same rules
              run on chain as the{" "}
              <span className="font-mono text-zinc-100">
                gno.land/p/g1wt8ndw7u974eazjaxvfjw23w6xrw689cv0ueuu/auditrules
              </span>{" "}
              package, so any project can import them.
            </li>
            <li>
              The score is 100 minus severity weights (critical 25, high 15,
              medium 8, low 3). Saving a report stores it in the report realm
              with the source hash, so anyone can verify it later.
            </li>
          </ol>
          <p className="mt-4 text-xs leading-relaxed text-zinc-500">
            Findings are signals for human review, not verdicts. A clean
            result means no known shape was found, not that the realm is safe.
            RealmCheck never moves funds and never calls a realm on your
            behalf.
          </p>
        </section>
      </main>

      <footer className="border-t border-zinc-800">
        <div className="mx-auto max-w-5xl px-4 py-8">
          <div className="flex flex-col gap-6 sm:flex-row sm:justify-between">
            <div className="max-w-sm">
              <p className="text-sm font-bold text-zinc-100">RealmCheck</p>
              <p className="mt-1 text-xs leading-relaxed text-zinc-500">
                Read the source before you trust the realm. Built for the
                Gnome Tavern Hackathon on Gno.land, Onyx testnet.
              </p>
            </div>
            <div className="flex flex-col gap-6 sm:flex-row sm:gap-12">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  Project
                </p>
                <ul className="mt-2 space-y-1 text-xs">
                  <li>
                    <a
                      className="text-emerald-400 underline underline-offset-2"
                      href="https://github.com/dunoil/realmcheck"
                      target="_blank"
                      rel="noreferrer"
                    >
                      GitHub
                    </a>
                  </li>
                  <li>
                    <a
                      className="text-emerald-400 underline underline-offset-2"
                      href="https://dorahacks.io/hackathon/gnome-tavern/detail"
                      target="_blank"
                      rel="noreferrer"
                    >
                      Hackathon page
                    </a>
                  </li>
                </ul>
              </div>
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-zinc-500">
                  Gno.land
                </p>
                <ul className="mt-2 space-y-1 text-xs">
                  <li>
                    <a
                      className="text-emerald-400 underline underline-offset-2"
                      href="https://docs.gno.land/"
                      target="_blank"
                      rel="noreferrer"
                    >
                      Gno.land docs
                    </a>
                  </li>
                  <li>
                    <a
                      className="text-emerald-400 underline underline-offset-2"
                      href={gnowebUrl(REALMCHECK_REALM)}
                      target="_blank"
                      rel="noreferrer"
                    >
                      Report realm on gnoweb
                    </a>
                  </li>
                  <li>
                    <a
                      className="text-emerald-400 underline underline-offset-2"
                      href={GNO_GNOWEB}
                      target="_blank"
                      rel="noreferrer"
                    >
                      Gnoweb (Onyx)
                    </a>
                  </li>
                </ul>
              </div>
            </div>
          </div>
          <p className="mt-6 border-t border-zinc-800 pt-4 text-xs leading-relaxed text-zinc-500">
            Findings are signals for human review, not verdicts. A clean
            result means no known shape was found, not that the realm is
            safe. RealmCheck never moves funds and never calls a realm on
            your behalf.
          </p>
        </div>
      </footer>
    </div>
  );
}
