# PRD 4.0: Professional Workflow & Polish

## Executive Summary

This PRD defines the "Tier 3" power features that enable professional, asynchronous workflows and provide an exceptional level of polish. These features make the tool indispensable for teams and position it as a production-ready professional design platform.

## Performance Requirements

- **Version History:** Loading and restoring versions must complete within **1 second**
- **Comments:** Creating and loading comments must complete within **200ms**
- **Export:** PNG export for 1000x1000px canvas must complete within **2 seconds**
- **Undo/Redo:** Undo operations must execute within **100ms**
- **Overall:** All UI interactions must feel instant (<100ms feedback)

## Core Features

### 4.1 Version History

**User Story:** As a team lead, I can view a history of all major changes to a canvas, see who made them, and restore the canvas to a previous point in time.

**Requirements:**

1. **Automatic Snapshots**
   - Create snapshot on canvas save (manual trigger)
   - Auto-snapshot every N changes (configurable, default: 50)
   - Auto-snapshot on time interval (e.g., every 30 minutes with changes)
   - Snapshot on major events: component creation, bulk delete
   - Maximum snapshots per canvas: 100 (auto-delete oldest)

2. **Version Metadata**
   - Timestamp of snapshot
   - User who triggered the snapshot
   - Number of objects in snapshot
   - Optional description/message
   - Thumbnail preview of canvas state
   - Change summary: "Added 3 objects, deleted 1, modified 5"

3. **Version History UI**
   - Timeline view showing all versions
   - Side-by-side comparison of two versions
   - Preview version without committing (read-only mode)
   - Search/filter versions by date, user, description
   - Restore button with confirmation dialog

4. **Version Restore**
   - Restore creates new version (non-destructive)
   - Current state is auto-saved before restore
   - Restore confirmation: "This will restore to [date]. Current work will be saved as a new version."
   - After restore, broadcast to all connected users
   - Show notification: "Canvas restored to version from [date] by [user]"

5. **Version Comparison**
   - Visual diff showing added (green), removed (red), modified (blue) objects
   - Attribute diff: show specific property changes
   - Option to selectively restore specific objects
   - Export diff report as text/JSON

6. **Storage Optimization**
   - Store snapshots as deltas when possible
   - Compress snapshot data
   - Periodic full snapshots for faster restore
   - Clean up old snapshots based on retention policy

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: canvas_versions
create table(:canvas_versions) do
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :version_number, :integer
  add :description, :text
  add :created_by, :string
  add :snapshot_data, :binary  # Compressed JSON
  add :object_count, :integer
  add :change_summary, :map
  add :thumbnail_url, :string
  add :is_auto_snapshot, :boolean, default: false

  timestamps()
end

create index(:canvas_versions, [:canvas_id, :inserted_at])
```

- **Backend:**
  - Context: `lib/collab_canvas/versions.ex`
  - Functions:
    - `create_snapshot(canvas_id, user_id, description \\ nil)`
    - `get_versions(canvas_id, opts \\ [])`
    - `restore_version(canvas_id, version_id, user_id)`
    - `compare_versions(version_id_1, version_id_2)`
  - Background job for auto-snapshots
  - Compression using `:zlib.compress/1`

- **Frontend:**
  - New LiveView page: `VersionHistoryLive`
  - Timeline component with version cards
  - Comparison view with split screen
  - Preview mode overlay

**API Changes:**

```elixir
# New events
handle_event("create_snapshot", %{"description" => desc}, socket)
handle_event("restore_version", %{"version_id" => id}, socket)
handle_event("preview_version", %{"version_id" => id}, socket)
handle_event("compare_versions", %{
  "version_id_1" => id1,
  "version_id_2" => id2
}, socket)
```

**Acceptance Criteria:**

- Snapshots are created automatically based on configured rules
- Users can view complete version history with thumbnails
- Version restore works correctly and is non-destructive
- Comparison view shows clear visual diff
- All operations complete within performance SLA
- Storage optimization keeps database size manageable

---

### 4.2 Collaborative Comments

**User Story:** As a collaborator, I can drop a pin anywhere on the canvas, write a comment, and @mention a team member to review it.

**Requirements:**

1. **Comment Creation**
   - Tool mode: "Comment" tool in toolbar (shortcut: C)
   - Click anywhere on canvas to drop a comment pin
   - Comment input appears immediately
   - Support markdown in comments
   - Attach comment to specific object (optional)

2. **Comment Threads**
   - Reply to comments to create threads
   - Nested replies (up to 3 levels)
   - Like/emoji reactions on comments
   - Edit and delete own comments
   - Timestamp and user attribution

3. **@Mentions**
   - Type @ to trigger mention autocomplete
   - Mention specific users: @username
   - Mention everyone: @all
   - Send notification to mentioned users
   - Email notification for offline users

4. **Comment States**
   - Open (default state)
   - Resolved (checkmark, archived)
   - Show/hide resolved comments toggle
   - Reopen resolved comments
   - Filter by status

5. **Comment Positioning**
   - Pin shows at exact canvas coordinates
   - Pin follows object if attached to object
   - Pin number badge (e.g., "12" for comment #12)
   - Thread with multiple comments shows count badge
   - Hover to preview comment content

6. **Comments Panel**
   - Sidebar showing all comments
   - Filter by: status, author, date, mentioned user
   - Click to jump to comment on canvas
   - Sort by: date, status, thread activity
   - Unread comments indicator

7. **Notifications**
   - In-app notification badge
   - Browser push notifications (opt-in)
   - Email digest for mentions
   - Real-time presence: show who's typing

**Technical Implementation:**

- **Database Schema:**

```elixir
# New table: comments
create table(:comments) do
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :object_id, references(:objects, on_delete: :nilify)
  add :parent_comment_id, references(:comments, on_delete: :cascade)
  add :content, :text
  add :position_x, :float
  add :position_y, :float
  add :created_by, :string
  add :resolved_at, :utc_datetime
  add :resolved_by, :string

  timestamps()
end

# New table: comment_mentions
create table(:comment_mentions) do
  add :comment_id, references(:comments, on_delete: :cascade)
  add :user_id, :string
  add :read_at, :utc_datetime

  timestamps()
end

# New table: comment_reactions
create table(:comment_reactions) do
  add :comment_id, references(:comments, on_delete: :cascade)
  add :user_id, :string
  add :emoji, :string

  timestamps()
end
```

- **Backend:**
  - Context: `lib/collab_canvas/comments.ex`
  - Functions:
    - `create_comment(canvas_id, attrs)`
    - `reply_to_comment(parent_id, attrs)`
    - `resolve_comment(comment_id, user_id)`
    - `add_reaction(comment_id, user_id, emoji)`
  - PubSub broadcasts for real-time updates
  - Email notification job for mentions

- **Frontend:**
  - New tool mode in `CanvasRenderer`: Comment tool
  - Comment pin component (PixiJS sprite)
  - New LiveComponent: `CommentsPanelLive`
  - Comment thread component with replies
  - Mention autocomplete input

**API Changes:**

```elixir
# New events
handle_event("create_comment", %{
  "content" => content,
  "position" => %{"x" => x, "y" => y},
  "object_id" => object_id  # optional
}, socket)

handle_event("reply_comment", %{
  "parent_id" => parent_id,
  "content" => content
}, socket)

handle_event("resolve_comment", %{"comment_id" => id}, socket)
handle_event("add_reaction", %{
  "comment_id" => id,
  "emoji" => emoji
}, socket)
```

**Acceptance Criteria:**

- Comment pins can be placed anywhere on canvas
- Comments appear in real-time for all users
- @Mentions trigger notifications correctly
- Resolved comments can be hidden/shown
- Comments panel provides comprehensive filtering
- All comment operations sync instantly across clients

---

### 4.3 High-Fidelity Export

**User Story:** As a user, I need to export my entire canvas or a selection of objects as a high-quality PNG or SVG file for use in other applications.

**Requirements:**

1. **Export Formats**
   - PNG (raster): multiple resolutions (1x, 2x, 3x)
   - SVG (vector): with embedded fonts and styles
   - PDF: single page or multi-artboard
   - JPG: with quality slider

2. **Export Scope**
   - Entire canvas
   - Selected objects only
   - Specific artboard
   - Multiple artboards as separate files or single PDF

3. **Export Settings**
   - Resolution/scale factor (1x, 2x, 3x, custom)
   - Background: transparent, white, canvas color, custom
   - Include/exclude: hidden objects, comments, grid
   - Trim transparent edges option
   - File naming template

4. **PNG Export**
   - Use PixiJS renderer to generate bitmap
   - Support high DPI (2x, 3x for retina)
   - Optional background color
   - Maintain exact visual fidelity

5. **SVG Export**
   - Convert PixiJS objects to SVG elements
   - Preserve vector quality
   - Embed fonts or convert to paths
   - Include CSS styles
   - Proper layer ordering

6. **Batch Export**
   - Export all artboards at once
   - Export all components
   - Export at multiple scales simultaneously
   - Generate ZIP file for batch exports

7. **Export Queue**
   - Large exports run as background jobs
   - Show progress indicator
   - Notification when export complete
   - Download link expires after 24 hours

**Technical Implementation:**

- **Frontend (Primary):**
  - PNG export using PixiJS `renderer.extract`:

```javascript
async function exportToPNG(canvas, objects, scale = 1, backgroundColor = null) {
  const app = canvas.app;
  const bounds = calculateBounds(objects);

  // Create temporary container
  const tempContainer = new PIXI.Container();
  objects.forEach(obj => tempContainer.addChild(obj.clone()));

  // Add background if specified
  if (backgroundColor) {
    const bg = new PIXI.Graphics();
    bg.beginFill(backgroundColor);
    bg.drawRect(bounds.x, bounds.y, bounds.width, bounds.height);
    tempContainer.addChildAt(bg, 0);
  }

  // Extract and scale
  const canvas = app.renderer.extract.canvas(tempContainer);
  const scaledCanvas = scaleCanvas(canvas, scale);

  // Trigger download
  const blob = await canvasToBlob(scaledCanvas);
  downloadBlob(blob, `canvas-export-${Date.now()}.png`);

  tempContainer.destroy();
}
```

- **SVG Export Library:**
  - Use or create a PixiJS-to-SVG converter
  - Map PixiJS primitives to SVG elements:
    - Rectangle → `<rect>`
    - Circle → `<circle>`
    - Text → `<text>` with font attributes
    - Image → `<image>` with embedded base64

- **Backend (For Large Exports):**
  - Use headless browser (Puppeteer/ChromeDP)
  - Render canvas server-side
  - Generate export file
  - Store in temporary S3/storage
  - Return download URL

- **Database Schema:**

```elixir
# New table: export_jobs (for async exports)
create table(:export_jobs) do
  add :canvas_id, references(:canvases, on_delete: :cascade)
  add :user_id, :string
  add :format, :string  # "png", "svg", "pdf"
  add :settings, :map
  add :status, :string  # "pending", "processing", "completed", "failed"
  add :file_url, :string
  add :expires_at, :utc_datetime

  timestamps()
end
```

**API Changes:**

```elixir
# New events
handle_event("export_canvas", %{
  "format" => format,
  "scope" => scope,  # "all", "selection", "artboard"
  "settings" => settings
}, socket)

handle_event("get_export_status", %{"job_id" => id}, socket)
```

**Acceptance Criteria:**

- PNG export produces pixel-perfect output
- SVG export maintains vector quality
- Exports work for large canvases (5000x5000px)
- Batch export generates ZIP with all files
- Background job system handles large exports
- All exports complete within performance SLA

---

### 4.4 Per-User Undo/Redo

**User Story:** As a user, I can undo and redo my own actions using Ctrl+Z / Ctrl+Shift+Z without affecting the actions of my collaborators.

**Requirements:**

1. **Per-User Action Stack**
   - Each user maintains their own undo/redo stack
   - Stack persists across browser refresh (localStorage)
   - Maximum stack size: 100 actions
   - Clear stack on canvas switch

2. **Undoable Actions**
   - Create object
   - Delete object
   - Update object (move, resize, rotate, style)
   - Group/ungroup
   - Create component
   - Apply style
   - AI-generated changes

3. **Action Recording**
   - Record inverse operation for each action
   - Store minimal data needed to reverse
   - Batch related operations (e.g., multi-select move)
   - Include timestamp and user ID

4. **Undo Behavior**
   - Ctrl+Z / Cmd+Z: Undo last action
   - Sends inverse event to server
   - Removes action from undo stack
   - Adds action to redo stack
   - Shows toast: "Undone: Created rectangle"

5. **Redo Behavior**
   - Ctrl+Shift+Z / Cmd+Shift+Z: Redo last undone action
   - Replays original event
   - Moves action back to undo stack
   - Shows toast: "Redone: Created rectangle"

6. **Collaborative Considerations**
   - Only undo own actions, not collaborators'
   - If object was modified by another user since your action, show warning
   - Option: "Force undo" or "Cancel"
   - Track object ownership for each action

7. **Complex Scenarios**
   - Undo a create when object was later modified by someone else: prompt user
   - Undo a delete when object ID is reused: prevent undo
   - Undo a group when group was later modified: ungroup and restore original positions

8. **UI Feedback**
   - Grayed out undo/redo buttons when stack is empty
   - Show action description on hover
   - Undo history panel (optional): list of all actions with undo button per action

**Technical Implementation:**

- **Frontend (Primary):**

```javascript
// hooks/undo_manager.js
class UndoManager {
  constructor() {
    this.undoStack = this.loadFromLocalStorage('undo') || [];
    this.redoStack = [];
  }

  recordAction(action) {
    this.undoStack.push(action);
    this.redoStack = []; // Clear redo stack on new action
    this.trimStack();
    this.saveToLocalStorage();
  }

  undo() {
    if (this.undoStack.length === 0) return;

    const action = this.undoStack.pop();
    this.redoStack.push(action);

    // Execute inverse operation
    this.executeInverse(action);
    this.saveToLocalStorage();
  }

  redo() {
    if (this.redoStack.length === 0) return;

    const action = this.redoStack.pop();
    this.undoStack.push(action);

    // Re-execute original operation
    this.executeAction(action);
    this.saveToLocalStorage();
  }

  executeInverse(action) {
    switch (action.type) {
      case 'create':
        this.socket.push('delete_object', { id: action.objectId });
        break;
      case 'delete':
        this.socket.push('create_object', action.objectData);
        break;
      case 'update':
        this.socket.push('update_object', {
          id: action.objectId,
          data: action.previousData
        });
        break;
      // ... more cases
    }
  }
}
```

- **Action Recording Pattern:**

```javascript
// When user creates object
const action = {
  type: 'create',
  objectId: newObject.id,
  timestamp: Date.now(),
  userId: currentUser.id
};
undoManager.recordAction(action);

// When user updates object
const action = {
  type: 'update',
  objectId: object.id,
  previousData: object.data.clone(),
  newData: updatedData,
  timestamp: Date.now(),
  userId: currentUser.id
};
undoManager.recordAction(action);
```

- **Backend:**
  - No schema changes needed
  - Server validates undo/redo operations
  - Check if object still exists and wasn't locked
  - Return error if undo not possible

**API Changes:**

```elixir
# Use existing events, but add metadata
handle_event("delete_object", %{
  "id" => id,
  "is_undo" => true  # Flag for undo operation
}, socket)
```

**Acceptance Criteria:**

- Users can undo/redo their own actions
- Undo stack persists across browser refresh
- Collaborative conflicts are handled gracefully
- UI clearly indicates when undo/redo is available
- Complex multi-object actions can be undone as unit
- Performance impact is negligible (<10ms per action recording)

---

## Additional Polish Features

### 4.5 Keyboard Shortcuts

**Requirements:**
- Comprehensive keyboard shortcut system
- Shortcuts panel (press ? to show)
- Customizable shortcuts
- Context-aware shortcuts (tool-specific)
- Vim mode support (optional)

**Key Shortcuts:**
- V: Select tool
- R: Rectangle tool
- C: Circle tool
- T: Text tool
- H: Hand/Pan tool
- Z: Zoom tool
- Cmd+D: Duplicate
- Cmd+G: Group
- Cmd+Shift+G: Ungroup
- Cmd+]: Bring forward
- Cmd+[: Send backward

### 4.6 Canvas Navigation

**Requirements:**
- Zoom: pinch, scroll, zoom tool, Cmd+/Cmd-
- Pan: spacebar+drag, middle mouse drag, hand tool
- Fit to screen: Cmd+0
- Zoom to selection: Cmd+2
- Zoom to 100%: Cmd+1
- Mini-map overview (bottom right corner)

### 4.7 Performance Monitoring

**Requirements:**
- FPS counter (dev mode)
- Latency indicator
- Object count indicator
- Memory usage monitoring
- Performance warnings for large canvases

### 4.8 Accessibility

**Requirements:**
- Keyboard navigation for all features
- Screen reader support for UI panels
- High contrast mode
- Focus indicators
- ARIA labels on all interactive elements

### 4.9 Onboarding

**Requirements:**
- Interactive tutorial for first-time users
- Contextual tooltips
- Sample canvas templates
- Video tutorials library
- Keyboard shortcuts cheat sheet

---

## Testing Requirements

1. **Version History Tests**
   - Test snapshot creation and restoration
   - Test with large canvases (1000+ objects)
   - Test comparison view accuracy
   - Test storage optimization

2. **Comments Tests**
   - Test comment creation and threading
   - Test @mentions and notifications
   - Test resolved/unresolved states
   - Test real-time sync with multiple users

3. **Export Tests**
   - Test PNG export at various scales
   - Test SVG export quality
   - Test batch export functionality
   - Test with various canvas sizes

4. **Undo/Redo Tests**
   - Test all undoable action types
   - Test collaborative undo scenarios
   - Test stack persistence
   - Test conflict resolution

5. **Polish Tests**
   - Test all keyboard shortcuts
   - Test canvas navigation
   - Test accessibility features
   - Test onboarding flow

## Success Metrics

- Version restore completes within 1 second
- Comments load within 200ms
- Export completes within 2 seconds for standard sizes
- Undo/redo executes within 100ms
- 99% of keyboard shortcuts work correctly
- Accessibility score >90% (WCAG 2.1 AA)
- User onboarding completion rate >80%
- User satisfaction rating of 4.8+/5 for overall polish
- Professional teams report 50% efficiency improvement
