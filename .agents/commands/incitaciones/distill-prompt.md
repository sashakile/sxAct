---
title: Distill Prompt
type: task
tags: [prompt-engineering, optimization, token-efficiency]
status: tested
---

# Distill Prompt

## When to Use

This task is for taking a verbose, developer-facing prompt and converting it into a concise, token-efficient, LLM-facing prompt. The goal is to remove all human-centric explanatory text and metadata, leaving only the essential instructions required for an LLM to perform its task.

## The Prompt

Analyze the provided `DEVELOPER-FACING PROMPT`. Your task is to distill it into a concise, token-efficient, `LLM-FACING PROMPT`.

The distilled prompt must retain only the essential instructions, rules, and structured commands required for the LLM to perform its task.

### Rules for Distillation

You MUST REMOVE:
1.  All front-matter and metadata (e.g., title, tags, status, version, related, source).
2.  All explanatory sections intended for humans (e.g., "When to Use," "Notes," "Example," "References," "Philosophy").
3.  Descriptive introductions, justifications, and conversational text.
4.  Verbose examples. Summarize them only if they are essential for defining a format.

The final output should be a clean, direct set of instructions for the LLM, with no additional commentary from you.

### Input Format

DEVELOPER-FACING PROMPT:
---
[Paste the verbose prompt content here]
---