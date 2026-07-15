## 1. Fix spec folder naming in existing changes (COHR-3.1)

- [ ] 1.1 Rename `add-component-boundary/specs/add-component-boundary/` → `add-component-boundary/specs/component-architecture/`
- [ ] 1.2 Rename `add-confidence-scoring/specs/add-confidence-scoring/` → `add-confidence-scoring/specs/confidence-scoring/`
- [ ] 1.3 Rename `add-provenance-explainability/specs/add-provenance-explainability/` → `add-provenance-explainability/specs/provenance/`
- [ ] 1.4 Rename `add-runtime-feedback/specs/add-runtime-feedback/` → `add-runtime-feedback/specs/runtime-feedback/`
- [ ] 1.5 Rename `add-safety-invariants/specs/add-safety-invariants/` → `add-safety-invariants/specs/safety-invariants/`

## 2. Add missing MODIFIED Requirements deltas (COMP-3.2)

- [ ] 2.1 `add-component-boundary`: add `specs/smart-selection/spec.md` with MODIFIED query and orchestration
- [ ] 2.2 `add-component-boundary`: add `specs/coverage-index/spec.md` with MODIFIED data model
- [ ] 2.3 `add-component-boundary`: add `specs/recording/spec.md` with MODIFIED per-component recording
- [ ] 2.4 `add-component-boundary`: add `specs/ci-integration/spec.md` with ADDED shard plan
- [ ] 2.5 `add-confidence-scoring`: add `specs/smart-selection/spec.md` with MODIFIED `smart_run` decision logic
- [ ] 2.6 `add-confidence-scoring`: add `specs/coverage-index/spec.md` with ADDED confidence metadata
- [ ] 2.7 `add-runtime-feedback`: add `specs/smart-selection/spec.md` with MODIFIED `smart_run` orchestration
- [ ] 2.8 `add-runtime-feedback`: add `specs/recording/spec.md` with ADDED ingest mode
- [ ] 2.9 `add-runtime-feedback`: add `specs/coverage-index/spec.md` with ADDED runtime edges
- [ ] 2.10 `add-safety-invariants`: add `specs/smart-selection/spec.md` with MODIFIED `smart_run` orchestration
- [ ] 2.11 `add-safety-invariants`: add `specs/ci-integration/spec.md` with ADDED incident detection and reconciliation

## 3. Fix confidence-scoring formula and threshold conflict (CORR-2.1, CORR-2.2)

- [ ] 3.1 Fix `layer_coverage` formula in `add-confidence-scoring/design.md`: `1 / (num_layers_available + 1)` → `num_layers_available / (num_layers_available + 1)`
- [ ] 3.2 Fix `add-confidence-scoring/design.md` Risks table: "conservative 0.5 default" → "conservative 0.7 default" to match Goals, Decision 2, and CONF-003 spec
- [ ] 3.3 Verify `add-confidence-scoring/specs/confidence-scoring/spec.md` CONF-003 default threshold (0.5) is reconciled with design.md (0.7) — keep 0.7, update the spec line

## 4. Resolve circular dependency between runtime-feedback and safety-invariants (COHR-3.3)

- [ ] 4.1 Move "Flaky test runtime edge exclusion" scenario from FEED-002 into a MODIFIED SAFE-007 scenario in `add-safety-invariants/specs/safety-invariants/spec.md`
- [ ] 4.2 Update `add-runtime-feedback/proposal.md` to declare dependency on `add-safety-invariants`
- [ ] 4.3 Remove the flaky-exclusion scenario from FEED-002 in `add-runtime-feedback/specs/runtime-feedback/spec.md`

## 5. Add missing scenario to REC-011 (COMP-1.1)

- [ ] 5.1 Add a `#### Scenario:` block to REC-011 in `implement-coverage-layer/specs/recording/spec.md`

## 6. Add field definitions for layer_data and manual_edges (COMP-1.2)

- [ ] 6.1 Add `layer_data::Dict{Symbol, Any}` field to CI-001 `CoverageIndex` struct in `implement-coverage-layer/specs/coverage-index/spec.md`
- [ ] 6.2 Update CI-004 in same file to reference `line_to_tests` directly instead of `layer_data`
- [ ] 6.3 Add `manual_edges` field to coverage-index spec (MODIFIED CI-001 or ADDED CI requirement) in whichever change introduces it (safety-invariants for SAFE-005)

## 7. Add missing dependency declaration (COMP-1.3)

- [ ] 7.1 Add `add-component-boundary` to `add-confidence-scoring/proposal.md` Dependencies line

## 8. Resolve "testaruda" citation (COHR-3.4)

- [ ] 8.1 Add `testaruda` to `openspec/project.md` References section with a link or note
- [ ] 8.2 If testaruda does not exist or is unverifiable, rewrite 5 affected `design.md` files to remove external citations and make rationale self-standing

## 9. Move misplaced scenario (COHR-3.5)

- [ ] 9.1 Move "No git repository" scenario out of COMP-001 (`add-component-boundary/specs/component-architecture/spec.md`) to SAFE-003 or its own stand-alone requirement in `safety-invariants`