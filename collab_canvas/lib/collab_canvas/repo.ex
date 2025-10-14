defmodule CollabCanvas.Repo do
  @moduledoc """
  Ecto repository for database access in CollabCanvas.

  This module serves as the primary interface for all database operations in the
  CollabCanvas application. It uses Ecto as the database wrapper and query generator,
  configured to use SQLite3 via the Exqlite adapter.

  ## Database Configuration

  The repository is configured with:
  - **Adapter**: `Ecto.Adapters.SQLite3` (via Exqlite package)
  - **OTP App**: `:collab_canvas`
  - **Database File**: `collab_canvas_dev.db` (development), `collab_canvas_test.db` (test)
  - **Location**: Configurable via `DATABASE_PATH` environment variable
  - **Pool Size**: 5 connections in development

  ### SQLite-Specific Considerations

  SQLite is an embedded, serverless database engine that:
  - Stores the entire database in a single file
  - Is well-suited for development and small-to-medium deployments
  - Has limited concurrency compared to PostgreSQL/MySQL
  - Automatically handles transactions and ACID compliance
  - Supports foreign key constraints (used for cascading deletes)

  ## Core Database Operations

  The Repo module provides standard Ecto repository functions for CRUD operations:

  ### Queries
  - `all/2` - Fetch all records matching a query
  - `get/3` - Fetch a single record by primary key
  - `get_by/3` - Fetch a single record by arbitrary field
  - `one/2` - Fetch exactly one record (raises if 0 or multiple)

  ### Modifications
  - `insert/2` - Insert a new record from a changeset
  - `update/2` - Update an existing record using a changeset
  - `delete/2` - Delete a record
  - `delete_all/2` - Delete all records matching a query

  ### Associations
  - `preload/3` - Eagerly load associations for structs

  ### Transactions
  - `transaction/2` - Execute multiple operations atomically
  - `rollback/1` - Manually rollback a transaction

  ## Usage Patterns in Context Modules

  The Repo is primarily accessed through context modules (e.g., `CollabCanvas.Canvases`,
  `CollabCanvas.Accounts`) that provide business logic layer over raw database operations.

  ### Standard CRUD Pattern

      # In a context module
      alias CollabCanvas.Repo
      import Ecto.Query

      def create_canvas(user_id, name) do
        %Canvas{}
        |> Canvas.changeset(%{user_id: user_id, name: name})
        |> Repo.insert()
      end

      def get_canvas(id) do
        Repo.get(Canvas, id)
      end

      def list_user_canvases(user_id) do
        Canvas
        |> where([c], c.user_id == ^user_id)
        |> order_by([c], desc: c.updated_at)
        |> Repo.all()
      end

      def update_object(id, attrs) do
        case Repo.get(Object, id) do
          nil -> {:error, :not_found}
          object ->
            object
            |> Object.changeset(attrs)
            |> Repo.update()
        end
      end

  ### Preloading Associations

      # Eager load relationships to avoid N+1 queries
      canvas = Repo.get(Canvas, id)
      canvas_with_objects = Repo.preload(canvas, :objects)

      # Preload in queries
      Canvas
      |> preload(:user)
      |> Repo.all()

  ### Transactions for Atomic Operations

      Repo.transaction(fn ->
        {:ok, canvas} = create_canvas(user_id, "New Canvas")
        {:ok, object} = create_object(canvas.id, "rectangle", %{})
        {canvas, object}
      end)

  ## Database Schema Management

  The repository manages several core schemas:
  - **Users**: Application users (via Auth0)
  - **Canvases**: Drawing workspaces belonging to users
  - **Objects**: Shapes and elements on canvases

  Database migrations are stored in `priv/repo/migrations/` and applied using:

      mix ecto.migrate

  ## Environment-Specific Configuration

  Configuration is environment-aware:
  - **Development**: Local SQLite file with verbose logging
  - **Test**: Separate test database with sandbox mode
  - **Production**: Configured via runtime environment variables

  See `config/dev.exs`, `config/test.exs`, and `config/runtime.exs` for details.

  ## Testing Considerations

  In tests, Ecto's SQL Sandbox provides transaction-based isolation:
  - Each test runs in a transaction that's rolled back
  - Tests can run concurrently without interfering
  - Database state is clean for each test

  ## Performance Notes

  - Use `preload/3` to avoid N+1 query problems
  - Leverage Ecto queries for complex filtering (avoid loading then filtering in Elixir)
  - SQLite supports indexes on frequently queried columns
  - Use `Repo.delete_all/2` for bulk deletions instead of iterating
  - Connection pooling is handled automatically by Ecto

  For more information, see:
  - [Ecto documentation](https://hexdocs.pm/ecto)
  - [Ecto.Repo documentation](https://hexdocs.pm/ecto/Ecto.Repo.html)
  - [Exqlite adapter](https://hexdocs.pm/exqlite)
  """

  use Ecto.Repo,
    otp_app: :collab_canvas,
    adapter: Ecto.Adapters.SQLite3
end
