defmodule SocialScribe.Workers.BotStatusPoller do
  use Oban.Worker, queue: :polling, max_attempts: 3

  alias SocialScribe.Bots
  alias SocialScribe.RecallApi
  alias SocialScribe.Meetings

  require Logger

  @impl Oban.Worker
  def perform(_job) do
    bots_to_poll = Bots.list_pending_bots()

    if Enum.any?(bots_to_poll) do
      Logger.info("Polling #{Enum.count(bots_to_poll)} pending Recall.ai bots...")
    end

    for bot_record <- bots_to_poll do
      poll_and_process_bot(bot_record)
    end

    :ok
  end

  defp poll_and_process_bot(bot_record) do
    case RecallApi.get_bot(bot_record.recall_bot_id) do
      {:ok, %Tesla.Env{body: bot_api_info}} ->
        new_status =
          bot_api_info
          |> Map.get(:status_changes)
          |> List.last()
          |> Map.get(:code)

        {:ok, updated_bot_record} = Bots.update_recall_bot(bot_record, %{status: new_status})

        if new_status == "done" &&
             is_nil(Meetings.get_meeting_by_recall_bot_id(updated_bot_record.id)) do
          process_completed_bot(updated_bot_record, bot_api_info)
        else
          if new_status != bot_record.status do
            Logger.info("Bot #{bot_record.recall_bot_id} status updated to: #{new_status}")
          end
        end

      {:error, reason} ->
        Logger.error(
          "Failed to poll bot status for #{bot_record.recall_bot_id}: #{inspect(reason)}"
        )

        Bots.update_recall_bot(bot_record, %{status: "polling_error"})
    end
  end

  defp process_completed_bot(bot_record, bot_api_info) do
    Logger.info("Bot #{bot_record.recall_bot_id} is done. Extracting transcript download URL...")

    transcript_url = extract_transcript_download_url(bot_api_info)

    if transcript_url do
      Logger.info("Found transcript download URL. Fetching transcript...")

      case fetch_transcript_from_url(transcript_url) do
        {:ok, transcript_data} ->
          Logger.info("Successfully fetched transcript for bot #{bot_record.recall_bot_id}")

          Logger.debug("Transcript data: #{inspect(transcript_data)}")

          case Meetings.create_meeting_from_recall_data(bot_record, bot_api_info, transcript_data) do
            {:ok, meeting} ->
              Logger.info(
                "Successfully created meeting record #{meeting.id} from bot #{bot_record.recall_bot_id}"
              )

              SocialScribe.Workers.AIContentGenerationWorker.new(%{meeting_id: meeting.id})
              |> Oban.insert()

              Logger.info("Enqueued AI content generation for meeting #{meeting.id}")

              # Enqueue contact suggestions worker for all participants (single job)
              SocialScribe.Workers.ContactSuggestionsWorker.new(%{meeting_id: meeting.id})
              |> Oban.insert()

              Logger.info("Enqueued contact suggestions worker for meeting #{meeting.id}")

            {:error, reason} ->
              Logger.error(
                "Failed to create meeting record from bot #{bot_record.recall_bot_id}: #{inspect(reason)}"
              )
          end

        {:error, reason} ->
          Logger.error(
            "Failed to fetch transcript for bot #{bot_record.recall_bot_id} after completion: #{inspect(reason)}"
          )
      end
    else
      Logger.error(
        "No transcript download URL found in bot info for bot #{bot_record.recall_bot_id}"
      )
    end
  end

  defp extract_transcript_download_url(bot_api_info) do
    bot_api_info
    |> Map.get(:recordings, [])
    |> List.first()
    |> case do
      nil ->
        nil

      recording ->
        get_in(recording, [:media_shortcuts, :transcript, :data, :download_url])
    end
  end

  defp fetch_transcript_from_url(url) do
    case Tesla.get(url) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        case Jason.decode(body, keys: :atoms) do
          {:ok, parsed_data} -> {:ok, parsed_data}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, %Tesla.Env{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Tesla.Env{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
