# ADHD Hackathon Concept Research Memo

Prepared: 2026-03-21

## 1. Executive Summary

The strongest ADHD-related hackathon concept is **ThreadBack**, an **ADHD-friendly re-entry assistant** that helps a user recover the thread of what they were doing after an interruption. It is not a planner, habit tracker, or therapy chatbot. It solves a narrower but sharper problem: "I got pulled away, now I cannot restart because I forgot my context, my next step, and why this mattered."

This concept won the research process for five reasons:

1. **It addresses a real, severe pain** grounded in executive-function, working-memory, planning, and organization-in-time literature for adult ADHD. Adults with ADHD commonly struggle with organization, task completion, remembering daily tasks, planning, and executive function in daily life. Emotion dysregulation also compounds the cost of re-entry failure. (Sources: S01, S02, S03, S04, S05, S10, S11, S12, S13)
2. **It matches what current products under-serve.** Current ADHD apps over-index on planners, reminders, psychoeducation, and gamified self-care, while user feedback repeatedly points to bugs, setup friction, reminder failure, and lack of in-the-moment rescue when a day gets blown up. (Sources: S06, S08, S16-S36)
3. **It is unusually demoable.** The before/after transformation is obvious in under 90 seconds: chaos after interruption, then one-tap re-entry card, then restored next step and context.
4. **It is feasible in 24-36 hours** if scoped to one flow: Chrome extension plus lightweight web/mobile companion that captures a short context snapshot, summarizes it, and produces a re-entry card with a next action.
5. **It fits HooHacks judging well.** HooHacks scores UI/UX, creativity, feasibility, functionality, and impact equally. ThreadBack can be polished, useful, human, and technically credible without requiring a risky full-stack health product. (Sources: S37, S38, S39, S40, S41, S42)

**Bottom line:** build an executive-function accessibility tool, not a "planner for ADHD" and not a quasi-clinical treatment app. Pitch it as a **real-time accessibility layer for interruption recovery**.

## 2. Research Method

### Scope

- Goal: find the single ADHD concept with the best chance to win a weekend hackathon.
- Time horizon: optimized for a **24-36 hour** build, not a venture-scale roadmap.
- Lens: mixed-method synthesis across clinical evidence, user complaints, competitor weaknesses, and hackathon judging patterns.

### Source strategy

- **Tier 1:** NIMH, CDC, peer-reviewed reviews, meta-analyses, RCTs.
- **Tier 2:** peer-reviewed digital health and wearable reviews, app-quality reviews.
- **Tier 3:** public app reviews, Reddit threads, Trustpilot-style public feedback.
- **Tier 4:** HooHacks pages, Devpost winner pages, judging criteria.

### Collection notes

- Clinical evidence was used for symptom burden, functional impairment, emotional burden, and the current state of digital evidence.
- User pain mining was based on a **manual coding pass over 31 public user-signal excerpts** pulled from app review summaries, App Store pages, Reddit threads, and public review sites. These counts are directional, not population estimates.
- Competitor analysis focused on products users actually discuss for ADHD support or adjacent executive-function support.
- Hackathon pattern analysis focused on current HooHacks judging criteria and recent winning/project examples.

### Confidence model

- **High confidence:** adult ADHD executive-function burden, planning/working-memory impairment, poor organization, emotion dysregulation burden, weak evidence for most digital ADHD interventions. (Sources: S01-S14)
- **Medium confidence:** exact ranking of consumer pain clusters, because user complaints are public but non-representative. (Sources: S16-S36)
- **Medium-high confidence:** hackathon pattern claims, because HooHacks criteria are explicit and recent winners are inspectable. (Sources: S37-S42)

## 3. Scientific Evidence Summary

### 3.1 Symptom-level struggles

Adult ADHD is associated with persistent inattention, disorganization, procrastination, difficulty finishing large projects, poor time management, trouble remembering daily tasks, and trouble staying on task. NIMH and CDC both frame these as impairments that affect work, school, home, and relationships. (Sources: S01, S02)

Recent adult ADHD evidence reviews also note frequent deficits in working memory, planning/organization, focused attention, sustained attention, decision-making, and response regulation. A review of meta-analyses found neurocognitive disadvantages across nearly every examined domain, with working-memory effects among the larger ones. (Sources: S03, S12)

### 3.2 Workflow-level struggles

The most hackathon-relevant clinical insight is that the burden is not just forgetfulness in the abstract. It is failure in daily workflow execution:

- planning and problem-solving
- organization-in-time
- task initiation
- task completion
- task switching and resumption
- prospective memory for delayed intentions

The 2025 organization-in-time study found adults with ADHD had poorer organization-in-time and quality of life than controls, with executive-function measures and time-organization measures both contributing to quality-of-life variance. (Source: S10)

The prospective-memory study found the clearest impairment was **task planning**, not a uniform collapse across every memory component. That matters for product strategy: many users may know what they want to do later, but cannot reconstruct or sequence the plan after disruption. (Source: S11)

BRIEF-A based adult ADHD work also highlights impairments in initiate, shift, working memory, plan/organize, and task monitor in everyday settings. (Source: S13)

### 3.3 Emotional struggles

Emotion dysregulation is not formally required for diagnosis, but it is highly relevant in adult lived experience. Reviews report emotion dysregulation in roughly **34-70% of affected adults** in the available adult literature and link it to poorer social, academic, and occupational outcomes. (Sources: S04, S05)

This matters because many ADHD product failures are not neutral. When a system fails, users often experience shame, guilt, self-blame, or avoidance. The re-entry problem is therefore both cognitive and emotional.

### 3.4 Environmental/context struggles

Symptoms often worsen when demands rise, routines break, or multiple systems have to be coordinated across work, school, and personal life. CDC specifically notes difficulty with long tasks, organization, attention management, and daily consistency under adult demands. (Source: S02)

This reinforces a key product thesis: the strongest product opportunity is not another static planning surface. It is a **context-aware support layer** for moments when a day is already off-plan.

### 3.5 What the evidence says about digital tools

The digital-intervention literature is useful mainly for what it **does not** support:

- A 2025 systematic review of reviews found **inconclusive overall effectiveness** and mostly low or critically low quality evidence for digital ADHD interventions. (Source: S06)
- A 2026 adult ADHD digital-health scoping review found a broad landscape of tools, but emphasized poor translation into real-world clinical or daily-life value and a need to incorporate lived experience and adherence realities. (Source: S07)
- A 2026 mHealth app quality review found ADHD-specific apps were **moderate overall quality**, with functionality stronger than engagement; many apps were centered on psychoeducation and organization rather than interactivity or social/contextual support. (Source: S08)
- One RCT showed that a smartphone psychoeducation app can support clinical psychoeducation, but that is very different from proving consumer app effectiveness for day-to-day task rescue. (Source: S09)

**Implication:** the safest evidence-backed position is to build a non-clinical support tool that solves a practical executive-function problem, not to claim symptom treatment.

## 4. User Pain Synthesis

### 4.1 Highest-frequency, highest-severity pains not well solved

From the combined clinical and user-signal review, the most important under-served pains are:

1. **Task initiation under overwhelm**
2. **Interruption recovery / losing the thread**
3. **Reminders that fail, blur into wallpaper, or never arrive**
4. **Tools that require too much setup and cross-app coordination**
5. **No rescue in the moment when the user is already off track**
6. **Trust collapse when bugs, sync failures, and subscriptions punish inconsistency**

### 4.2 Why interruption recovery stands out

Interruption recovery is the strongest concept territory because it sits at the intersection of:

- working memory
- planning
- organization-in-time
- shifting and task monitoring
- shame/avoidance after disruption

Users do not just need a reminder. They need to know:

- what they were doing
- why it mattered
- what changed
- what the next tiny step is
- how to restart without re-planning the entire task

That is a tighter and more emotionally resonant job than generic productivity.

### 4.3 Manual user-pain coding summary

The coded sample repeatedly showed that users dislike:

- unreliable reminders and notifications
- over-complicated planning workflows
- high-friction onboarding
- generic self-help content that is not situational
- cross-platform inconsistency
- expensive subscriptions that feel like ADHD tax
- tools that help with planning but not with doing or restarting

See `data/user_pain_clusters.csv` for the structured export.

### 4.4 What users actually complain about

Representative recurring complaints across the sample:

- "This is great in theory, but I still need help in the moment." (paraphrase from Inflow and Motion threads; Sources: S18, S34)
- "The reminders either did not show up or were easy to miss." (Sources: S16, S20, S23, S25)
- "I need everything in one place or I will not use it." (Source: S24)
- "The app is useful until my day gets thrown in a blender by life." (Source: S21)
- "I can have it in my calendar and still get distracted and not do it." (Source: S34)
- "Body doubling helps, but continuity and partner availability are still problems." (Sources: S31, S32)
- "I forgot to cancel it and paid again for something I never used." (Sources: S17, S34)

### 4.5 Demoable pain points

The most demoable ADHD pains are the ones with a visible state change:

- **Before:** user is overwhelmed, distracted, or lost.
- **After:** user sees one clear action and resumes.

Best demoable pains:

1. interruption recovery
2. hard-to-start tasks
3. reminders that adapt instead of silently failing
4. backlog triage after falling behind

Least demoable within a weekend:

- long-horizon coaching
- multi-week behavior change
- broad caregiver platforms
- clinically framed therapy tools

## 5. Competitor Analysis

### 5.1 What current ADHD/support apps over-focus on

Current tools over-focus on:

- calendarizing tasks
- routine building
- psychoeducation
- journaling
- gamification
- general-purpose AI planning

They under-serve:

- interruption recovery
- context restoration
- next-step re-entry
- dynamic rescue when a plan has already failed
- shame-safe recovery after derailment

### 5.2 Competitor teardown summary

See `data/competitors.csv` for the exported table. The short version:

| Competitor | Best at | Weakest point for this problem |
| --- | --- | --- |
| Tiimo | Visual scheduling and neurodivergent-friendly planning | Still assumes planning fidelity; notification/sync issues and paywall complaints remain |
| Structured | Clean timeline UI and drag/drop replanning | More planner than rescue tool; reminder discoverability and feature parity issues |
| Inflow | Empathetic education/coaching framing | Too much content, not enough fast situational action; high-cost and trust complaints |
| Goblin Tools | Task breakdown and language support | Helps decompose work but does not preserve live context or resume interrupted work |
| Focusmate | External accountability and body doubling | Requires session setup, partner availability, and social tolerance |
| Motion | Auto-scheduling and backlog surfacing | High setup, clutter, cost, and follow-through gap |
| Finch | Emotional warmth and gamified motivation | Useful for self-care consistency, not context recovery during cognitively demanding work |

### 5.3 Core market gap

No major competitor cleanly owns this job:

> "When I get interrupted, help me get back into the task without rebuilding the whole mental context."

That is why ThreadBack is not just another planner variant.

## 6. Hackathon Winner Pattern Analysis

### 6.1 What HooHacks explicitly rewards

HooHacks 2025 scored **UI/UX, Creativity, Feasibility, Functionality, and Impact**, each out of five, for a total of 25 points. Teams also had to submit to one main track. (Sources: S37, S38)

### 6.2 What recent HooHacks winners suggest

Recent winning/project examples point to a repeatable formula:

- **First-Voice.AI** won Best Health with a clear mental-health access story, structured AI flow, and practical output artifact. (Source: S40)
- **wearit** placed overall with a polished, context-aware AI experience that solved an everyday decision problem in a visually intuitive way. (Source: S41)
- **HeyHoo** and similar accessibility projects succeed when the assistive story is obvious and the demo transformation is immediate. (Source: S42)

### 6.3 Pattern synthesis

Concepts that tend to perform well in student hackathons have:

1. a clear human story
2. a visible before/after change
3. one sharp job-to-be-done
4. enough technical depth to feel real
5. no obvious overclaiming
6. a polished, low-friction demo

### 6.4 Why ThreadBack fits this pattern

- **Impact:** executive-function accessibility for students and adults
- **Creativity:** not another calendar or checklist
- **Feasibility:** narrow workflow, extension plus app
- **Functionality:** easy to show live
- **UI/UX:** re-entry card is visually legible and emotionally satisfying

## 7. Opportunity Gap Map

| Opportunity zone | What is crowded | What is under-served | Why it matters |
| --- | --- | --- | --- |
| Planning | planners, calendars, habit trackers | rescue after plan failure | users already know how to make plans; they struggle when plans break |
| Education | psychoeducation modules, ADHD explainers | action in the moment | insight without execution is weak demo value |
| Accountability | body doubling, coworking rooms | asynchronous low-pressure restart help | many users need help without scheduling a partner |
| AI | generic chatbots, AI planner wrappers | AI that compresses context into a restartable next step | judges reward AI when it is clearly necessary |
| Accessibility | dyslexia/vision/speech tools | executive-function accessibility tools for interruption recovery | strong social-impact framing with lower clinical risk |

**Sweet spot:** context-aware executive-function rescue, especially **re-entry after disruption**.

## 8. 20 Raw Ideas

| Idea | One-sentence description | Why current tools fail here | Why it could win | Build difficulty | Demo quality | Main risk |
| --- | --- | --- | --- | --- | --- | --- |
| 1. ThreadBack | AI re-entry cards that restore context after interruptions | planners store tasks, not live mental context | sharp emotional story and obvious transformation | Medium | Very high | privacy of captured context |
| 2. Launch Ladder | converts "I cannot start" into one tiny step, timer, and optional accountability | many tools decompose tasks but do not ignite action | phone-friendly and easy to understand | Low-Medium | High | lower novelty |
| 3. Sidecar Intent Layer | floating scratchpad that keeps current intent visible across apps | working memory fails when tabs/apps multiply | accessibility angle is strong | Medium | Medium-High | desktop integration scope |
| 4. Nudge Ladder | reminders escalate across modalities until acknowledged | static reminders become invisible | visible system logic and good mobile demo | Medium | High | can feel naggy |
| 5. Focus Relay | one-tap handoff to AI or human body double when stuck | current body doubling requires scheduling | social proof plus action | Medium | High | network/availability complexity |
| 6. Future Breadcrumbs | voice notes plus context tags to help future self restart | notes are too unstructured to help later | strong phone-only version | Low-Medium | High | overlap with voice memo apps |
| 7. Reset Ritual | shame-safe daily reset after missed tasks or a derailed day | most apps punish misses or ignore emotions | emotionally resonant | Low | Medium-High | softer technical wow |
| 8. Chaos Map | AI errand sequencer that groups context-switching tasks | standard to-do apps ignore spatial friction | practical utility | Medium | Medium | less emotionally powerful |
| 9. Sticky Context Browser | preserves reading/research context with resume bundles | tabs do not explain intent | strong for student research demo | Medium | High | narrower audience |
| 10. Commute Cue | location-based prompts linked to routines and items | reminders arrive at bad times | very tangible phone demo | Medium | Medium | permissions/privacy |
| 11. Decision Dial | reduces small daily decisions when depleted | planners do not reduce cognitive load | useful and friendly | Low | Medium | weaker wow factor |
| 12. Syllabus Rescue | converts syllabi/assignments into next actions and deadlines | students do not act on course docs consistently | student-specific and obvious | Medium | High | crowded AI summarizer territory |
| 13. Deadline Triage | backlog rescue that shows what to do, defer, or drop when behind | tools rarely help after failure | high student relevance | Medium | High | may feel too productivity-generic |
| 14. Trigger Shield | calendar events automatically trigger focus mode and app blocking | calendars do not protect execution | useful and buildable | Low-Medium | Medium-High | needs OS controls |
| 15. Household Handshake | caregiver/partner dashboard for shared executive-function load | current tools ignore relationship burden | strong emotional story | Medium-High | Medium | heavier coordination/privacy |
| 16. Momentum Pet 2.0 | context-aware self-care pet that reacts to real task friction | gamified tools are often detached from real work | lovable demo | Medium | Medium-High | novelty may look shallow |
| 17. Reflect and Restart | emotional check-in plus next-step rescue after setbacks | apps split emotion support from task support | human story is strong | Low-Medium | Medium-High | can drift toward therapy framing |
| 18. Context Canvas | map of all active open loops across email, docs, and tasks | fragmentation hides priorities | strong knowledge-work angle | High | Medium | scope creep |
| 19. Haptic Anchor | hardware button/wearable that captures current task and pings the next step later | phone prompts are easy to ignore | hardware plus accessibility is memorable | Medium-High | Very high | hardware reliability in 36h |
| 20. Social Reboot | summarizes missed messages and drafts low-stress replies | social backlog is emotionally heavy | broad emotional relevance | Medium | Medium-High | weaker ADHD specificity |

## 9. Top 5 Shortlisted Ideas

### 1. ThreadBack

- Best combination of unmet need, novelty, demo clarity, and emotional resonance.
- Solves an under-served problem that maps well to adult ADHD executive-function burden.

### 2. Launch Ladder

- Best pure phone-only concept.
- Very feasible and broadly relatable, but closer to existing decomposition/start-task tools.

### 3. Haptic Anchor

- Best one-device hardware concept.
- Excellent demo theater, but more build risk and more hardware dependence.

### 4. Reset Ritual

- Strong emotional fit and low-risk scope.
- Slightly less judge-visible technical differentiation.

### 5. Deadline Triage

- Strong for students and hackathon judges who understand deadline panic.
- Still too close to smart planner territory compared with ThreadBack.

## 10. Top 3 Finalists

| Rank | Concept | Why it made the final three | Why it did not win / did win |
| --- | --- | --- | --- |
| 1 | ThreadBack | strongest unmet need plus best demo | **Winner** |
| 2 | Launch Ladder | easiest phone build and very practical | more crowded and less differentiated from Goblin/body-double ecosystems |
| 3 | Haptic Anchor | best hardware theater and memorable accessibility framing | extra device risk, BLE/firmware complexity, and hardware setup dependency |

## 11. Final Recommended Concept

### 11.1 Final concept name

**ThreadBack**

Tagline: **Pick up the thread after life interrupts.**

### 11.2 User persona

- Primary persona: college student or young professional with ADHD
- Situation: juggling assignments, admin tasks, and communication across laptop and phone
- Core behavior: gets pulled away by messages, meetings, chores, or rabbit holes and then cannot cleanly resume the original task

### 11.3 Core pain statement

> I do not need another planner. I need help getting back into the thing I was just doing after I get interrupted and lose the thread.

### 11.4 One-line pitch

**ThreadBack is an executive-function accessibility tool that captures a tiny breadcrumb before distraction and gives you a one-tap re-entry card with your context, why it mattered, and the next doable step.**

### 11.5 Two-minute demo narrative

1. A student is halfway through writing a paper and has three relevant tabs open.
2. A text and a side task interrupt them.
3. They hit **Save my spot** before leaving.
4. Later they return and cannot remember what the next step was.
5. ThreadBack shows:
   - what task they were in
   - what was already done
   - one suggested next action
   - the button to reopen the original links
6. They tap **Resume** and a 10-minute restart timer begins.
7. The story closes on reduced shame and faster restart.

### 11.6 Why this beats generic ADHD planner apps

- Planners help **before** work starts.
- ThreadBack helps **after** the plan breaks.
- That is where the emotional and functional cost is highest, and where existing tools are weakest.

### 11.7 Why judges will care

- **Impact:** directly addresses a neurodivergent accessibility problem
- **Creativity:** not another calendar or checklist
- **Functionality:** easy to show live
- **Feasibility:** clear MVP within a weekend
- **UI/UX:** compact re-entry cards can look polished fast

### 11.8 Exact MVP feature list

1. **Quick capture**
   - Browser extension button or mobile quick-add
   - One tap for "Save my spot"
   - Optional short voice note

2. **Context snapshot**
   - active tab title and URL
   - selected text or page title
   - optional typed or spoken note
   - timestamp

3. **AI re-entry card**
   - what you were doing
   - why it mattered
   - what changed since then
   - next 2-minute action
   - reopen links button

4. **Resume mode**
   - 10-minute focus timer
   - distraction-free card view
   - simple "done / still stuck" feedback

5. **Stuck fallback**
   - if still stuck, offer one smaller next step
   - optional body-double link-out or timer escalation

### 11.9 What not to build

- no diagnosis flow
- no treatment claims
- no always-on surveillance
- no full operating-system capture
- no full project-management suite
- no multi-week coaching program
- no therapist-matching or crisis chatbot as core scope

### 11.10 Ideal tech stack

- **Frontend:** Next.js or Expo/React Native
- **Extension:** Chrome Extension Manifest V3
- **Backend:** Supabase (Auth, Postgres, edge functions, storage)
- **AI:** OpenAI API for summarization and next-step generation
- **Speech:** browser speech-to-text or Whisper endpoint if needed
- **State:** local-first cache plus optional cloud sync

### 11.11 Strongest modality

**Strongest overall:** AI-assisted, cross-device, extension plus phone/web companion

Reason: AI is genuinely useful here because the product must compress messy context into a short re-entry artifact. That is a better use of AI than generic "plan my day" chat.

## 12. MVP Build Plan

### Build scope for 24-36 hours

**Day 1**

1. Build re-entry card UI
2. Build Chrome extension capture flow
3. Save snapshots to Supabase or local storage
4. Generate summary plus next step with AI

**Day 2**

1. Add mobile-friendly companion page or Expo screen
2. Add voice-note capture
3. Add reopen links flow
4. Add 10-minute resume mode
5. Polish the demo path and visual states

### Success criteria

- capture a context snapshot in under 2 seconds
- generate a readable re-entry card in under 5 seconds
- reopen the original task context reliably
- make the before/after obvious without explanation

## 13. Demo Plan

### 90-second demo narrative

1. Show a student mid-task on a laptop.
2. They get interrupted by a text or urgent side task.
3. They tap **Save my spot** and leave.
4. Time passes; they come back confused.
5. ThreadBack shows:
   - "You were comparing three articles for your HCI paper."
   - "You already finished notes on Article 1 and 2."
   - "Next 2-minute step: reopen Article 3 and highlight one methods quote."
6. User taps **Resume**, links reopen, timer starts.
7. End with the emotional line: "From 'What was I doing again?' to 'I can start now.'"

### 2-minute judge version

- add one example of selected text becoming a better next-step suggestion
- show opt-in privacy controls
- emphasize accessibility framing over medical framing

## 14. Ethical / Privacy Considerations

### Product posture

- executive-function accessibility tool
- non-diagnostic
- non-treatment
- supportive, not authoritative

### Risks

1. **Privacy risk:** captured tabs, text, or notes may contain sensitive information.
2. **Overcapture risk:** passive logging could feel invasive fast.
3. **Hallucination risk:** AI may infer the wrong next step.
4. **Medical framing risk:** judges or users may assume treatment intent.

### Mitigations

- explicit opt-in capture only
- local-first or minimal-retention design
- let users edit/delete cards instantly
- frame AI output as "suggested re-entry summary"
- avoid collecting health status unless essential
- do not claim symptom treatment or clinical efficacy

## 15. Citation Appendix

### Strong-evidence claims

- adult ADHD causes impairment in organization, task completion, memory, planning, and daily functioning: S01, S02, S03
- executive-function, working-memory, planning, and related neurocognitive deficits are common in adult ADHD: S03, S10, S11, S12, S13
- emotion dysregulation is common and impairing in adult ADHD: S04, S05
- digital ADHD interventions have mixed and mostly low-quality evidence: S06, S07, S08

### User/market claims

- many consumer tools are praised for structure but criticized for bugs, reminder failures, paywalls, sync problems, or lack of in-the-moment help: S16-S36

### Hackathon/judging claims

- HooHacks scores UI/UX, creativity, feasibility, functionality, and impact equally: S37
- HooHacks requires one main track submission and recent winners show strong fit for polished, practical, human-centered tools: S38-S42

## 16. Raw Data Appendix With Links / Scraped Notes / Exported Tables

### 16.1 Quick raw notes by source cluster

- **Inflow:** empathetic tone and coaching praised; major complaints about crashes, reminders, pricing, removed features, and exploitative subscription feel. (S15-S18)
- **Structured:** loved for visual day layout and drag/drop flexibility; criticized for paywalled features, reminder discoverability, lag, and platform parity gaps. (S19-S21)
- **Tiimo:** loved for neurodivergent-friendly visual planning; criticized for crashes, silent notifications, login/sync issues, and premium gating. (S22-S25)
- **Goblin Tools:** loved for breaking overwhelming tasks into steps; criticized for missing reminders/widgets/integration and occasional instability. (S26-S28)
- **Focusmate:** valued for body doubling and accountability; limitations include partner availability, continuity, etiquette anxiety, and the need to pre-book support. (S29-S32)
- **Motion:** praised for auto-rescheduling and surfacing forgotten tasks; criticized for clutter, setup friction, cost, bugs, and the fact that scheduled tasks can still be ignored. (S33-S34)
- **Finch:** praised for warmth, gamification, and strong free tier; less relevant to hard cognitive task re-entry. (S35-S36)

### 16.2 Exported tables

- `data/competitors.csv`
- `data/user_pain_clusters.csv`
- `data/concept_scorecard.csv`
- `sources.md`

### 16.3 Final decision summary

- **Best overall concept:** ThreadBack
- **Best concept for HooHacks specifically:** ThreadBack, submitted as **Accessibility & Empowerment**, with an AI-assisted implementation
- **Best concept if phone-only:** Launch Ladder
- **Best concept if using one lightweight hardware device:** Haptic Anchor

### 16.4 Exact reason the winner beat the runners-up

ThreadBack beat **Launch Ladder** because task-start support is already partially served by Goblin Tools, Focusmate, and AI planners, while interruption recovery is less crowded and more novel. It beat **Haptic Anchor** because hardware boosts demo theater but increases execution risk, whereas ThreadBack keeps the same emotional insight with a safer build. It beat **Reset Ritual** and **Deadline Triage** because those are useful but look closer to wellness/productivity software, while ThreadBack creates a cleaner "I have never seen this exact thing before" reaction from judges.
