require Logger

# Gemini Server

defmodule GeminiServer do

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
    routes = :ets.new(:routes, [:set, :protected])
    :ets.insert(routes, {"/", fn -> "20 text/gemini\r\n# Test\n\nHello world\n" end})

    # examples
    add_route(routes, "/", fn ->
      "20 text/gemini\r\n# Test\n\nHello world\n"
    end)
    add_route(routes, "/test", fn ->
      "20 text/gemini\r\n# Test page\n\n> 123456\n"
    end)
    add_route(routes, "/generic/:", fn ->
      "20 text/gemini\r\n# Test page\n\n> 123456\n"
    end)

    accept(socket, routes)
  end

  defp accept(socket, routes) do
    {:ok, client} = :ssl.transport_accept(socket)
    spawn(fn -> handshake(client, routes) end)
    accept(socket, routes)
  end

  defp getaddr(socket) do
    {:ok, {addr, port}} = :ssl.peername(socket)
    " [#{elem(addr, 0)}.#{elem(addr, 1)}.#{elem(addr, 2)}.#{elem(addr, 3)}:#{port}]"
  end

  defp handshake(socket, routes) do
    try do
      {:ok, client} = :ssl.handshake(socket)
      read(client, routes)
    rescue
      e ->
        Logger.error("Client handshake failure :" <> 
          getaddr(socket) <> "\n" <>
          Exception.format(:error, e, __STACKTRACE__))
        :ssl.close(socket)
    end
  end

  defp add_route(routes, route, func) do
    if hd(to_charlist(String.last(route))) != ?/ do
      :ets.insert(routes, {route <> "/", func})
    else
      :ets.insert(routes, {route, func})
    end
  end

  defp getroute_iter(url, route, start, n, url_str) do
    cond do
      url == [] && n == 0 ->
        []
      url == [] ->
        route ++ [String.slice(url_str, start..n - 1)]
      hd(url) == ?/ && n != start ->
        getroute_iter(tl(url), route ++ [String.slice(url_str, start..n - 1)],
          n + 1, n + 1, url_str)
      hd(url) == ?/ && n == start ->
        getroute_iter(tl(url), route, start + 1, n + 1, url_str)
      true ->
        getroute_iter(tl(url), route, start, n + 1, url_str)
    end
  end

  defp getroute(url) do
    getroute_iter(to_charlist(url), [], 0, 0, url)
  end

  defp rmhost(data) do
    if String.length(data) == 0 || hd(to_charlist(data)) == ?/ do
      data
    else
      rmhost(String.slice(data, 1..-1))
    end
  end

  defp rmslash(data) do
    if hd(to_charlist(String.last(data))) == ?/ do
      rmslash(String.slice(data, 0..-2))
    else
      rmhost(data)
    end
  end

  defp geturl(data) do
    cond do
      String.slice(data, 0..8) != "gemini://" ->
        {:error, "Invalid request, no protocol specification"}
      String.slice(data, String.length(data) - 1, 2) != "\r\n" ->
        {:error, "Invalid request, no CRLF"}
      true ->
        url = rmslash(String.slice(data, 9..-2)) <> "/"
        {url, getroute(url)}
    end
  end

  defp read(socket, routes) do
    try do
      {state, data} = :ssl.recv(socket, 1024)
      if state == :ok do
        {url, route} = geturl(data)
        if url == :error do
          raise route
        end
        row = :ets.lookup(routes, url)
        if row == [] do
          Logger.info("Not found : " <> url <> getaddr(socket))
          :ssl.send(socket, "59 Page not found\r\n")
        else
          Logger.info("Request : " <> url <> getaddr(socket))
          :ssl.send(socket, elem(hd(row), 1).())
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

end
