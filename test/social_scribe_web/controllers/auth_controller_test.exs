defmodule SocialScribeWeb.AuthControllerTest do
  use SocialScribeWeb.ConnCase, async: true

  import SocialScribe.AccountsFixtures

  alias SocialScribe.Accounts

  setup :register_and_log_in_user

  describe "GET /auth/hubspot" do
    test "redirects to Hubspot OAuth authorize URL", %{conn: conn} do
      conn = get(conn, ~p"/auth/hubspot")

      assert redirected_to(conn, 302) =~ "https://app.hubspot.com/oauth/authorize"
      assert redirected_to(conn, 302) =~ "client_id="
      assert redirected_to(conn, 302) =~ "redirect_uri="
    end
  end

  describe "GET /auth/hubspot/callback" do
    test "creates user credential and redirects to settings on success", %{conn: conn, user: user} do
      # Mock the Ueberauth auth struct
      auth = %Ueberauth.Auth{
        provider: :hubspot,
        uid: "hubspot-user-123",
        credentials: %Ueberauth.Auth.Credentials{
          token: "hubspot_access_token",
          refresh_token: "hubspot_refresh_token",
          expires_at: 1_735_689_600
        },
        info: %Ueberauth.Auth.Info{
          email: "hubspot@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/hubspot/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :info) == "Hubspot account added successfully."

      # Verify credential was created
      credentials = Accounts.list_user_credentials(user, provider: "hubspot")
      assert length(credentials) == 1

      credential = List.first(credentials)
      assert credential.uid == "hubspot-user-123"
      assert credential.provider == "hubspot"
      assert credential.token == "hubspot_access_token"
      assert credential.refresh_token == "hubspot_refresh_token"
      assert credential.email == "hubspot@example.com"
    end

    test "updates existing credential if already linked", %{conn: conn, user: user} do
      # Create existing credential
      user_credential_fixture(%{
        user_id: user.id,
        provider: "hubspot",
        uid: "hubspot-user-123",
        token: "old_token",
        refresh_token: "old_refresh_token"
      })

      # Mock the Ueberauth auth struct with updated tokens
      auth = %Ueberauth.Auth{
        provider: :hubspot,
        uid: "hubspot-user-123",
        credentials: %Ueberauth.Auth.Credentials{
          token: "new_access_token",
          refresh_token: "new_refresh_token",
          expires_at: 1_735_689_600
        },
        info: %Ueberauth.Auth.Info{
          email: "hubspot@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/hubspot/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"

      # Verify credential was updated, not duplicated
      credentials = Accounts.list_user_credentials(user, provider: "hubspot")
      assert length(credentials) == 1

      credential = List.first(credentials)
      assert credential.token == "new_access_token"
      assert credential.refresh_token == "new_refresh_token"
    end

    test "shows error message when credential creation fails", %{conn: conn} do
      # Mock auth with invalid data (missing required uid)
      auth = %Ueberauth.Auth{
        provider: :hubspot,
        uid: nil,
        credentials: %Ueberauth.Auth.Credentials{
          token: "hubspot_access_token"
        },
        info: %Ueberauth.Auth.Info{}
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/hubspot/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :error) == "Could not add Hubspot account."
    end

    test "requires authenticated user", %{conn: conn} do
      # Use a fresh connection without authentication
      conn = recycle(conn)

      auth = %Ueberauth.Auth{
        provider: :hubspot,
        uid: "hubspot-user-123",
        credentials: %Ueberauth.Auth.Credentials{
          token: "hubspot_access_token"
        },
        info: %Ueberauth.Auth.Info{
          email: "hubspot@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/hubspot/callback")

      # Should redirect to login or handle as new user signup
      # Adjust based on your actual auth logic
      assert redirected_to(conn) != ~p"/dashboard/settings"
    end
  end

  describe "GET /auth/google/callback" do
    test "creates user credential for Google OAuth", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :google,
        uid: "google-user-123",
        credentials: %Ueberauth.Auth.Credentials{
          token: "google_access_token",
          refresh_token: "google_refresh_token",
          expires_at: 1_735_689_600
        },
        info: %Ueberauth.Auth.Info{
          email: "google@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/google/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :info) == "Google account added successfully."

      credentials = Accounts.list_user_credentials(user, provider: "google")
      assert length(credentials) == 1
    end
  end

  describe "GET /auth/linkedin/callback" do
    test "creates user credential for LinkedIn OAuth", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        provider: :linkedin,
        uid: "linkedin-user-123",
        credentials: %Ueberauth.Auth.Credentials{
          token: "linkedin_access_token",
          refresh_token: "linkedin_refresh_token",
          expires_at: 1_735_689_600
        },
        info: %Ueberauth.Auth.Info{
          email: "linkedin@example.com"
        }
      }

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> get(~p"/auth/linkedin/callback")

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :info) == "LinkedIn account added successfully."

      credentials = Accounts.list_user_credentials(user, provider: "linkedin")
      assert length(credentials) == 1
    end
  end
end
