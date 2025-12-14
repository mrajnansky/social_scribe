defmodule SocialScribe.AIContentGenerator do
  @moduledoc "Generates content using Google Gemini."

  @behaviour SocialScribe.AIContentGeneratorApi

  alias SocialScribe.Meetings
  alias SocialScribe.Automations

  @gemini_model "gemini-2.0-flash-lite"
  @gemini_api_base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @impl SocialScribe.AIContentGeneratorApi
  def generate_follow_up_email(meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        Based on the following meeting transcript, please draft a concise and professional follow-up email.
        The email should summarize the key discussion points and clearly list any action items assigned, including who is responsible if mentioned.
        Keep the tone friendly and action-oriented.

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_automation(automation, meeting) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        prompt = """
        #{Automations.generate_prompt_for_automation(automation)}

        #{meeting_prompt}
        """

        call_gemini(prompt)
    end
  end

  @impl SocialScribe.AIContentGeneratorApi
  def generate_contact_suggestions_batch(meeting, _participant_names, hubspot_fields) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        # Generate field list from HubSpot properties
        field_list = generate_field_list(hubspot_fields)

        prompt = """
        You are an expert CRM analyst helping to identify contact and account information changes from meeting transcripts for HubSpot.

        Your task is to analyze the meeting transcript and extract ALL contact information updates, changes, or new data points mentioned during the meeting, as well as company/account information.

        Return a flat array of changes - it doesn't matter which contact or company they belong to. Any information mentioned should be included as a separate change item.

        CRITICAL FORMATTING REQUIREMENTS:
        - Return ONLY the JSON array, nothing else
        - Do NOT wrap the response in markdown code blocks
        - Do NOT include ```json or ``` markers
        - Start directly with [ and end with ]

        JSON Structure (return exactly this format):
        [
          {
            "type": "contact",
            "hubspotField": "email",
            "value": "email@example.com",
            "confidence": "high",
            "source": "John mentioned his email at 00:05:23"
            "transcriptTimestamp": "00:05:23"  // Optional: include if available
          },
          {
            "type": "contact",
            "hubspotField": "jobtitle",
            "value": "Senior Product Manager",
            "confidence": "high",
            "source": "John stated role during introduction"
            "transcriptTimestamp": "00:05:23"
          },
          {
            "type": "account",
            "hubspotField": "name",
            "value": "Acme Corporation",
            "confidence": "high",
            "source": "Jane mentioned company name"
            "transcriptTimestamp": "00:10:45"
          }
        ]

        #{field_list}

        CRITICAL GUIDELINES:
        - Only include factual information directly from the transcript
        - Do NOT make assumptions or inferences beyond what was explicitly stated
        - Set confidence to "high" only for explicitly stated facts, "medium" for reasonable inferences, "low" for uncertain information
        - Always include a "source" field explaining where/who this information came from in the transcript
        - Include the person's name in the source field when possible (e.g., "John mentioned his email", "Sarah stated her role")
        - Set "type" to "contact" for person-specific information (email, phone, job title, etc.)
        - Set "type" to "account" for company/organization information (company name, industry, revenue, etc.)
        - Extract ALL contact and account information mentioned, regardless of who it belongs to
        - Each piece of information should be a separate item in the array
        - Use "notes" fields for contextual information like deal status, challenges, opportunities, timelines
        - Return ONLY the JSON array, no other text

        #{meeting_prompt}
        """

        call_gemini_json(prompt)
    end
  end

  defp generate_field_list(hubspot_fields) when is_list(hubspot_fields) and length(hubspot_fields) > 0 do
    # Filter to only include editable contact fields
    contact_fields = hubspot_fields
    |> Enum.filter(fn prop ->
      modificationMetadata = Map.get(prop, "modificationMetadata", %{})
      readOnlyValue = Map.get(modificationMetadata, "readOnlyValue", false)
      hidden = Map.get(prop, "hidden", false)
      fieldType = Map.get(prop, "fieldType", "")

      !readOnlyValue && !hidden && fieldType in ["text", "textarea", "number", "select", "radio", "checkbox", "date", "datetime", "phonenumber", "file", "booleancheckbox"]
    end)
    |> Enum.map(fn prop ->
      name = Map.get(prop, "name", "")
      label = Map.get(prop, "label", name)
      description = Map.get(prop, "description", "")
      type = Map.get(prop, "type", "")

      if description != "" do
        "- #{name} (#{label}): #{description}"
      else
        "- #{name} (#{label}) [#{type}]"
      end
    end)
    |> Enum.sort()
    |> Enum.join("\n")

    """
    Available HubSpot CONTACT fields (use these exact field names):
    #{contact_fields}

    Note: Focus on extracting information that matches these available fields. If information doesn't clearly fit any field, use the "notes" field for contextual information.
    """
  end

  defp generate_field_list(_hubspot_fields) do
    # Fallback to default fields if HubSpot fields aren't provided
    """
    Common HubSpot CONTACT fields to extract (use these exact field names):
    - email, phone, mobilephone
    - jobtitle, company, industry
    - city, state, country
    - website, linkedin_url, twitter_handle
    - firstname, lastname
    - notes (for general insights, next steps, interests, business context)
    - hs_lead_status (e.g., "NEW", "OPEN", "IN_PROGRESS", "QUALIFIED")

    Common HubSpot ACCOUNT/COMPANY fields to extract (use these exact field names):
    - name (company name)
    - domain (company website domain)
    - industry, type (e.g., "PROSPECT", "PARTNER", "RESELLER")
    - city, state, country, zip
    - phone, website
    - numberofemployees, annualrevenue
    - notes (deal context, business challenges, opportunities, timeline)
    - description (company description)
    """
  end

  defp call_gemini(prompt_text) do
    api_key = Application.fetch_env!(:social_scribe, :gemini_api_key)
    url = "#{@gemini_api_base_url}/#{@gemini_model}:generateContent?key=#{api_key}"

    payload = %{
      contents: [
        %{
          parts: [%{text: prompt_text}]
        }
      ]
    }

    case Tesla.post(client(), url, payload) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        # Safely extract the text content
        # The response structure is typically: body.candidates[0].content.parts[0].text

        text_path = [
          "candidates",
          Access.at(0),
          "content",
          "parts",
          Access.at(0),
          "text"
        ]

        case get_in(body, text_path) do
          nil -> {:error, {:parsing_error, "No text content found in Gemini response", body}}
          text_content -> {:ok, text_content}
        end

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp call_gemini_json(prompt_text) do
    api_key = Application.fetch_env!(:social_scribe, :gemini_api_key)
    url = "#{@gemini_api_base_url}/#{@gemini_model}:generateContent?key=#{api_key}"

    payload = %{
      contents: [
        %{
          parts: [%{text: prompt_text}]
        }
      ],
      generationConfig: %{
        response_mime_type: "application/json"
      }
    }

    case Tesla.post(client(), url, payload) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        text_path = [
          "candidates",
          Access.at(0),
          "content",
          "parts",
          Access.at(0),
          "text"
        ]

        case get_in(body, text_path) do
          nil ->
            {:error, {:parsing_error, "No text content found in Gemini response", body}}

          text_content ->
            # Parse the JSON response
            case Jason.decode(text_content) do
              {:ok, parsed_json} when is_list(parsed_json) ->
                {:ok, parsed_json}

              {:ok, _not_array} ->
                {:error, {:invalid_format, "Expected JSON array, got different structure", text_content}}

              {:error, json_error} ->
                {:error, {:json_parse_error, "Failed to parse JSON from Gemini", text_content, json_error}}
            end
        end

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @gemini_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
