defmodule SocialScribe.Hubspot do
  @moduledoc """
  The HubSpot context for managing contact suggestions and syncing to HubSpot CRM.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo
  alias SocialScribe.Hubspot.ContactSuggestion
  alias SocialScribe.Workers.ContactSuggestionsWorker

  @doc """
  Enqueues a job to generate contact suggestions for all participants in a meeting.

  This worker processes all meeting participants in a single Gemini API call,
  returning structured JSON with HubSpot field suggestions for each participant.

  ## Parameters
    - meeting_id: The ID of the meeting to analyze

  ## Examples

      iex> enqueue_contact_suggestions(123)
      {:ok, %Oban.Job{}}

  """
  def enqueue_contact_suggestions(meeting_id) do
    %{meeting_id: meeting_id}
    |> ContactSuggestionsWorker.new()
    |> Oban.insert()
  end

  @doc """
  Creates contact suggestions from the structured JSON output.

  ## Parameters
    - meeting_id: The ID of the meeting
    - suggestions_json: Array of maps with format:
      [%{"name" => "John Doe", "suggestions" => [%{"hubspotField" => "email", ...}]}]

  ## Examples

      iex> create_contact_suggestions_batch(123, suggestions_json)
      {:ok, [%ContactSuggestion{}, ...]}
  """
  def create_contact_suggestions_batch(meeting_id, suggestions_json) when is_list(suggestions_json) do
    Repo.transaction(fn ->
      Enum.map(suggestions_json, fn %{"name" => name, "suggestions" => suggestions} ->
        attrs = %{
          meeting_id: meeting_id,
          contact_name: name,
          suggestions: suggestions,
          status: "pending"
        }

        case create_contact_suggestion(attrs) do
          {:ok, contact_suggestion} -> contact_suggestion
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
    end)
  end

  @doc """
  Creates a single contact suggestion.
  """
  def create_contact_suggestion(attrs \\ %{}) do
    %ContactSuggestion{}
    |> ContactSuggestion.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a single contact suggestion by ID.
  """
  def get_contact_suggestion!(id), do: Repo.get!(ContactSuggestion, id)

  @doc """
  Lists all contact suggestions for a meeting.
  """
  def list_contact_suggestions_by_meeting(meeting_id) do
    from(cs in ContactSuggestion,
      where: cs.meeting_id == ^meeting_id,
      order_by: [desc: cs.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Lists all pending contact suggestions.
  """
  def list_pending_contact_suggestions do
    from(cs in ContactSuggestion,
      where: cs.status == "pending",
      order_by: [desc: cs.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Updates a contact suggestion.
  """
  def update_contact_suggestion(%ContactSuggestion{} = contact_suggestion, attrs) do
    contact_suggestion
    |> ContactSuggestion.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Marks a contact suggestion as approved.
  """
  def approve_contact_suggestion(%ContactSuggestion{} = contact_suggestion) do
    update_contact_suggestion(contact_suggestion, %{status: "approved"})
  end

  @doc """
  Marks a contact suggestion as synced to HubSpot.
  """
  def mark_synced_to_hubspot(%ContactSuggestion{} = contact_suggestion) do
    update_contact_suggestion(contact_suggestion, %{
      status: "synced",
      synced_to_hubspot_at: DateTime.utc_now()
    })
  end

  # TODO: Add HubSpot API integration to sync approved suggestions
end
