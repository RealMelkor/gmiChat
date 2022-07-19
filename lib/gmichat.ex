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
    accept(socket)
  end

  defp accept(socket) do
    {:ok, client} = :ssl.transport_accept(socket)
    spawn(fn -> handshake(client) end)
    accept(socket)
  end

  defp handshake(socket) do
    try do
      {:ok, client} = :ssl.handshake(socket)
      read(client)
    rescue
      e ->
        Logger.error("Client handshake failure :\n" <>
          Exception.format(:error, e, __STACKTRACE__))
        :ssl.close(socket)
        exit(1)
    end
  end

  defp request(data) do
    "20 text/gemini\r\n# Test\n\nHello world\n" <> data
  end

  defp getaddr(socket) do
    {:ok, {addr, port}} = :ssl.peername(socket)
    " [#{elem(addr, 0)}.#{elem(addr, 1)}.#{elem(addr, 2)}.#{elem(addr, 3)}:#{port}]"
  end

  defp geturl(data) do
    String.slice(data, 0..-2)
  end

  defp read(socket) do
    try do
      {state, data} = :ssl.recv(socket, 0)
      if state == :ok do
        Logger.info("Requested : " <> geturl(data) <> getaddr(socket))
        :ssl.send(socket, request(data))
      else
        Logger.error("Client read failure : " <> data <> getaddr(socket))
      end
      :ssl.close(socket)
    rescue
      e ->
        Logger.error("Client read failure :\n" <>
          Exception.format(:error, e, __STACKTRACE__) <>
            getaddr(socket))
        :ssl.close(socket)
    end
  end

end
