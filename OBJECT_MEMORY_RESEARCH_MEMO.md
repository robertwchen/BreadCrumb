# Breadcrumb Object Memory Research Memo

Prepared: 2026-03-22

## Goal

Rebuild Breadcrumb into an object-memory system that automatically discovers object candidates, tracks them through time, clusters repeated sightings into persistent identities, infers hand-linked events, and helps answer:

> Where did I last put this specific object?

This memo uses primary sources from Apple SDK headers / WWDC material plus official model papers and repositories for the hosted stack.

## 1. Best Local-Only Design

### Best Apple-native components

- `VNGenerateObjectnessBasedSaliencyImageRequest`
  - Good for proposing likely object regions automatically without a registered object list.
  - Works as proposal generation, not identity.
- `VNGenerateAttentionBasedSaliencyImageRequest`
  - Useful as a secondary proposal source for visually prominent regions.
- `VNGenerateForegroundInstanceMaskRequest`
  - Best Apple-native way to separate salient foreground instances from background on iOS 17+.
  - Useful for tighter crops and less background contamination before embedding / clustering.
- `VNGenerateImageFeaturePrintRequest`
  - Strong Apple-native image descriptor for local similarity and candidate clustering.
  - Good for local re-identification support, but still weaker than modern hosted embedding stacks for messy real-world instance identity.
- `VNTrackObjectRequest` + `VNSequenceRequestHandler`
  - Good for short-horizon box tracking once an object proposal already exists.
  - Not candidate discovery; it needs a seeded bounding box.
- `VNGenerateOpticalFlowRequest` / `VNTrackOpticalFlowRequest`
  - Can estimate dense motion between frames.
  - Likely too expensive for the main phone loop unless used sparingly for refinement.
- `VNDetectTrajectoriesRequest`
  - Specialized for parabolic motion.
  - Not the right backbone for everyday object-memory tracking.
- `VNDetectHumanHandPoseRequest`
  - Strong local cue for pickup / in-hand inference.
- `VNDetectHumanBodyPoseRequest`
  - Helpful for larger interaction context; less directly useful than hand pose for small-object memory.
- ARKit world tracking / plane detection / world maps / scene reconstruction
  - Best Apple-native path for richer scene context and location memory.
  - Helpful for “which surface / which part of the room” context, but not enough to solve instance identity by itself.
- visionOS object tracking
  - Powerful, but it requires per-object training from a 3D asset and is not the right iPhone answer for automatic candidate discovery.

### Best local-only pipeline

1. Sample frames during an observation session.
2. Generate automatic candidate proposals from objectness saliency, attention saliency, foreground instance masks, and active track boxes.
3. Crop candidates with foreground masks when available.
4. Compute local feature prints for each candidate crop.
5. Associate candidates across nearby frames with box overlap, feature-print similarity, and short-horizon `VNTrackObjectRequest` state.
6. Cluster repeated sightings into persistent local candidates.
7. Use hand pose overlap + motion state to infer:
   - seen
   - resting on surface
   - picked up
   - in hand / near hand
   - lost from frame / likely carried
   - reidentified
   - put down
8. Persist evidence thumbnails, observations, events, and last-known state locally.

### Local-only strengths

- Private by default.
- Responsive.
- Shippable entirely on iPhone.
- Good enough for automatic candidate discovery and a believable memory graph.

### Local-only ceiling

- Weak open-vocabulary semantics.
- Weaker instance-level identity under clutter, occlusion, deformable objects, lighting changes, and long disappearance gaps.
- Event inference still depends on heuristics layered over model outputs.
- Surface / room localization stays approximate unless AR context is integrated carefully.

## 2. Best Hybrid Design

### Recommended hybrid split

#### On-device

- Live capture and responsive UI.
- Automatic local candidate proposal.
- Local tracklet continuity.
- Hand-pose cues and immediate event hints.
- Local persistence and offline cache.
- Fast local fallback when backend is unavailable.

#### Backend

- Open-vocabulary detection.
- Stronger segmentation and video tracking refinement.
- Better visual embeddings / re-identification.
- Cross-session candidate clustering.
- Heavier event refinement over buffered frame windows.
- Better context labels and evidence scoring.

### Strongest practical hybrid model stack

- Open-vocabulary detection:
  - Grounding DINO is the strongest official baseline considered here.
  - YOLO-World is useful when lower latency is more important than absolute quality.
- Segmentation / video propagation:
  - SAM 2 is the strongest official segmentation/video foundation model in this stack.
  - Grounded-SAM-2 combines Grounding DINO with SAM 2 for grounded tracking in videos.
- Embeddings / re-identification:
  - DINOv2 is the best fit from the evaluated official open-source options for durable visual descriptors.
  - CLIP-like embeddings help open-vocabulary alignment and label hints, but DINOv2 is the better identity backbone.
- Tracking / association:
  - ByteTrack remains a strong practical association baseline for detection-to-track linking.
  - CoTracker is valuable for point-level continuity and occlusion handling, especially for refinement.
- Multimodal reasoning:
  - A hosted multimodal model can improve context summaries and event-note generation.
  - It should refine the memory graph, not replace the detector / tracker / embedding stack.

### Hybrid strengths

- Best balance of phone responsiveness and accuracy ceiling.
- Real automatic discovery on device.
- Materially better re-identification and clustering when backend is available.
- Clean fallback story.

### Hybrid weaknesses

- More engineering and deployment complexity.
- Requires explicit sync / retry / cache behavior.
- Privacy posture depends on deployment choices.

## 3. Best Cloud-Backed Design

### Cloud-first design

- Phone captures and uploads keyframes / short frame windows.
- Backend performs detection, segmentation, tracking, embeddings, clustering, and event inference.
- Phone acts primarily as sensor, cache, and visualization client.

### Strengths

- Highest raw model ceiling.
- Easier to upgrade model stack over time.
- Simplifies cross-device syncing and shared memory graph.

### Weaknesses

- Worse latency under weak network.
- More privacy burden.
- Higher infra cost.
- Less trustworthy for users who want a memory prosthetic for home/personal spaces.
- A poor offline story hurts the product at exactly the moment the user needs it.

## 4. Architecture Comparison

| Option | Accuracy ceiling | Latency | Privacy | Cost | Engineering complexity | Deployment complexity | Product robustness |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Local-only | Medium | Best | Best | Lowest | Medium | Lowest | Good, but identity ceiling is limited |
| Hybrid | High | Good | Medium-good | Medium | High | High | Best overall |
| Cloud-backed | Highest | Variable | Weakest | Highest | High | Highest | Strong online, weakest offline |

## 5. Recommended Architecture

### Recommendation: Hybrid

Hybrid is the best architecture for Breadcrumb.

Why:

- The app must automatically discover candidates without scan-first setup.
- The product goal is instance memory, not generic detection.
- Local Apple-native APIs are strong enough for proposal generation, local continuity, and hand cues.
- They are not strong enough by themselves to maximize specific-object identity across clutter, occlusion, and long gaps.
- A backend materially improves the hardest part of the problem: persistent instance identity and re-identification.
- The phone should still stay useful and responsive when the backend is missing or unreachable.

### Product stance

- The iPhone does real CV work locally.
- The backend improves confidence, identity quality, and event refinement when available.
- The user never has to pre-scan an object just to start detection.

## 6. Identity Problem Breakdown

### Generic object detection

"There is a mug-like thing in frame."

Useful for proposal / labeling, but not enough to answer where a specific mug was left.

### Instance-level identity

"This sighting is likely the same specific mug as earlier."

This is the core product problem.

### User-confirmed identity

The user promotes or names a candidate:

"Yes, candidate C is my blue pill bottle."

This should improve trust and future retrieval, but cannot be required before the system starts working.

### Unsupervised candidate clustering

Repeated similar sightings are grouped into a persistent candidate before naming.

### Re-identification after disappearance

The system must reconnect a reappearing sighting to the same identity after occlusion, offscreen carry, or longer time gaps.

This is where hosted embeddings and stronger video/segmentation stacks matter most.

## 7. Event Inference Recommendation

### Model-backed signals

- objectness / saliency proposals
- foreground instance masks
- hand pose
- local or hosted embeddings
- detector / segmenter outputs
- tracker outputs

### Heuristic state machine on top

Infer events from the sequence of model outputs:

- `seen`
  - stable observation
- `restingOnSurface`
  - stable position, low motion, not hand-linked
- `pickedUp`
  - recent stable rest -> hand contact / motion spike
- `inHand`
  - sustained hand proximity or carry-like motion
- `lostFromFrameLikelyCarried`
  - disappears after hand-linked movement
- `reidentified`
  - identity returns after absence
- `putDown`
  - in-hand / carried -> reappears stable away from hand

### Important truth

Pickup / put-down inference is not directly "solved" by a single model. It is a temporal inference problem built from detector, tracker, hand, motion, and context outputs.

## 8. Persistence Architecture

### Recommendation

- Local cache on iPhone: SwiftData
- Asset storage on iPhone: files on disk for evidence images / thumbnails
- Remote service schema: relational backend, with vector-capable storage recommended in production

### Why SwiftData locally

- Better fit than a single JSON blob for:
  - candidates
  - objects
  - observations
  - events
  - sessions
  - last-known state
  - hand interactions
- Built into the Apple stack and fits SwiftUI well.
- Good enough for a local memory graph and sync cache.

### Why not ad hoc JSON

- The product is graph-shaped and history-heavy.
- We need structured fetches, updates, and future migrations.
- JSON is acceptable for exports, not as the main memory graph.

### Remote schema direction

- sessions
- detections / observations
- tracklets
- candidate clusters
- promoted objects
- embeddings
- event timeline
- sync jobs / refinement jobs

In production, a vector-capable backend is justified for embedding-based re-identification. In this repo, the service contract should already expose embeddings and candidate cluster metadata even if infra deployment is not completed here.

## 9. What Should Be Automatic vs User-Confirmed

### Automatic

- candidate discovery
- tracklet creation
- repeated-sighting clustering
- evidence capture
- initial last-seen memory
- event suggestions with confidence
- possible missing state

### User-confirmed

- naming promoted objects
- confirming or correcting identity
- marking which objects matter most
- editing notes / priorities
- correcting mistaken merges

## 10. What Cannot Be Solved Well Without Hosted Strength

- Long-gap re-identification in messy home scenes.
- Open-vocabulary object cues that remain useful without manual registration.
- Cleaner segmentation for cluttered / partially occluded objects.
- More reliable cross-session candidate clustering.
- Better context summarization from richer multimodal reasoning.

## 11. Source Notes

### Apple-native

- Apple Vision SDK headers in Xcode 26.3 / iPhoneOS 26.2 SDK:
  - `VNGenerateObjectnessBasedSaliencyImageRequest`
  - `VNGenerateAttentionBasedSaliencyImageRequest`
  - `VNGenerateForegroundInstanceMaskRequest`
  - `VNGenerateImageFeaturePrintRequest`
  - `VNTrackObjectRequest`
  - `VNGenerateOpticalFlowRequest`
  - `VNTrackOpticalFlowRequest`
  - `VNDetectTrajectoriesRequest`
  - `VNDetectHumanHandPoseRequest`
  - `VNDetectHumanBodyPoseRequest`
  - `VNStatefulRequest`
- Apple ARKit SDK headers:
  - `ARWorldTrackingConfiguration`
  - `ARSession.getCurrentWorldMap`
  - `ARFrame.worldMappingStatus`
  - plane detection / scene reconstruction APIs
- WWDC24:
  - "Discover Swift enhancements in the Vision framework"
  - "Explore object tracking for visionOS"
  - "Create enhanced spatial computing experiences with ARKit"

### Hosted / open-source

- Grounding DINO official repo and paper
- Grounded-SAM-2 official repo
- SAM 2 official paper and repo
- YOLO-World official paper / repo
- DINOv2 official paper / repo
- ByteTrack official paper / repo
- CoTracker3 official paper / repo
- CLIP official paper / repo
