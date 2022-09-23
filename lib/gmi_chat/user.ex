defmodule Gmichat.User do
  use Ecto.Schema

  schema "users" do
    field :name, :string
    field :password, :string
    field :timezone, :integer
    field :leftmargin, :integer
    field :linelength, :integer
    field :timestamp, :integer
  end

  def validate_password(changeset) do
    password = Ecto.Changeset.get_field(changeset, :password)
    len = if is_bitstring(password) do String.length(password) else 0 end
    cond do
      password == :ignore ->
        changeset
      len < 6 or len > 24 ->
        Ecto.Changeset.add_error(changeset, :password, "must be between 6 and 24")
      true ->
        Ecto.Changeset.put_change(changeset, :password, Argon2.hash_pwd_salt(password))
    end
  end
  
  def is_name_valid(name) do
    if name == [] do
      true
    else
      c = hd(name)
      if (c >= ?a and c <= ?z) or (c >= ?A and c <= ?Z) or (c >= ?0 and c <= ?9) do
        is_name_valid(tl(name))
      else
        false
      end
    end
  end

  def validate_name(changeset) do
    name = Ecto.Changeset.get_field(changeset, :name)
    len = String.length(name)
    cond do
      !is_name_valid(to_charlist(name)) ->
        Ecto.Changeset.add_error(changeset, :name, "must contains only letters and numbers")
      len < 3 or len > 12 ->
        Ecto.Changeset.add_error(changeset, :name, "must be between 3 and 12 characters")
      true -> 
        changeset
    end
  end

  def validate_timezone(changeset) do
    zone = Ecto.Changeset.get_field(changeset, :timezone)
    if zone < -14 or zone > 14 do
      Ecto.Changeset.add_error(changeset, :timezone, "must be between -14 and 14")
    else
      changeset
    end
  end

  def validate_linelength(changeset) do
    ll = Ecto.Changeset.get_field(changeset, :linelength)
    if ll < 0 or ll > 1024 do
      Ecto.Changeset.add_error(changeset, :linelength, "must be between 0 and 1024")
    else
      changeset
    end
  end

  def validate_leftmargin(changeset) do
    ll = Ecto.Changeset.get_field(changeset, :leftmargin)
    if ll < 0 or ll > 4096 do
      Ecto.Changeset.add_error(changeset, :leftmargin, "must be between 0 and 4096")
    else
      changeset
    end
  end


  def changeset(user, params \\ %{}) do
    user
    |> Ecto.Changeset.cast(params, [:name, :password, :timezone,
                                    :linelength, :leftmargin, :timestamp])
    |> validate_name
    |> validate_password
    |> validate_timezone
    |> validate_linelength
    |> validate_leftmargin
    |> Ecto.Changeset.unique_constraint(:name)
  end

end
