defmodule LivWeb.Guardian do
  alias Liv.{Configer, Shadow}
  alias :ets, as: ETS

  # name of the ETS table
  @ets_sessions Liv.Sessions

  def init(), do: ETS.new(@ets_sessions, [:named_table, :public])

  def build_token() do
    ttl = Configer.default(:token_ttl)
    key = :crypto.strong_rand_bytes(12)
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)
    ETS.insert(@ets_sessions, {key, now + ttl})
    key
  end

  defp cull_sessions() do
    now = System.convert_time_unit(System.monotonic_time(), :native, :second)
    ETS.safe_fixtable(@ets_sessions, true)
    cull_sessions(ETS.first(@ets_sessions), now)
    ETS.safe_fixtable(@ets_sessions, false)
  end

  defp cull_sessions(:"$end_of_table", _), do: :ok

  defp cull_sessions(key, now) do
    case ETS.lookup(@ets_sessions, key) do
      [{^key, expired_at}] when expired_at >= now -> :ok
      _ -> drop_session(key)
    end

    cull_sessions(ETS.next(@ets_sessions, key), now)
  end

  defp drop_session(key) do
    Shadow.stop(key)
    ETS.delete(@ets_sessions, key)
  end

  def valid_token?(token) do
    cull_sessions()
    ETS.member(@ets_sessions, token)
  end
end
