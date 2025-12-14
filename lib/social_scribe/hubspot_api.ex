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

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, @hubspot_api_base_url},
      Tesla.Middleware.JSON
    ])
  end
end
