defmodule GrangeWeb.AuthControllerTest do
  @moduledoc false
  use GrangeWeb.ConnCase, async: false

  alias Grange.{Accounts, AuthToken, FarmStore, Mailer}

  @alice %{
    "username" => "Alice",
    "email" => "alice@example.test",
    "password" => "harvest-please"
  }

  setup do
    Accounts.reset()
    FarmStore.reset()
    Mailer.Console.reset()
    :ok
  end

  defp json_post(conn, path, params) do
    conn
    |> put_req_header("content-type", "application/json")
    |> post(path, Jason.encode!(params))
  end

  defp session_cookie(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.starts_with?(&1, "_grange_key="))
  end

  defp register(conn \\ build_conn()),
    do: json_post(conn, "/api/auth/register", @alice)

  # Registration leaves the account locked, so most tests open the verify link
  # programmatically and keep the resulting session cookie.
  defp register_and_verify(conn \\ build_conn()) do
    register(conn)
    user = Accounts.find_by_email(@alice["email"])
    token = AuthToken.issue(user.id, :verify_email)
    json_post(build_conn(), "/api/auth/verify-email", %{"token" => token})
  end

  test "register creates a locked account and mails a verification link" do
    conn = register()

    assert %{"ok" => true, "pending" => true, "emailSent" => true} =
             json_response(conn, 201)

    refute session_cookie(conn)
    assert Mailer.Console.latest(@alice["email"])
  end

  test "register rejects duplicate credentials with 400" do
    register()
    assert %{"ok" => false} = json_response(register(), 400)
  end

  test "verify-email burns the token and sets the session cookie" do
    register()
    user = Accounts.find_by_email(@alice["email"])
    token = AuthToken.issue(user.id, :verify_email)

    conn = json_post(build_conn(), "/api/auth/verify-email", %{"token" => token})

    assert %{"ok" => true, "user" => %{"emailVerifiedAt" => verified}} =
             json_response(conn, 200)

    assert verified
    assert session_cookie(conn) =~ "HttpOnly"
  end

  test "a verification link cannot be used twice" do
    register()
    user = Accounts.find_by_email(@alice["email"])
    token = AuthToken.issue(user.id, :verify_email)

    assert %{"ok" => true} =
             json_post(build_conn(), "/api/auth/verify-email", %{"token" => token})
             |> json_response(200)

    assert %{"ok" => false} =
             json_post(build_conn(), "/api/auth/verify-email", %{"token" => token})
             |> json_response(400)
  end

  test "login is forbidden until the email is verified" do
    register()

    conn =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "harvest-please"
      })

    assert %{"ok" => false, "code" => "unverified"} = json_response(conn, 403)
    refute session_cookie(conn)
  end

  test "login with valid credentials sets the session cookie" do
    register_and_verify()

    conn =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "harvest-please"
      })

    assert %{"ok" => true, "user" => %{"username" => "Alice"}} =
             json_response(conn, 200)

    assert session_cookie(conn) =~ "HttpOnly"
  end

  test "login with a wrong password is 401 and sets no cookie" do
    register_and_verify()

    conn =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "wrong-password"
      })

    assert %{"ok" => false} = json_response(conn, 401)
    refute session_cookie(conn)
  end

  test "login as an unknown user is 401" do
    conn =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Nobody",
        "password" => "whatever-123"
      })

    assert %{"ok" => false} = json_response(conn, 401)
  end

  test "me is 401 when signed out" do
    conn = get(build_conn(), "/api/auth/me")
    assert %{"ok" => false} = json_response(conn, 401)
  end

  test "me returns the user when the session cookie is presented" do
    conn = register_and_verify() |> recycle()

    assert %{"ok" => true, "user" => %{"username" => "Alice"}} =
             json_response(get(conn, "/api/auth/me"), 200)
  end

  test "logout clears the session so me is 401 afterwards" do
    conn = register_and_verify() |> recycle()
    conn = json_post(conn, "/api/auth/logout", %{}) |> recycle()

    assert %{"ok" => false} = json_response(get(conn, "/api/auth/me"), 401)
  end

  test "resend-verification is uniform for known and unknown addresses" do
    register()
    Mailer.Console.reset()

    conn =
      json_post(build_conn(), "/api/auth/resend-verification", %{
        "email" => @alice["email"]
      })

    assert %{"ok" => true} = json_response(conn, 200)
    assert Mailer.Console.latest(@alice["email"])

    conn =
      json_post(build_conn(), "/api/auth/resend-verification", %{
        "email" => "nobody@example.test"
      })

    assert %{"ok" => true} = json_response(conn, 200)
  end

  test "a password can be reset through the emailed token" do
    register_and_verify()
    Mailer.Console.reset()

    json_post(build_conn(), "/api/auth/request-password-reset", %{
      "email" => @alice["email"]
    })

    token = token_from(Mailer.Console.latest(@alice["email"]).text, "/reset")

    conn =
      json_post(build_conn(), "/api/auth/reset-password", %{
        "token" => token,
        "password" => "brand-new-pass"
      })

    assert %{"ok" => true} = json_response(conn, 200)

    login =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "brand-new-pass"
      })

    assert %{"ok" => true} = json_response(login, 200)

    stale =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "harvest-please"
      })

    assert %{"ok" => false} = json_response(stale, 401)
  end

  test "reset-password rejects a short password and a reused token" do
    register_and_verify()
    Mailer.Console.reset()
    json_post(build_conn(), "/api/auth/request-password-reset", %{"email" => @alice["email"]})
    token = token_from(Mailer.Console.latest(@alice["email"]).text, "/reset")

    short =
      json_post(build_conn(), "/api/auth/reset-password", %{
        "token" => token,
        "password" => "short"
      })

    assert %{"ok" => false} = json_response(short, 400)

    assert %{"ok" => true} =
             json_post(build_conn(), "/api/auth/reset-password", %{
               "token" => token,
               "password" => "brand-new-pass"
             })
             |> json_response(200)

    assert %{"ok" => false} =
             json_post(build_conn(), "/api/auth/reset-password", %{
               "token" => token,
               "password" => "another-pass"
             })
             |> json_response(400)
  end

  test "the dev mailbox returns the captured verification link" do
    register()

    conn = get(build_conn(), "/api/auth/mailbox?to=#{@alice["email"]}")

    assert %{"ok" => true, "email" => %{"text" => text}} =
             json_response(conn, 200)

    assert text =~ "/verify"
  end

  test "the dev mailbox is empty for an address with no mail" do
    conn = get(build_conn(), "/api/auth/mailbox?to=nobody@example.test")
    assert %{"ok" => true, "email" => nil} = json_response(conn, 200)
  end

  test "unmatched /api routes return a JSON 404" do
    conn = get(build_conn(), "/api/auth/regiter")

    assert %{"ok" => false} = json_response(conn, 404)

    assert conn
           |> get_resp_header("content-type")
           |> List.first()
           |> String.contains?("application/json")
  end

  test "register, login, and me report the opening balance" do
    conn = register_and_verify()
    assert %{"user" => %{"balance" => 100}} = json_response(conn, 200)

    me = conn |> recycle() |> get("/api/auth/me")
    assert %{"user" => %{"balance" => 100}} = json_response(me, 200)

    login =
      json_post(build_conn(), "/api/auth/login", %{
        "username" => "Alice",
        "password" => "harvest-please"
      })

    assert %{"user" => %{"balance" => 100}} = json_response(login, 200)
  end

  test "balance transactions require a session" do
    conn = json_post(build_conn(), "/api/economy/transaction", %{"delta" => -10})
    assert %{"ok" => false} = json_response(conn, 401)
  end

  test "a regular account can spend but cannot grant itself wallet credits" do
    conn = register_and_verify() |> recycle()

    conn = json_post(conn, "/api/economy/transaction", %{"delta" => -25})
    assert %{"ok" => true, "balance" => 75} = json_response(conn, 200)

    conn = conn |> recycle() |> json_post("/api/economy/transaction", %{"delta" => 5})
    assert %{"ok" => false} = json_response(conn, 403)

    # The change belongs to the account, not the connection.
    me = conn |> recycle() |> get("/api/auth/me")
    assert %{"user" => %{"balance" => 75}} = json_response(me, 200)
  end

  test "balance transactions reject a non-integer delta" do
    conn = register_and_verify() |> recycle()
    conn = json_post(conn, "/api/economy/transaction", %{"delta" => "loot"})
    assert %{"ok" => false} = json_response(conn, 400)
  end

  test "slot spins settle once and reject reuse with a different wager" do
    conn = register_and_verify() |> recycle()
    params = %{"spin_id" => Ecto.UUID.generate(), "bet" => 5}
    conn = json_post(conn, "/api/casino/slots/spin", params)

    assert %{"reels" => [_, _, _], "payout" => payout, "balance" => balance} =
             result = json_response(conn, 200)

    assert balance == 95 + payout

    retry = conn |> recycle() |> json_post("/api/casino/slots/spin", params)
    assert json_response(retry, 200) == result

    conflict =
      retry |> recycle() |> json_post("/api/casino/slots/spin", %{params | "bet" => 10})

    assert %{"error" => _} = json_response(conflict, 409)

    assert %{"user" => %{"balance" => ^balance}} =
             conflict |> recycle() |> get("/api/auth/me") |> json_response(200)
  end

  test "roulette validates spots and replays the same settled spin" do
    conn = register_and_verify() |> recycle()
    path = "/api/casino/roulette/spin"
    spin_id = Ecto.UUID.generate()
    invalid = json_post(conn, path, %{"spin_id" => spin_id, "bets" => %{"n:999" => 5}})
    assert %{"error" => _} = json_response(invalid, 400)

    params = %{"spin_id" => spin_id, "bets" => %{"n:0" => 5}}
    spin = invalid |> recycle() |> json_post(path, params)
    result = json_response(spin, 200)
    assert %{"pocket" => pocket, "payout" => payout, "balance" => balance} = result
    assert payout == if(pocket == "0", do: 180, else: 0)
    assert balance == 95 + payout

    retry = spin |> recycle() |> json_post(path, params)
    assert json_response(retry, 200) == result
  end

  test "poker resumes the same hand and never posts the blind twice" do
    path = "/api/casino/poker"
    action = %{"action_id" => Ecto.UUID.generate(), "version" => 0, "move" => "deal"}
    conn = register_and_verify() |> recycle() |> json_post(path, action)
    result = json_response(conn, 200)
    assert %{"version" => 1, "balance" => 95, "hand" => hand} = result
    assert %{"phase" => "playerTurn", "pot" => 15, "dealerHidden" => true} = hand
    assert Enum.uniq(hand["dealerHole"]) |> length() == 1
    refute Map.has_key?(hand, "deck")

    retry = conn |> recycle() |> json_post(path, action)
    assert json_response(retry, 200) == result

    resumed = retry |> recycle() |> get(path)
    assert json_response(resumed, 200) == result

    stale = %{action | "action_id" => Ecto.UUID.generate(), "move" => "fold"}
    assert resumed |> recycle() |> json_post(path, stale) |> json_response(409)
  end

  test "unmatched /api routes return JSON even when html is requested" do
    conn =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> get("/api/auth/regiter")

    assert %{"ok" => false} = json_response(conn, 404)
  end

  defp token_from(text, marker) do
    line = text |> String.split("\n") |> Enum.find(&String.contains?(&1, marker))
    [_, token] = Regex.run(~r/token=([^\s&]+)/, line)
    URI.decode_www_form(token)
  end
end
