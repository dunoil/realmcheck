// adena.js: Adena wallet signing for the RealmCheck save panel.
//
// Talks to the Adena browser extension directly through the injected
// `window.adena` object. No npm dependency: the official SDK
// (@adena-wallet/sdk 0.1.3, docs at https://docs.adena.app) is itself a
// thin wrapper over these same `window.adena` calls, and the UI already
// ships plain JS lib modules, so calling the extension API directly keeps
// the bundle small and the flow explicit.
//
// API verified 27 Nov 2026 from the published @adena-wallet/sdk 0.1.3
// package (README plus bin/index.d.ts and bin/index.mjs):
//   window.adena.AddEstablish(siteName, chainIds?) -> {code, status, type, message, data}
//   window.adena.GetAccount() -> data {accountNumber, address, coins, chainId, sequence, status, publicKey}
//   window.adena.GetNetwork() -> data {chainId, networkName, addressPrefix, rpcUrl, indexerUrl}
//   window.adena.SwitchNetwork(chainId) -> data {chainId}; type SWITCH_NETWORK_SUCCESS,
//     REDUNDANT_CHANGE_REQUEST (already there), or UNADDED_NETWORK (add it first)
//   window.adena.AddNetwork({chainId, chainName, rpcUrl})
//   window.adena.DoContract(params) -> data BroadcastTxCommitResult {hash, height, check_tx, deliver_tx}
//     DoContract signs AND broadcasts. Success is status "success" (code 0).
//     SignTx alone only returns an encoded transaction and does not
//     broadcast, so this module does not use it.
//   TransactionParams: {messages, gasFee (number, ugnot), gasWanted (number), memo?, networkInfo?}
//   MsgCall message: {type: "/vm.m_call", value: {caller, send, max_deposit, pkg_path, func, args}}
//     (field shape from @gnolang/gno-js-client 3.1.0, MsgCall in dist/proto/gno/vm.d.mts)
//
// Gas follows docs/API.md and ui/src/lib/gnoRpc.js: gas-wanted 10,000,000
// plus 7,000,000 per finding, fee gas-wanted divided by 500 (twice the
// chain minimum of 1 ugnot per 1,000 gas).
//
// Live test status: connecting and signing against a real Adena extension
// with a funded key is NOT verified here. It needs a browser with Adena
// installed and an Onyx-funded key, which belongs to the M6 deploy phase.
// What is verified here: the module imports cleanly under node, the pure
// helpers (gas formula, params builder) match gnoRpc.js exactly, and the
// full connect plus sign flow runs under node against a stubbed
// window.adena (see M6-PREP-STATUS.md).

import { encodeFindings, GNO_RPC, REALMCHECK_REALM } from "./gnoRpc.js";

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

// Chain the UI is configured for. The Onyx default matches gnoRpc.js;
// a local dev server sets VITE_GNO_CHAIN_ID=dev next to VITE_GNO_RPC.
export const GNO_CHAIN_ID = envVar("VITE_GNO_CHAIN_ID", "onyx-1");

export const ADENA_INSTALL_URL = "https://adena.app/";

// Where to send a user who needs the extension.
export const ADENA_EXTENSION_URL =
  "https://chromewebstore.google.com/detail/adena/oefglhbffgfkcpboeackfgdagmlnihnh";

export function chainDisplayName(chainId) {
  if (chainId === "onyx-1") return "Gno.land Onyx Testnet";
  if (chainId === "dev") return "Gno.land Local Dev";
  if (chainId === "gnoland-1") return "Gno.land Mainnet";
  return `Gno.land ${chainId}`;
}

export class AdenaError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "AdenaError";
    this.code = code;
  }
}

// Human text for the wallet response types the UI can see. Unknown types
// fall through to the wallet's own message.
export function describeAdenaFailure(type, fallbackMessage) {
  switch (type) {
    case "TRANSACTION_REJECTED":
    case "SIGN_REJECTED":
    case "CONNECTION_REJECTED":
      return "You rejected the request in Adena. Nothing was sent. Try again when ready.";
    case "WALLET_LOCKED":
      return "Adena is locked. Unlock the extension and try again.";
    case "NO_ACCOUNT":
      return "Adena has no account selected. Create or select an account in the extension and try again.";
    case "UNADDED_NETWORK":
      return "This network is not added to Adena yet.";
    case "TRANSACTION_FAILED":
    case "SIGN_FAILED":
      return "Adena could not sign the transaction. Check the extension and try again.";
    case "NOT_CONNECTED":
      return "Adena is not connected to this site. Connect first, then sign.";
    default:
      return fallbackMessage || "Adena returned an error. Try again.";
  }
}

function adenaResponseError(response, what) {
  const type = response?.type || "UNKNOWN";
  const message =
    response?.message || describeAdenaFailure(type, `${what} failed.`);
  return new AdenaError(type, describeAdenaFailure(type, message));
}

function isSuccessResponse(response) {
  return (
    response &&
    (response.status === "success" || response.code === 0) &&
    response.status !== "failure"
  );
}

// True when the Adena extension is present in this browser. False under
// node, in a browser without the extension, and before the extension
// injects its object.
export function isAdenaInstalled() {
  return (
    typeof window !== "undefined" &&
    typeof window.adena !== "undefined" &&
    window.adena !== null
  );
}

function getAdena() {
  if (!isAdenaInstalled()) {
    throw new AdenaError(
      "not-installed",
      "Adena is not installed in this browser. Install it from adena.app, then try again.",
    );
  }
  return window.adena;
}

// Gas for a SubmitReport call with n findings. Identical to
// buildSubmitCommand in gnoRpc.js; keep the two in sync.
export function gasForFindings(nFindings) {
  const gasWanted = 10000000 + 7000000 * nFindings;
  return { gasWanted, gasFee: gasWanted / 500 };
}

// Builds the exact DoContract params for a SubmitReport call. Pure: safe
// to call under node and in tests. The caller address becomes the stored
// Auditor. networkInfo pins the transaction to the configured chain
// instead of whichever network the wallet currently has selected.
export function buildSubmitReportParams({
  address,
  realmPath,
  sourceHash,
  score,
  findings,
}) {
  const { gasWanted, gasFee } = gasForFindings(findings.length);
  return {
    messages: [
      {
        type: "/vm.m_call",
        value: {
          caller: address,
          send: "",
          max_deposit: "",
          pkg_path: REALMCHECK_REALM,
          func: "SubmitReport",
          args: [realmPath, sourceHash, String(score), encodeFindings(findings)],
        },
      },
    ],
    gasFee,
    gasWanted,
    memo: "RealmCheck audit report",
    networkInfo: { chainId: GNO_CHAIN_ID, rpcUrl: GNO_RPC },
  };
}

// Makes sure the wallet sits on the configured chain. Returns the network
// the wallet reports. When the chain is missing from the wallet, it is
// added from the UI config first (chain id, display name, RPC URL), then
// selected. Throws AdenaError when the user rejects a step.
async function ensureNetwork(chainId) {
  const adena = getAdena();
  const network = await adena.GetNetwork();
  if (!isSuccessResponse(network)) {
    throw adenaResponseError(network, "Reading the Adena network");
  }
  if (network.data && network.data.chainId === chainId) return network.data;
  const switched = await adena.SwitchNetwork(chainId);
  if (isSuccessResponse(switched)) return switched.data || network.data;
  if (switched?.type === "REDUNDANT_CHANGE_REQUEST") {
    return network.data;
  }
  if (switched?.type === "UNADDED_NETWORK") {
    const added = await adena.AddNetwork({
      chainId,
      chainName: chainDisplayName(chainId),
      rpcUrl: GNO_RPC,
    });
    if (!isSuccessResponse(added)) {
      throw adenaResponseError(added, "Adding the network to Adena");
    }
    const reselected = await adena.SwitchNetwork(chainId);
    if (
      !isSuccessResponse(reselected) &&
      reselected?.type !== "REDUNDANT_CHANGE_REQUEST"
    ) {
      throw adenaResponseError(reselected, "Switching the Adena network");
    }
    return reselected.data || { chainId };
  }
  throw adenaResponseError(switched, "Switching the Adena network");
}

// Connects the site to Adena and returns the connected account. The
// chain id is requested in the same approval when the extension
// supports it; when an older extension refuses the chained request,
// the call is retried as a plain site approval.
export async function connectAdena() {
  const adena = getAdena();
  let established;
  try {
    established = await adena.AddEstablish("RealmCheck", [GNO_CHAIN_ID]);
  } catch (e) {
    established = await adena.AddEstablish("RealmCheck");
  }
  if (
    !isSuccessResponse(established) &&
    established?.type !== "ALREADY_CONNECTED"
  ) {
    throw adenaResponseError(established, "Connecting to Adena");
  }
  const account = await adena.GetAccount();
  if (!isSuccessResponse(account) || !account.data?.address) {
    throw adenaResponseError(account, "Reading the Adena account");
  }
  const network = await ensureNetwork(GNO_CHAIN_ID);
  return {
    address: account.data.address,
    chainId: network?.chainId || account.data.chainId || GNO_CHAIN_ID,
    accountNumber: account.data.accountNumber,
    coins: account.data.coins,
  };
}

// Signs and broadcasts a SubmitReport call through Adena and returns the
// transaction hash and height. The caller must already be connected (see
// connectAdena); the address passed here is the MsgCall caller.
export async function submitReportWithAdena({
  address,
  realmPath,
  sourceHash,
  score,
  findings,
}) {
  if (!address) {
    throw new AdenaError(
      "no-address",
      "No Adena address is connected. Connect Adena first, then sign.",
    );
  }
  const adena = getAdena();
  const params = buildSubmitReportParams({
    address,
    realmPath,
    sourceHash,
    score,
    findings,
  });
  const response = await adena.DoContract(params);
  if (!isSuccessResponse(response)) {
    throw adenaResponseError(response, "Signing the report");
  }
  const data = response.data || {};
  const hash = data.hash;
  if (!hash) {
    throw new AdenaError(
      "no-tx-hash",
      "Adena reported success but returned no transaction hash.",
    );
  }
  // A broadcast can still carry a failed delivery (for example out of
  // gas). Surface the chain log instead of reporting a success.
  const deliverError =
    data.deliver_tx?.ResponseBase?.Error ||
    data.check_tx?.ResponseBase?.Error;
  if (deliverError) {
    const log =
      (typeof deliverError === "string" ? deliverError : deliverError.log) ||
      "Transaction failed on chain.";
    throw new AdenaError("transaction-failed", `On-chain error: ${log}`);
  }
  return { hash, height: data.height ? Number(data.height) : null };
}

export function shortAddress(address) {
  if (!address || address.length <= 14) return address || "";
  return `${address.slice(0, 8)}...${address.slice(-4)}`;
}
