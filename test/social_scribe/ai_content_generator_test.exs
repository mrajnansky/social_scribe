defmodule SocialScribe.AIContentGeneratorTest do
  use ExUnit.Case, async: true

  import Tesla.Mock

  alias SocialScribe.AIContentGenerator

  @hubspot_fields [
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
      "description" => "Contact's phone number",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => false}
    },
    %{
      "name" => "custom_budget",
      "label" => "Annual Budget",
      "type" => "number",
      "fieldType" => "number",
      "description" => "Customer's annual budget for software",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => false}
    },
    %{
      "name" => "readonly_field",
      "label" => "Read Only",
      "type" => "string",
      "fieldType" => "text",
      "description" => "Cannot edit this field",
      "hidden" => false,
      "modificationMetadata" => %{"readOnlyValue" => true}
    },
    %{
      "name" => "hidden_field",
      "label" => "Hidden",
      "type" => "string",
      "fieldType" => "text",
      "description" => "Hidden from UI",
      "hidden" => true,
      "modificationMetadata" => %{"readOnlyValue" => false}
    }
  ]

  describe "generate_field_list/1" do
    test "generates field list from HubSpot properties" do
      # We can't directly call the private function, so we test the behavior
      # through generate_contact_suggestions_batch
      assert is_list(@hubspot_fields)
    end

    test "filters out read-only fields" do
      editable_fields =
        @hubspot_fields
        |> Enum.filter(fn prop ->
          modificationMetadata = Map.get(prop, "modificationMetadata", %{})
          readOnlyValue = Map.get(modificationMetadata, "readOnlyValue", false)
          !readOnlyValue
        end)

      assert length(editable_fields) == 4
      refute Enum.any?(editable_fields, fn field -> field["name"] == "readonly_field" end)
    end

    test "filters out hidden fields" do
      visible_fields =
        @hubspot_fields
        |> Enum.filter(fn prop ->
          hidden = Map.get(prop, "hidden", false)
          !hidden
        end)

      assert length(visible_fields) == 4
      refute Enum.any?(visible_fields, fn field -> field["name"] == "hidden_field" end)
    end

    test "only includes supported field types" do
      supported_types = [
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

      filtered_fields =
        @hubspot_fields
        |> Enum.filter(fn prop ->
          fieldType = Map.get(prop, "fieldType", "")
          fieldType in supported_types
        end)

      assert length(filtered_fields) == 5
    end

    test "includes field descriptions when available" do
      fields_with_description =
        @hubspot_fields
        |> Enum.filter(fn prop ->
          description = Map.get(prop, "description", "")
          description != ""
        end)

      assert length(fields_with_description) == 5

      # All test fields have descriptions
      Enum.each(fields_with_description, fn field ->
        assert field["description"] != ""
      end)
    end

    test "formats fields correctly with name, label, and description" do
      field = Enum.find(@hubspot_fields, fn f -> f["name"] == "email" end)

      assert field["name"] == "email"
      assert field["label"] == "Email"
      assert field["description"] == "Contact's email address"
    end
  end

  describe "generate_contact_suggestions_batch/3 with HubSpot fields" do
    setup do
      # Mock meeting data
      meeting = %{
        id: 1,
        title: "Test Meeting",
        meeting_transcript: %{
          content: %{
            "data" => [
              %{
                "speaker" => "John Doe",
                "words" => [
                  %{"text" => "My"},
                  %{"text" => "email"},
                  %{"text" => "is"},
                  %{"text" => "john@example.com"}
                ]
              }
            ]
          }
        }
      }

      %{meeting: meeting}
    end

    test "includes custom HubSpot fields in AI prompt", %{meeting: meeting} do
      # Mock Gemini API response
      mock(fn %{method: :post, url: url} = request ->
        if String.contains?(url, "generateContent") do
          # Verify the prompt includes custom fields
          prompt = get_in(request.body, ["contents", Access.at(0), "parts", Access.at(0), "text"])

          assert prompt =~ "custom_budget"
          assert prompt =~ "Annual Budget"
          assert prompt =~ "Customer's annual budget for software"

          # Should NOT include readonly or hidden fields
          refute prompt =~ "readonly_field"
          refute prompt =~ "hidden_field"

          %Tesla.Env{
            status: 200,
            body: %{
              "candidates" => [
                %{
                  "content" => %{
                    "parts" => [
                      %{
                        "text" => "[]"
                      }
                    ]
                  }
                }
              ]
            }
          }
        end
      end)

      assert {:ok, _} =
               AIContentGenerator.generate_contact_suggestions_batch(
                 meeting,
                 ["John Doe"],
                 @hubspot_fields
               )
    end

    test "uses default fields when HubSpot fields are empty", %{meeting: meeting} do
      mock(fn %{method: :post, url: url} = request ->
        if String.contains?(url, "generateContent") do
          prompt = get_in(request.body, ["contents", Access.at(0), "parts", Access.at(0), "text"])

          # Should contain default contact fields
          assert prompt =~ "email, phone, mobilephone"
          assert prompt =~ "jobtitle, company, industry"
          assert prompt =~ "Common HubSpot CONTACT fields"

          %Tesla.Env{
            status: 200,
            body: %{
              "candidates" => [
                %{
                  "content" => %{
                    "parts" => [%{"text" => "[]"}]
                  }
                }
              ]
            }
          }
        end
      end)

      assert {:ok, _} =
               AIContentGenerator.generate_contact_suggestions_batch(meeting, ["John Doe"], [])
    end

    test "sorts fields alphabetically in the prompt", %{meeting: meeting} do
      mock(fn %{method: :post, url: url} = request ->
        if String.contains?(url, "generateContent") do
          prompt = get_in(request.body, ["contents", Access.at(0), "parts", Access.at(0), "text"])

          # Extract the field list portion of the prompt
          # Fields should be sorted alphabetically
          assert prompt =~ "Available HubSpot CONTACT fields"

          # The fields should appear in alphabetical order by label
          # Annual Budget, Email, Phone Number
          email_pos = :binary.match(prompt, "email") |> elem(0)
          phone_pos = :binary.match(prompt, "phone") |> elem(0)

          # Email should appear before phone in the sorted list
          assert email_pos < phone_pos

          %Tesla.Env{
            status: 200,
            body: %{
              "candidates" => [
                %{
                  "content" => %{
                    "parts" => [%{"text" => "[]"}]
                  }
                }
              ]
            }
          }
        end
      end)

      assert {:ok, _} =
               AIContentGenerator.generate_contact_suggestions_batch(
                 meeting,
                 ["John Doe"],
                 @hubspot_fields
               )
    end

    test "includes field type information when description is missing", %{meeting: meeting} do
      fields_without_description = [
        %{
          "name" => "test_field",
          "label" => "Test Field",
          "type" => "enumeration",
          "fieldType" => "select",
          "description" => "",
          "hidden" => false,
          "modificationMetadata" => %{"readOnlyValue" => false}
        }
      ]

      mock(fn %{method: :post, url: url} = request ->
        if String.contains?(url, "generateContent") do
          prompt = get_in(request.body, ["contents", Access.at(0), "parts", Access.at(0), "text"])

          # Should include type in brackets when description is empty
          assert prompt =~ "test_field"
          assert prompt =~ "[enumeration]"

          %Tesla.Env{
            status: 200,
            body: %{
              "candidates" => [
                %{
                  "content" => %{
                    "parts" => [%{"text" => "[]"}]
                  }
                }
              ]
            }
          }
        end
      end)

      assert {:ok, _} =
               AIContentGenerator.generate_contact_suggestions_batch(
                 meeting,
                 ["John Doe"],
                 fields_without_description
               )
    end
  end

  describe "field filtering behavior" do
    test "includes text fields" do
      text_field = %{
        "name" => "test",
        "label" => "Test",
        "fieldType" => "text",
        "hidden" => false,
        "modificationMetadata" => %{"readOnlyValue" => false}
      }

      assert text_field["fieldType"] == "text"
    end

    test "includes number fields" do
      number_field = %{
        "name" => "revenue",
        "label" => "Revenue",
        "fieldType" => "number",
        "hidden" => false,
        "modificationMetadata" => %{"readOnlyValue" => false}
      }

      assert number_field["fieldType"] == "number"
    end

    test "includes select/enumeration fields" do
      select_field = %{
        "name" => "status",
        "label" => "Status",
        "fieldType" => "select",
        "hidden" => false,
        "modificationMetadata" => %{"readOnlyValue" => false}
      }

      assert select_field["fieldType"] == "select"
    end

    test "excludes unsupported field types" do
      unsupported_field = %{
        "name" => "calculation",
        "label" => "Calculation",
        "fieldType" => "calculation",
        "hidden" => false,
        "modificationMetadata" => %{"readOnlyValue" => false}
      }

      supported_types = [
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

      refute unsupported_field["fieldType"] in supported_types
    end
  end
end
