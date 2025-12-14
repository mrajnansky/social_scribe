defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton

  require Logger

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApi
  alias SocialScribe.Hubspot
  alias SocialScribe.HubspotTokenRefresher

  @impl true
  def mount(%{"id" => meeting_id}, _session, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    user_has_automations =
      Automations.list_active_user_automations(socket.assigns.current_user.id)
      |> length()
      |> Kernel.>(0)

    automation_results = Automations.list_automation_results_for_meeting(meeting_id)

    contact_suggestions = Hubspot.list_contact_suggestions_by_meeting(meeting_id)

    hubspot_credential =
      Accounts.list_user_credentials(socket.assigns.current_user, provider: "hubspot")
      |> List.first()

    if meeting.calendar_event.user_id != socket.assigns.current_user.id do
      socket =
        socket
        |> put_flash(:error, "You do not have permission to view this meeting.")
        |> redirect(to: ~p"/dashboard/meetings")

      {:error, socket}
    else
      socket =
        socket
        |> assign(:page_title, "Meeting Details: #{meeting.title}")
        |> assign(:meeting, meeting)
        |> assign(:automation_results, automation_results)
        |> assign(:user_has_automations, user_has_automations)
        |> assign(:contact_suggestions, contact_suggestions)
        |> assign(:hubspot_credential, hubspot_credential)
        |> assign(:selected_contact, nil)
        |> assign(:contact_search_results, [])
        |> assign(:contact_current_values, %{})
        |> assign(:selected_suggestions, %{})
        |> assign(:updated_suggestion_values, %{})
        |> assign(
          :follow_up_email_form,
          to_form(%{
            "follow_up_email" => ""
          })
        )

      {:ok, socket}
    end
  end

  @impl true
  def handle_params(%{"automation_result_id" => automation_result_id}, _uri, socket) do
    automation_result = Automations.get_automation_result!(automation_result_id)
    automation = Automations.get_automation!(automation_result.automation_id)

    socket =
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)

    {:noreply, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_contacts", params, socket) do
    query = get_in(params, ["value"]) || ""

    {results, updated_socket} =
      if socket.assigns.hubspot_credential && String.length(query) >= 2 do
        case ensure_valid_hubspot_token(socket.assigns.hubspot_credential) do
          {:ok, access_token, updated_credential} ->
            # Update socket with new credential if it was refreshed
            new_socket =
              if updated_credential do
                assign(socket, :hubspot_credential, updated_credential)
              else
                socket
              end

            case HubspotApi.search_contacts(access_token, query) do
              {:ok, contacts} -> {contacts, new_socket}
              {:error, reason} ->
                Logger.error("HubSpot search error: #{inspect(reason)}")
                {[], new_socket}
            end

          {:error, reason} ->
            Logger.error("Failed to ensure valid HubSpot token: #{inspect(reason)}")
            {[], socket}
        end
      else
        {[], socket}
      end

    Logger.info("Contact search results: #{inspect(results)}")

    updated_socket =
      updated_socket
      |> assign(:contact_search_results, results)

    {:noreply, updated_socket}
  end

  defp ensure_valid_hubspot_token(credential) do
    # Check if token is expired or about to expire (within 5 minutes)
    now = DateTime.utc_now()
    expires_at = credential.expires_at || DateTime.add(now, -1, :second)

    if DateTime.compare(expires_at, DateTime.add(now, 300, :second)) == :lt do
      Logger.info("HubSpot token expired or expiring soon, refreshing...")

      case HubspotTokenRefresher.refresh_token(credential.refresh_token) do
        {:ok, new_token_data} ->
          # Update credential with new tokens
          {:ok, updated_credential} =
            Accounts.update_credential_tokens(credential, new_token_data)

          Logger.info("HubSpot token refreshed successfully")
          {:ok, updated_credential.token, updated_credential}

        {:error, reason} ->
          Logger.error("Failed to refresh HubSpot token: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Token is still valid
      {:ok, credential.token, nil}
    end
  end

  @impl true
  def handle_event("select_contact", params, socket) do
    contact_id = Map.get(params, "contact_id")

    selected_contact = %{
      id: contact_id,
      name: Map.get(params, "contact_name", ""),
      email: Map.get(params, "contact_email")
    }

    # Fetch full contact details from HubSpot to get current values
    contact_properties =
      if socket.assigns.hubspot_credential do
        case ensure_valid_hubspot_token(socket.assigns.hubspot_credential) do
          {:ok, access_token, _updated_credential} ->
            case HubspotApi.get_contact(access_token, contact_id) do
              {:ok, contact_data} ->
                Map.get(contact_data, :properties, %{})

              {:error, reason} ->
                Logger.error("Failed to fetch contact details: #{inspect(reason)}")
                %{}
            end

          {:error, reason} ->
            Logger.error("Failed to get valid token: #{inspect(reason)}")
            %{}
        end
      else
        %{}
      end

    socket =
      socket
      |> assign(:selected_contact, selected_contact)
      |> assign(:contact_search_results, [])
      |> assign(:contact_current_values, contact_properties)

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    socket =
      socket
      |> assign(:selected_contact, nil)
      |> assign(:contact_current_values, %{})

    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_search_results", _params, socket) do
    socket =
      socket
      |> assign(:contact_search_results, [])

    {:noreply, socket}
  end

  @impl true
  def handle_event("generate_suggestions", %{"contact_name" => _contact_name}, socket) do
    # Enqueue job to generate contact and account changes
    case Hubspot.enqueue_contact_suggestions(socket.assigns.meeting.id) do
      {:ok, _job} ->
        socket =
          socket
          |> put_flash(:info, "Generating contact and account changes from meeting...")
          |> push_navigate(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, _reason} ->
        socket =
          socket
          |> put_flash(:error, "Failed to generate changes. Please try again.")

        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_suggestion", %{"index" => index}, socket) do
    selected_suggestions = socket.assigns.selected_suggestions
    current_value = Map.get(selected_suggestions, index, false)

    updated_selections = Map.put(selected_suggestions, index, !current_value)

    {:noreply, assign(socket, :selected_suggestions, updated_selections)}
  end

  @impl true
  def handle_event("update_suggestion_value", %{"index" => index, "value" => value}, socket) do
    updated_values = Map.put(socket.assigns.updated_suggestion_values, index, value)

    {:noreply, assign(socket, :updated_suggestion_values, updated_values)}
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  defp get_initials(name) when is_binary(name) do
    name
    |> String.split()
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp get_initials(_), do: "?"

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
