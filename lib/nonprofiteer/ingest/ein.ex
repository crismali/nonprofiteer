defmodule Nonprofiteer.Ingest.Ein do
  @moduledoc """
  Canonicalizes an EIN to a single stored form.

  The EIN is the one value Nonprofiteer normalizes — not for matching (names/addresses stay
  raw; consumers normalize those), but because it's the **identifier** every source's orgs are
  looked up and joined on. A dashed, space-padded, or leading-zero-dropped EIN from a new
  source would silently miss the org spine, so it's canonicalized at the ingest boundary to a
  bare 9-digit string.
  """

  @doc """
  Returns `value` as a bare 9-digit EIN string, or `nil` if it isn't a recoverable EIN.

  Strips all non-digits, then accepts exactly 9 digits, or recovers a dropped leading zero
  from an 8-digit value (a common artifact of EINs handled as numbers). Anything else is `nil`
  — better an orphan skip than a wrong identifier.

  ## Examples

      iex> Nonprofiteer.Ingest.Ein.normalize("01-0631747")
      "010631747"

      iex> Nonprofiteer.Ingest.Ein.normalize("10631747")
      "010631747"

      iex> Nonprofiteer.Ingest.Ein.normalize("nope")
      nil
  """
  @spec normalize(String.t() | nil) :: String.t() | nil
  def normalize(nil), do: nil

  def normalize(value) when is_binary(value) do
    case String.replace(value, ~r/\D/, "") do
      <<_::binary-size(9)>> = ein -> ein
      <<_::binary-size(8)>> = short -> "0" <> short
      _ -> nil
    end
  end
end
