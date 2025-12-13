defmodule SocialScribe.Workers.ContactSuggestionsWorker do
  @moduledoc """
  Worker that generates Gemini-based suggestions for all HubSpot contacts in a meeting.
  This worker analyzes meeting transcripts and generates actionable insights for all participants
  in a single API call, returning structured JSON data.
  """

  use Oban.Worker, queue: :ai_content, max_attempts: 3

  alias SocialScribe.Meetings
  alias SocialScribe.Hubspot
  alias SocialScribe.AIContentGeneratorApi

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"meeting_id" => meeting_id}}) do
    Logger.info(
      "Starting contact suggestions generation for all participants in meeting_id: #{meeting_id}"
    )

    case Meetings.get_meeting_with_details(meeting_id) do
      nil ->
        Logger.error("ContactSuggestionsWorker: Meeting not found for id #{meeting_id}")
        {:error, :meeting_not_found}

      meeting ->
        process_all_contact_suggestions(meeting)
    end
  end

  defp process_all_contact_suggestions(meeting) do
    if is_nil(meeting.meeting_participants) or Enum.empty?(meeting.meeting_participants) do
      Logger.info("No participants found for meeting #{meeting.id}, skipping contact suggestions")
      :ok
    else
      participant_names = Enum.map(meeting.meeting_participants, & &1.name)

      Logger.info(
        "Processing suggestions for #{length(participant_names)} participants in meeting #{meeting.id}"
      )

      case AIContentGeneratorApi.generate_contact_suggestions_batch(meeting, participant_names) do
        {:ok, suggestions_json} ->
          Logger.info(
            "Generated contact suggestions for #{length(participant_names)} participants in meeting #{meeting.id}"
          )

          # Log the structured JSON response
          Logger.info("Contact suggestions JSON: #{inspect(suggestions_json)}")

          # Save suggestions to database
          case Hubspot.create_contact_suggestions_batch(meeting.id, suggestions_json) do
            {:ok, saved_suggestions} ->
              Logger.info(
                "Successfully saved #{length(saved_suggestions)} contact suggestions to database for meeting #{meeting.id}"
              )

              :ok

            {:error, reason} ->
              Logger.error(
                "Failed to save contact suggestions to database for meeting #{meeting.id}: #{inspect(reason)}"
              )

              {:error, :db_save_failed}
          end

        {:error, reason} ->
          Logger.error(
            "Failed to generate contact suggestions for meeting #{meeting.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end
end
