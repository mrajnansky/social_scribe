defmodule SocialScribe.Workers.ContactSuggestionsWorkerTest do
  use SocialScribe.DataCase, async: true
  use Oban.Testing, repo: SocialScribe.Repo

  alias SocialScribe.Workers.ContactSuggestionsWorker

  describe "perform/1" do
    test "returns error when meeting not found" do
      job = %Oban.Job{
        args: %{"meeting_id" => 999_999}
      }

      assert {:error, :meeting_not_found} = ContactSuggestionsWorker.perform(job)
    end

    # Add more tests as needed when you have meeting fixtures
  end
end
