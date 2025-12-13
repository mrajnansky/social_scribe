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
  def generate_contact_suggestions_batch(meeting, participant_names) do
    case Meetings.generate_prompt_for_meeting(meeting) do
      {:error, reason} ->
        {:error, reason}

      {:ok, meeting_prompt} ->
        participants_list = Enum.join(participant_names, ", ")

        prompt = """
        You are an expert CRM analyst helping to enrich contact records in HubSpot based on meeting interactions.

        Your task is to analyze the meeting transcript and generate structured, actionable suggestions for updating HubSpot contact records for ALL meeting participants.

        Participants to analyze: #{participants_list}

        For each participant, extract information that could be used to update their HubSpot contact record. Return ONLY a valid JSON array with NO markdown formatting, NO code blocks, NO backticks.

        CRITICAL FORMATTING REQUIREMENTS:
        - Return ONLY the JSON array, nothing else
        - Do NOT wrap the response in markdown code blocks
        - Do NOT include ```json or ``` markers
        - Start directly with [ and end with ]

        JSON Structure (return exactly this format):
        [
          {
            "name": "Full Name",
            "suggestions": [
              {
                "hubspotField": "email",
                "value": "email@example.com",
                "confidence": "high",
                "source": "mentioned in transcript at 00:05:23"
              },
              {
                "hubspotField": "jobtitle",
                "value": "Senior Product Manager",
                "confidence": "high",
                "source": "stated role during introduction"
              },
              {
                "hubspotField": "company",
                "value": "Acme Corp",
                "confidence": "medium",
                "source": "discussed working at Acme"
              },
              {
                "hubspotField": "phone",
                "value": "+1-555-0123",
                "confidence": "high",
                "source": "shared contact number"
              },
              {
                "hubspotField": "notes",
                "value": "Key decision maker for Q1 budget allocation. Interested in enterprise tier. Mentioned competitor evaluation ending March 15.",
                "confidence": "high",
                "source": "discussed throughout meeting"
              }
            ]
          }
        ]

        Common HubSpot fields to populate (use these exact field names):
        - email, phone, mobilephone
        - jobtitle, company, industry
        - city, state, country
        - website, linkedin_url, twitter_handle
        - notes (for general insights, next steps, interests)
        - hs_lead_status (e.g., "NEW", "OPEN", "IN_PROGRESS", "QUALIFIED")

        CRITICAL GUIDELINES:
        - Only include factual information directly from the transcript
        - Do NOT make assumptions or inferences beyond what was explicitly stated
        - Set confidence to "high" only for explicitly stated facts, "medium" for reasonable inferences, "low" for uncertain information
        - Always include a "source" field explaining where in the transcript this information came from
        - If a participant appears with name variations (e.g., "John" vs "John Smith"), use the most complete name
        - If a participant was not present or barely mentioned, include them with an empty suggestions array
        - Use the "notes" field for insights that don't fit standard fields (business context, interests, next steps, deal insights)
        - Return ONLY the JSON array, no other text

        #{meeting_prompt}
        """

        call_gemini_json(prompt)
    end
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
