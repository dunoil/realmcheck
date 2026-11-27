// explain.js: "Explain this function" support for RealmCheck findings.
//
// extractEnclosingFunction pulls the function or method that contains a
// finding line out of the fetched realm source, client-side, so the UI
// can show the finding in context with the exact line highlighted.
// RULE_EXPLAIN holds the plain-English explanation for each rule: why
// the shape is risky, what an attacker could do with it, what to check
// before calling the realm, and the fix pattern.
//
// Plain JavaScript (not TypeScript) on purpose, like audit.js: the same
// file runs in the browser and under plain node, so the verification
// script can import it directly without a build step. No em dashes
// anywhere in this file: commas, periods, and colons only.

// cleanLine returns a copy of a line with comments and string or rune
// literal contents replaced by spaces. Positions are preserved, so
// brace counting and func detection on the result cannot be fooled by
// a brace or the word "func" sitting inside a comment or a string.
// st carries block comment and raw string state across lines.
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

function countBraces(line) {
  let depth = 0;
  for (let i = 0; i < line.length; i++) {
    if (line[i] === "{") depth++;
    else if (line[i] === "}") depth--;
  }
  return depth;
}

// parseFuncName pulls the function name out of a cleaned "func ..."
// line, including methods such as "func (r *Store) Register(...)".
// Returns null when the line is not a function declaration.
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

// extractEnclosingFunction returns the function or method that contains
// the given 1-based line, or null when the line is outside every
// function (package level code) or the inputs are invalid. The result
// is { name, startLine, endLine, lines }, where lines is the raw source
// of the whole function with 1-based numbers and isFinding set on the
// finding line. Very long functions are capped at 120 lines around the
// finding line so the card stays readable.
export function extractEnclosingFunction(source, line) {
  if (typeof source !== "string" || source === "") return null;
  if (!line || line < 1) return null;
  const raw = source.split("\n");
  if (line > raw.length) return null;
  const st = { inBlock: false, inRaw: false };
  const clean = raw.map((l) => cleanLine(l, st));

  let depth = 0;
  let cur = null;
  let seenBrace = false;
  let span = null;
  for (let i = 0; i < clean.length; i++) {
    const trimmed = clean[i].trim();
    if (cur === null && depth === 0 && trimmed.startsWith("func ")) {
      const name = parseFuncName(trimmed);
      if (name !== null) {
        cur = { name, start: i + 1, end: i + 1 };
        seenBrace = false;
      }
    }
    depth += countBraces(clean[i]);
    if (cur !== null) {
      if (clean[i].includes("{")) seenBrace = true;
      cur.end = i + 1;
      if (seenBrace && depth === 0) {
        if (line >= cur.start && line <= cur.end) span = cur;
        cur = null;
        if (span !== null) break;
      }
    }
  }
  if (span === null) return null;

  const MAX_LINES = 120;
  let start = span.start;
  let end = span.end;
  if (end - start + 1 > MAX_LINES) {
    start = Math.max(span.start, line - 40);
    end = Math.min(span.end, start + MAX_LINES - 1);
  }
  const lines = [];
  for (let n = start; n <= end; n++) {
    lines.push({ number: n, text: raw[n - 1], isFinding: n === line });
  }
  return { name: span.name, startLine: start, endLine: end, lines };
}

// RULE_EXPLAIN: plain-English explanation per rule. risk says why the
// shape is dangerous, attacker says what someone could do with it,
// check says what to verify before calling the realm, fix names the
// pattern that removes the finding.
export const RULE_EXPLAIN = {
  "RC-01": {
    risk: "This function moves funds or changes admin state, but nothing in the function checks who is calling it. On Gno.land any address can call any exported function, so a missing caller check means the function is open to everyone, not just to the owner or to a trusted realm.",
    attacker: "An attacker calls the function directly with their own address and triggers the fund movement or admin change for themselves. No special access is needed, just a normal transaction.",
    check: "Look for a caller guard at the top of the function, such as an IsUserCall check, an OriginCaller comparison against a stored owner, or an assert helper. Also check whether a wrapper function guards the call, because this rule only sees guards inside the same function.",
    fix: "Add a caller guard as the first statement, for example require cur.Previous().IsUserCall() or compare the caller against the stored owner and return an error otherwise. Keep the guard in the same function as the sensitive action.",
  },
  "RC-02": {
    risk: "This mint function creates new coins with no access control. New supply dilutes every existing holder, so an open mint is an open license to print the token.",
    attacker: "An attacker mints a huge amount to their own address, then sells it or uses it to outvote other holders. The cost is one transaction.",
    check: "Check whether minting is restricted to an owner, a minter role, or an allowlist, and whether total supply has a cap. If anyone can call Mint with any amount, the token has no scarcity.",
    fix: "Restrict Mint to an authorized minter or owner with a caller guard, and cap total supply where the design allows it. Mint only to the caller or to an address the minter explicitly approves.",
  },
  "RC-03": {
    risk: "A single stored admin or owner address can drain funds from this realm, and the drain path has no timelock or multi-signature check. The whole treasury depends on one key staying honest and uncompromised.",
    attacker: "Whoever controls the admin key, or steals it, empties the treasury in a single transaction. There is no delay to notice the theft and no second approver to stop it.",
    check: "Check who holds the admin key, whether it is a single person or a shared wallet, and whether any timelock, spending cap, or second approval constrains the drain. A drain that only checks 'is the caller the admin' is still one key away from empty.",
    fix: "Put the drain behind a timelock, a multi-signature threshold, or a per-call spending cap, so no single key can move everything at once. Prefer a multi-signature wallet as the admin.",
  },
  "RC-04": {
    risk: "This function appends to a persistent collection with no length check or cap. Every call permanently grows on-chain state, and on Gno.land storage is paid for, so the deposit grows without bound.",
    attacker: "An attacker spams the function with entries, bloating state and raising storage costs for everyone who uses the realm. In the worst case the realm becomes too expensive to use at all.",
    check: "Check whether the collection has a maximum size, a per-user quota, or pruning of old entries. If none exists, the list grows forever.",
    fix: "Add a maximum size and reject entries past it, cap entry size, add a per-user quota, or prune old entries. Check len() before appending.",
  },
  "RC-05": {
    risk: "This function reads the coins sent with the transaction but never verifies the amount. It credits something, a deposit, chips, or a purchase, based on a claimed amount rather than on coins that actually arrived.",
    attacker: "An attacker claims a deposit or purchase without sending any coins and still gets credited. The realm hands out value for free.",
    check: "Check whether the function reads the sent coins with OriginSend and compares the amount against the expected price or minimum, for example with AmountOf or an IsGTE comparison. A credit that never looks at the sent amount is unverified.",
    fix: "Read the sent coins with OriginSend, verify the amount with AmountOf or an IsGTE comparison against the expected price, and only credit after the check passes.",
  },
  "RC-06": {
    risk: "This function derives a random outcome from block height, block time, or time.Now. Those values are public before the transaction runs, and partly predictable, so the outcome is not random to someone who looks.",
    attacker: "An attacker reads the block height and time, computes the winning number in advance, and only bets when they know they will win. Or they read the winning number directly if the draw function is exported.",
    check: "Check where the random value comes from. If it is block height, block time, or time.Now combined with modulo, anyone can reproduce it off chain before betting.",
    fix: "Use a commit-reveal scheme, where players commit to a hidden choice and reveal it later, or an external verifiable randomness source. Never derive a payout from public block values alone.",
  },
  "RC-07": {
    risk: "This function calls another realm and ignores the result. If the other realm fails, this realm carries on as if the call succeeded, so state and reality drift apart.",
    attacker: "An attacker, or just an unlucky failure in the other realm, leaves this realm recording a payment or bonus that never happened. The false record can then be used to claim funds or rewards twice.",
    check: "Check whether the return value of the cross-realm call is captured and whether the error is handled. A bare call, or an error discarded with _ =, means failures pass silently.",
    fix: "Capture the return value, check the error, and return it or roll back the local state change when the call fails. Never record success before the call succeeds.",
  },
  "RC-08": {
    risk: "This exported function rewrites realm state with no caller guard at all. Anyone can change the stored data, not just the owner or an authorized caller.",
    attacker: "An attacker calls the function directly and overwrites stored values, deletes records, or sets fields that control later payouts. The realm's state becomes whatever the attacker wants it to be.",
    check: "Check whether the function has any caller guard, and whether the state it writes affects funds, ownership, or access control. Also check whether the function should be exported at all.",
    fix: "Add a caller guard in the same function, or make the function non-exported when only other realm code should call it.",
  },
};

// explainRule returns the plain-English explanation for a rule ID, or
// a generic fallback for unknown IDs.
export function explainRule(ruleID) {
  const entry = RULE_EXPLAIN[ruleID];
  if (entry) return { ruleID, ...entry };
  return {
    ruleID,
    risk: "This finding flags a risky code shape that a human should review before trusting the realm.",
    attacker: "The exact abuse depends on what the flagged code does. Read the function source below and trace what an arbitrary caller could trigger.",
    check: "Read the enclosing function and check whether a caller guard, an amount check, or a cap already covers the flagged line.",
    fix: "Add the missing guard, check, or cap in the same function, then re-run the audit to confirm the finding is gone.",
  };
}
