require Logger
require Ecto.Query

# Gemini Chat

defmodule Gmichat do

  defp main_page(args) do
    content = "# GmiChat\n\n" <>
      if get_user(args[:cert]) == nil do
        "=>/login Login\n" <>
        "=>/register Register\n"
      else
        "=>/disconnect Disconnect\n"
      end
    Gmi.content(content)
  end

  defp register(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input("Username")
      true ->
        Gmi.redirect("/register/" <> args[:query])
    end
  end

  defp write_msg(message, from, dst, dm) do
    msg = %Gmichat.Message{
      message: message,
      user_id: from,
      destination: dst,
      timestamp: System.system_time(:second),
      dm: dm
    }
    {state, ret} = msg |> Gmichat.Repo.insert
    if state == :ok do
      :ok
    else
      elem(elem(hd(ret.errors), 1), 0)
    end
  end

  defp create_user(name, password) do
    user = %Gmichat.User{
      name: String.downcase(name), 
      password: Argon2.hash_pwd_salt(password), 
      timezone: 0,
      timestamp: System.system_time(:second)
    }
    {state, ret} = Gmichat.User.changeset(user, %{}) |> Gmichat.Repo.insert
    if state == :ok do
      :ok
    else
      name <> " " <> elem(elem(hd(ret.errors), 1), 0)
    end
  end

  defp register_complete(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input_secret("Password")
      true ->
        ret = create_user(args[:name], args[:query])
        if ret == :ok do
          Gmi.redirect("/register/x/success")
        else
          Gmi.bad_request(ret)
        end
    end
  end

  defp login(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input("Username")
      true ->
        Gmi.redirect("/login/" <> args[:query])
    end
  end

  defp try_login(name, password) do
    user = Gmichat.User |> Gmichat.Repo.get_by(name: name)
    if user != nil and Argon2.verify_pass(password, user.password) do
      {:ok, user}
    else
      {:error, "Invalid username or password"}
    end
  end

  defp login_complete(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input_secret("Password")
      true ->
        {state, ret} = try_login(args[:name], args[:query])
        if state == :ok do
          :ets.insert(:users, {
            args[:cert], ret
          })
          Gmi.redirect("/account")
        else
          Gmi.bad_request(ret)
        end
    end
  end

  defp show_messages(rows, timezone, out \\ "") do
    if rows == [] do
      out
    else
      row = hd(rows)
      {:ok, time} = DateTime.from_unix(row.timestamp + timezone * 3600)
      show_messages(tl(rows), timezone, out 
        <> "[" <> DateTime.to_string(time) <> "] "
        <> "<" <> row.user.name <> "> "
        <> row.message <> "\n")
    end
  end

  defp account(args) do
    user = get_user(args[:cert])
    if user == nil do
      Gmi.redirect("/")
    else
      results = Ecto.Query.from u in Gmichat.Message,
      order_by: [asc: u.timestamp],
      limit: 50,
      where: u.dm == false and u.destination == 0
      results = results 
      
      results = results |> Ecto.Query.preload(:user) |> Gmichat.Repo.all
      content = "# Connected as " <> user.name <>
        "\n\n" <> "## Public chat\n" <> show_messages(results, user.timezone)
        <> "\n=>/account/write Send message"
        <> "\n=>/account/zone Set time zone [UTC " 
        <> to_string(user.timezone) <> "]"
      Gmi.content(content)
    end
  end

  defp account_zone(args) do
    user = get_user(args[:cert])
    if user == nil do
      Gmi.redirect("/")
    else
      if args[:query] == "" do
        Gmi.input("UTC offset")
      else
        ret = Integer.parse(args[:query])
        ret = if ret == :error do ret else elem(ret, 0) end
        cond do
          ret == :error ->
            Gmi.bad_request("Invalid value")
          ret < -14 or ret > 14 ->
            Gmi.bad_request("Offset must be between -14 and 14")
          true ->
            Ecto.Changeset.change(user, %{timezone: ret}) |>
            Gmichat.User.changeset |>
            Gmichat.Repo.update!
            :ets.insert(:users, {args[:cert], %{user | timezone: ret}})
            Gmi.redirect("/account")
        end
      end
    end
  end

  defp account_write(args) do
    user = get_user(args[:cert])
    if user == nil do
      Gmi.redirect("/")
    else
      if args[:query] == "" do
        Gmi.input(user.name)
      else
        ret = write_msg(args[:query], user.id, 0, false)
        if ret == :ok do
          Gmi.redirect("/account")
        else
          Gmi.bad_request(ret)
        end
      end
    end
  end

  def get_user(cert) do
    if cert == nil do
        nil
    else
      rows = :ets.lookup(:users, cert)
      if rows == [] do
        nil
      else
        elem(hd(rows), 1)
      end
    end
  end

  def start() do
    :users = :ets.new(:users, [:set, :public, :named_table])
    Gmi.init()
    Gmi.add_route("/", fn args -> main_page(args) end)
    Gmi.add_route("/register", fn args -> register(args) end)
    Gmi.add_route("/register/:name", fn args -> register_complete(args) end)
    Gmi.add_route("/register/x/success", fn _ ->
      Gmi.content(
        "# Registration complete\n\n" <>
        "=>/login You can now login with your account\n")
    end)
    Gmi.add_route("/login", fn args -> login(args) end)
    Gmi.add_route("/login/:name", fn args -> login_complete(args) end)
    Gmi.add_route("/account", fn args -> account(args) end)
    Gmi.add_route("/account/write", fn args -> account_write(args) end)
    Gmi.add_route("/account/zone", fn args -> account_zone(args) end)
    Gmi.listen()
  end
  
end
