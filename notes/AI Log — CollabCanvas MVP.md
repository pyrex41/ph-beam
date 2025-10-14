# AI Log — CollabCanvas MVP

I felt comfortable that I could complete the MVP easily in the time window, so I decided to turn this into a bit of an experiment: start building the same app using three totally different tech stacks at once, all powered by AI tools, to see how it would handle different stacks and approaches. Spoiler: it didn’t work like I expected. I'll walk through how I set it up, the tools I leaned on, and what I learned.

## Why This Crazy Setup? The Plan and Philosophy

Most of my variation was on the backend side \- CollabCanvas needed real-time drawing/collaboration (think shared canvas with multiple users), user auth, and AI tools for suggesting shapes or layouts. PixiJS was the canvas engine for all three, selected for being lean and performant. I picked these stacks:

* **Stack 1: Svelte \+ Bun \+ Elysia** – I thought this was my "comfort zone." Svelte's lightweight, Bun's fast, Elysia for the API. Figured this would zip along since I'd done similar stuff before, using AI.  
* **Stack 2: Common Lisp \+ Vanilla JS \+ PixiJS** – The wildcard, old school. It’s so expressive and open-ended in how it could be used \- but also not tons of training data, so I was very curious if AI would struggle. Also can b very performant and compiled down to a binary. Vanilla JS frontend to keep it simple. Expected bugs, but fun insights.  
* **Stack 3: Phoenix/Elixir \+ LiveView \+ PixiJS \+ Redis** – Expected to be most performant but most time intensive choice. Elixir's functional focus w/ and LiveView for real-time magic sounded ideal for a collaborative app, but I’ve never built more than a toy app with it. Thought it'd be a slog.


Philosophy was parallize these: spin up separate Claude Code sessions for each, feed them variants of the same PRD (adjusting for the different stacks), then leverage TaskMaster to build tasks. I borrowed from Ash's class on planning—pour time into specs upfront, use Task Master for breaking things down, then execute. Spent extra time planning and verifying tasks than I had done in the past.

## The Workflow:

Started with PRD generation. I bounced ideas between Claude (Sonnet 4.5) and Grok, some with Gemini—cross-pollinate their outputs to get a rock-solid spec. Covered user flows, data models, real-time sync (ended up modifying this, started w/ last write wins), AI integration (function calling for design suggestions), and scaling notes (SQLite MVP, Redis later), Auth0 for auth (used hand-rolled auth in CL — could/would switch to Auth0 or similar later). Added Mermaid diagrams for architecture: data flows, component breakdowns. Then, off to Task Master (i used grok-code-fast-1 for the task master model, much faster than claude, but then i had claude code (sonnet-4.5) review the tasks along with me).

1. `tm parse-prd -n N` – Spit out N high-level tasks like "Set up auth," "Implement canvas rendering," "Wire in real-time collab."  
2. `tm analyze complexity` – Flags tough spots, like WebSocket handling.  
3. My review loop: Tweak tasks for clarity, make sure they tie back to the PRD. (Spent extra time here per Ash's advice—huge payoff later.)  
4. Generate/update Mermaid files in Claude, have it review for compliance.  
5. `tm expand --all`  
6. Update docs in Claude Code with all the context.  
7. Git commit, then prompt: "Dive into these tasks. Parallelize with subagents or task executors where you can, using a single task invocation/command." Wasn’t really able to induce Claude Code to work in parallel very much. For Grok, I used it quick for parsing tasks—super fast. I used Cursor for peeking at files or quick edits. I fired all three stacks at once in separate tabs/sessions. Told them to run autonomously: "Work the task list, invoke multiple agents in parallel." (Claude's iffy on true parallelism—often does one-by-one).  
8. Along the way, I would frequently use repomix to take the whole project and dump in Gemini Pro-2.5 to get a summary of what was there to make sure we were on track, and to generate some interim mermaid files to visualize what we had so far.

## What Went Happened

Kicked off expecting Svelte to lap the field in speed, Phoenix to drag/get stuck in setup (i didn’t even do the environment setup), Lisp to get stuck on endless debugger / edit loops. Results were pretty much the opposite.

### Phoenix/Elixir: The Unexpected Champ

This one just *ran*. I gave it the tasks, stepped away for coffee, and it chewed through everything—environment setup, LiveView hooks, PixiJS canvas, PubSub for real-time, even Auth0 integration. Everything worked until I got to the canvas, then that worked after 5-10min of pasting error messages. Only hiccup: Canvas rendering glitched initially. Prompted Claude to debug, and it nailed the fix in one go—Elixir's compiler errors were gold, pointing right at the issue. It was working on the dev server after a few hours, minimal hand-holding. Deployment took a little longer, maybe an hour, getting the right docker image etc. Looks slick, feels responsive. Why? Strong types caught dumb errors early, functional style kept state sane, Phoenix conventions guided the AI like a pro. Beam concurrency offers very strong performance.

### Common Lisp: Solid Middle Ground

Came in second, which shocked me. Backend compiled clean to a binary—deployment took some docker work but fairly straightforward. Vanilla JS \+ PixiJS handled the canvas fine, drag-and-drop mostly smooth. Auth was basic email/password, no fuss (could add Auth0 later, didn’t realize how easy it would have been when i made the choice). Quirks: Some UI lag on fast draws that I never pinned down. But overall? Functional MVP. AI grokked Lisp's syntax almost flawlessly, and the simplicity let it focus. Fun to tinker, but not the star. Had a couple times where it screwed up the parenthesis (AI is almost human, I guess?), but I think a good linter or similar would have made this a non-issue.

### Svelte/Bun/Elysia: Dependency Issues

The "easy" one fought me tooth and nail. Bun's quirks (not quite Node) tripped up deps—AI kept suggesting Node swaps, ignoring my CLAUDE.md rules. WebSockets? Different syntax/api, was a nightmare. Connection drops, lifecycle bugs, endless loops of pasting the same error over and over in Claude Code. Eventually I tried grok-code-fast-1, and was shocked it finally got past the websocket connection issue where Claude whiffed repeatedly. By this point though the Elixir one was done. Root issue: I didn’t put enough information into the PRD and tasks to provide strong guide rails on the environment and stack. I thought it would infer from the environment being set up, but that was not sufficient. Now, I could pivot to node and react in probably an hour, but given that the Elixir one is in great shape,  I prefer that anyway for realtime collaboration. Phoenix humming in the background while I wrestled Bun / Elysia. Lisp chugged steadily. By 2-3 hours in (after I had all the PRDs and tasks lined up), Phoenix was mvp-ready; Lisp close behind.

## Day 2

I spent most of day 2 working on cleaning up stray markdown files, cleaning up the code, and refactoring the concurrency conflict resolution model. Initially we used last write wins for the Common Lisp and Elixir approaches. Once those were working, I went back and changed that to use an object locking model, where once one user selects the object, it locks it so another user cannot select the same object until it's released by the first user. There's still theoretically a possible race condition where you end up with last-write-wins, but in combination with fast websockets and sqlite on backend, I chose this tradeoff for performance and simplicity.

## Tool Breakdown

- **Claude Code (Sonnet 4.5):** Nailed architecture, stuck to the PRD/tasks like glue. Great with Task Master—systematic task-crushing. Weak spot: Parallel agents. It pretends, but mostly still sequences them. Still, 80% autonomous wins.  
- **Cursor:** Pop in for "show me this component" or quick diffs—faster than scrolling Claude's output. Paired it with Claude for edits.  
- **Grok (code-fast-1):** Speed demon. Blitzed refactors I thought would suck—canvas tweaks, auth wiring. But man, it *loves* coding. Tell it "analyze only"? Ignores, spits code. Workflow approach: Separate Git worktree, let it rip, diff-review in Claude. Didn’t have to refactor like I expected, but would have been easy to do just leave it behind. Possible goal: Integrate as a tool / mcp server inside Claude Code.  
- **Task Master:** Game-changer. Decomposition kept scope tight; complexity scans flagged WebSocket hell early. That human review step more critical than I even realized..

## The Wins, Fails, and "Aha" Moments

| Stack | Expectation | Reality | Why It Worked (or Didn't) |
| ----- | ----- | ----- | ----- |
| Phoenix/Elixir | Slow & painful | First across the line | Killer PRD \+ compiler context |
| Common Lisp | Buggy curiosity | Surprisingly solid | Simple deploy, low drama auth |
| Svelte/Bun | Quick win | Endless frustration | Skimpy guardrails,, Bun weirdness |

**Big Insights:**

1. **Planning \> Everything.** PRD depth let Phoenix fly solo. Future me: 3x time on specs, always.  
2. **Compilers Can Provide Great Context.** Elixir's errors were crystal—fixed fast. Types/functional forced clean code. (Elm flashbacks: I’ve used this approach with Elm on frontend in the past. Didn’t make sense for this given the canvas aspect).   
3. **Esoteric vs Familiar:** had more issues with code that looked familiar but should be subtly different (bun / elysia) than I did code that was really off the beaten path (Common Lisp)

**Takeaways:**Highest ROI? Planning loops. Phoenix: Strong performance and features, prettiest UI, rock-solid foundation, easy scale. Lisp was fun, and it could really work for this, but with scale would take a lot more work to stay performant — erlang gives us that by design. Plus the Elixir ai generated a way slicker UI than the Common Lisp one, for whatever reason.

**Note:** you can see the PRD and some post-generated mermaid diagrams in the /notes folder in the root of my project

**Elixir/Phoenix:** 

* [https://github.com/pyrex41/ph-beam](https://github.com/pyrex41/ph-beam)  
* 

**Common Lisp:** [https://github.com/pyrex41/cl-fun](https://github.com/pyrex41/cl-fun) (not as polished)  
