defmodule SocialScribe.HubspotTokenRefresher do
  @moduledoc """
  Refreshes HubSpot OAuth tokens.
  """

  require Logger

  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"

  def client do
    middlewares = [
      {Tesla.Middleware.FormUrlencoded,
       encode: &Plug.Conn.Query.encode/1, decode: &Plug.Conn.Query.decode/1},
      Tesla.Middleware.JSON
    ]

    Tesla.client(middlewares)
  end

  @doc """
  Refreshes a HubSpot access token using the refresh token.

  ## Parameters
    - refresh_token_string: The HubSpot OAuth refresh token

  ## Returns
    - {:ok, token_data} - Map with "access_token", "refresh_token", "expires_in"
    - {:error, reason} - Error tuple
  """
  def refresh_token(refresh_token_string) do
    client_id = Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)[:client_id]

    client_secret =
      Application.fetch_env!(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)[:client_secret]

    body = %{
      grant_type: "refresh_token",
      client_id: client_id,
      client_secret: client_secret,
      refresh_token: refresh_token_string
    }

    Logger.debug("Refreshing HubSpot token with refresh_token: #{refresh_token_string}")

    case Tesla.post(client(), @hubspot_token_url, body, opts: [form_urlencoded: true]) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        Logger.info("Successfully refreshed HubSpot token")
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Failed to refresh HubSpot token: #{status} - #{inspect(error_body)}")
        {:error, {status, error_body}}

      {:error, reason} ->
        Logger.error("HTTP error refreshing HubSpot token: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
