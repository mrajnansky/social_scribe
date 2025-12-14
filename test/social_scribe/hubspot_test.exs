defmodule SocialScribe.HubspotTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.Hubspot
  alias SocialScribe.Hubspot.ContactSuggestion

  describe "contact_suggestions" do
    @valid_attrs %{
      meeting_id: 1,
      contact_name: "All Meeting Changes",
      suggestions: [
        %{
          "type" => "contact",
          "hubspotField" => "email",
          "value" => "john@example.com",
          "confidence" => "high",
          "source" => "John mentioned his email in transcript"
        },
        %{
          "type" => "account",
          "hubspotField" => "industry",
          "value" => "Software",
          "confidence" => "medium",
          "source" => "discussed industry"
        }
      ],
      status: "pending"
    }

    @invalid_attrs %{meeting_id: nil, contact_name: nil, suggestions: nil}

    test "create_contact_suggestion/1 with valid data creates a contact suggestion" do
      assert {:ok, %ContactSuggestion{} = contact_suggestion} =
               Hubspot.create_contact_suggestion(@valid_attrs)

      assert contact_suggestion.contact_name == "All Meeting Changes"
      assert contact_suggestion.status == "pending"
      assert length(contact_suggestion.suggestions) == 2
    end

    test "create_contact_suggestion/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Hubspot.create_contact_suggestion(@invalid_attrs)
    end

    test "approve_contact_suggestion/1 updates status to approved" do
      {:ok, contact_suggestion} = Hubspot.create_contact_suggestion(@valid_attrs)
      assert {:ok, updated} = Hubspot.approve_contact_suggestion(contact_suggestion)
      assert updated.status == "approved"
    end

    test "mark_synced_to_hubspot/1 updates status and timestamp" do
      {:ok, contact_suggestion} = Hubspot.create_contact_suggestion(@valid_attrs)
      assert {:ok, updated} = Hubspot.mark_synced_to_hubspot(contact_suggestion)
      assert updated.status == "synced"
      assert %DateTime{} = updated.synced_to_hubspot_at
    end
  end
end
