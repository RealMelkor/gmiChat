defmodule Gmichat.Message do
  use Ecto.Schema

  @primary_key false
  schema "messages" do
    field :message, :string
    field :source, :integer
    field :timestamp, :integer
    field :destination, :integer
    field :dm, :boolean
  end
end
