defmodule Ueberauth.Strategy.HubspotTest do
  use SocialScribeWeb.ConnCase, async: true

  alias Ueberauth.Strategy.Hubspot

  describe "handle_request!/1" do
    test "redirects to Hubspot OAuth authorize URL", %{conn: conn} do
      conn = get(conn, "/auth/hubspot")

      assert redirected_to(conn, 302) =~ "https://app.hubspot.com/oauth/authorize"
      assert redirected_to(conn, 302) =~ "client_id="
      assert redirected_to(conn, 302) =~ "redirect_uri="
      assert redirected_to(conn, 302) =~ "scope=crm.objects.contacts.read"
    end

    test "includes custom scope when provided in params", %{conn: conn} do
      conn = get(conn, "/auth/hubspot?scope=crm.objects.contacts.read+crm.objects.companies.read")

      assert redirected_to(conn, 302) =~ "scope=crm.objects.contacts.read"
    end
  end

  describe "uid/1" do
    test "extracts uid from user_id field in private data" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_user, %{"user_id" => "12345"})

      assert Hubspot.uid(conn) == "12345"
    end

    test "extracts uid from user field if user_id is missing" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_user, %{"user" => "user@example.com"})

      assert Hubspot.uid(conn) == "user@example.com"
    end
  end

  describe "credentials/1" do
    test "extracts credentials from token" do
      token = %OAuth2.AccessToken{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: 1_735_689_600,
        token_type: "Bearer",
        other_params: %{"scope" => "crm.objects.contacts.read crm.objects.contacts.write"}
      }

      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_token, token)

      credentials = Hubspot.credentials(conn)

      assert credentials.token == "test_access_token"
      assert credentials.refresh_token == "test_refresh_token"
      assert credentials.expires_at == 1_735_689_600
      assert credentials.token_type == "Bearer"
      assert credentials.expires == true
      assert "crm.objects.contacts.read" in credentials.scopes
      assert "crm.objects.contacts.write" in credentials.scopes
    end

    test "handles missing scope in token" do
      token = %OAuth2.AccessToken{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token",
        expires_at: 1_735_689_600,
        token_type: "Bearer",
        other_params: %{}
      }

      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_token, token)

      credentials = Hubspot.credentials(conn)

      assert credentials.scopes == [""]
    end
  end

  describe "info/1" do
    test "extracts user info from private data" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_user, %{
          "user" => "testuser@example.com",
          "hub_id" => 123_456
        })

      info = Hubspot.info(conn)

      assert info.email == "testuser@example.com"
      assert info.name == "testuser@example.com"
    end
  end

  describe "extra/1" do
    test "includes raw token and user data" do
      token = %OAuth2.AccessToken{
        access_token: "test_access_token",
        refresh_token: "test_refresh_token"
      }

      user = %{"user" => "testuser@example.com", "hub_id" => 123_456}

      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_token, token)
        |> Plug.Conn.put_private(:hubspot_user, user)

      extra = Hubspot.extra(conn)

      assert extra.raw_info.token == token
      assert extra.raw_info.user == user
    end
  end

  describe "handle_cleanup!/1" do
    test "clears private hubspot data" do
      conn =
        build_conn()
        |> Plug.Conn.put_private(:hubspot_token, %OAuth2.AccessToken{})
        |> Plug.Conn.put_private(:hubspot_user, %{"user" => "test"})

      cleaned_conn = Hubspot.handle_cleanup!(conn)

      assert cleaned_conn.private[:hubspot_token] == nil
      assert cleaned_conn.private[:hubspot_user] == nil
    end
  end
end
