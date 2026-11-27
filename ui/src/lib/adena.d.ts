import type { Finding } from "./audit.js";

export const GNO_CHAIN_ID: string;
export const ADENA_INSTALL_URL: string;
export const ADENA_EXTENSION_URL: string;

export function chainDisplayName(chainId: string): string;

export class AdenaError extends Error {
  code: string;
  constructor(code: string, message: string);
}

export function describeAdenaFailure(
  type: string,
  fallbackMessage?: string,
): string;

export function isAdenaInstalled(): boolean;

export function gasForFindings(nFindings: number): {
  gasWanted: number;
  gasFee: number;
};

export interface SubmitReportParams {
  messages: {
    type: "/vm.m_call";
    value: {
      caller: string;
      send: string;
      max_deposit: string;
      pkg_path: string;
      func: string;
      args: string[];
    };
  }[];
  gasFee: number;
  gasWanted: number;
  memo?: string;
  networkInfo?: { chainId: string; rpcUrl: string };
}

export function buildSubmitReportParams(args: {
  address: string;
  realmPath: string;
  sourceHash: string;
  score: number;
  findings: Finding[];
}): SubmitReportParams;

export interface AdenaAccount {
  address: string;
  chainId: string;
  accountNumber?: string;
  coins?: string;
}

export function connectAdena(): Promise<AdenaAccount>;

export function submitReportWithAdena(args: {
  address: string;
  realmPath: string;
  sourceHash: string;
  score: number;
  findings: Finding[];
}): Promise<{ hash: string; height: number | null }>;

export function shortAddress(address: string): string;
