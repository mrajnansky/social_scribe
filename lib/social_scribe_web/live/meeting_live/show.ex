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
        |> assign(:updated_suggestion_fields, %{})
        |> assign(:show_field_mapping, %{})
        |> assign(:collapsed_fields, %{})
        |> assign(:hubspot_contact_properties, [])
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
    # Fetch HubSpot contact properties when modal opens
    socket =
      if socket.assigns[:live_action] == :contact_suggestions &&
           socket.assigns.hubspot_credential &&
           Enum.empty?(socket.assigns.hubspot_contact_properties) do
        case ensure_valid_hubspot_token(socket.assigns.hubspot_credential) do
          {:ok, access_token, updated_credential} ->
            # Update socket with new credential if it was refreshed
            new_socket =
              if updated_credential do
                assign(socket, :hubspot_credential, updated_credential)
              else
                socket
              end

            case HubspotApi.get_contact_properties(access_token) do
              {:ok, properties} ->
                assign(new_socket, :hubspot_contact_properties, properties)

              {:error, reason} ->
                Logger.error("Failed to fetch HubSpot contact properties: #{inspect(reason)}")
                new_socket
            end

          {:error, reason} ->
            Logger.error("Failed to ensure valid HubSpot token: #{inspect(reason)}")
            socket
        end
      else
        socket
      end

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
    case Hubspot.enqueue_contact_suggestions(socket.assigns.meeting.id, socket.assigns.current_user.id) do
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
  def handle_event("toggle_field", %{"field" => field_key}, socket) do
    contact_suggestions = socket.assigns.contact_suggestions
    updated_suggestion_fields = socket.assigns.updated_suggestion_fields

    # Get all suggestions from the first (and only) suggestion record
    all_suggestions =
      contact_suggestions
      |> List.first()
      |> case do
        nil -> []
        record -> Map.get(record, :suggestions, [])
      end

    # Find all indices for this field
    indices_for_field =
      all_suggestions
      |> Enum.with_index()
      |> Enum.filter(fn {change, index} ->
        current_field = Map.get(updated_suggestion_fields, to_string(index), Map.get(change, "hubspotField", ""))
        current_field == field_key
      end)
      |> Enum.map(fn {_change, index} -> to_string(index) end)

    # Check if all are currently selected
    all_selected = Enum.all?(indices_for_field, fn idx ->
      Map.get(socket.assigns.selected_suggestions, idx, false)
    end)

    # Toggle all - if all are selected, deselect all; otherwise select all
    updated_selections =
      Enum.reduce(indices_for_field, socket.assigns.selected_suggestions, fn idx, acc ->
        Map.put(acc, idx, !all_selected)
      end)

    {:noreply, assign(socket, :selected_suggestions, updated_selections)}
  end

  @impl true
  def handle_event("toggle_field_collapse", %{"field" => field_key}, socket) do
    collapsed_fields = socket.assigns.collapsed_fields
    current_value = Map.get(collapsed_fields, field_key, false)

    updated_collapsed = Map.put(collapsed_fields, field_key, !current_value)

    {:noreply, assign(socket, :collapsed_fields, updated_collapsed)}
  end

  @impl true
  def handle_event("update_suggestion_value", %{"index" => index, "value" => value}, socket) do
    updated_values = Map.put(socket.assigns.updated_suggestion_values, index, value)

    {:noreply, assign(socket, :updated_suggestion_values, updated_values)}
  end

  @impl true
  def handle_event("update_suggestion_field", params, socket) do
    Logger.info("update_suggestion_field params: #{inspect(params)}")

    index = Map.get(params, "index")

    # Extract the field value from params
    field = Map.get(params, "field-select-#{index}")

    Logger.info("Updating field for index #{index} to #{field}")

    updated_fields = Map.put(socket.assigns.updated_suggestion_fields, index, field)

    # Close the dropdown after selection
    show_field_mapping = Map.put(socket.assigns.show_field_mapping, index, false)

    socket =
      socket
      |> assign(:updated_suggestion_fields, updated_fields)
      |> assign(:show_field_mapping, show_field_mapping)

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_field_mapping", %{"index" => index}, socket) do
    show_field_mapping = socket.assigns.show_field_mapping
    current_value = Map.get(show_field_mapping, index, false)

    updated_mapping = Map.put(show_field_mapping, index, !current_value)

    {:noreply, assign(socket, :show_field_mapping, updated_mapping)}
  end

  @impl true
  def handle_event("sync_to_hubspot", _params, socket) do
    contact_id = socket.assigns.selected_contact.id
    selected_suggestions = socket.assigns.selected_suggestions
    updated_values = socket.assigns.updated_suggestion_values
    updated_fields = socket.assigns.updated_suggestion_fields
    contact_suggestions = socket.assigns.contact_suggestions

    # Get all suggestions from the first (and only) suggestion record
    all_suggestions =
      contact_suggestions
      |> List.first()
      |> case do
        nil -> []
        record -> Map.get(record, :suggestions, [])
      end

    # Build properties map from selected suggestions
    properties =
      selected_suggestions
      |> Enum.filter(fn {_index, selected} -> selected end)
      |> Enum.reduce(%{}, fn {index_str, _selected}, acc ->
        index = String.to_integer(index_str)
        suggestion = Enum.at(all_suggestions, index)

        if suggestion do
          # Use updated field name if available, otherwise use original
          field_name = Map.get(updated_fields, index_str, Map.get(suggestion, "hubspotField"))
          # Use updated value if available, otherwise use original suggestion value
          value = Map.get(updated_values, index_str, Map.get(suggestion, "value"))
          # Convert nil to empty string, keep everything else as-is (including empty strings)
          final_value = if is_nil(value), do: "", else: value
          Map.put(acc, field_name, final_value)
        else
          acc
        end
      end)

    if map_size(properties) == 0 do
      socket =
        socket
        |> put_flash(:error, "No contact fields selected. Please select at least one contact field to sync.")

      {:noreply, socket}
    else
      case ensure_valid_hubspot_token(socket.assigns.hubspot_credential) do
        {:ok, access_token, _updated_credential} ->
          case HubspotApi.update_contact(access_token, contact_id, properties) do
            {:ok, _updated_contact} ->
              socket =
                socket
                |> put_flash(:info, "Successfully synced #{map_size(properties)} field(s) to HubSpot!")
                |> push_navigate(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

              {:noreply, socket}

            {:error, reason} ->
              Logger.error("Failed to sync to HubSpot: #{inspect(reason)}")

              socket =
                socket
                |> put_flash(:error, "Failed to sync to HubSpot. Please try again.")

              {:noreply, socket}
          end

        {:error, reason} ->
          Logger.error("Failed to get valid token for sync: #{inspect(reason)}")

          socket =
            socket
            |> put_flash(:error, "Failed to authenticate with HubSpot. Please try reconnecting.")

          {:noreply, socket}
      end
    end
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

  defp format_field_name(field_key) do
    case field_key do
      "email" -> "Email"
      "phone" -> "Phone"
      "mobilephone" -> "Mobile Phone"
      "jobtitle" -> "Job Title"
      "company" -> "Company"
      "industry" -> "Industry"
      "city" -> "City"
      "state" -> "State"
      "country" -> "Country"
      "website" -> "Website"
      "linkedin_url" -> "LinkedIn URL"
      "twitter_handle" -> "Twitter Handle"
      "notes" -> "Notes"
      "hs_lead_status" -> "Lead Status"
      "firstname" -> "First Name"
      "lastname" -> "Last Name"
      # Account fields
      "name" -> "Company Name"
      "domain" -> "Domain"
      "type" -> "Company Type"
      "zip" -> "Zip Code"
      "numberofemployees" -> "Number of Employees"
      "annualrevenue" -> "Annual Revenue"
      "description" -> "Description"
      # Default: title case the field key
      _ -> field_key |> String.split("_") |> Enum.map(&String.capitalize/1) |> Enum.join(" ")
    end
  end

  defp get_available_contact_fields(hubspot_properties \\ []) do
    if Enum.empty?(hubspot_properties) do
      # Fallback to default fields if HubSpot properties aren't loaded
      [
        {"email", "Email"},
        {"phone", "Phone"},
        {"mobilephone", "Mobile Phone"},
        {"jobtitle", "Job Title"},
        {"company", "Company"},
        {"industry", "Industry"},
        {"city", "City"},
        {"state", "State"},
        {"country", "Country"},
        {"website", "Website"},
        {"linkedin_url", "LinkedIn URL"},
        {"twitter_handle", "Twitter Handle"},
        {"firstname", "First Name"},
        {"lastname", "Last Name"},
        {"notes", "Notes"},
        {"hs_lead_status", "Lead Status"}
      ]
    else
      # Filter and format HubSpot properties
      hubspot_properties
      |> Enum.filter(fn prop ->
        # Only include properties that:
        # 1. Are not read-only
        # 2. Are not hidden
        # 3. Are relevant field types (string, number, enumeration, date, etc.)
        modificationMetadata = Map.get(prop, "modificationMetadata", %{})
        readOnlyValue = Map.get(modificationMetadata, "readOnlyValue", false)
        hidden = Map.get(prop, "hidden", false)
        fieldType = Map.get(prop, "fieldType", "")

        !readOnlyValue && !hidden && fieldType in ["text", "textarea", "number", "select", "radio", "checkbox", "date", "datetime", "phonenumber", "file", "booleancheckbox"]
      end)
      |> Enum.map(fn prop ->
        name = Map.get(prop, "name", "")
        label = Map.get(prop, "label", name)
        {name, label}
      end)
      |> Enum.sort_by(fn {_name, label} -> label end)
    end
  end

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
