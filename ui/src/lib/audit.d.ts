export interface Finding {
  ruleID: string;
  severity: "critical" | "high" | "medium" | "low";
  title: string;
  description: string;
  file: string;
  line: number;
  sourceLine: string;
}

export interface Rule {
  id: string;
  name: string;
  severity: string;
  description: string;
}

export const MAX_SOURCE_BYTES: number;
export const MAX_LINES: number;
export const MAX_FINDINGS: number;
export const SEVERITY_WEIGHTS: Record<string, number>;
export const RULES: Rule[];

export function ruleByID(id: string): Rule | null;
export function severityWeight(severity: string): number;
export function score(findings: Finding[]): number;
export function audit(src: string): Finding[];
export function auditFile(file: string, src: string): Finding[];
export function auditFiles(files: { name: string; source: string }[]): Finding[];
