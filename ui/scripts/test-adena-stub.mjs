// test-adena-stub.mjs: drives ui/src/lib/adena.js against a stubbed
// window.adena (no real extension, no funded key). Verifies the
// connect flow, the SubmitReport params shape, the gas formula parity
// with gnoRpc.js buildSubmitCommand, and the submit result handling.
// Run from ui/: node scripts/test-adena-stub.mjs
// Exit 0 when every check passes. Added by the coordinator during the
// M6-prep verification, 27 Nov 2026, so the stub check is re-runnable.

import { strict as assert } from "node:assert";
import {
  buildSubmitReportParams,
  connectAdena,
  gasForFindings,
  isAdenaInstalled,
  submitReportWithAdena,
} from "../src/lib/adena.js";
import { buildSubmitCommand } from "../src/lib/gnoRpc.js";

const ADDRESS = "g1testtesttesttesttesttesttesttesttesttesttest";

globalThis.window = {
  adena: {
    AddEstablish: async () => ({ code: 0 }),
    GetAccount: async () => ({
      code: 0,
      data: { address: ADDRESS, chainId: "onyx-1", status: "active" },
    }),
    GetNetwork: async () => ({ code: 0, data: { chainId: "onyx-1" } }),
    DoContract: async (params) => {
      globalThis.__lastParams = params;
      return {
        code: 0,
        data: {
          hash: "ABCDEF123456",
          height: 99,
          check_tx: {},
          deliver_tx: { code: 0 },
        },
      };
    },
  },
};

assert.equal(isAdenaInstalled(), true, "adena should be detected");

const conn = await connectAdena();
assert.equal(conn.address, ADDRESS, "connected address");
assert.equal(conn.chainId, "onyx-1", "connected chain");

const findings = [
  {
    ruleID: "RC-02",
    severity: "critical",
    line: 41,
    title: "Unrestricted mint",
    description: "d",
    sourceLine: "func Mint() {",
  },
];
const args = {
  address: ADDRESS,
  realmPath: "gno.land/r/dunoil/vulnmint",
  sourceHash: "ab".repeat(32),
  score: 75,
  findings,
};
const params = buildSubmitReportParams(args);
assert.equal(params.messages[0].type, "/vm.m_call", "message type");
assert.equal(params.messages[0].value.func, "SubmitReport", "function");
assert.equal(
  params.messages[0].value.pkg_path,
  "gno.land/r/dunoil/realmcheck",
  "report realm",
);
assert.equal(
  params.messages[0].value.caller,
  ADDRESS,
  "caller is the connected address",
);
assert.deepEqual(
  gasForFindings(1),
  { gasWanted: 17000000, gasFee: 34000 },
  "gas for 1 finding",
);
assert.deepEqual(
  gasForFindings(4),
  { gasWanted: 38000000, gasFee: 76000 },
  "gas for 4 findings",
);

const res = await submitReportWithAdena(args);
assert.equal(res.hash, "ABCDEF123456", "submit hash");
assert.equal(res.height, 99, "submit height");

const cmd = buildSubmitCommand(args);
assert.ok(
  cmd.includes("-gas-fee 34000ugnot -gas-wanted 17000000"),
  "gas parity with buildSubmitCommand",
);

console.log("PASS adena stub: connect, params, gas parity, submit");
