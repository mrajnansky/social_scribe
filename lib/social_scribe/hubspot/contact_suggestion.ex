defmodule SocialScribe.Hubspot.ContactSuggestion do
  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  schema "contact_suggestions" do
    field :contact_name, :string
    field :suggestions, {:array, :map}, default: []
    field :status, :string, default: "pending"
    field :synced_to_hubspot_at, :utc_datetime

    belongs_to :meeting, Meeting

    timestamps()
  end

  @doc false
  def changeset(contact_suggestion, attrs) do
    contact_suggestion
    |> cast(attrs, [:meeting_id, :contact_name, :suggestions, :status, :synced_to_hubspot_at])
    |> validate_required([:meeting_id, :contact_name, :suggestions])
    |> validate_inclusion(:status, ["pending", "approved", "synced", "rejected"])
    |> foreign_key_constraint(:meeting_id)
  end
end
