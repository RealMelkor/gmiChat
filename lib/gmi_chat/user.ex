defmodule Gmichat.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :password, :string
    field :timezone, :integer
    field :timestamp, :integer
  end

  def changeset(user, params \\ %{}) do
    user
    |> Ecto.Changeset.cast(params, [:name])
    |> Ecto.Changeset.unique_constraint(:name)
  end

end
