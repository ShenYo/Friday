# Scenario-Driven Testing

> **中文摘要**：測試應從使用者或領域情境、驗收條件與可觀察行為出發，並在有
> 意義的邊界取得足夠證據。情境可跨越 class、module 或 layer；不以「每個函式或
> class 一個測試」為合規定義，也不要求所有工作都先寫 unit test。選擇最小但足夠的
> 測試層級，依風險涵蓋正常、邊界、失敗與回歸情況；無法執行證據時如實標示
> `UNVERIFIED`。

This document is normative whenever a requested outcome needs testing or other
behavioral evidence. It defines a portable contract for demonstrating the
outcome; a consumer may add compatible, domain-specific requirements.

## Scenario and acceptance criteria

Start with a user or domain scenario and its acceptance criteria. State the
observable behavior that would show the criteria are met, including meaningful
inputs, outputs, state changes, integrations, and failure behavior as relevant.

A scenario may cross classes, modules, or architectural layers. Choose the
boundary that makes the intended behavior observable without reducing the
evidence to incidental implementation structure.

Compliance is not defined as one test per function or class, assertions about
implementation details, or a universal unit-test-first ordering. Those may be
useful techniques in a particular change, but they are not substitutes for
evidence of the requested scenario.

## Adequate evidence

Use the smallest test level that adequately proves the scenario:

- A domain-level test can prove isolated business rules.
- A service or integration test can prove behavior across collaborating code or
  infrastructure boundaries.
- A component test can prove a user-facing unit and its local interactions.
- An end-to-end test can prove a critical flow through the deployed-facing
  boundary.

Unit tests are optional: add them when they provide the clearest or cheapest
useful evidence, not as a mandatory layer. Preserve fast red-green feedback
where it helps, while selecting the level and ordering that fit the scenario,
risk, and available boundaries.

Cover happy paths, edge cases, failures, and regressions in proportion to the
risk of the change. Higher-impact, ambiguous, externally integrated, or
previously failing behavior normally needs stronger evidence than a small,
well-bounded rule.

## Traceability and reporting

Keep a reviewable connection from each material scenario and acceptance
criterion to its evidence: name the test, command, fixture, observation, or
other check that demonstrates it. Report what ran and the result without
claiming coverage the evidence does not support.

When required evidence cannot run, state the reason and report it as
`UNVERIFIED`. Do not replace unavailable behavioral evidence with
implementation-detail assertions or a claim that tests should have been run.
