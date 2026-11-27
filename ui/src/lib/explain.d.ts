export interface FunctionLine {
  number: number;
  text: string;
  isFinding: boolean;
}

export interface EnclosingFunction {
  name: string;
  startLine: number;
  endLine: number;
  lines: FunctionLine[];
}

export function extractEnclosingFunction(
  source: string,
  line: number,
): EnclosingFunction | null;

export interface RuleExplanation {
  ruleID: string;
  risk: string;
  attacker: string;
  check: string;
  fix: string;
}

export const RULE_EXPLAIN: Record<string, Omit<RuleExplanation, "ruleID">>;

export function explainRule(ruleID: string): RuleExplanation;
