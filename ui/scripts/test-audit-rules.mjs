#!/usr/bin/env node
// test-audit-rules.mjs: unit tests for the JavaScript audit port
// (src/lib/audit.js), mirroring the Gno regression tests in
// contracts/auditrules/auditrules_test.gno for the M4 rule changes.
// The port test (test-audit-port.mjs) proves the port matches Gno Audit()
// on the five demo realms; this file pins the individual rule shapes
// (hard-coded admin, parameter taint, assert* guards, receiver rules)
// directly on fixtures, so a port drift in one shape fails here first.
//
// Run from the project root: node ui/scripts/test-audit-rules.mjs
// Exit code 0 means every case passes; 1 means a mismatch.

import { audit } from "../src/lib/audit.js";

let failures = 0;
let passes = 0;

function hasRule(findings, id) {
  return findings.some((f) => f.ruleID === id);
}

function lineOf(findings, id) {
  const f = findings.find((x) => x.ruleID === id);
  return f ? f.line : 0;
}

function check(name, cond, detail = "") {
  if (cond) {
    passes += 1;
    console.log(`PASS ${name}`);
  } else {
    failures += 1;
    console.log(`FAIL ${name}${detail ? ` (${detail})` : ""}`);
  }
}

// RC-03: hard-coded admin constant guarding a ledger drain.
{
  const src = `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Drain(cur realm, to address) (int64, error) {
\tcaller := cur.Previous().Address()
\tif caller != Admin {
\t\treturn 0, errors.New("only the admin can drain the treasury")
\t}
\tamount := treasury
\ttreasury = 0
\treturn amount, nil
}
`;
  const findings = audit(src);
  check("RC-03 hardcoded admin fires", hasRule(findings, "RC-03"));
  check("RC-03 hardcoded admin line 12", lineOf(findings, "RC-03") === 12, `got ${lineOf(findings, "RC-03")}`);
  check("RC-03 hardcoded admin is the only finding", findings.length === 1, `got ${findings.length}`);
}

// RC-03: reversed guard form, still a backdoor, still guarded for RC-01/RC-08.
{
  const src = `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64

func Drain(cur realm, to address) (int64, error) {
\tcaller := cur.Previous().Address()
\tif Admin != caller {
\t\treturn 0, errors.New("only the admin can drain the treasury")
\t}
\ttreasury = 0
\treturn treasury, nil
}
`;
  const findings = audit(src);
  check("RC-03 reversed guard fires", hasRule(findings, "RC-03"));
  check("RC-03 reversed guard line 11", lineOf(findings, "RC-03") === 11, `got ${lineOf(findings, "RC-03")}`);
  check("RC-03 reversed guard is the only finding", findings.length === 1, `got ${findings.length}`);
}

// RC-03: timelock suppresses the hard-coded shape.
{
  const src = `package demo

var Admin = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
var treasury int64
var UnlockTime int64 = 9999999999

func Drain(cur realm, to address) (int64, error) {
\tcaller := cur.Previous().Address()
\tif caller != Admin {
\t\treturn 0, errors.New("only the admin can drain the treasury")
\t}
\tif runtime.ChainHeight() < UnlockTime {
\t\tpanic("timelock not expired")
\t}
\ttreasury = 0
\treturn treasury, nil
}
`;
  check("RC-03 timelock clean", !hasRule(audit(src), "RC-03"));
}

// RC-03: stored admin with capital-A mention on a banker drain.
{
  const src = `package demo

var Admin address = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

func Withdraw(cur realm, amount int64) {
\tbanker.SendCoins(cur, Admin, amount)
}
`;
  check("RC-03 capital mention fires", hasRule(audit(src), "RC-03"));
}

// RC-06: taint through parameters, one hop (luckydice shape).
{
  const src = `package demo

func DrawNumberAt(height int64, unixTime int64) int {
\treturn int((height*31 + unixTime) % 6)
}

func DrawNumber() int {
\treturn DrawNumberAt(runtime.ChainHeight(), time.Now().Unix())
}
`;
  const findings = audit(src);
  check("RC-06 taint fires", hasRule(findings, "RC-06"));
  check("RC-06 taint line 4", lineOf(findings, "RC-06") === 4, `got ${lineOf(findings, "RC-06")}`);
  check("RC-06 taint exactly once", findings.filter((f) => f.ruleID === "RC-06").length === 1);
}

// RC-06: taint through parameters, two hops.
{
  const src = `package demo

func Pick(height int64, n int) int {
\treturn int(height % int64(n))
}

func Middle(h int64, n int) int {
\treturn Pick(h, n)
}

func Start() int {
\treturn Middle(runtime.ChainHeight(), 6)
}
`;
  const findings = audit(src);
  check("RC-06 multi-hop taint fires", hasRule(findings, "RC-06"));
  check("RC-06 multi-hop taint line 4", lineOf(findings, "RC-06") === 4, `got ${lineOf(findings, "RC-06")}`);
}

// RC-06: helper does the modulo but no call site passes a source.
{
  const src = `package demo

func Pick(height int64, n int) int {
\treturn int(height % int64(n))
}

func Start() int {
\treturn Pick(10, 6)
}
`;
  check("RC-06 constant args clean", !hasRule(audit(src), "RC-06"));
}

// RC-06: sources stored in locals first are not followed (known limit).
{
  const src = `package demo

func DrawNumberAt(height int64, unixTime int64) int {
\treturn int((height*31 + unixTime) % 6)
}

func DrawNumber() int {
\th := runtime.ChainHeight()
\tt := time.Now().Unix()
\treturn DrawNumberAt(h, t)
}
`;
  check("RC-06 local-variable limit", !hasRule(audit(src), "RC-06"));
}

// assert* helper calls count as guards for RC-01 and RC-08.
{
  const src = `package demo

func assertDelegate(level int, rlm realm, want string) {
\tif want == "" {
\t\tpanic("no delegate")
\t}
}

func Withdraw(cur realm, to address, amount int64) {
\tassertDelegate(0, cur, "manager")
\tbanker.SendCoins(cur, to, amount)
}
`;
  check("RC-01 assert guard clean", !hasRule(audit(src), "RC-01"));
}
{
  const src = `package demo

func assertDelegate(level int, rlm realm, want string) {
\tif want == "" {
\t\tpanic("no delegate")
\t}
}

var store *Store

func SetSetting(cur realm, key string, value string) {
\tassertDelegate(0, cur, "manager")
\tstore.Set(key, value)
}
`;
  check("RC-08 assert guard clean", !hasRule(audit(src), "RC-08"));
}

// RC-08: method on the gov/dao Proposals type mutates only its receiver.
{
  const src = `package demo

type Proposals struct {
\tseq int64
}

func (ps *Proposals) SetProposal(p *Proposal) int64 {
\tupdated := ps.Set("1", p)
\tif updated {
\t\tpanic("override not allowed")
\t}
\tps.seq++
\treturn ps.seq
}
`;
  check("RC-08 receiver-only mutation clean", !hasRule(audit(src), "RC-08"));
}

// RC-08: method on a genuinely unexported type is not public at all.
{
  const src = `package demo

type proposals struct {
\tseq int64
}

var store *Store

func (ps *proposals) Save(key string, value string) {
\tstore.Set(key, value)
}
`;
  check("RC-08 unexported receiver clean", !hasRule(audit(src), "RC-08"));
}

// RC-08: same shape on an exported receiver type still fires.
{
  const src = `package demo

type Registry struct {
\tseq int64
}

func (r *Registry) Put(key string, value string) {
\tr.store.Set(key, value)
}
`;
  const findings = audit(src);
  check("RC-08 exported receiver fires", hasRule(findings, "RC-08"));
  check("RC-08 exported receiver line 8", lineOf(findings, "RC-08") === 8, `got ${lineOf(findings, "RC-08")}`);
}

// RC-08: a method that assigns a package-level variable still fires.
{
  const src = `package demo

type Registry struct {
\tseq int64
}

var treasury int64

func (r *Registry) Reset(amount int64) int64 {
\ttreasury = 0
\treturn amount
}
`;
  const findings = audit(src);
  check("RC-08 method package-var fires", hasRule(findings, "RC-08"));
  check("RC-08 method package-var line 10", lineOf(findings, "RC-08") === 10, `got ${lineOf(findings, "RC-08")}`);
}

// RC-02: a Mint method on an unexported type is not an unrestricted mint.
{
  const src = `package demo

type minter struct {
\ttotal int64
}

func (m *minter) Mint(to address, amount int64) {
\tbanker.IssueCoin(to, "demo", amount)
\tm.total += amount
}
`;
  check("RC-02 unexported receiver clean", !hasRule(audit(src), "RC-02"));
}

if (failures > 0) {
  console.log(`\n${failures} case(s) failed, ${passes} passed. JS rule port is NOT verified.`);
  process.exit(1);
}
console.log(`\nAll ${passes} cases passed. JS rule port verified.`);
