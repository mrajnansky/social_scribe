defmodule Ueberauth.Strategy.Hubspot do
  @moduledoc """
  Hubspot OAuth2 strategy for Ueberauth.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "crm.objects.contacts.read crm.objects.contacts.write crm.schemas.custom.write",
    oauth2_module: Ueberauth.Strategy.Hubspot.OAuth

  alias Ueberauth.Auth.Info
  alias Ueberauth.Auth.Credentials
  alias Ueberauth.Auth.Extra

  @doc """
  Handles the initial request to Hubspot.
  """
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)
    redirect_uri = Application.get_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)[:redirect_uri]

    opts =
      [scope: scopes, redirect_uri: redirect_uri]
      |> with_state_param(conn)

    module = option(conn, :oauth2_module)
    redirect!(conn, apply(module, :authorize_url!, [opts]))
  end

  @doc """
  Handles the callback from Hubspot.
  """
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    module = option(conn, :oauth2_module)
    redirect_uri = Application.get_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)[:redirect_uri]

    token = apply(module, :get_token!, [[code: code, redirect_uri: redirect_uri, client_secret: Application.get_env(:ueberauth, Ueberauth.Strategy.Hubspot.OAuth)[:client_secret]]])

    if token.token.access_token == nil do
      set_errors!(conn, [
        error(token.other_params["error"], token.other_params["error_description"])
      ])
    else
      token = token.token
      fetch_user(conn, token)
    end
  end

  @doc false
  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @doc """
  Cleans up the private area of the connection used for passing the raw Hubspot response around.
  """
  def handle_cleanup!(conn) do
    conn
    |> put_private(:hubspot_token, nil)
    |> put_private(:hubspot_user, nil)
  end

  @doc """
  Fetches the uid field from the Hubspot response.
  """
  def uid(conn) do
    user = conn.private[:hubspot_user]
    uid_value = user["user_id"] || user["user"]
    to_string(uid_value)
  end

  @doc """
  Includes the credentials from the Hubspot response.
  """
  def credentials(conn) do
    token = conn.private[:hubspot_token]
    scope_string = token.other_params["scope"] || ""
    scopes = String.split(scope_string, " ")

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      expires_at: token.expires_at,
      token_type: token.token_type,
      expires: !!token.expires_at,
      scopes: scopes
    }
  end

  @doc """
  Fetches the fields to populate the info section of the `Ueberauth.Auth` struct.
  """
  def info(conn) do
    user = conn.private[:hubspot_user]

    %Info{
      email: user["user"],
      name: user["user"]
    }
  end

  @doc """
  Stores the raw information (including the token) obtained from the Hubspot callback.
  """
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private[:hubspot_token],
        user: conn.private[:hubspot_user]
      }
    }
  end

  defp fetch_user(conn, token) do
    conn = put_private(conn, :hubspot_token, token)

    # Fetch user info from Hubspot
    case Ueberauth.Strategy.Hubspot.OAuth.get(
           token,
           "/oauth/v1/access-tokens/" <> token.access_token
         ) do
      {:ok, %OAuth2.Response{status_code: 401, body: _body}} ->
        set_errors!(conn, [error("token", "unauthorized")])

      {:ok, %OAuth2.Response{status_code: status_code, body: user}}
      when status_code in 200..399 ->
        put_private(conn, :hubspot_user, user)

      {:error, %OAuth2.Error{reason: reason}} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
