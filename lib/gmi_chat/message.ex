defmodule Gmichat.Message do
  use Ecto.Schema

  @primary_key false
  schema "messages" do
    field :message, :string
    belongs_to :user, Gmichat.User
    field :timestamp, :integer
    field :destination, :integer
    field :dm, :boolean
  end
end
