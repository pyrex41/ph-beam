# CollabCanvas - Technical Architecture Summary

**Real-Time Collaborative Design Tool with AI-Powered Canvas Manipulation**

---

## Technology Stack

### Backend
- **Elixir 1.15+ / Phoenix 1.7+**
  - Built-in concurrency and fault tolerance
  - Phoenix LiveView 0.20+ for real-time server-rendered UX
  - Minimal JavaScript required

- **Data Layer**
  - **Ecto 3.11+ with SQLite** (MVP)
    - Zero-configuration embedded database
    - Built-in ACID transactions
    - Perfect for moderate traffic (100s of users)
    - Clear migration path to Redis when needed

- **Authentication**
  - **Auth0** - Professional auth in 15 minutes
  - **Ueberauth** - OAuth integration framework
  - Social login (Google, GitHub) with zero config

### Frontend
- **PixiJS 7.x**
  - WebGL 2D rendering engine
  - GPU-accelerated, 10,000+ objects at 60 FPS
  - WebGL API for high-performance graphics

- **Alpine.js 3.x**
  - Lightweight reactive UI (~15KB)
  - Declarative reactivity for toolbars and controls

- **Tailwind CSS**
  - Utility-first styling
  - Rapid UI development

### AI & APIs
- **Anthropic Claude API**
  - Function calling for natural language → canvas actions
  - Executes commands like "create a login form"
  - Multi-step operation support

### Infrastructure
- **Fly.io**
  - Deployment with persistent volumes for SQLite
  - Global edge network
  - Simple scaling

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Browser Client                           │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────────┐│
│  │  Alpine.js   │  │  PixiJS        │  │  LiveView Socket     ││
│  │  (UI Layer)  │  │  (WebGL Canvas)│  │  (Real-time)         ││
│  └──────────────┘  └────────────────┘  └──────────────────────┘│
└──────────────────────────────┼────────────────────────────────────┘
                               │ WebSocket (Phoenix Channel)
┌──────────────────────────────┼────────────────────────────────────┐
│                    Phoenix LiveView Server                        │
│  ┌──────────────────────────────────────────────────────────────┐│
│  │                  Canvas LiveView Process                      ││
│  │  • Manages canvas state                                       ││
│  │  • Broadcasts updates via PubSub                              ││
│  │  • Coordinates AI agent                                       ││
│  │  • Enforces authorization                                     ││
│  └──────────────────────────────────────────────────────────────┘│
│           │                    │                    │              │
│  ┌────────────────┐  ┌─────────────────┐  ┌──────────────────┐  │
│  │ Phoenix.PubSub │  │  SQLite (Ecto)  │  │   Claude AI API  │  │
│  │ (Broadcasting) │  │  • Canvas state │  │  • Function call │  │
│  │                │  │  • User data    │  │  • NL→Actions    │  │
│  │                │  │  • Objects      │  │                  │  │
│  └────────────────┘  └─────────────────┘  └──────────────────┘  │
└───────────────────────────────────────────────────────────────────┘
                               │
┌──────────────────────────────┼────────────────────────────────────┐
│                          Auth0                                    │
│  • User authentication                                            │
│  • Social login (Google, GitHub)                                  │
│  • JWT token management                                           │
└───────────────────────────────────────────────────────────────────┘
```

---

## Core Features

### Real-Time Collaboration
- **Multiplayer Canvas**
  - Multiple users editing simultaneously
  - < 100ms latency for object synchronization
  - Optimistic updates for instant feedback

- **Presence System**
  - Phoenix.Presence with CRDT (Conflict-free Replicated Data Types)
  - Real-time user tracking
  - Distributed consensus without coordination

- **Multiplayer Cursors**
  - Real-time cursor positions via PubSub
  - Name labels and color-coded per user
  - Smooth interpolation

### Canvas Capabilities
- **Shape Types**
  - Rectangles with fill/stroke
  - Circles with customizable properties
  - Text with font family, size, styling

- **Transformations**
  - Move (drag and drop)
  - Resize (handles and constraints)
  - Rotate (angle manipulation)

- **Selection System**
  - Single object selection
  - Multi-select with bounding box
  - Keyboard shortcuts

- **Layer Management**
  - Z-index ordering
  - Bring to front / send to back
  - Layer visibility controls

- **Canvas Controls**
  - Pan (Space + drag)
  - Zoom (scroll wheel)
  - Viewport culling for performance

### AI Agent Features
- **Natural Language Commands**
  - Basic: "create a rectangle at 100, 100"
  - Layout: "arrange these in a grid"
  - Complex: "create a login form with email and password"

- **Claude Function Calling**
  - Structured output for canvas operations
  - Multi-step command execution
  - Context-aware suggestions

- **Real-Time Broadcasting**
  - AI operations synced to all users
  - Operation streaming for feedback
  - Undo/redo support

### Authentication & Authorization
- **Auth0 Integration**
  - Social login (Google, GitHub)
  - JWT token management
  - Session persistence

- **User Management**
  - User profiles with avatars
  - Canvas ownership and sharing
  - Activity tracking

---

## Technical Design Choices

### Why Phoenix LiveView?
- **Built-in Real-Time:** WebSocket connections managed automatically
- **Server-Rendered:** Minimal client-side JavaScript
- **PubSub Integration:** Broadcast to thousands of users efficiently
- **Presence Tracking:** CRDT-based presence with no central coordination
- **Fault Tolerance:** OTP supervision trees for reliability

### Why SQLite (for MVP)?
- **Zero Configuration:** No separate database server required
- **ACID Transactions:** Built-in data integrity
- **SQL Familiarity:** Standard query language
- **Native Relations:** Foreign keys and joins
- **Cost:** Completely free
- **Perfect for MVP:** Handles 100s of concurrent users
- **Easy Migration:** Clear path to Redis when scaling needed

**SQLite vs Redis Trade-offs:**

| Aspect | SQLite (MVP) | Redis (Production Scale) |
|--------|-------------|--------------------------|
| Latency | ~5-10ms | Sub-millisecond |
| Setup | Zero-config | Requires service |
| Persistence | Built-in ACID | Requires RDB/AOF |
| Query Language | SQL | Custom commands |
| Cost | Free | $10-50/month |
| Scaling | 100s users | 1000s+ users |
| Relations | Native | Manual |

### Why PixiJS?
- **GPU Acceleration:** WebGL for hardware rendering
- **Performance:** 10,000+ objects at 60 FPS
- **Scene Graph:** Hierarchical object management
- **Plugin Ecosystem:** Rich features (filters, particles, etc.)
- **Production Ready:** Battle-tested by major apps

### Why Alpine.js?
- **Lightweight:** ~15KB vs React's ~100KB+
- **Declarative:** HTML-first approach
- **No Build Step:** Works directly in browser
- **Perfect for LiveView:** Minimal client-side state management

### Data Synchronization Strategy

**Optimistic Updates + Server Authority:**
1. **Client Action:** User drags object
2. **Optimistic Render:** PixiJS updates immediately (no latency)
3. **Server Event:** LiveView receives position update
4. **Database Write:** Ecto persists to SQLite
5. **PubSub Broadcast:** All other users notified
6. **Client Sync:** Other clients update their PixiJS scenes
7. **Reconciliation:** Server state is authoritative on conflicts

**Benefits:**
- Instant local feedback (optimistic)
- Consistent eventual state (server authority)
- Conflict resolution via timestamps

### Real-Time Architecture

**Phoenix.PubSub for Broadcasting:**
- Topic-based: `canvas:#{canvas_id}`
- Process-to-process messaging
- Distributed across nodes
- Low latency (< 10ms)

**Phoenix.Presence for User Tracking:**
- CRDT-based (Conflict-free Replicated Data Types)
- No central coordination needed
- Automatic conflict resolution
- Distributed consensus

**Cursor Updates:**
- Fast path via PubSub (no database writes)
- Throttled to ~30 updates/second per user
- Interpolation on receiving clients

### AI Integration Pattern

**Asynchronous Task Execution:**
```elixir
# User sends AI command
task = Task.async(fn ->
  Claude.execute_command(canvas_id, command, objects, user_id)
end)

# AI returns operations
{:ok, operations} = Task.await(task)

# Execute operations and broadcast
Enum.each(operations, fn op ->
  execute_operation(op)
  PubSub.broadcast("canvas:#{canvas_id}", {:ai_operation, op})
end)
```

**Benefits:**
- Non-blocking (doesn't freeze UI)
- Supports multi-step operations
- Real-time streaming of results
- Broadcast to all collaborators

---

## Data Models

### User Schema
```elixir
schema "users" do
  field :email, :string
  field :name, :string
  field :avatar, :string
  field :provider, :string          # "auth0", "google", "github"
  field :provider_uid, :string
  field :last_login, :utc_datetime

  has_many :owned_canvases, Canvas, foreign_key: :owner_id
  timestamps()
end
```

### Canvas Schema
```elixir
schema "canvases" do
  field :name, :string

  belongs_to :owner, User
  has_many :objects, Object
  timestamps()
end
```

### Object Schema
```elixir
schema "objects" do
  field :type, :string              # "rectangle", "circle", "text"
  field :x, :float
  field :y, :float
  field :width, :float
  field :height, :float
  field :rotation, :float
  field :fill, :string              # "#FF0000"
  field :stroke, :string
  field :text, :string              # For text objects
  field :font_size, :integer
  field :font_family, :string
  field :z_index, :integer

  belongs_to :canvas, Canvas
  belongs_to :creator, User, foreign_key: :created_by
  belongs_to :modifier, User, foreign_key: :modified_by
  timestamps()
end
```

---

## Performance Considerations

### Target Metrics
- **Latency:** < 100ms object sync between users
- **FPS:** 60 FPS with 1,000+ objects on canvas
- **Concurrent Users:** 100+ per canvas (SQLite), 1,000+ (Redis)
- **AI Response:** < 3s for simple commands

### Optimization Techniques
- **Viewport Culling:** Only render visible objects
- **Object Pooling:** Reuse PixiJS graphics objects
- **Batched Updates:** Group database writes
- **Cursor Throttling:** Limit position updates
- **Lazy Loading:** Load canvas objects on demand
- **Index Optimization:** Database indexes on `canvas_id`, `z_index`

---

## Security Architecture

### Authentication Layer
- **Auth0:** Industry-standard OAuth 2.0
- **JWT Tokens:** Stateless session management
- **Secure Cookies:** HTTPOnly, Secure flags

### Authorization Model
- **Canvas Ownership:** Only owner can delete canvas
- **Collaborative Editing:** Any authenticated user can edit
- **Operation Validation:** Server-side checks on all mutations

### Input Validation
- **Ecto Changesets:** Type validation and constraints
- **Phoenix CSRF:** Built-in CSRF protection
- **Rate Limiting:** Prevent AI command abuse

---

## Conflict Resolution

### Last-Write-Wins (LWW)
- **Timestamps:** Server timestamps for all updates
- **Authority:** Server state is authoritative
- **Resolution:** Most recent update wins

### CRDT for Presence
- **Phoenix.Presence:** Built-in CRDT
- **No Conflicts:** Mathematically guaranteed consistency
- **Distributed:** Works across multiple nodes

---

## Future: Redis Migration Path

### When to Migrate
- Beyond 100s of concurrent users per canvas
- Need for sub-millisecond latency
- Distributed deployment across regions
- Need for ephemeral data with TTL

### Migration Strategy
1. **Phase 1:** Redis for ephemeral data (cursors, presence)
2. **Phase 2:** Redis as read-through cache for objects
3. **Phase 3:** Full migration with SQLite as backup

### Technical Changes
```elixir
# SQLite (Current)
Repo.all(from o in Object, where: o.canvas_id == ^canvas_id)

# Redis (Future)
Redis.command(["SMEMBERS", "canvas:#{canvas_id}:objects"])
|> Enum.map(&Redis.command(["HGETALL", "object:#{&1}"]))
```

---

## Key Takeaways

1. **Phoenix LiveView** provides built-in real-time infrastructure
2. **SQLite** enables rapid MVP development with zero configuration
3. **PixiJS** delivers 60 FPS WebGL rendering with GPU acceleration
4. **Phoenix.Presence** offers CRDT-based user tracking
5. **Claude AI** enables natural language canvas manipulation
6. **Optimistic updates** provide instant local feedback
7. **Server authority** ensures eventual consistency
8. **Clear migration path** from SQLite to Redis when scaling

**Architecture Philosophy:** Start simple (SQLite), scale when needed (Redis).
