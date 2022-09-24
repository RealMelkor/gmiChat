require Logger
require Ecto.Query

# Gemini Chat

defmodule Gmichat do

  @max_register 3
  @max_attemps_ip 10
  @max_attemps_account 50
  @max_messages 3
  @max_messages_timeout 2

  defp main_page(args) do
      if get_user(args[:cert]) == nil do
        Gmi.content(
          "# GmiChat\n\n" <>
          "Chat platform for the Gemini protocol\n" <>
          "A client certificate is required to register and to login\n\n" <>
          "=>/login Login\n" <>
          "=>/register Register\n\n" <>
          "## Softwares\n\n" <>
          "=>gemini://gemini.rmf-dev.com/repo/Vaati/gmiChat Source code\n" <>
          "=>gemini://gemini.rmf-dev.com/repo/Vaati/Vgmi/readme Recommended client"
        )
      else
        Gmi.redirect("/account")
      end
  end

  defp can_attempt(table, key, threshold) do
    rows = :ets.lookup(table, key)
    rows == [] or elem(hd(rows), 1) < threshold
  end

  defp add_attempt(table, key) do
    value = :ets.lookup(table, key)
    value = if value == [] do 0 else elem(hd(value), 1) end
    :ets.insert(table, {
      key, value + 1
    })
  end

  defp ask_input(args, field, to) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input(field)
      true ->
        Gmi.redirect(to <> args[:query])
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
    last_message = :ets.lookup(:messages_rate, from)
    last_message = if last_message != [] do
      elem(hd(last_message), 1)
    else
      last_message
    end
    last_message = 
      if last_message == [] or elem(last_message, 0) + @max_messages_timeout 
          < System.system_time(:second) do 
        {System.system_time(:second), 1}
      else 
        {elem(last_message, 0), elem(last_message, 1) + 1}
      end
    if elem(last_message, 1) > @max_messages do
      "You sent too many messages in a short period of time"
    else
      :ets.insert(:messages_rate, {from, last_message})
      {state, ret} = msg |> Gmichat.Repo.insert
      if state == :ok do
        :ok
      else
        elem(elem(hd(ret.errors), 1), 0)
      end
    end
  end

  defp create_user(name, password) do
    user = %Gmichat.User{
      name: String.downcase(name), 
      password: password,
      timezone: 0,
      linelength: 0,
      leftmargin: 0,
      timestamp: System.system_time(:second)
    }
    {state, ret} = Gmichat.User.changeset(user, %{}) |> Gmichat.Repo.insert
    if state == :ok do
      :ok
    else
      to_string(elem(hd(ret.errors), 0)) <> " " <> elem(elem(hd(ret.errors), 1), 0)
    end
  end

  defp register_complete(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input_secret("Password")
      !can_attempt(:registrations, elem(args[:addr], 0), @max_register) ->
        Gmi.failure("Temporary registration limit reached for your ip")
      true ->
        ret = create_user(args[:name], args[:query])
        if ret == :ok do
          add_attempt(:registrations, elem(args[:addr], 0))
          Gmi.redirect("/register/x/success")
        else
          Gmi.failure(ret)
        end

    end
  end

  defp try_login(name, password, addr) do
    name = String.downcase(name)
    cond do
      !can_attempt(:account_attempts, name, @max_attemps_account) ->
        {:error, "Too many login attempts for this account"}
      !can_attempt(:ip_attempts, addr, @max_attemps_ip) ->
        {:error, "Too many login attempts from your ip"}
      true ->
        user = Gmichat.User |> Gmichat.Repo.get_by(name: name)
        if user != nil and Argon2.verify_pass(password, user.password) do
          {:ok, user}
        else
          add_attempt(:account_attempts, name)
          add_attempt(:ip_attempts, addr)
          {:error, "Invalid username or password"}
        end
    end
  end

  defp login_complete(args) do
    cond do
      args[:cert] == nil ->
        Gmi.cert_required("Certificate required to register")
      args[:query] == "" ->
        Gmi.input_secret("Password")
      true ->
        {state, ret} = try_login(args[:name], args[:query], elem(args[:addr], 0))
        if state == :ok do
          :ets.insert(:users, {
            args[:cert], %{ret | password: :ignore}
          })
          Gmi.redirect("/account")
        else
          Gmi.failure(ret)
        end
    end
  end

  defp format_message(message, llength, margin, pos \\ 0) do
    if llength == 0 do
      String.duplicate(" ", margin) <> message <> "\n"
    else
      lastline = pos + llength >= String.length(message)
      length = if lastline do
        String.length(message) - pos
      else
        llength
      end
      new_message =
        String.slice(message, 0, pos) <>
        String.duplicate(" ", margin) <>
        String.slice(message, pos, length) <> "\n" <>
        String.slice(message, pos + length, String.length(message) - pos - length)
      if lastline do
        new_message
      else
        format_message(new_message,
            llength, margin, pos + llength + margin + 1)
      end
    end
  end

  defp show_messages(rows, timezone, llength, margin, out \\ "") do
    if rows == [] do
      out
    else
      row = hd(rows)
      {:ok, time} = DateTime.from_unix(row.timestamp + timezone * 3600)
      show_messages(tl(rows), timezone, llength, margin,
        format_message(
        "[" <> String.slice(DateTime.to_string(time), 0..-2) <> "] "
        <> "<" <> row.user.name <> "> "
        <> row.message, llength, margin) <> out)
    end
  end

  defp account(_, user) do
    results = Ecto.Query.from m in Gmichat.Message,
    order_by: [desc: m.timestamp],
    limit: 30,
    where: m.dm == false and m.destination == 0
    
    results = results |> Ecto.Query.preload(:user) |> Gmichat.Repo.all
    content = "# Connected as " <> user.name <>
      "\n\n" <> "## Public chat\n"
      <> show_messages(results, user.timezone, user.linelength, user.leftmargin)
      <> "\n=>/account/write Send message"
      <> "\n=>/account/dm Send direct message"
      <> "\n=>/account/contacts Contacts"
      <> "\n\n## Options\n"
      <> "\n=>/account/zone Set time zone [UTC " 
      <> to_string(user.timezone) <> "]"
      <> "\n=>/account/llength Set line length [" 
      <> to_string(user.linelength) <> "]"
      <> "\n=>/account/margin Set left margin [" 
      <> to_string(user.leftmargin) <> "]"
      <> "\n\n=>/account/disconnect Disconnect" 
    Gmi.content(content)
  end

  defp account_zone(args, user) do
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

  defp account_line_length(args, user) do
    if args[:query] == "" do
      Gmi.input("Chat line length (0 = no limit)")
    else
      ret = Integer.parse(args[:query])
      ret = if ret == :error do ret else elem(ret, 0) end
      cond do
        ret == :error ->
          Gmi.bad_request("Invalid value")
        ret < 0 or ret > 1024 ->
          Gmi.bad_request("Line length must be between 0 and 1024")
        true ->
          Ecto.Changeset.change(user, %{linelength: ret}) |>
          Gmichat.User.changeset |>
          Gmichat.Repo.update!
          :ets.insert(:users, {args[:cert], %{user | linelength: ret}})
          Gmi.redirect("/account")
      end
    end
  end

  defp account_left_margin(args, user) do
    if args[:query] == "" do
      Gmi.input("Left margin (0 = no margin)")
    else
      ret = Integer.parse(args[:query])
      ret = if ret == :error do ret else elem(ret, 0) end
      cond do
        ret == :error ->
          Gmi.bad_request("Invalid value")
        ret < 0 or ret > 4096 ->
          Gmi.bad_request("Left margin must be between 0 and 4096")
        true ->
          Ecto.Changeset.change(user, %{leftmargin: ret}) |>
          Gmichat.User.changeset |>
          Gmichat.Repo.update!
          :ets.insert(:users, {args[:cert], %{user | leftmargin: ret}})
          Gmi.redirect("/account")
      end
    end
  end

  defp account_write(args, user) do
    if args[:query] == "" do
      Gmi.input(user.name)
    else
      ret = write_msg(args[:query], user.id, 0, false)
      if ret == :ok do
        Gmi.redirect("/account")
      else
        Gmi.failure(ret)
      end
    end
  end

  def dm(args, user) do
    to = Gmichat.User |> Gmichat.Repo.get_by(name: args[:name])
    if to != nil and user.id != to.id do
      results = Ecto.Query.from m in Gmichat.Message,
      order_by: [desc: m.timestamp],
      limit: 30,
      where: m.dm == true and
      (m.destination == ^to.id and m.user_id == ^user.id) or
      (m.destination == ^user.id and m.user_id == ^to.id)
      results = results |> Ecto.Query.preload(:user) |> Gmichat.Repo.all
      Gmi.content(
        "=>/account/contacts Go back\n\n" <>
        "# " <> to.name <> " - Direct messages\n\n" <>
        show_messages(results, user.timezone, user.linelength, user.leftmargin) <>
        "\n=>/account/dm/" <> to.name <> "/write Send message")
    else
      Gmi.bad_request("User " <> args[:name] <> " not found")
    end
  end

  def dm_write(args, user) do
    if args[:query] == "" do
      Gmi.input("Send message")
    else
      to = Gmichat.User |> Gmichat.Repo.get_by(name: args[:name])
      if to != nil and user.id != to.id do
        write_msg(args[:query], user.id, to.id, true)
        Gmi.redirect("/account/dm/" <> to.name)
      else
        Gmi.bad_request("User " <> args[:name] <> " not found")
      end
    end
  end

  def show_contacts(rows, out \\ "") do
    if rows == [] do
      out
    else
      name = hd(hd(rows))
      show_contacts(tl(rows), out <> "=>/account/dm/" <> 
        name <> " " <> name <> "\n")
    end
  end

  def contacts(_, user) do
    query = """
    SELECT name FROM 
    (SELECT DISTINCT
    (CASE WHEN user_id=$1::integer THEN destination ELSE user_id END) AS uid, MAX(timestamp)
    FROM messages WHERE dm = true AND (destination = $1::integer OR user_id = $1::integer)
    GROUP BY uid) dms
    INNER JOIN users u ON u.id = dms.uid
    ORDER BY dms.max DESC;
    """

    results = Ecto.Adapters.SQL.query!(Gmichat.Repo, query, [user.id])
    
    Gmi.content("=>/account Go back\n\n# Contacts\n\n" <>
      show_contacts(results.rows))
  end

  def connected(args, func) do
    user = get_user(args[:cert])
    if user == nil do
      Gmi.redirect("/")
    else
      func.(args, user)
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

  defp decrease_limit_iter(table, rows) do
    if rows != [] do
      :ets.insert(table, {elem(hd(rows), 0), elem(hd(rows), 1) - 1})
      decrease_limit_iter(table, tl(rows))
    end
  end

  defp decrease_limit() do
    select = [{{:"$1", :"$2"}, [{:>, :"$2", 0}], [{{:"$1", :"$2"}}]}]
    decrease_limit_iter(:registrations, :ets.select(:registrations, select))
    decrease_limit_iter(:account_attempts, :ets.select(:account_attempts, select))
    decrease_limit_iter(:ip_attempts, :ets.select(:ip_attempts, select))
    :timer.sleep(30000)
    decrease_limit()
  end

  def start() do
    :users = :ets.new(:users, [:set, :public, :named_table])
    :registrations = :ets.new(:registrations, [:set, :public, :named_table])
    :ip_attempts = :ets.new(:ip_attempts, [:set, :public, :named_table])
    :account_attempts = :ets.new(:account_attempts, [:set, :public, :named_table])
    :messages_rate = :ets.new(:messages_rate, [:set, :public, :named_table])
    Gmi.init()
    Gmi.add_route("/", fn args -> main_page(args) end)
    Gmi.add_route("/register", fn args -> ask_input(args, "Username", "/register/") end)
    Gmi.add_route("/register/:name", fn args -> register_complete(args) end)
    Gmi.add_route("/register/x/success", fn _ ->
      Gmi.content(
        "# Registration complete\n\n" <>
        "=>/login You can now login with your account\n")
    end)
    Gmi.add_route("/login", fn args -> ask_input(args, "Username", "/login/") end)
    Gmi.add_route("/login/:name", fn args -> login_complete(args) end)
    Gmi.add_route("/account", fn args -> 
      connected(args, fn args, user ->
        account(args, user)
      end)
    end)
    Gmi.add_route("/account/write", fn args ->
      connected(args, fn args, user ->
        account_write(args, user)
      end)
    end)
    Gmi.add_route("/account/zone", fn args ->
      connected(args, fn args, user ->
        account_zone(args, user)
      end)
    end)
    Gmi.add_route("/account/llength", fn args ->
      connected(args, fn args, user ->
        account_line_length(args, user)
      end)
    end)
    Gmi.add_route("/account/margin", fn args ->
      connected(args, fn args, user ->
        account_left_margin(args, user)
      end)
    end)
    Gmi.add_route("/account/dm", fn args -> 
      connected(args, fn args, _ ->
        ask_input(args, "Username", "/account/dm/") 
      end)
    end)
    Gmi.add_route("/account/dm/:name", fn args -> 
      connected(args, fn args, user ->
        dm(args, user)
      end)
    end)
    Gmi.add_route("/account/dm/:name/write", fn args -> 
      connected(args, fn args, user ->
        dm_write(args, user)
      end)
    end)
    Gmi.add_route("/account/contacts", fn args -> 
      connected(args, fn args, user ->
        contacts(args, user)
      end)
    end)
    Gmi.add_route("/account/disconnect", fn args -> 
      if args[:cert] != nil do
        :ets.delete(:users, args[:cert]) 
      end
      Gmi.redirect("/")
    end)
    spawn_link(fn -> decrease_limit() end)
    Gmi.listen()
  end
  
end
