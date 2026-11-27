import type { Finding } from "./audit.js";

export const GNO_RPC: string;
export const GNO_GNOWEB: string;
export const REALMCHECK_REALM: string;
export const ONYX_RPC: string;
export const ONYX_GNOWEB: string;

export function abciQuery(path: string, data: string): Promise<string>;
export function qfile(filepath: string): Promise<string>;
export function qeval(expr: string): Promise<string>;
export function fetchRealmFiles(
  realmPath: string,
): Promise<{ name: string; source: string }[]>;
export function sha256Hex(str: string): Promise<string>;
export function encodeFindings(findings: Finding[]): string;
export function decodeFindings(encoded: string): Finding[];
export function parsePrintedString(text: string): string;

export interface StoredReport {
  id: number;
  realmPath: string;
  sourceHash: string;
  score: number;
  auditor: string;
  height: number;
}

export function parsePrintedReport(text: string): StoredReport | null;
export function buildSubmitCommand(args: {
  realmPath: string;
  sourceHash: string;
  score: number;
  findings: Finding[];
}): string;
export function gnowebUrl(realmPath: string): string;
