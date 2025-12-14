defmodule SocialScribe.HubspotApi do
  @moduledoc """
  HubSpot API client for interacting with HubSpot CRM.
  """

  @hubspot_api_base_url "https://api.hubapi.com"

  require Logger

  @doc """
  Searches for contacts in HubSpot by name.

  ## Parameters
    - access_token: The HubSpot OAuth access token
    - query: The search query string
    - limit: Maximum number of results (default: 10)

  ## Returns
    - {:ok, contacts} - List of contact maps
    - {:error, reason} - Error tuple
  """
  def search_contacts(access_token, query, limit \\ 10) do
    url = "#{@hubspot_api_base_url}/crm/v3/objects/contacts/search"

    payload = %{
      query: query,
      properties: ["firstname", "lastname", "email", "company", "jobtitle"],
      limit: limit
    }

    headers = [{"Authorization", "Bearer #{access_token}"}]

    Logger.debug("HubSpot contact search request payload: #{inspect(payload)}")
    Logger.debug("HubSpot contact search request headers: #{inspect(headers)}")

    case Tesla.post(client(), url, payload, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        contacts =
          body
          |> Map.get("results", [])
          |> Enum.map(&format_contact/1)

        Logger.debug("HubSpot contact search response: #{inspect(body)}")

        {:ok, contacts}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        Logger.error("HubSpot API error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  @doc """
  Gets a contact by ID from HubSpot.

  ## Parameters
    - access_token: The HubSpot OAuth access token
    - contact_id: The HubSpot contact ID

  ## Returns
    - {:ok, contact} - Contact map with properties
    - {:error, reason} - Error tuple
  """
  def get_contact(access_token, contact_id) do
    url = "#{@hubspot_api_base_url}/crm/v3/objects/contacts/#{contact_id}"

    # Request all common properties
    properties = [
      "firstname",
      "lastname",
      "email",
      "phone",
      "mobilephone",
      "company",
      "jobtitle",
      "industry",
      "city",
      "state",
      "country",
      "website",
      "linkedin_url",
      "twitter_handle",
      "notes",
      "hs_lead_status"
    ]

    params = [properties: Enum.join(properties, ",")]
    headers = [{"Authorization", "Bearer #{access_token}"}]

    Logger.debug("HubSpot get contact request for ID: #{contact_id}")

    case Tesla.get(client(), url, query: params, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        contact = format_contact_with_all_properties(body)
        Logger.debug("HubSpot get contact response: #{inspect(contact)}")
        {:ok, contact}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        Logger.error("HubSpot API error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp format_contact(contact) do
    properties = Map.get(contact, "properties", %{})
    firstname = Map.get(properties, "firstname", "")
    lastname = Map.get(properties, "lastname", "")

    %{
      id: Map.get(contact, "id"),
      name: String.trim("#{firstname} #{lastname}"),
      email: Map.get(properties, "email"),
      company: Map.get(properties, "company"),
      jobtitle: Map.get(properties, "jobtitle")
    }
  end

  @doc """
  Updates a contact in HubSpot with new property values.

  ## Parameters
    - access_token: The HubSpot OAuth access token
    - contact_id: The HubSpot contact ID
    - properties: Map of property names to values (e.g., %{"email" => "new@example.com", "jobtitle" => "CEO"})

  ## Returns
    - {:ok, contact} - Updated contact data
    - {:error, reason} - Error tuple
  """
  def update_contact(access_token, contact_id, properties) when is_map(properties) do
    url = "#{@hubspot_api_base_url}/crm/v3/objects/contacts/#{contact_id}"

    payload = %{properties: properties}
    headers = [{"Authorization", "Bearer #{access_token}"}]

    Logger.debug("HubSpot update contact #{contact_id} with properties: #{inspect(properties)}")

    case Tesla.patch(client(), url, payload, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} ->
        Logger.info("Successfully updated HubSpot contact #{contact_id}")
        {:ok, body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Failed to update HubSpot contact: #{status} - #{inspect(error_body)}")
        {:error, {:api_error, status, error_body}}

      {:error, reason} ->
        Logger.error("HubSpot API error: #{inspect(reason)}")
        {:error, {:http_error, reason}}
    end
  end

  defp format_contact_with_all_properties(contact) do
    properties = Map.get(contact, "properties", %{})

    %{
      id: Map.get(contact, "id"),
      properties: properties
    }
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @hubspot_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
