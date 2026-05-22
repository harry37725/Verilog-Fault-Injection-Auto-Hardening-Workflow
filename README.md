# 🔐 Verilog Fault Injection & Auto-Hardening Workflow

> An automated hardware security audit pipeline built in **n8n** that performs fault-injection attacks on any Verilog module, identifies critical vulnerabilities, auto-generates hardened RTL using Triple Modular Redundancy (TMR), validates the fix, and produces a professional security disclosure report — all with zero manual intervention.

---

## 📋 Table of Contents

- [Overview](#overview)
- [How It Works](#how-it-works)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Setup & Configuration](#setup--configuration)
- [Running the Workflow](#running-the-workflow)
- [Output](#output)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)

---

## Overview

This workflow takes a **Verilog source file** as input and fully automates the following security pipeline:

1. **Attack** — Inject single-bit faults into the primary state register across multiple trials
2. **Analyse** — Parse simulation output to detect control-flow hijacks and alignment crashes
3. **Harden** — Generate a TMR-hardened version of the module using Gemini AI
4. **Validate** — Re-attack the hardened module to confirm the fix works
5. **Report** — Produce an executive-level security disclosure document

This is particularly useful for hardware security research, pre-silicon security audits, and academic work on fault-tolerant RTL design.

---

## How It Works

```
Webhook Trigger
     │
     ▼
Read Verilog File from Disk
     │
     ▼
Gemini AI: Generate Fault-Injection Testbench  ◄─────────────────┐
     │                                                           │
     ▼                                                           │
Build Combined Script (DUT + Testbench)                          │
     │                                                           │
     ▼                                                      (loop, up to 4x)
JDoodle API: Compile & Simulate Verilog                          │
     │                                                           │
     ▼                                                           │
Parse Simulation Logs → Detect PC Jumps, Crashes, Misalignments  │
     │                                                           │
     ▼                                                           │
Counter: Track Bit History → Loop Back ──────────────────────────┘
     │
     ▼ (after 4 trials)
Aggregate All Logs → Classify Serious vs Masked Faults
     │
     ├── No serious faults → Mark as Masked → End
     │
     └── Serious faults found ──►
              │
              ▼
        Gemini AI: Generate Hardened Verilog (TMR)
              │
              ▼
        Gemini AI: Generate Validation Testbench (attacks shadow reg)
              │
              ▼
        JDoodle API: Simulate Hardened Module
              │
              ▼
        Validate: Did TMR hold?
              │
              ├── Yes → Proceed to Report
              │
              └── No  → Retry hardening (up to 4 iterations)
                              │
                              ▼
                        Final Code Node
                              │
                              ▼
                  Gemini AI: Write Disclosure Report
                              │
                              ▼
                  Save Hardened Verilog to Disk
```

---

## Features

### 🧪 Automated Fault Injection Campaign
The workflow uses **Gemini 2.5 Flash** to automatically analyse the provided Verilog source and generate a targeted fault-injection testbench — no manual testbench writing required. It targets the primary state register (e.g., Program Counter, FSM state), injects single-bit flips using `force`/`release`, and records the PC state before and after each flip. Up to **4 trials** are run per campaign, each targeting a different bit, with a built-in history tracker ensuring no bit is tested twice.

### 🔍 Intelligent Log Analysis
After each simulation, the workflow parses the output to detect:
- **Control Flow Hijacks** — when a bit flip causes the PC to jump to an unintended address
- **Alignment Crashes** — when the flipped PC lands on a non-word-aligned address
- **Runtime Crashes** — segfaults and fatal errors caused by the injected fault
- **Masked Faults** — flips that had no observable effect

Each trial is classified with a severity level (Critical / High / Masked) and a jump distance in bytes.

### 🤖 AI-Powered Verilog Hardening
When serious faults are detected, **Gemini 2.5 Flash** is prompted with the full vulnerability report and the original source to generate a hardened version of the module. The hardening strategy includes:
- **Triple Modular Redundancy (TMR)** on the primary state register — three shadow copies (`reg_1`, `reg_2`, `reg_3`) with a majority voter
- **Alignment enforcement** — forces the state register to stay word-aligned after every clock edge
- **Watchdog logic** — limits state jumps to a safe range where appropriate
- **Illegal-state recovery** — for FSMs, resets to a known-safe state on illegal transitions

The hardener is module-agnostic: it reads port names, register widths, clock polarity, and reset polarity directly from the source, so it works on any Verilog design — not just CPUs.

### ✅ Automated Hardening Validation
After generating the hardened module, the workflow generates a **new testbench** specifically designed to attack the TMR shadow registers (not the voter output). This confirms whether the majority voter correctly masks the injected fault. If validation fails, the workflow automatically retries the hardening process up to **4 times** before finalising.

### 📄 Executive Security Disclosure Report
Once validation passes, the workflow compiles all trial data into a structured raw report and passes it to Gemini to rewrite as a polished **executive-level security advisory** with the following sections:
1. Executive Summary
2. Module Under Test
3. Vulnerability Details
4. Mitigation Strategy Applied
5. Validation Results
6. Recommendations

The hardened Verilog source is also saved back to disk.

### 🔁 Loop Control & Rate Limiting
A **20-second wait node** is placed before each loop iteration to respect JDoodle API rate limits. A counter node tracks the run index and enforces a maximum of 4 fault-injection trials before moving to the analysis phase.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **n8n** | Self-hosted instance (v1.x recommended) |
| **Google Gemini API** | Via the n8n Google Gemini (PaLM) node — configure credentials in n8n Settings |
| **JDoodle API** | Free or paid account at [jdoodle.com](https://www.jdoodle.com) for Verilog compilation |
| **Verilog source file** | A `.v` file accessible on the machine running n8n |

---

## Setup & Configuration

### 1. Import the Workflow
In your n8n instance, go to **Workflows → Import from File** and upload `Verilog Fault Injection and Auto-Hardening.json`.

### 2. Configure Google Gemini Credentials
The workflow uses Google Gemini 2.5 Flash across three AI nodes: **Message a model**, **Revise code**, **Testbench Generator**, and **Disclosure Report**.

In n8n, go to **Settings → Credentials** and add a **Google Gemini (PaLM) API** credential. Then assign it to each of the four Gemini nodes in the workflow.

### 3. ⚠️ Configure JDoodle Credentials

> **This step is required — the workflow will not execute Verilog without it.**

The workflow uses JDoodle to compile and simulate Verilog via two HTTP Request nodes: **HTTP Request** and **HTTP Request1**.

1. Sign up for a free account at [jdoodle.com](https://www.jdoodle.com)
2. Navigate to your dashboard and copy your `clientId` and `clientSecret`
3. In n8n, open the **HTTP Request** node and fill in the `clientId` and `clientSecret` body parameters
4. Repeat for the **HTTP Request1** node

### 4. ⚠️ Update the Local File Path

> **This step is required — the workflow reads your Verilog file from disk.**

The **Read/Write Files from Disk** node is currently hardcoded to:
```
C:\Users\marti\.n8n-files\counter.txt
```

Update this path to the location of your Verilog `.v` file on the machine running n8n. For example:
- **Windows:** `C:\Users\YourName\projects\my_cpu.v`
- **Linux/macOS:** `/home/yourname/projects/my_cpu.v`

Similarly, the **Save Hardened Code to Disk** node at the end of the workflow saves the hardened output — update that path too if needed.

---

## Running the Workflow

1. Activate the workflow in n8n (toggle **Active** to on)
2. Trigger it via HTTP POST to your n8n webhook URL:

```bash
curl -X POST https://<your-n8n-host>/webhook/audit_cpu
```

Or call it from any HTTP client — no request body is needed. The workflow reads the Verilog source directly from the configured file path.

3. Monitor execution in the n8n execution log. The full run takes approximately **2–5 minutes** depending on the number of trials and Gemini response times.

---

## Output

| Output | Location |
|---|---|
| **Hardened Verilog source** | Saved to disk (configure path in **Save Hardened Code to Disk** node) |
| **Security Disclosure Report** | Available in the final n8n execution data (Disclosure Report node output) |
| **Trial-by-trial attack logs** | Visible in the Log Generator and Aggregate Logs node outputs |

The disclosure report includes every trial's bit target, PC before/after, jump distance, severity classification, and a confirmation of whether the TMR mitigation succeeded.

---

## Architecture

| Node | Role |
|---|---|
| `Webhook` | Entry point — triggers the workflow |
| `Read/Write Files from Disk` | Reads the Verilog `.v` file |
| `Extract from File` | Converts binary file data to base64 text |
| `Code in JavaScript1` | Decodes base64 to raw Verilog string |
| `Message a model` (Gemini) | Generates the fault-injection testbench for the current trial |
| `Parse Analyser` | Extracts module metadata: name, ports, register widths, clock/reset polarity |
| `Source Code` | Decodes and stores the original Verilog for downstream nodes |
| `Code + Testbench` | Combines DUT source and testbench; enforces port names and register widths |
| `HTTP Request` | Sends the combined script to JDoodle for Verilog simulation |
| `Wait` | 20-second delay between trials to respect API rate limits |
| `loop initialising` | Tracks the current run index |
| `update counter` | Maintains bit history to avoid re-testing the same bit |
| `If` | Loops back for up to 4 trials |
| `Log Generator` | Parses simulation output — extracts PC values, jump distances, bit flipped |
| `log checker` | Classifies each trial as serious or masked |
| `Aggregate Logs` | Summarises all trials; identifies the worst fault |
| `Serious Check` | Routes to hardening if serious faults exist, or masked result if not |
| `Revise code` (Gemini) | Generates TMR-hardened Verilog |
| `Testbench Generator` (Gemini) | Generates a validation testbench that attacks the shadow register |
| `Build Hardened Script` | Combines hardened DUT + validation testbench |
| `HTTP Request1` | Simulates the hardened module via JDoodle |
| `Validation Log Parser` | Checks if TMR successfully masked the re-injected fault |
| `Validation Result IF` | Loops hardening if validation fails; proceeds if it passes |
| `Hardening Loop Init / Counter IF` | Controls the hardening retry loop (max 4 iterations) |
| `Final Code` | Compiles the full disclosure data |
| `Disclosure Report` (Gemini) | Rewrites raw data as an executive security advisory |
| `Prepare Hardened File` | Encodes the hardened Verilog for file output |
| `Save Hardened Code to Disk` | Writes the hardened `.v` file to disk |
| `Masked Result` | Terminal node for faults that required no action |

---

## Troubleshooting

**Workflow triggers but no simulation output appears**
Verify your JDoodle `clientId` and `clientSecret` are correctly entered in both **HTTP Request** and **HTTP Request1** nodes. Check the JDoodle dashboard to confirm your account is active and has remaining credits.

**File not found error at startup**
The file path in the **Read/Write Files from Disk** node does not exist on your machine. Update it to the full absolute path of your Verilog file.

**Gemini node returns an error**
Ensure your Google Gemini API credentials are valid and assigned to all four AI nodes. The workflow uses `models/gemini-2.5-flash` — confirm this model is available on your API key.

**Workflow loops indefinitely**
This should not happen due to the counter guards, but if it does, manually stop execution in n8n and check the `update counter` node output to see the current trial count.

**Hardened Verilog fails to compile**
This can happen on unusual module structures. The hardening retry loop will attempt up to 4 iterations automatically. If all fail, the Final Code node still produces a partial report.

---
