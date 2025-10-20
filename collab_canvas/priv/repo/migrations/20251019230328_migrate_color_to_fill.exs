defmodule CollabCanvas.Repo.Migrations.MigrateColorToFill do
  use Ecto.Migration

  def up do
    # Migrate all objects with 'color' field to use 'fill' field instead
    execute """
    UPDATE objects
    SET data = json_set(
      json_remove(data, '$.color'),
      '$.fill',
      json_extract(data, '$.color')
    )
    WHERE json_extract(data, '$.color') IS NOT NULL
      AND json_extract(data, '$.fill') IS NULL
    """
  end

  def down do
    # Revert by copying 'fill' back to 'color'
    execute """
    UPDATE objects
    SET data = json_set(
      data,
      '$.color',
      json_extract(data, '$.fill')
    )
    WHERE json_extract(data, '$.fill') IS NOT NULL
      AND json_extract(data, '$.color') IS NULL
    """
  end
end
