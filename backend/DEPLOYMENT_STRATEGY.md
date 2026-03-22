# Breadcrumb Deployment Strategy

This document compares the practical deployment shapes for Breadcrumb's object-memory system and explains why the current repo implements a hybrid, local-first path.

## Recommendation

Ship Breadcrumb as a hybrid system:

- keep live candidate discovery, hand proximity, memory-graph updates, and local fallback on-device
- use a backend to refine labels, embeddings, and difficult re-identification cases
- store the durable user-facing memory graph locally first, then optionally sync higher-value evidence and embeddings upstream

This gives the best product tradeoff for "where did I leave this specific object?" because the app remains responsive during observation, still works when offline, and can benefit from stronger hosted models when available.

## Architecture Comparison

### Local-only

- Accuracy ceiling: lowest of the three for long-gap re-identification, clutter, and open-vocabulary labeling
- Latency: best
- Privacy: best
- Cost: best
- Engineering complexity: moderate
- Deployment complexity: lowest
- Product fit: good for live observation, weaker for recovering a specific object after long disappearance or visually confusing scenes

### Hybrid

- Accuracy ceiling: materially higher than local-only
- Latency: still good because local observation remains primary
- Privacy: strong if only selective evidence is uploaded
- Cost: controllable because heavy inference can be sampled or triggered selectively
- Engineering complexity: highest overall, because local and remote paths must agree on schema and fallbacks
- Deployment complexity: moderate to high
- Product fit: best overall balance for the current product goal

### Cloud-backed

- Accuracy ceiling: highest
- Latency: worst unless streaming and GPU inference are tuned carefully
- Privacy: weakest
- Cost: highest
- Engineering complexity: can be lower on-device but higher operationally
- Deployment complexity: highest
- Product fit: strongest only if the product can tolerate upload-heavy capture and relies on backend truth for most answers

## Model Stack Comparison

## Current repo backend

- Detection: Grounding DINO via `transformers`
- Embeddings: DINOv2 via `transformers`
- Strengths:
  - real open-vocabulary labels
  - simple integration path
  - good dev ergonomics
  - useful refinement over the on-device Vision stack
- Weaknesses:
  - frame-centric, not session-centric
  - no true segmentation propagation yet
  - no persistent remote vector store in this repo

## Stronger production cloud stack

- Detection: Grounding DINO or YOLO-World for proposals
- Segmentation and mask propagation: SAM 2
- Temporal association: ByteTrack or CoTracker-style track support around masks and detections
- Embeddings: DINOv2 or SigLIP/CLIP-style embeddings for stronger re-identification features
- Reasoning layer: multimodal or language model summarization over event candidates, not raw-frame truth

This stronger stack raises the accuracy ceiling, especially for occlusion, reappearance, and confusing context, but it needs GPU-serving infrastructure and better evidence retention than this repo currently contains.

## Recommended Deployment Phases

### Phase 1: Local-first hybrid

- iOS app performs automatic candidate discovery and event inference locally
- backend offers synchronous frame refinement only
- local SwiftData graph remains the user-facing source of truth
- uploads are optional and selective

This is what the current repo supports.

### Phase 2: Production hybrid

- keep the synchronous refinement endpoint for live hints
- add async clip or burst upload jobs for hard scenes
- store evidence in object storage
- store metadata in Postgres
- store embeddings in `pgvector` or another vector-capable store
- add a session-level re-identification worker that can revisit earlier candidates

This is the best next deployment step if the goal is noticeably better object-memory accuracy without making the app cloud-dependent.

### Phase 3: Full cloud memory service

- backend owns session-scale tracking and object-memory graph reconciliation
- mobile app becomes a capture, browse, and cache client
- cloud can run stronger temporal models and richer reasoning over longer horizons

This is only worth it if the product decides accuracy matters more than privacy, offline support, and cost.

## Why Not Full Cloud First

- live observation quality depends on low-latency feedback
- users need local confidence and last-known-state views even when upload fails
- continuously uploading observation video is expensive and privacy-sensitive
- many object-memory actions are good enough with on-device Vision plus lightweight heuristics

## What Would Justify Moving Further Cloudward

- frequent long-gap re-identification failures
- strong demand for household-scale search across long time windows
- willingness to pay GPU inference and storage costs
- product acceptance of upload-heavy capture

## Operational Notes

- `GET /healthz` should be used only for process liveness
- `GET /readyz` should gate deploy readiness because it reports whether the required model-serving dependencies are present
- `POST /v1/frame/analyze` already fails closed with `503` when the heavy ML stack is unavailable

## Bottom Line

The current hybrid deployment strategy is the right one for Breadcrumb today. The strongest cloud model stack is better on paper, but not enough better to justify replacing the local memory graph and live perception loop yet. The next meaningful upgrade is not "make everything cloud"; it is "keep the local system primary, then add async GPU-backed session refinement and remote embedding search where the local stack is weakest."
