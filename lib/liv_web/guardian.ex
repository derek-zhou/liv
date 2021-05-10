defmodule LivWeb.Guardian do
  use Guardian, otp_app: :liv

  @impl true
  def subject_for_token(user, _claims), do: {:ok, user}

  @impl true
  def resource_from_claims(%{"sub" => str}), do: {:ok, str}

  def build_token(user) do
    case encode_and_sign(user) do
      {:ok, token, claims} -> {:ok, token, claims}
      _ -> raise("cannot encode token")
    end
  end

  def decode_token(token) do
    case resource_from_token(token) do
      {:ok, user, _claims} -> user
      _ -> nil
    end
  end
end
