defmodule SocialScribe.Workers.ContactSuggestionsWorker do
  @moduledoc """
  Worker that generates Gemini-based suggestions for all HubSpot contacts in a meeting.
  This worker analyzes meeting transcripts and generates actionable insights for all participants
  in a single API call, returning structured JSON data.
  """

  use Oban.Worker, queue: :ai_content, max_attempts: 3

  alias SocialScribe.Meetings
  alias SocialScribe.Hubspot
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApi
  alias SocialScribe.HubspotTokenRefresher
  alias SocialScribe.AIContentGeneratorApi

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"meeting_id" => meeting_id, "user_id" => user_id}}) do
    Logger.info(
      "Starting contact suggestions generation for all participants in meeting_id: #{meeting_id}"
    )

    case Meetings.get_meeting_with_details(meeting_id) do
      nil ->
        Logger.error("ContactSuggestionsWorker: Meeting not found for id #{meeting_id}")
        {:error, :meeting_not_found}

      meeting ->
        # Fetch HubSpot credentials and available fields
        hubspot_fields = fetch_hubspot_fields(user_id)
        process_all_contact_suggestions(meeting, hubspot_fields)
    end
  end

  defp fetch_hubspot_fields(user_id) do
    case Accounts.get_user!(user_id) do
      nil ->
        Logger.warning("User #{user_id} not found, using default fields")
        []

      user ->
        case Accounts.get_user_credential(user, "hubspot") do
          nil ->
            Logger.warning("No HubSpot credential found for user #{user_id}, using default fields")
            []

          credential ->
            case ensure_valid_hubspot_token(credential) do
              {:ok, access_token, _updated_credential} ->
                case HubspotApi.get_contact_properties(access_token) do
                  {:ok, properties} ->
                    Logger.info("Fetched #{length(properties)} HubSpot contact properties")
                    properties

                  {:error, reason} ->
                    Logger.error("Failed to fetch HubSpot properties: #{inspect(reason)}, using defaults")
                    []
                end

              {:error, reason} ->
                Logger.error("Failed to get valid HubSpot token: #{inspect(reason)}, using defaults")
                []
            end
        end
    end
  end

  defp ensure_valid_hubspot_token(credential) do
    now = DateTime.utc_now()
    expires_at = credential.expires_at || DateTime.add(now, -1, :second)

    if DateTime.compare(expires_at, DateTime.add(now, 300, :second)) == :lt do
      case HubspotTokenRefresher.refresh_token(credential.refresh_token) do
        {:ok, new_token_data} ->
          {:ok, updated_credential} =
            Accounts.update_credential_tokens(credential, new_token_data)

          {:ok, updated_credential.token, updated_credential}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, credential.token, nil}
    end
  end

  defp process_all_contact_suggestions(meeting, hubspot_fields) do
    if is_nil(meeting.meeting_participants) or Enum.empty?(meeting.meeting_participants) do
      Logger.info("No participants found for meeting #{meeting.id}, skipping contact suggestions")
      :ok
    else
      participant_names = Enum.map(meeting.meeting_participants, & &1.name)

      Logger.info(
        "Processing suggestions for #{length(participant_names)} participants in meeting #{meeting.id}"
      )

      case AIContentGeneratorApi.generate_contact_suggestions_batch(meeting, participant_names, hubspot_fields) do
        {:ok, suggestions_json} ->
          Logger.info(
            "Generated #{length(suggestions_json)} contact and account changes for meeting #{meeting.id}"
          )

          # Log the structured JSON response
          Logger.info("Contact/Account changes JSON: #{inspect(suggestions_json)}")

          # Save suggestions to database
          case Hubspot.create_contact_suggestions_batch(meeting.id, suggestions_json) do
            {:ok, _saved_suggestion} ->
              Logger.info(
                "Successfully saved #{length(suggestions_json)} contact/account changes to database for meeting #{meeting.id}"
              )

              :ok

            {:error, reason} ->
              Logger.error(
                "Failed to save contact/account changes to database for meeting #{meeting.id}: #{inspect(reason)}"
              )

              {:error, :db_save_failed}
          end

        {:error, reason} ->
          Logger.error(
            "Failed to generate contact/account changes for meeting #{meeting.id}: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end
end
