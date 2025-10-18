# CollabCanvas

A real-time collaborative canvas application with AI-powered design assistance. Think Figma-lite with intelligent natural language commands - multiple users can simultaneously create, edit, and manipulate shapes, text, and UI components on a shared canvas with real-time synchronization.

## Features

### Real-Time Collaboration
- Multi-user simultaneous editing with live cursor tracking
- Real-time object creation, manipulation, and deletion
- Conflict-free editing with smart object locking
- Per-user viewport persistence (pan/zoom state saved)

### AI-Powered Design
- Natural language canvas commands ("create 3 blue circles in a row")
- Intelligent layout algorithms (grid, circular, constraint-based)
- Component generation (login forms, navigation bars, cards)
- Semantic object selection and arrangement
- Support for multiple AI providers (Claude, OpenAI, Groq)

### Canvas Features
- Shape creation (rectangles, circles, text)
- Object manipulation (drag, resize, rotate)
- Pan and zoom controls
- Object locking and selection
- Batch operations for multiple objects
- High-performance rendering with PixiJS

## Tech Stack

### Backend
- **Elixir 1.15+** - Functional, concurrent programming
- **Phoenix 1.8** - Web framework
- **Phoenix LiveView 1.1** - Real-time server-rendered UI
- **Ecto 3.13** - Database wrapper and query generator
- **SQLite** - Embedded database

### Frontend
- **JavaScript (ES6+)** - Modern browser scripting
- **PixiJS v8** - WebGL-powered 2D rendering engine
- **Vite** - Fast ESM bundler
- **Tailwind CSS 4.1.7** - Utility-first CSS framework

### Infrastructure
- **Phoenix PubSub** - Real-time message broadcasting
- **Phoenix Presence** - User presence tracking
- **Auth0** - Authentication via Ueberauth
- **Claude/OpenAI/Groq APIs** - AI command processing

## Getting Started

### Prerequisites

- **Elixir 1.15+** - [Install Elixir](https://elixir-lang.org/install.html)
- **Erlang/OTP 25+** - Usually installed with Elixir
- **Node.js 18+** - [Install Node.js](https://nodejs.org/)
- **SQLite 3** - Usually pre-installed on macOS/Linux

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd ph-beam/collab_canvas
```

2. Copy environment configuration:
```bash
cp .env.example .env
```

3. Configure environment variables in `.env`:
```bash
# Required for AI features (at least one)
CLAUDE_API_KEY=your_claude_api_key_here
# OPENAI_API_KEY=your_openai_api_key_here
# GROQ_API_KEY=your_groq_api_key_here

# Optional: Select AI provider (default: claude)
# AI_PROVIDER=claude  # or openai, groq

# Auth0 configuration (optional, for authentication)
AUTH0_DOMAIN=your_domain.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret
```

4. Install dependencies and set up the database:
```bash
mix setup
```

This command will:
- Install Elixir dependencies
- Create and migrate the database
- Install JavaScript dependencies
- Build frontend assets

5. Start the development server:
```bash
mix phx.server
```

6. Visit [http://localhost:4000](http://localhost:4000) in your browser

## Development Commands

### Server Management
```bash
# Start Phoenix server
mix phx.server

# Interactive Elixir shell with app loaded
iex -S mix phx.server
```

### Database Operations
```bash
# Create database
mix ecto.create

# Run migrations
mix ecto.migrate

# Rollback last migration
mix ecto.rollback

# Reset database (drop, create, migrate, seed)
mix ecto.reset

# Generate new migration
mix ecto.gen.migration migration_name
```

### Testing
```bash
# Run all tests
mix test

# Run specific test file
mix test test/path/to/file_test.exs

# Run specific test at line number
mix test test/path/to/file_test.exs:42
```

### Code Quality
```bash
# Run pre-commit checks (compile, format, test)
mix precommit

# Format code
mix format
```

### Asset Management
```bash
# Install JavaScript dependencies
npm install --prefix assets

# Build assets for production
npm run build --prefix assets

# Compile Tailwind CSS
mix tailwind collab_canvas
```

## Architecture Overview

### Real-Time Collaboration Flow

```
Client Action → LiveView Event → Server Processing → PubSub Broadcast → All Clients Update → Client Rendering
```

1. **Client Action** - User interacts with PixiJS canvas
2. **LiveView Event** - JavaScript hook sends event to Phoenix LiveView
3. **Server Processing** - LiveView validates and persists to SQLite
4. **PubSub Broadcast** - Change broadcast to all connected clients
5. **All Clients Update** - LiveViews receive broadcast via `handle_info/2`
6. **Client Rendering** - Server pushes update to JavaScript hooks, PixiJS renders

### AI Command Processing

```
User Command → AI Agent → Claude API → Tool Execution → Object Creation → PubSub Broadcast
```

- Natural language commands processed by AI Agent
- Function calling with 15+ tools (create_shape, arrange_objects, etc.)
- Non-blocking async execution with 30-second timeout protection
- Intelligent layout algorithms for complex arrangements

### Key Components

- **CanvasLive** (`lib/collab_canvas_web/live/canvas_live.ex`) - LiveView orchestration
- **Canvases Context** (`lib/collab_canvas/canvases.ex`) - Database operations
- **AI Agent** (`lib/collab_canvas/ai/agent.ex`) - Natural language processing
- **Canvas Manager** (`assets/js/hooks/canvas_manager.js`) - PixiJS rendering

## Project Structure

```
collab_canvas/
├── lib/
│   ├── collab_canvas/           # Business logic contexts
│   │   ├── accounts.ex          # User management
│   │   ├── canvases.ex          # Canvas/object CRUD
│   │   ├── components.ex        # Component templates
│   │   ├── styles.ex            # Shared styles
│   │   └── ai/                  # AI-powered features
│   │       ├── agent.ex         # AI command orchestration
│   │       ├── tools.ex         # AI tool definitions
│   │       ├── layout.ex        # Layout algorithms
│   │       └── component_builder.ex  # UI component generation
│   └── collab_canvas_web/       # Web layer
│       ├── live/                # LiveView modules
│       │   └── canvas_live.ex   # Main canvas interface
│       ├── controllers/         # HTTP controllers
│       └── components/          # Reusable UI components
├── assets/
│   ├── js/
│   │   ├── app.js               # Entry point
│   │   ├── hooks/               # LiveView hooks
│   │   │   └── canvas_manager.js  # Main PixiJS hook
│   │   └── core/                # Core PixiJS logic
│   │       ├── canvas_manager.js  # Object management
│   │       └── performance_monitor.js  # FPS tracking
│   └── css/
│       └── app.css              # Tailwind styles
├── priv/
│   └── repo/
│       └── migrations/          # Database migrations
├── test/                        # Test files
└── config/                      # Configuration files
```

## Task Master Integration

This project uses [Task Master AI](https://github.com/taskmaster-ai/taskmaster) for development workflow management. See `.taskmaster/CLAUDE.md` for detailed integration guide.

### Quick Start with Task Master

```bash
# View all tasks
task-master list

# Get next available task
task-master next

# View task details
task-master show <task-id>

# Mark task as complete
task-master set-status --id=<task-id> --status=done
```

## AI Commands Examples

```
"create 3 blue circles in a row"
"arrange all objects in a grid"
"create a login form"
"make all rectangles red"
"create a navigation bar"
"arrange objects in a circle"
"create a card component with title and description"
```

## Configuration

### AI Provider Selection

Set `AI_PROVIDER` in `.env` to choose your preferred AI backend:

```bash
AI_PROVIDER=claude   # Default - Anthropic Claude 3.5 Sonnet
AI_PROVIDER=openai   # OpenAI GPT-4
AI_PROVIDER=groq     # Groq Llama 3.3
```

### Authentication

Configure Auth0 credentials in `.env` for user authentication:

```bash
AUTH0_DOMAIN=your_domain.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret
```

## Performance Considerations

- Layout operations complete in <500ms for up to 50 objects
- Batch updates use transactional operations with single broadcast
- PixiJS rendering optimizations:
  - Object pooling for shapes
  - Texture atlasing for icons
  - Performance monitoring with FPS tracking
- Database queries use eager loading to avoid N+1 problems

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and formatting (`mix precommit`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Deployment

The application is configured for deployment with:

- Production asset compilation: `mix assets.deploy`
- Bandit web server (configured in `config/config.exs`)
- SQLite database (configurable path in `config/runtime.exs`)
- Fly.io configuration included (`fly.toml`)

## License

[Add your license here]

## Support

For issues, questions, or contributions, please open an issue on the repository.

---

Built with Elixir, Phoenix LiveView, and PixiJS
