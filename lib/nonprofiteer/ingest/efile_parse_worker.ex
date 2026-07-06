defmodule Nonprofiteer.Ingest.EfileParseWorker do
  @moduledoc """
  Parses one 990 e-file return into a `Filing` and its Part VII `Person`s.

  Per-filing (fanned out from `EfileIndexWorker`), so it writes **no** per-run audit row — the
  `Filing` row's existence is the success record, and the batch-level `Ingest.Run` lives on the
  index pass. The flow: download XML → mirror to object storage (D11) → parse → resolve the org
  by EIN → upsert the filing, its people, and their shared filer address.

  Idempotent (upserts keyed on `source_object_id` / `(filing_id, part_vii_sequence)`), so an
  Oban retry converges. Skips that aren't failures — a return whose EIN isn't in the BMF spine
  (**orphan**), or one out of Phase-1 scope (**unsupported**: pre-2013 schema / non-990) — are
  logged and return `:ok` (no retry, no filing). Genuine errors (download, mirror, DB) raise so
  Oban retries.
  """
  use Oban.Worker,
    queue: :ingest_incremental,
    max_attempts: 5,
    unique: [keys: [:object_id], period: {1, :day}]

  require Ash.Query
  require Logger

  alias Nonprofiteer.Ingest.Client
  alias Nonprofiteer.Ingest.Efile.PartVii
  alias Nonprofiteer.Ingest.Efile.PartVii.UnsupportedReturnError
  alias Nonprofiteer.Ingest.ObjectStore
  alias Nonprofiteer.Orgs.Address
  alias Nonprofiteer.Orgs.Filing
  alias Nonprofiteer.Orgs.Organization
  alias Nonprofiteer.Orgs.Person

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"object_id" => object_id, "xml_url" => url} = args}) do
    xml = Client.fetch!(url)
    mirror!(object_id, xml)

    case safe_parse(xml) do
      {:ok, parsed} -> ingest(parsed, object_id, parse_date(args["filed_on"]))
      {:unsupported, reason} -> skip(object_id, "unsupported: #{reason}")
    end
  end

  # Mirror is a precondition when R2 is configured (so a re-parse can read our own copy, D11);
  # dormant in dev/test. A configured-but-failing mirror raises so Oban retries.
  defp mirror!(object_id, xml) do
    if ObjectStore.configured?() do
      case ObjectStore.put("efile/#{object_id}.xml", xml) do
        :ok -> :ok
        {:error, reason} -> raise "R2 mirror failed for #{object_id}: #{inspect(reason)}"
      end
    else
      :ok
    end
  end

  defp safe_parse(xml) do
    {:ok, PartVii.parse!(xml)}
  rescue
    error in UnsupportedReturnError -> {:unsupported, Exception.message(error)}
  end

  defp ingest(%{ein: ein} = parsed, object_id, filed_on) do
    case org_for(ein) do
      nil ->
        skip(object_id, "orphan: EIN #{inspect(ein)} not in the org spine")

      org ->
        filing = upsert_filing!(parsed, org, object_id, filed_on)
        people = Enum.map(parsed.people, &upsert_person!(&1, org, filing))
        link_shared_address!(people, parsed.address)
        :ok
    end
  end

  # Org lookup is on the BMF-sourced, canonical EIN. A nil/absent EIN can't anchor to the spine.
  defp org_for(nil), do: nil

  defp org_for(ein) do
    Organization
    |> Ash.Query.filter(source == :bmf and ein == ^ein)
    |> Ash.read_one!()
  end

  defp upsert_filing!(parsed, org, object_id, filed_on) do
    Filing
    |> Ash.Changeset.for_create(:upsert_from_efile, %{
      organization_id: org.id,
      return_type: parsed.return_type,
      tax_year: parsed.tax_year,
      source_object_id: object_id,
      filed_on: filed_on,
      schema_version: parsed.schema_version
    })
    |> Ash.create!()
  end

  defp upsert_person!(person, org, filing) do
    Person
    |> Ash.Changeset.for_create(:upsert_from_efile, %{
      organization_id: org.id,
      filing_id: filing.id,
      name: person.name,
      title: person.title,
      part_vii_sequence: person.part_vii_sequence
    })
    |> Ash.create!()
  end

  # All of a filing's Part VII people share the one filer address. Reuse the address already
  # linked on a re-parse (update in place); otherwise create it once — no orphan churn.
  defp link_shared_address!([], _attrs), do: :ok

  defp link_shared_address!(people, attrs) do
    address_id =
      case Enum.find_value(people, & &1.address_id) do
        nil -> create_address!(attrs).id
        existing_id -> update_address!(existing_id, attrs).id
      end

    Enum.each(people, fn person ->
      if person.address_id != address_id, do: set_person_address!(person, address_id)
    end)
  end

  defp create_address!(attrs) do
    Address |> Ash.Changeset.for_create(:create, attrs) |> Ash.create!()
  end

  defp update_address!(id, attrs) do
    Address |> Ash.get!(id) |> Ash.Changeset.for_update(:update, attrs) |> Ash.update!()
  end

  defp set_person_address!(person, address_id) do
    person |> Ash.Changeset.for_update(:update, %{address_id: address_id}) |> Ash.update!()
  end

  defp skip(object_id, reason) do
    Logger.info("EfileParseWorker skip #{object_id}: #{reason}")
    :ok
  end

  defp parse_date(nil), do: nil

  defp parse_date(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      {:error, _} -> nil
    end
  end
end
