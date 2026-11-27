// audit.js: JavaScript port of the RealmCheck audit-rules package.
//
// It must produce the same findings as Audit() in
// contracts/auditrules/ (auditrules.gno and rules.gno). The port is
// line-based string scanning, exactly like the Gno original: it blanks
// comments and string contents, tracks function spans and brace depth,
// and looks for known risky shapes. Findings are signals for human
// review, not verdicts.
//
// Plain JavaScript (not TypeScript) on purpose: the same file runs in
// the browser and under plain node, so the port test script can import
// it directly without a build step.

export const MAX_SOURCE_BYTES = 262144;
export const MAX_LINES = 20000;
export const MAX_FINDINGS = 256;

export const SEVERITY_WEIGHTS = {
  critical: 25,
  high: 15,
  medium: 8,
  low: 3,
};

export const RULES = [
  {
    id: "RC-01",
    name: "Sensitive function without caller check",
    severity: "high",
    description:
      "An exported function moves funds or changes admin state but contains no caller guard such as IsUser, IsRealm, OriginCaller, or an owner check. Any caller can invoke it.",
  },
  {
    id: "RC-02",
    name: "Unrestricted mint",
    severity: "critical",
    description:
      "A mint function issues coins or grows supply with no access control. Anyone can mint new tokens.",
  },
  {
    id: "RC-03",
    name: "Single admin backdoor",
    severity: "critical",
    description:
      "A single stored or hard-coded admin or owner address can drain funds or rewrite state, and the path has no timelock or multi-signature check. One key controls the funds.",
  },
  {
    id: "RC-04",
    name: "Unbounded storage growth",
    severity: "medium",
    description:
      "A persistent collection is appended to with no length check or cap in the same function. Storage, and the deposit that pays for it, can grow without bound.",
  },
  {
    id: "RC-05",
    name: "Funds accepted without a check",
    severity: "high",
    description:
      "A function reads coins sent with the transaction through OriginSend but never verifies the sender amount with AmountOf, IsGTE, IsEqual, or an equivalent check.",
  },
  {
    id: "RC-06",
    name: "Weak randomness",
    severity: "medium",
    description:
      "Block height, block time, or time.Now is used with modulo or a random call to pick a winner or outcome. Block values are public and partly miner or proposer influenced, so the outcome is predictable.",
  },
  {
    id: "RC-07",
    name: "Unchecked external realm call",
    severity: "medium",
    description:
      "A cross-realm call is made as a bare statement and its return value or failure is ignored. A failed call in another realm can pass silently.",
  },
  {
    id: "RC-08",
    name: "Public state mutation without guard",
    severity: "high",
    description:
      "An exported function mutates realm state with no caller guard at all. Anyone can rewrite that state.",
  },
];

export function ruleByID(id) {
  return RULES.find((r) => r.id === id) || null;
}

export function severityWeight(severity) {
  return SEVERITY_WEIGHTS[severity] || 0;
}

// Score turns findings into a 0 to 100 risk score. 100 means no findings.
export function score(findings) {
  let s = 100;
  for (const f of findings) s -= severityWeight(f.severity);
  return s < 0 ? 0 : s;
}

const GUARD_TOKENS = [
  "IsUserCall", "IsUserRun", "IsUser(", "IsRealm(", "OriginCaller",
  "AssertOriginCall", "PreviousRealm", "AssertCaller", "IsCurrent(",
  "OnlyOwner", "AssertOwner", "RequireOwner", "MustBeOwner",
  "CheckOwner", "AssertAuthorized", "RequireAdmin", "AssertAdmin",
  "IsAdmin(", "IsOwner(", "Authorized",
  "assert", "Assert",
  "owner ==", "owner !=", "admin ==", "admin !=",
  "Owner ==", "Owner !=", "Admin ==", "Admin !=",
  "caller ==", "caller !=",
];

const TIMELOCK_TOKENS = [
  "Timelock", "timelock", "TimeLock", "UnlockTime", "unlockTime",
  "ExecuteAfter", "executeAfter", "MinDelay", "minDelay",
  "TooEarly", "tooEarly", "NotYet", "Scheduled", "scheduled",
];

const MULTISIG_TOKENS = [
  "MultiSig", "multisig", "Threshold", "threshold",
  "Approvals", "approvals", "Confirmations", "confirmations",
  "Signers", "signers",
];

function countBraces(line) {
  let depth = 0;
  for (let i = 0; i < line.length; i++) {
    if (line[i] === "{") depth++;
    else if (line[i] === "}") depth--;
  }
  return depth;
}

function isExported(name) {
  return name.length > 0 && name[0] >= "A" && name[0] <= "Z";
}

function parseFuncName(trimmed) {
  let rest = trimmed.slice("func ".length).trim();
  if (rest.startsWith("(")) {
    const idx = rest.indexOf(")");
    if (idx < 0) return null;
    rest = rest.slice(idx + 1).trim();
  }
  const end = rest.indexOf("(");
  if (end < 0) return null;
  const name = rest.slice(0, end).trim();
  return name === "" ? null : name;
}

// parseFuncReceiver extracts the receiver variable name and type name
// from a trimmed line that starts with "func (", or "" and "" for a plain
// function. The type is the last field inside the receiver parens, with a
// leading * stripped and a package qualifier removed, so
// (ps *Proposals) yields variable ps and type Proposals. An unnamed
// receiver yields "" for the variable name.
function parseFuncReceiver(trimmed) {
  let rest = trimmed.slice("func ".length).trim();
  if (!rest.startsWith("(")) return ["", ""];
  const idx = rest.indexOf(")");
  if (idx < 0) return ["", ""];
  const inner = rest.slice(1, idx).trim();
  if (inner === "") return ["", ""];
  const fields = inner.split(/\s+/);
  let typ = fields[fields.length - 1];
  if (typ.startsWith("*")) typ = typ.slice(1);
  const dot = typ.lastIndexOf(".");
  if (dot >= 0) typ = typ.slice(dot + 1);
  if (fields.length === 1) return ["", typ];
  return [fields[0], typ];
}

const BUILTIN_TYPE_NAMES = new Set([
  "int", "int8", "int16", "int32", "int64",
  "uint", "uint8", "uint16", "uint32", "uint64",
  "string", "bool", "byte", "rune",
  "float32", "float64", "error", "address",
  "realm", "any",
]);

// parseFuncParams extracts the parameter names of the function declared
// on trimmed, in order. It returns [] for a multi-line signature, whose
// closing paren is not on this line, and for a function with no named
// parameters. Grouped names (a, b int) and variadic parameters are
// handled; unnamed parameters are skipped. A single-word part that starts
// with an uppercase letter is a type name, not a parameter name, so an
// unnamed parameter of a named type is skipped too.
function parseFuncParams(trimmed) {
  let rest = trimmed.slice("func ".length).trim();
  if (rest.startsWith("(")) {
    const idx = rest.indexOf(")");
    if (idx < 0) return [];
    rest = rest.slice(idx + 1).trim();
  }
  const open = rest.indexOf("(");
  if (open < 0) return [];
  let depth = 0;
  let close = -1;
  for (let i = open; i < rest.length; i++) {
    if (rest[i] === "(") depth++;
    else if (rest[i] === ")") {
      depth--;
      if (depth === 0) {
        close = i;
        break;
      }
    }
  }
  if (close < 0) return [];
  const inner = rest.slice(open + 1, close);
  if (inner.trim() === "") return [];
  const params = [];
  for (const part of splitTopLevel(inner, ",")) {
    const fields = part.trim().split(/\s+/).filter((f) => f !== "");
    if (fields.length === 0) continue;
    let name = fields[0];
    if (name.startsWith("*")) name = name.slice(1);
    if (fields.length === 1) {
      if (BUILTIN_TYPE_NAMES.has(name)) continue;
      if (name.length > 0 && name[0] >= "A" && name[0] <= "Z") continue;
    }
    params.push(name);
  }
  return params;
}

// splitTopLevel splits s on sep, ignoring separators nested inside
// parentheses.
function splitTopLevel(s, sep) {
  const out = [];
  let depth = 0;
  let start = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === "(") depth++;
    else if (s[i] === ")") depth--;
    else if (s[i] === sep && depth === 0) {
      out.push(s.slice(start, i));
      start = i + 1;
    }
  }
  out.push(s.slice(start));
  return out;
}

function isIdentStart(c) {
  return c === "_" || (c >= "a" && c <= "z") || (c >= "A" && c <= "Z");
}

function isIdentChar(c) {
  return isIdentStart(c) || (c >= "0" && c <= "9");
}

// cleanLine returns a copy of line with comments and string or rune
// literal contents replaced by spaces. Positions are preserved, so
// brace counting and keyword search on the result cannot be fooled by
// a keyword sitting inside a comment or a string literal. st carries
// block comment and raw string state across lines.
function cleanLine(line, st) {
  const out = line.split("");
  let i = 0;
  while (i < out.length) {
    if (st.inRaw) {
      if (out[i] === "`") st.inRaw = false;
      else out[i] = " ";
      i++;
      continue;
    }
    if (st.inBlock) {
      if (out[i] === "*" && i + 1 < out.length && out[i + 1] === "/") {
        out[i] = " ";
        out[i + 1] = " ";
        st.inBlock = false;
        i += 2;
        continue;
      }
      out[i] = " ";
      i++;
      continue;
    }
    const c = out[i];
    if (c === "`") {
      st.inRaw = true;
      out[i] = " ";
      i++;
      continue;
    }
    if (c === '"') {
      out[i] = " ";
      i++;
      while (i < out.length) {
        if (out[i] === "\\") {
          out[i] = " ";
          if (i + 1 < out.length) out[i + 1] = " ";
          i += 2;
          continue;
        }
        if (out[i] === '"') {
          out[i] = " ";
          i++;
          break;
        }
        out[i] = " ";
        i++;
      }
      continue;
    }
    if (c === "'") {
      out[i] = " ";
      i++;
      while (i < out.length) {
        if (out[i] === "\\") {
          out[i] = " ";
          if (i + 1 < out.length) out[i + 1] = " ";
          i += 2;
          continue;
        }
        if (out[i] === "'") {
          out[i] = " ";
          i++;
          break;
        }
        out[i] = " ";
        i++;
      }
      continue;
    }
    if (c === "/" && i + 1 < out.length && out[i + 1] === "/") {
      for (; i < out.length; i++) out[i] = " ";
      break;
    }
    if (c === "/" && i + 1 < out.length && out[i + 1] === "*") {
      out[i] = " ";
      out[i + 1] = " ";
      st.inBlock = true;
      i += 2;
      continue;
    }
    i++;
  }
  return out.join("");
}

function parseSource(src) {
  if (src.length > MAX_SOURCE_BYTES) src = src.slice(0, MAX_SOURCE_BYTES);
  let raw = src.split("\n");
  if (raw.length > MAX_LINES) raw = raw.slice(0, MAX_LINES);
  const ps = {
    raw,
    clean: new Array(raw.length),
    funcs: [],
    pkgVars: [],
    adminVars: [],
    adminConsts: [],
    adminAddrLine: 0,
  };
  const st = { inBlock: false, inRaw: false };
  for (let i = 0; i < raw.length; i++) {
    ps.clean[i] = cleanLine(raw[i], st);
  }
  scanStructure(ps);
  return ps;
}

function addPkgVar(ps, fields, rawLine) {
  if (fields.length < 2) return;
  let name = fields[1].replace(/,$/, "");
  if (name === "") return;
  ps.pkgVars.push(name);
  const lower = name.toLowerCase();
  if (lower.includes("admin") || lower.includes("owner")) {
    ps.adminVars.push(name);
    // A hard-coded admin constant is an admin or owner name initialized
    // with an address literal on the raw line: the cleaned line cannot
    // show it, because string contents are blanked before scanning.
    if (rawLine.includes('"g1')) {
      ps.adminConsts.push(name);
    }
  }
}

function scanStructure(ps) {
  let depth = 0;
  let curIdx = -1;
  let seenBrace = false;
  let inDeclBlock = false;
  for (let i = 0; i < ps.clean.length; i++) {
    const trimmed = ps.clean[i].trim();
    const before = depth;
    if (curIdx === -1 && before === 0) {
      if (trimmed.startsWith("func ")) {
        const name = parseFuncName(trimmed);
        if (name !== null) {
          const [receiverVar, receiver] = parseFuncReceiver(trimmed);
          const params = parseFuncParams(trimmed);
          ps.funcs.push({
            name,
            start: i + 1,
            end: i + 1,
            receiver,
            receiverVar,
            params,
            tainted: new Array(params.length).fill(false),
            // A method on an unexported type is only reachable from the
            // realm's own code, even when the method name is exported,
            // so it counts as non-exported for the access control
            // rules. Note that a capitalized type name is exported by
            // this test: gov/dao Proposals is capitalized, so its
            // methods stay exported here, and RC-08 clears them instead
            // because their mutations target only the receiver.
            exported: isExported(name) && (receiver === "" || isExported(receiver)),
          });
          curIdx = ps.funcs.length - 1;
          seenBrace = false;
        }
      } else if (trimmed.startsWith("var (") || trimmed.startsWith("const (")) {
        inDeclBlock = true;
      } else if (inDeclBlock) {
        if (trimmed.startsWith(")")) inDeclBlock = false;
        else {
          // Inside a var or const block the name is the first field,
          // not the second, so prepend a marker to keep addPkgVar's
          // field positions.
          addPkgVar(ps, ["var", ...trimmed.split(/\s+/)], ps.raw[i]);
        }
      } else if (trimmed.startsWith("var ") || trimmed.startsWith("const ")) {
        addPkgVar(ps, trimmed.split(/\s+/), ps.raw[i]);
      }
      // The address literal lives inside a string, and string contents
      // are blanked on the cleaned line, so this check must read the raw
      // line.
      const lowerRaw = ps.raw[i].toLowerCase();
      if (
        lowerRaw.includes("g1") &&
        (lowerRaw.includes("admin") || lowerRaw.includes("owner"))
      ) {
        if (ps.adminAddrLine === 0) ps.adminAddrLine = i + 1;
      }
    }
    depth += countBraces(ps.clean[i]);
    if (curIdx >= 0) {
      if (ps.clean[i].includes("{")) seenBrace = true;
      ps.funcs[curIdx].end = i + 1;
      if (seenBrace && depth === 0) curIdx = -1;
    }
  }
}

// bodyLine returns the cleaned text of line i that belongs to the
// function body. On the signature line only the text after the opening
// brace counts, so the function name itself can never match an action
// token such as Withdraw, while a single-line function still scans its
// body. When the brace opens on a later line, the signature line
// contributes nothing.
function bodyLine(ps, fn, i) {
  const line = ps.clean[i];
  if (i === fn.start - 1) {
    const idx = line.indexOf("{");
    if (idx >= 0) return line.slice(idx + 1);
    return "";
  }
  return line;
}

function firstLineWith(ps, fn, tokens) {
  for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
    for (const tok of tokens) {
      if (bodyLine(ps, fn, i).includes(tok)) return i + 1;
    }
  }
  return 0;
}

function bodyHasAny(ps, fn, tokens) {
  return firstLineWith(ps, fn, tokens) !== 0;
}

function lineAssignsPkgVar(ps, line) {
  const trimmed = line.trim();
  for (const v of ps.pkgVars) {
    if (
      trimmed.startsWith(v + " =") ||
      trimmed.startsWith(v + " :=") ||
      trimmed.startsWith(v + " +=") ||
      trimmed.startsWith(v + " -=")
    ) {
      return true;
    }
  }
  return false;
}

function containsAny(line, tokens) {
  return tokens.some((tok) => line.includes(tok));
}

function newFinding(rule, line, rawLine, desc) {
  return {
    ruleID: rule.id,
    severity: rule.severity,
    title: rule.name,
    description: desc,
    file: "",
    line,
    sourceLine: rawLine.trim(),
  };
}

function checkNoCallerGuard(ps) {
  const rule = ruleByID("RC-01");
  const actions = [
    "SendCoins", "RemoveCoin", "TransferOwnership",
    "SetOwner", "SetAdmin", "ChangeOwner", "ChangeAdmin",
    "Withdraw", "Transfer(",
  ];
  const out = [];
  for (const fn of ps.funcs) {
    if (!fn.exported) continue;
    if (fn.name.includes("Mint")) continue;
    if (bodyHasAny(ps, fn, GUARD_TOKENS)) continue;
    const line = firstLineWith(ps, fn, actions);
    if (line === 0) continue;
    const desc =
      `Function ${fn.name} moves funds or changes admin state but contains no caller check in its own body. Add a guard such as cur.Previous().IsUserCall(), an OriginCaller comparison against the stored owner, or an AssertOwner call before the sensitive action. A guard in a wrapper function does not count for this check.`;
    out.push(newFinding(rule, line, ps.raw[line - 1], desc));
  }
  return out;
}

function checkUnrestrictedMint(ps) {
  const rule = ruleByID("RC-02");
  const mintEvidence = ["IssueCoin", "Supply", "balances", "Balance"];
  const out = [];
  for (const fn of ps.funcs) {
    if (!fn.exported) continue;
    if (!fn.name.includes("Mint")) continue;
    if (bodyHasAny(ps, fn, GUARD_TOKENS)) continue;
    if (!bodyHasAny(ps, fn, mintEvidence)) continue;
    const desc =
      `Function ${fn.name} mints new coins with no caller check in its own body. Restrict minting to an authorized minter or owner, and cap total supply where the design allows it. A guard in a wrapper function does not count for this check.`;
    out.push(newFinding(rule, fn.start, ps.raw[fn.start - 1], desc));
  }
  return out;
}

function checkAdminBackdoor(ps) {
  const rule = ruleByID("RC-03");
  const drain = ["SendCoins", "Withdraw"];
  const adminMention = ["admin", "Admin", "owner", "Owner"];
  const out = [];
  for (const fn of ps.funcs) {
    if (!fn.exported) continue;
    if (bodyHasAny(ps, fn, TIMELOCK_TOKENS) || bodyHasAny(ps, fn, MULTISIG_TOKENS)) continue;
    let line = 0;
    if (ps.adminVars.length > 0) {
      const l = firstLineWith(ps, fn, drain);
      if (l !== 0 && bodyHasAny(ps, fn, adminMention)) line = l;
    }
    if (line === 0 && ps.adminConsts.length > 0) {
      line = firstHardcodedAdminDrain(ps, fn);
    }
    if (line === 0) continue;
    const desc =
      `Function ${fn.name} lets a single stored or hard-coded admin or owner drain funds or rewrite state, with no timelock or multi-signature check on the path. Consider a timelock, a multi-signature threshold, or a capped withdrawal before deploying with real funds.`;
    out.push(newFinding(rule, line, ps.raw[line - 1], desc));
  }
  return out;
}

// firstHardcodedAdminDrain returns the line of the first drain or
// persistent state rewrite in fn, when fn compares a value against a
// hard-coded admin or owner constant, or 0 otherwise. A drain is a
// SendCoins or Withdraw call. A rewrite is an assignment to a
// package-level variable or a Set, Delete, or Remove call. Append lines
// are skipped: unbounded appends belong to RC-04, not to this rule.
function firstHardcodedAdminDrain(ps, fn) {
  let guarded = false;
  for (const name of ps.adminConsts) {
    if (bodyComparesAgainst(ps, fn, name)) {
      guarded = true;
      break;
    }
  }
  if (!guarded) return 0;
  const drain = ["SendCoins", "Withdraw"];
  const line = firstLineWith(ps, fn, drain);
  if (line !== 0) return line;
  const mutateTokens = [".Set(", ".Delete(", ".Remove("];
  for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
    const line = bodyLine(ps, fn, i);
    if (line.includes("append(")) continue;
    if (containsAny(line, mutateTokens)) return i + 1;
    if (lineAssignsPkgVar(ps, line)) return i + 1;
  }
  return 0;
}

// bodyComparesAgainst reports whether any line of fn compares a value
// against name with == or !=, the shape of a guard such as
// caller != Admin.
function bodyComparesAgainst(ps, fn, name) {
  for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
    const line = bodyLine(ps, fn, i);
    if (!line.includes(name)) continue;
    if (line.includes("==") || line.includes("!=")) return true;
  }
  return false;
}

function appendTarget(line) {
  const idx = line.indexOf("append(");
  if (idx < 0) return "";
  const rest = line.slice(idx + "append(".length);
  const comma = rest.indexOf(",");
  if (comma < 0) return "";
  return rest.slice(0, comma).trim();
}

function isPersistentTarget(ps, target) {
  for (const v of ps.pkgVars) {
    if (target === v) return true;
  }
  return target.includes(".");
}

function checkUnboundedStorage(ps) {
  const rule = ruleByID("RC-04");
  const capTokens = ["len(", "Max", "Limit", "limit"];
  const out = [];
  for (const fn of ps.funcs) {
    if (bodyHasAny(ps, fn, capTokens)) continue;
    for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
      const line = bodyLine(ps, fn, i);
      if (!line.includes("append(")) continue;
      const target = appendTarget(line);
      if (target === "") continue;
      if (!isPersistentTarget(ps, target)) continue;
      const desc =
        `Function ${fn.name} appends to persistent collection ${target} with no length check or cap in the same function. Add a maximum size and reject or prune entries past it, or the storage deposit grows without bound.`;
      out.push(newFinding(rule, i + 1, ps.raw[i], desc));
      break;
    }
  }
  return out;
}

function checkFundsWithoutCheck(ps) {
  const rule = ruleByID("RC-05");
  const verifyTokens = [
    "AmountOf", "IsGTE", "IsEqual", "IsPositive", "IsZero",
    "GetCoin", "IsNegative",
  ];
  const out = [];
  for (const fn of ps.funcs) {
    const line = firstLineWith(ps, fn, ["OriginSend"]);
    if (line === 0) continue;
    if (bodyHasAny(ps, fn, verifyTokens)) continue;
    const desc =
      `Function ${fn.name} reads coins sent with the transaction through OriginSend but never verifies the amount. Check the received amount against the expected price or minimum with AmountOf or an IsGTE comparison before crediting anything.`;
    out.push(newFinding(rule, line, ps.raw[line - 1], desc));
  }
  return out;
}

function checkWeakRandomness(ps) {
  const rule = ruleByID("RC-06");
  const sources = [
    "ChainHeight", "BlockHeight", "blockHeight",
    "ChainTime", "BlockTime", "blockTime",
    "time.Now", "UnixNano", "Unix()",
  ];
  const use = ["%", "rand", "Random", "Seed"];
  computeTaint(ps, sources);
  const out = [];
  for (const fn of ps.funcs) {
    for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
      const line = bodyLine(ps, fn, i);
      const direct = containsAny(line, sources) && containsAny(line, use);
      let tainted = false;
      if (!direct) tainted = lineUsesTaintedParam(ps, fn, line, use);
      if (!direct && !tainted) continue;
      let desc;
      if (direct) {
        desc =
          `Function ${fn.name} derives a random outcome from block height, block time, or time.Now. These values are public and partly predictable, so the outcome can be anticipated. Use a commit-reveal scheme or an external verifiable randomness source instead.`;
      } else {
        desc =
          `Function ${fn.name} receives block height, block time, or time.Now as a parameter and applies modulo or a random call to it. The caller passes a public, partly predictable value, so the outcome can be anticipated. Use a commit-reveal scheme or an external verifiable randomness source instead.`;
      }
      out.push(newFinding(rule, i + 1, ps.raw[i], desc));
      break;
    }
  }
  return out;
}

// computeTaint marks, for every function, which of its parameters receive
// a randomness source, directly as a call argument or transitively
// through another tainted parameter. It runs to a fixed point, capped at
// eight passes, so it always terminates. A call is only tracked when its
// callee is defined in the same audited source; calls into other files or
// packages are not followed.
function computeTaint(ps, sources) {
  const byName = new Map();
  for (let i = 0; i < ps.funcs.length; i++) {
    if (!byName.has(ps.funcs[i].name)) byName.set(ps.funcs[i].name, i);
  }
  for (let pass = 0; pass < 8; pass++) {
    let changed = false;
    for (const fn of ps.funcs) {
      for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
        const line = bodyLine(ps, fn, i);
        if (!line.includes("(")) continue;
        for (const call of findCalls(line, byName)) {
          const ci = byName.get(call.name);
          for (let j = 0; j < call.args.length; j++) {
            if (j >= ps.funcs[ci].params.length) break;
            if (ps.funcs[ci].tainted[j]) continue;
            if (containsAny(call.args[j], sources) || argUsesTaintedParam(ps, fn, call.args[j])) {
              ps.funcs[ci].tainted[j] = true;
              changed = true;
            }
          }
        }
      }
    }
    if (!changed) break;
  }
}

// findCalls extracts the calls on line whose callee is a function defined
// in the audited source. Candidate names are the identifiers immediately
// followed by "(", looked up in the defined function names.
function findCalls(line, byName) {
  const out = [];
  for (let i = 0; i < line.length; i++) {
    if (!isIdentStart(line[i])) continue;
    let j = i;
    while (j < line.length && isIdentChar(line[j])) j++;
    const name = line.slice(i, j);
    if (j >= line.length || line[j] !== "(") {
      i = j;
      continue;
    }
    if (!byName.has(name)) {
      i = j;
      continue;
    }
    const parsed = parseCallArgs(line, j);
    if (parsed === null) {
      i = j;
      continue;
    }
    out.push({ name, args: parsed.args });
    i = parsed.end;
  }
  return out;
}

// parseCallArgs parses the argument list starting at the "(" at pos in
// line, returning the argument texts and the index just past the matching
// ")", or null when the call is not closed on this line.
function parseCallArgs(line, pos) {
  let depth = 0;
  for (let i = pos; i < line.length; i++) {
    if (line[i] === "(") depth++;
    else if (line[i] === ")") {
      depth--;
      if (depth === 0) {
        const inner = line.slice(pos + 1, i);
        if (inner.trim() === "") return { args: [], end: i + 1 };
        return { args: splitTopLevel(inner, ","), end: i + 1 };
      }
    }
  }
  return null;
}

// argUsesTaintedParam reports whether arg mentions, as a whole
// identifier, one of fn's tainted parameters.
function argUsesTaintedParam(ps, fn, arg) {
  for (let k = 0; k < fn.params.length; k++) {
    if (k < fn.tainted.length && fn.tainted[k] && lineHasIdent(arg, fn.params[k])) {
      return true;
    }
  }
  return false;
}

// lineUsesTaintedParam reports whether line applies a randomness use
// (modulo or a random call) to one of fn's tainted parameters.
function lineUsesTaintedParam(ps, fn, line, use) {
  if (!containsAny(line, use)) return false;
  for (let k = 0; k < fn.params.length; k++) {
    if (k < fn.tainted.length && fn.tainted[k] && lineHasIdent(line, fn.params[k])) {
      return true;
    }
  }
  return false;
}

// lineHasIdent reports whether name appears in line as a whole
// identifier, bounded by characters that cannot be part of an identifier.
function lineHasIdent(line, name) {
  if (name === "") return false;
  for (let i = 0; i + name.length <= line.length; i++) {
    if (line.slice(i, i + name.length) !== name) continue;
    if (i > 0 && isIdentChar(line[i - 1])) continue;
    const after = i + name.length;
    if (after < line.length && isIdentChar(line[after])) continue;
    return true;
  }
  return false;
}

function checkUncheckedCall(ps) {
  const rule = ruleByID("RC-07");
  const out = [];
  for (const fn of ps.funcs) {
    for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
      const line = bodyLine(ps, fn, i);
      if (!line.includes("cross(")) continue;
      const trimmed = line.trim();
      if (trimmed.startsWith("if ") || trimmed.startsWith("return ")) continue;
      if (line.includes("=") || line.includes("err")) continue;
      const desc =
        `Function ${fn.name} calls another realm through cross() as a bare statement and ignores the result. Capture the return value and handle the error, or a failure in the other realm passes silently.`;
      out.push(newFinding(rule, i + 1, ps.raw[i], desc));
      break;
    }
  }
  return out;
}

function checkPublicMutation(ps) {
  const rule = ruleByID("RC-08");
  const skipNames = ["Mint", "Withdraw", "Transfer", "Drain"];
  const out = [];
  for (const fn of ps.funcs) {
    if (!fn.exported) continue;
    if (fn.name === "Render") continue;
    if (containsAny(fn.name, skipNames)) continue;
    if (bodyHasAny(ps, fn, GUARD_TOKENS)) continue;
    let line = 0;
    for (let i = fn.start - 1; i < fn.end && i < ps.clean.length; i++) {
      const body = bodyLine(ps, fn, i);
      if (body.includes("append(")) continue;
      if (lineHasNonReceiverMutation(ps, fn, body)) {
        line = i + 1;
        break;
      }
      if (lineAssignsPkgVar(ps, body)) {
        line = i + 1;
        break;
      }
    }
    if (line === 0) continue;
    const desc =
      `Function ${fn.name} mutates realm state but contains no caller check in its own body. Add a caller guard, or make the function non-exported when only other realm code should call it.`;
    out.push(newFinding(rule, line, ps.raw[line - 1], desc));
  }
  return out;
}

// lineHasNonReceiverMutation reports whether line calls Set, Delete, or
// Remove on anything other than the method receiver. The target is the
// identifier segment immediately before the dot, so ps.Set counts as a
// receiver call while store.Set and settings.Set do not.
function lineHasNonReceiverMutation(ps, fn, line) {
  const mutateTokens = [".Set(", ".Delete(", ".Remove("];
  for (const tok of mutateTokens) {
    let start = 0;
    for (;;) {
      const rel = line.slice(start).indexOf(tok);
      if (rel < 0) break;
      const pos = start + rel;
      if (!mutationTargetsReceiver(fn, line, pos)) return true;
      start = pos + tok.length;
    }
  }
  return false;
}

// mutationTargetsReceiver reports whether the mutate call whose dot is at
// pos in line is a call on the method receiver, such as ps.Set(. The
// target is the identifier segment immediately before the dot.
function mutationTargetsReceiver(fn, line, pos) {
  if (fn.receiverVar === "" || pos === 0) return false;
  const end = pos;
  let start = end;
  while (start > 0 && isIdentChar(line[start - 1])) start--;
  return line.slice(start, end) === fn.receiverVar;
}

function dedupeFindings(input) {
  const seen = new Set();
  const out = [];
  for (const f of input) {
    const key = `${f.ruleID}:${f.line}`;
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(f);
  }
  return out;
}

// Audit audits one realm source text and returns its findings in rule
// order, then line order. The input is capped at MaxSourceBytes.
export function audit(src) {
  return auditFile("", src);
}

// AuditFile is Audit with a file name attached to every finding, so a
// report can cite the file the line came from.
export function auditFile(file, src) {
  const ps = parseSource(src);
  let out = [];
  out = out.concat(checkNoCallerGuard(ps));
  out = out.concat(checkUnrestrictedMint(ps));
  out = out.concat(checkAdminBackdoor(ps));
  out = out.concat(checkUnboundedStorage(ps));
  out = out.concat(checkFundsWithoutCheck(ps));
  out = out.concat(checkWeakRandomness(ps));
  out = out.concat(checkUncheckedCall(ps));
  out = out.concat(checkPublicMutation(ps));
  for (const f of out) f.file = file;
  out = dedupeFindings(out);
  if (out.length > MAX_FINDINGS) out = out.slice(0, MAX_FINDINGS);
  return out;
}

// auditFiles audits several source files and merges the findings,
// deduplicated by rule, file, and line.
export function auditFiles(files) {
  let out = [];
  for (const f of files) {
    out = out.concat(auditFile(f.name, f.source));
  }
  const seen = new Set();
  const merged = [];
  for (const f of out) {
    const key = `${f.ruleID}:${f.file}:${f.line}`;
    if (seen.has(key)) continue;
    seen.add(key);
    merged.push(f);
  }
  if (merged.length > MAX_FINDINGS) return merged.slice(0, MAX_FINDINGS);
  return merged;
}
