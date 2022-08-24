defmodule LivWeb.Guardian do
  alias Liv.Configer
  alias :ets, as: ETS

  # name of the ETS table
  @ets_sessions :liv_sessions

  def init(), do: ETS.new(@ets_sessions, [:named_table, :public])

  def build_token() do
    ttl = Configer.default(:token_ttl)
    key = :crypto.strong_rand_bytes(6)
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)
    ETS.insert(@ets_sessions, {key, now + ttl})
    Base.url_encode64(key)
  end

  def decode_token(token) do
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)

    case Base.url_decode64(token) do
      :error ->
        nil

      {:ok, key} ->
        case ETS.lookup(@ets_sessions, key) do
          [{^key, expired_at}] when expired_at > now -> true
          _ -> nil
        end
    end
  end
end
