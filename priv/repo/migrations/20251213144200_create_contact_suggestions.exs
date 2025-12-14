defmodule SocialScribe.Repo.Migrations.CreateContactSuggestions do
  use Ecto.Migration

  def change do
    create table(:contact_suggestions) do
      add :meeting_id, references(:meetings, on_delete: :delete_all), null: false
      add :contact_name, :string, null: false
      add :suggestions, :jsonb, null: false, default: "[]"
      add :status, :string, null: false, default: "pending"
      add :synced_to_hubspot_at, :utc_datetime

      timestamps()
    end

    create index(:contact_suggestions, [:meeting_id])
    create index(:contact_suggestions, [:status])
    create index(:contact_suggestions, [:contact_name])
  end
end
