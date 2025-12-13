# Workers

This directory contains Oban workers for background job processing in SocialScribe.

## Available Workers

### AIContentGenerationWorker

Generates AI-powered follow-up emails and automation content from meeting transcripts using Google Gemini.

**Usage:**
```elixir
# Enqueue a job to generate AI content for a meeting
%{meeting_id: meeting_id}
|> SocialScribe.Workers.AIContentGenerationWorker.new()
|> Oban.insert()
```

### ContactSuggestionsWorker

Generates Gemini-based suggestions for all HubSpot contacts in a meeting. This worker analyzes meeting transcripts and generates actionable insights for **all participants in a single API call**, returning structured JSON data ready for HubSpot sync.

**Automatic Trigger:**
This worker is **automatically triggered** by `BotStatusPoller` when a meeting is completed. It processes all participants in one batch.

**Manual Usage:**
```elixir
# Enqueue a job to generate suggestions for all participants
SocialScribe.Hubspot.enqueue_contact_suggestions(meeting_id)
```

**Output Format:**
The worker returns structured JSON in the following format:
```json
[
  {
    "name": "John Doe",
    "suggestions": [
      {
        "hubspotField": "email",
        "value": "john@example.com",
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
        "hubspotField": "notes",
        "value": "Key decision maker. Interested in enterprise tier.",
        "confidence": "high",
        "source": "discussed throughout meeting"
      }
    ]
  }
]
```

**The prompt is carefully designed to:**
- Process all participants in a single API call (efficient)
- Extract only factual information from the transcript
- Return structured JSON with HubSpot field mappings
- Include confidence levels and source attribution
- Avoid assumptions or hallucinations
- Handle name variations gracefully
- Clearly indicate when a contact was not present (empty suggestions array)

**Supported HubSpot Fields:**
- Contact info: `email`, `phone`, `mobilephone`
- Professional: `jobtitle`, `company`, `industry`
- Location: `city`, `state`, `country`
- Social: `website`, `linkedin_url`, `twitter_handle`
- CRM: `notes`, `hs_lead_status`

### BotStatusPoller

Polls Recall.ai API for bot status updates (runs via Oban.Plugins.Cron every 2 minutes).

## Queues

Workers are organized into queues defined in `config/config.exs`:

- `default`: 10 concurrent jobs
- `ai_content`: 10 concurrent jobs (used by AIContentGenerationWorker and ContactSuggestionsWorker)
- `polling`: 5 concurrent jobs (used by BotStatusPoller)

## Future Enhancements

For ContactSuggestionsWorker:
- [ ] Create database schema to store contact suggestions
- [ ] Add approval workflow for suggestions
- [ ] Implement HubSpot API integration to sync approved suggestions
- [ ] Add webhook to notify when suggestions are ready
- [ ] Add suggestion history and audit trail
