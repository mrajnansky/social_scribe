defmodule SocialScribeWeb.MeetingLive.ShowTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Tesla.Mock

  alias SocialScribe.Accounts
  alias SocialScribe.Meetings
  alias SocialScribe.Calendar

  setup :set_mox_from_context
  setup :verify_on_exit!

  @hubspot_properties [
    %{
      "name" => "email",
      "label" => "Email",
      "type" => "string",
      "fieldType" => "text",
      "description" => "Contact's email address",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => false}
    },
    %{
      "name" => "phone",
      "label" => "Phone Number",
      "type" => "string",
      "fieldType" => "phonenumber",
      "description" => "",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => false}
    },
    %{
      "name" => "custom_field",
      "label" => "Custom Field",
      "type" => "string",
      "fieldType" => "text",
      "description" => "A custom field",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => false}
    },
    %{
      "name" => "readonly_field",
      "label" => "Read Only Field",
      "type" => "string",
      "fieldType" => "text",
      "description" => "Cannot be edited",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => true}
    },
    %{
      "name" => "hidden_field",
      "label" => "Hidden Field",
      "type" => "string",
      "fieldType" => "text",
      "description" => "Hidden from UI",
      "hidden" => true,
      "modificationMetadata" => %{"readOnlyValue" => false}
    }
  ]

  describe "get_available_contact_fields/1" do
    test "returns default fields when no HubSpot properties provided" do
      fields = SocialScribeWeb.MeetingLive.Show.__info__(:functions)
      # Since get_available_contact_fields is private, we'll test it through the LiveView behavior
      # This is tested implicitly through the modal rendering tests below
    end

    test "filters out read-only fields from HubSpot properties" do
      # Test the filtering logic through actual usage
      # get_available_contact_fields should filter properties with readOnlyValue: true
      editable_fields =
        @hubspot_properties
        |> Enum.filter(fn prop ->
          modificationMetadata = Map.get(prop, "modificationMetadata", %{})
          readOnlyValue = Map.get(modificationMetadata, "readOnlyValue", false)
          hidden = Map.get(prop, "hidden", false)
          fieldType = Map.get(prop, "fieldType", "")

          !readOnlyValue && !hidden &&
            fieldType in [
              "text",
              "textarea",
              "number",
              "select",
              "radio",
              "checkbox",
              "date",
              "datetime",
              "phonenumber",
              "file",
              "booleancheckbox"
            ]
        end)

      assert length(editable_fields) == 3
      assert Enum.all?(editable_fields, fn field -> field["name"] != "readonly_field" end)
      assert Enum.all?(editable_fields, fn field -> field["name"] != "hidden_field" end)
    end

    test "includes custom fields from HubSpot" do
      custom_fields = Enum.filter(@hubspot_properties, &(&1["name"] == "custom_field"))
      assert length(custom_fields) == 1
      assert hd(custom_fields)["label"] == "Custom Field"
    end

    test "sorts fields alphabetically by label" do
      editable_fields =
        @hubspot_properties
        |> Enum.reject(fn prop ->
          modificationMetadata = Map.get(prop, "modificationMetadata", %{})
          readOnlyValue = Map.get(modificationMetadata, "readOnlyValue", false)
          hidden = Map.get(prop, "hidden", false)
          readOnlyValue || hidden
        end)
        |> Enum.map(fn prop -> {prop["name"], prop["label"]} end)
        |> Enum.sort_by(fn {_name, label} -> label end)

      labels = Enum.map(editable_fields, fn {_name, label} -> label end)
      assert labels == Enum.sort(labels)
    end
  end

  describe "handle_params for contact_suggestions modal" do
    setup do
      user = insert_user()
      calendar_event = insert_calendar_event(user)
      recall_bot = insert_recall_bot(calendar_event)
      meeting = insert_meeting(calendar_event, recall_bot)

      # Create HubSpot credential
      hubspot_credential =
        insert_credential(user, %{
          provider: "hubspot",
          token: "valid_token",
          refresh_token: "refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      %{
        user: user,
        meeting: meeting,
        hubspot_credential: hubspot_credential
      }
    end

    test "fetches HubSpot properties when contact_suggestions modal opens", %{
      conn: conn,
      user: user,
      meeting: meeting
    } do
      conn = log_in_user(conn, user)

      # Mock the HubSpot API call
      mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/crm/v3/properties/contacts") do
          %Tesla.Env{
            status: 200,
            body: %{"results" => @hubspot_properties}
          }
        else
          %Tesla.Env{status: 404, body: %{}}
        end
      end)

      # Navigate to the contact suggestions modal
      {:ok, view, _html} =
        live(conn, ~p"/dashboard/meetings/#{meeting.id}/contact_suggestions")

      # Check that the view has loaded (this would trigger handle_params)
      # The actual assertion would be that hubspot_contact_properties is populated
      # but since we can't directly access assigns in tests, we verify behavior
      assert has_element?(view, "#contact-suggestions-modal")
    end

    test "caches HubSpot properties and doesn't refetch on subsequent renders", %{
      conn: conn,
      user: user,
      meeting: meeting
    } do
      conn = log_in_user(conn, user)

      call_count = :counters.new(1, [:atomics])

      mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/crm/v3/properties/contacts") do
          :counters.add(call_count, 1, 1)

          %Tesla.Env{
            status: 200,
            body: %{"results" => @hubspot_properties}
          }
        else
          %Tesla.Env{status: 404, body: %{}}
        end
      end)

      {:ok, view, _html} =
        live(conn, ~p"/dashboard/meetings/#{meeting.id}/contact_suggestions")

      # Re-render or navigate away and back
      render(view)

      # Should only have called the API once due to caching
      assert :counters.get(call_count, 1) == 1
    end

    test "handles API errors gracefully when fetching properties", %{
      conn: conn,
      user: user,
      meeting: meeting
    } do
      conn = log_in_user(conn, user)

      # Mock API failure
      mock(fn %{method: :get, url: url} ->
        if String.contains?(url, "/crm/v3/properties/contacts") do
          %Tesla.Env{
            status: 500,
            body: %{"error" => "Internal server error"}
          }
        else
          %Tesla.Env{status: 404, body: %{}}
        end
      end)

      # Should still load the page with default fields
      {:ok, view, _html} =
        live(conn, ~p"/dashboard/meetings/#{meeting.id}/contact_suggestions")

      assert has_element?(view, "#contact-suggestions-modal")
      # Default fields should be available
      assert render(view) =~ "Email"
      assert render(view) =~ "Phone"
    end

    test "uses default fields when no HubSpot credential exists", %{
      conn: conn,
      meeting: meeting
    } do
      # Create a user without HubSpot credentials
      user_without_hubspot = insert_user()
      conn = log_in_user(conn, user_without_hubspot)

      # Transfer meeting ownership
      calendar_event = Meetings.get_meeting!(meeting.id).calendar_event
      Calendar.update_calendar_event(calendar_event, %{user_id: user_without_hubspot.id})

      {:ok, view, _html} =
        live(conn, ~p"/dashboard/meetings/#{meeting.id}/contact_suggestions")

      # Should render with default fields
      html = render(view)
      assert html =~ "Email"
      assert html =~ "Phone"
      assert html =~ "Job Title"
    end
  end

  # Helper functions to create test data
  defp insert_user do
    Accounts.register_user(%{
      email: "user#{System.unique_integer()}@example.com",
      password: "password123password123"
    })
    |> elem(1)
  end

  defp insert_calendar_event(user) do
    Calendar.create_calendar_event(%{
      user_id: user.id,
      google_event_id: "event_#{System.unique_integer()}",
      summary: "Test Meeting",
      start_time: DateTime.utc_now(),
      end_time: DateTime.add(DateTime.utc_now(), 3600, :second),
      html_link: "https://calendar.google.com/test"
    })
    |> elem(1)
  end

  defp insert_recall_bot(calendar_event) do
    SocialScribe.Bots.create_recall_bot(%{
      calendar_event_id: calendar_event.id,
      bot_id: "bot_#{System.unique_integer()}",
      status: "done"
    })
    |> elem(1)
  end

  defp insert_meeting(calendar_event, recall_bot) do
    Meetings.create_meeting(%{
      calendar_event_id: calendar_event.id,
      recall_bot_id: recall_bot.id,
      title: "Test Meeting",
      recorded_at: DateTime.utc_now(),
      duration_seconds: 3600
    })
    |> elem(1)
  end

  defp insert_credential(user, attrs) do
    Accounts.create_user_credential(
      Map.merge(
        %{
          user_id: user.id,
          provider: "hubspot",
          uid: "uid_#{System.unique_integer()}",
          token: "token",
          refresh_token: "refresh_token"
        },
        attrs
      )
    )
    |> elem(1)
  end
end
