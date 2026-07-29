# API Reference

## Core Types

```@docs
Testimonial.TestItemRef
Testimonial.CoverageIndex
Testimonial.ImpactResult
Testimonial.ImpactReason
Testimonial.CoverageGap
Testimonial.ItemCoverage
```

## Recording

```@docs
Testimonial.record_all
Testimonial.record_item
Testimonial.record_batch
```

## Query

```@docs
Testimonial.query
Testimonial.query_files
Testimonial.coverage_gaps
Testimonial.is_index_stale
```

## Confidence

```@docs
Testimonial.compute_confidence
Testimonial.ConfidenceConfig
Testimonial.components_below_threshold
```

## Provenance

```@docs
Testimonial.ProvenanceLink
Testimonial.LayerKind
Testimonial.save_provenance
Testimonial.load_provenance
Testimonial.prune_provenance
```

## Safety

```@docs
Testimonial.AlwaysRunReason
Testimonial.get_always_run_tests
Testimonial.MustRunRule
Testimonial.MissedSelectionIncident
Testimonial.reconcile
Testimonial.scoped_fallback
```

## Persistence

```@docs
Testimonial.save_index
Testimonial.load_index
Testimonial.save_run_history
Testimonial.load_run_history
```