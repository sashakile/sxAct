---
title: Systematic Debugging
type: workflow
tags: [debugging, troubleshooting, problem-solving]
status: tested
---

# Systematic Debugging

## When to Use

This workflow is for systematically diagnosing and resolving software issues, applying principles similar to medical differential diagnosis. It's particularly useful for complex bugs where the root cause is not immediately obvious, and a structured approach is needed to avoid guesswork and wasted effort.

## The Prompt

You are an expert systems diagnostician. We are going to apply the principles of medical differential diagnosis to debug a software issue.

### 1. Symptom & Problem Representation:

-   **The primary symptom is:** `[DESCRIBE THE OBSERVED PROBLEM, e.g., "p99 latency for the /api/v1/users endpoint has spiked by 300% in the last hour."]`
-   **The system context is:** `[BRIEFLY DESCRIBE THE SYSTEM, e.g., "A Node.js microservice connected to a PostgreSQL database, running on Kubernetes."]`

### Your Task: Follow this seven-step workflow:

#### Step 1: Re-state the Problem

Briefly summarize the problem representation in standard engineering terminology.

#### Step 2: Generate Hypotheses (Differential Diagnosis)

List all plausible root causes for the symptom, from most likely to least likely. Do not stop at the obvious; consider a wide range of possibilities.

#### Step 3: Define Illness Scripts

For each of your top 3 hypotheses, describe the "illness script"—the typical narrative or pattern of how this cause would manifest. What are the expected signs and symptoms if this hypothesis were true?

#### Step 4: Propose Diagnostic Tests

For each hypothesis, propose a specific, executable test (e.g., a command, a query, a metric to check) that could be used to *conclusively rule it out*. Design tests that yield clear positive or negative results.

#### Step 5: Simulate Results & Narrow

-   Assume Test #1 (for your most likely hypothesis) comes back *negative*. What does this tell you? Which hypotheses can now be ruled out?
-   Assume Test #2 (for your second most likely hypothesis) comes back *positive*. What does this confirm?

#### Step 6: State the Probable Diagnosis

Based on the simulated results, state the most likely diagnosis (root cause) of the problem.

#### Step 7: Recommend Treatment

Propose a specific, immediate action to mitigate or fix the identified issue. This should be a concrete, actionable step.