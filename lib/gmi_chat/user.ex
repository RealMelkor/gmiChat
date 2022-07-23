defmodule Gmichat.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :password, :string
    field :timezone, :integer
    field :timestamp, :integer
    #has_many :messages, Gmichat.Message
  end

  def validate_timezone(changeset) do
    zone = Ecto.Changeset.get_field(changeset, :timezone)
    if zone < -14 or zone > 14 do
      Ecto.Changeset.add_error(changeset, :timezone, "is not between -14 and 14")
    else
      changeset
    end
  end

  def changeset(user, params \\ %{}) do
    user
    |> Ecto.Changeset.cast(params, [:name, :password, :timezone, :timestamp])
    |> validate_timezone
    |> Ecto.Changeset.unique_constraint(:name)
  end

end
