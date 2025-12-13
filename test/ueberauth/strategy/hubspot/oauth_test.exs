defmodule Ueberauth.Strategy.Hubspot.OAuthTest do
  use ExUnit.Case, async: true

  alias Ueberauth.Strategy.Hubspot.OAuth

  describe "client/1" do
    test "creates OAuth2 client with correct defaults" do
      client = OAuth.client()

      assert client.strategy == OAuth
      assert client.site == "https://api.hubapi.com"
      assert client.authorize_url == "https://app.hubspot.com/oauth/authorize"
      assert client.token_url == "https://api.hubapi.com/oauth/v1/token"
    end

    test "allows overriding default options" do
      client = OAuth.client(site: "https://custom-site.com")

      assert client.site == "https://custom-site.com"
      assert client.authorize_url == "https://app.hubspot.com/oauth/authorize"
    end
  end

  describe "authorize_url!/2" do
    test "generates valid authorize URL" do
      url = OAuth.authorize_url!()

      assert url =~ "https://app.hubspot.com/oauth/authorize"
      assert url =~ "client_id="
      assert url =~ "redirect_uri="
      assert url =~ "response_type=code"
    end

    test "includes custom params in authorize URL" do
      url = OAuth.authorize_url!([scope: "crm.objects.contacts.read crm.objects.contacts.write"])

      assert url =~ "scope="
    end
  end
end
