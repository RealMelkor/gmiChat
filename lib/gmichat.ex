require Logger

# Gemini Server

defmodule Gmi do

  def init() do
    :routes = :ets.new(:routes, [:set, :protected, :named_table])
  end

  def listen(port \\ 1965) do
    :ok = :ssl.start()
    {:ok, socket} = :ssl.listen(port, [
      certfile: "cert.pem",
      keyfile: "key.pem",
      active: false,
      binary: true,
      packet: :line,
      reuseaddr: true
    ])
    Logger.info("Listening on port #{port}")
   
    accept(socket)
  end

  defp accept(socket) do
    {:ok, client} = :ssl.transport_accept(socket)
    spawn(fn -> handshake(client) end)
    accept(socket)
  end

  defp getaddr(socket) do
    {:ok, {addr, port}} = :ssl.peername(socket)
    " [#{elem(addr, 0)}.#{elem(addr, 1)}.#{elem(addr, 2)}.#{elem(addr, 3)}:#{port}]"
  end

  defp handshake(socket) do
    try do
      {:ok, client} = :ssl.handshake(socket)
      read(client)
    rescue
      e ->
        Logger.error("Client handshake failure :" <> 
          getaddr(socket) <> "\n" <>
          Exception.format(:error, e, __STACKTRACE__))
        :ssl.close(socket)
    end
  end

  def add_route(route, func) do
    :ets.insert(:routes, {get_route(rmslash(route)), func})
  end

  defp get_route_iter(url, route, start, n, url_str) do
    cond do
      url == [] && n == 0 ->
        []
      url == [] or (hd(url) == ?/ && n != start) ->
        str = String.slice(url_str, start..n - 1)
        route =
          if String.first(str) == ":" do
            route ++ [String.to_atom(String.slice(str, 1..-1))]
          else route ++ [str] end
        if url == [] do
          route
        else
          get_route_iter(tl(url), route, n + 1, n + 1, url_str)
        end
      hd(url) == ?/ && n == start ->
        get_route_iter(tl(url), route, start + 1, n + 1, url_str)
      true ->
        get_route_iter(tl(url), route, start, n + 1, url_str)
    end
  end

  defp get_route(url) do
    get_route_iter(to_charlist(url), [], 0, 0, url)
  end

  defp format_query(query, start \\ 0, n \\ 0, out \\ "", len \\ -1) do
    len = if len == -1 do String.length(query) else len end
    cond do
      len == n ->
        out <> String.slice(query, start, n - start)
      String.at(query, n) == "%" ->
        format_query(query, n + 3, n + 3,
          out <> String.slice(query, start, n - start) <>
            List.to_string([elem(
              Integer.parse(String.slice(query, n + 1, 2), 16), 0
            )]),
          len)
      true ->
        format_query(query, start, n + 1, out, len)
    end
  end

  defp rmhost(data) do
    if String.length(data) == 0 || String.first(data) == "/" do
      data
    else
      rmhost(String.slice(data, 1..-1))
    end
  end

  defp rmslash(data) do
    if String.length(data) > 0 && String.last(data) == "/" do
      rmslash(String.slice(data, 0..-2))
    else
      data
    end
  end

  defp rmquery(data, start \\ -1) do
    n = fn ->
      if start == -1 do
        String.length(data) - 1
      else 
        start
      end
    end.()
    cond do
      n <= 0 ->
        {data, ""}
      String.at(data, n) == "?" ->
        {String.slice(data, 0, n), String.slice(data, n + 1..-1)} 
      true ->
        rmquery(data, n - 1)
    end
  end

  defp get_url(data) do
    cond do
      String.slice(data, 0..8) != "gemini://" ->
        {:error, "Invalid request, no protocol specification"}
      String.slice(data, String.length(data) - 1, 2) != "\r\n" ->
        {:error, "Invalid request, no CRLF"}
      true ->
        rmquery(rmhost(rmslash(String.slice(data, 9..-2))))
    end
  end

  defp compare_route(routes, route, generic \\ []) do
    l1 = length(routes)
    l2 = length(route)
    cond do
      l1 != l2 ->
        nil
      l1 == 0 ->
        []
      !is_atom(hd(routes)) && hd(routes) != hd(route) ->
        nil
      true ->
        generic = if is_atom(hd(routes)) do
          generic ++ [{hd(routes), hd(route)}]
        else generic end
        if tl(routes) == [] do
          generic
        else
          compare_route(tl(routes), tl(route), generic) 
        end
    end
  end

  defp get_generic(route, routes) do
    generic = compare_route(elem(hd(routes), 0), route)
    cond do
      generic != nil ->
        {hd(routes), generic}
      tl(routes) == [] ->
        {nil, nil}
      true ->
        get_generic(route, tl(routes))
    end
  end

  defp read(socket) do
    try do
      {state, data} = :ssl.recv(socket, 1024)
      if state == :ok do
        {url, query} = get_url(data)
        if url == :error do
          raise url
        end
                
        table = :ets.select(:routes, [{:"$1", [], [:"$1"]}])
        {route, generic} = get_generic(get_route(url), table)

        url = if url != "" do url else url <> "/" end
        url = if query == "" do url else url <> "?<*>" end

        if route == nil do
          Logger.info("Not found : " <> url <> getaddr(socket))
          :ssl.send(socket, "59 Page not found\r\n")
        else
          Logger.info("Request : " <> url <> getaddr(socket))
          :ssl.send(socket, elem(route, 1).
            (generic ++ [{:query, format_query(query)}]))
        end
      else
        Logger.error("Client read failure : " <> data <> getaddr(socket))
      end
    rescue
      e ->
        Logger.error("Client read failure :" <>
          getaddr(socket) <> "\n" <>
            Exception.format(:error, e, __STACKTRACE__))
    after
      :ssl.close(socket)
    end
  end

  def content(data) do
    "20 text/gemini\r\n" <> data
  end

  def input(data) do
    "10 " <> data <> "\r\n"
  end

end
