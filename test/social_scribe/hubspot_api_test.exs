defmodule SocialScribe.HubspotApiTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias SocialScribe.HubspotApi

  @valid_access_token "valid_token_123"

  describe "get_contact_properties/1" do
    test "successfully fetches contact properties from HubSpot" do
      mock(fn %{method: :get, url: "https://api.hubapi.com/crm/v3/properties/contacts"} = request ->
        assert Enum.member?(request.headers, {"Authorization", "Bearer #{@valid_access_token}"})

        %Tesla.Env{
          status: 200,
          body: %{
            "results" => [
              %{
                "name" => "email",
                "label" => "Email",
                "type" => "string",
                "fieldType" => "text",
                "description" => "Contact's email address",
                "hidden" => false,
                "modificationMetadata" => %{
                  "readOnlyValue" => false
                }
              },
              %{
                "name" => "phone",
                "label" => "Phone Number",
                "type" => "string",
                "fieldType" => "phonenumber",
                "description" => "Contact's phone number",
                "hidden" => false,
                "modificationMetadata" => %{
                  "readOnlyValue" => false
                }
              },
              %{
                "name" => "custom_field",
                "label" => "Custom Field",
                "type" => "string",
                "fieldType" => "text",
                "description" => "A custom field",
                "hidden" => false,
                "modificationMetadata" => %{
                  "readOnlyValue" => false
                }
              }
            ]
          }
        }
      end)

      assert {:ok, properties} = HubspotApi.get_contact_properties(@valid_access_token)
      assert is_list(properties)
      assert length(properties) == 3

      [first_property | _] = properties
      assert first_property["name"] == "email"
      assert first_property["label"] == "Email"
      assert first_property["fieldType"] == "text"
    end

    test "handles empty results from HubSpot" do
      mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{"results" => []}
        }
      end)

      assert {:ok, properties} = HubspotApi.get_contact_properties(@valid_access_token)
      assert properties == []
    end

    test "handles API errors with non-200 status" do
      mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 401,
          body: %{
            "status" => "error",
            "message" => "Unauthorized"
          }
        }
      end)

      assert {:error, {:api_error, 401, error_body}} =
               HubspotApi.get_contact_properties(@valid_access_token)

      assert error_body["message"] == "Unauthorized"
    end

    test "handles network errors" do
      mock(fn %{method: :get} ->
        {:error, :timeout}
      end)

      assert {:error, {:http_error, :timeout}} =
               HubspotApi.get_contact_properties(@valid_access_token)
    end

    test "handles rate limiting" do
      mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 429,
          body: %{
            "status" => "error",
            "message" => "Rate limit exceeded"
          }
        }
      end)

      assert {:error, {:api_error, 429, _}} =
               HubspotApi.get_contact_properties(@valid_access_token)
    end

    test "filters out read-only fields in the response" do
      mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "results" => [
              %{
                "name" => "email",
                "label" => "Email",
                "fieldType" => "text",
                "hidden" => false,
                "modificationMetadata" => %{"readOnlyValue" => false}
              },
              %{
                "name" => "createdate",
                "label" => "Create Date",
                "fieldType" => "date",
                "hidden" => false,
                "modificationMetadata" => %{"readOnlyValue" => true}
              }
            ]
          }
        }
      end)

      assert {:ok, properties} = HubspotApi.get_contact_properties(@valid_access_token)
      # Both should be returned - filtering happens in the LiveView
      assert length(properties) == 2
    end

    test "includes custom fields in the response" do
      mock(fn %{method: :get} ->
        %Tesla.Env{
          status: 200,
          body: %{
            "results" => [
              %{
                "name" => "custom_budget_2024",
                "label" => "Budget 2024",
                "type" => "number",
                "fieldType" => "number",
                "description" => "Customer budget for 2024",
                "hidden" => false,
                "modificationMetadata" => %{"readOnlyValue" => false}
              },
              %{
                "name" => "custom_industry_preference",
                "label" => "Industry Preference",
                "type" => "enumeration",
                "fieldType" => "select",
                "description" => "Preferred industry",
                "hidden" => false,
                "modificationMetadata" => %{"readOnlyValue" => false}
              }
            ]
          }
        }
      end)

      assert {:ok, properties} = HubspotApi.get_contact_properties(@valid_access_token)
      assert length(properties) == 2

      custom_fields = Enum.filter(properties, &String.starts_with?(&1["name"], "custom_"))
      assert length(custom_fields) == 2
    end
  end
end
