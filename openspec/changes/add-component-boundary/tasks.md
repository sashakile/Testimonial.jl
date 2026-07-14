## 1. Data model changes
- [ ] 1.1 Add `component::String` field to `TestItemRef` (for equality and hashing)
- [ ] 1.2 Bump `SCHEMA_VERSION`; implement migration for existing indices
- [ ] 1.3 Add `inter_component_edges::Dict{String, Set{String}}` to `CoverageIndex`

## 2. Component auto-detection
- [ ] 2.1 Parse workspace `Project.toml` to discover components
- [ ] 2.2 Map each test file to its owning component
- [ ] 2.3 Add `components` override to `Testimonial.toml` (for projects without workspace)

## 3. Per-component index persistence
- [ ] 3.1 Restructure `.testimonial/` directory: routing file + per-component subdirs
- [ ] 3.2 Update `record_all` to build per-component indices
- [ ] 3.3 Update `load_index` to read per-component indices via routing file

## 4. Component graph and inter-component edges
- [ ] 4.1 Build component graph during index construction (from inter-component coverage)
- [ ] 4.2 Store component graph alongside the routing file

## 5. Bottom-up resolution in smart_run
- [ ] 5.1 Modify `query` to accept component scope
- [ ] 5.2 Implement bottom-up component resolution before per-component selection
- [ ] 5.3 Parallelize per-component query via `Threads.@threads`

## 6. Per-component cached selection
- [ ] 6.1 Compute and store dependency fingerprint per component
- [ ] 6.2 On load, check fingerprint; skip query if unchanged
- [ ] 6.3 Implement cache invalidation on fingerprint change

## 7. Shard plan
- [ ] 7.1 Read per-test durations from run history
- [ ] 7.2 Implement greedy duration-balancing shard assignment
- [ ] 7.3 Add `--shards N` option to `smart_run`