defmodule LivWeb.Draft do
  use Surface.Component

  prop text, :string, default: ""

  defp preview(text) do
    try do
      Earmark.as_html!(text)
    rescue
      RuntimeError ->
        """
        <div class="alert alert-danger">Ilegal markdown</div>
        """
    end
  end
end
