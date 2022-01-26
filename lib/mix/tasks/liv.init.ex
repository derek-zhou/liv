defmodule Mix.Tasks.Liv.Init do
  use Mix.Task

  @impl true
  def run(_argd) do
    nodes = [node()]
    Mix.Task.run("app.start", [])
    Memento.stop()
    Memento.Schema.create(nodes)
    Memento.start()
    Memento.Table.create!(Liv.Correspondent, disc_copies: nodes)
    Liv.AddressVault.migrate()
    Memento.stop()
  end
end
