defmodule SocialScribeWeb.UserSettingsLiveTest do
  use SocialScribeWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import SocialScribe.AccountsFixtures

  describe "UserSettingsLive" do
    @describetag :capture_log

    setup :register_and_log_in_user

    test "redirects if user is not logged in", %{conn: conn} do
      conn = recycle(conn)
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dashboard/settings")
      assert path == ~p"/users/log_in"
    end

    test "renders settings page for logged-in user", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "h1", "User Settings")
      assert has_element?(view, "h2", "Connected Google Accounts")
      assert has_element?(view, "a", "Connect another Google Account")
      assert has_element?(view, "h2", "Connected Hubspot Account")
      assert has_element?(view, "a", "Connect a Hubspot Account")
    end

    test "displays a message if no Google accounts are connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
      assert has_element?(view, "p", "You haven't connected any Google accounts yet.")
    end

    test "displays connected Google accounts", %{conn: conn, user: user} do
      # Create a Google credential for the user
      # Assuming UserCredential has an :email field for display purposes.
      # If not, you might display the UID or another identifier.
      credential_attrs = %{
        user_id: user.id,
        provider: "google",
        uid: "google-uid-123",
        token: "test-token",
        email: "linked_account@example.com"
      }

      _credential = user_credential_fixture(credential_attrs)

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "li", "UID: google-uid-123")
      assert has_element?(view, "li", "(linked_account@example.com)")
      refute has_element?(view, "p", "You haven't connected any Google accounts yet.")
    end

    test "displays a message if no Hubspot accounts are connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
      assert has_element?(view, "p", "You haven't connected any Hubspot accounts yet.")
    end

    test "displays connected Hubspot accounts", %{conn: conn, user: user} do
      credential_attrs = %{
        user_id: user.id,
        provider: "hubspot",
        uid: "hubspot-uid-456",
        token: "hubspot-test-token",
        refresh_token: "hubspot-refresh-token",
        email: "hubspot@example.com"
      }

      _credential = user_credential_fixture(credential_attrs)

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "li", "UID: hubspot-uid-456")
      assert has_element?(view, "li", "(hubspot@example.com)")
      refute has_element?(view, "p", "You haven't connected any Hubspot accounts yet.")
    end

    test "displays multiple connected accounts from different providers", %{conn: conn, user: user} do
      # Create credentials for multiple providers
      user_credential_fixture(%{
        user_id: user.id,
        provider: "google",
        uid: "google-uid-123",
        token: "google-token",
        email: "google@example.com"
      })

      user_credential_fixture(%{
        user_id: user.id,
        provider: "hubspot",
        uid: "hubspot-uid-456",
        token: "hubspot-token",
        email: "hubspot@example.com"
      })

      user_credential_fixture(%{
        user_id: user.id,
        provider: "linkedin",
        uid: "linkedin-uid-789",
        token: "linkedin-token",
        email: "linkedin@example.com"
      })

      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      # Verify all accounts are displayed
      assert has_element?(view, "li", "UID: google-uid-123")
      assert has_element?(view, "li", "UID: hubspot-uid-456")
      assert has_element?(view, "li", "URN: linkedin-uid-789")

      # Verify no "not connected" messages are shown
      refute has_element?(view, "p", "You haven't connected any Google accounts yet.")
      refute has_element?(view, "p", "You haven't connected any Hubspot accounts yet.")
      refute has_element?(view, "p", "You haven't connected any LinkedIn accounts yet.")
    end

    test "displays Hubspot link button when no account is connected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/settings")

      assert has_element?(view, "a[href='/auth/hubspot']", "Connect a Hubspot Account")
    end
  end
end
