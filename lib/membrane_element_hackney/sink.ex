defmodule Membrane.Element.Hackney.Sink do
  @moduledoc """
  An element uploading data over HTTP(S) based on Hackney
  """
  use Membrane.Element.Base.Sink
  use Membrane.Log, tags: :membrane_hackney_sink
  alias Membrane.{Buffer, Event}

  def_input_pad :input, caps: :any, demand_unit: :bytes

  def_options location: [
                type: :string,
                description: """
                The URL of a request
                """
              ],
              method: [
                type: :atom,
                spec: :post | :put | :patch,
                description: "HTTP method that will be used when making a request",
                default: :post
              ],
              headers: [
                type: :keyword,
                description:
                  "List of additional request headers in format accepted by `:hackney.request/5`",
                default: []
              ],
              hackney_opts: [
                type: :keyword,
                description:
                  "Additional options for Hackney in format accepted by `:hackney.request/5`",
                default: []
              ]

  @chunk_size 1024

  @impl true
  def handle_init(opts) do
    state = opts |> Map.from_struct() |> Map.merge(%{conn_ref: nil})
    {:ok, state}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {:ok, conn_ref} =
      :hackney.request(state.method, state.location, state.headers, :stream, state.hackney_opts)

    {{:ok, demand: {:input, @chunk_size}}, %{state | conn_ref: conn_ref}}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    :hackney.close(state.conn_ref)

    {:ok, %{state | conn_ref: nil}}
  end

  @impl true
  def handle_write(:input, %Buffer{payload: payload}, _ctx, state) do
    :hackney.send_body(state.conn_ref, payload)
    {{:ok, demand: {:input, @chunk_size}}, state}
  end

  @impl true
  def handle_event(:input, %Event.EndOfStream{}, _ctx, %{conn_ref: conn_ref} = state) do
    {:ok, status, headers, conn_ref} = :hackney.start_response(conn_ref)
    {:ok, body} = :hackney.body(conn_ref)

    response_notification = {:http_response, status, headers, body}
    {{:ok, notify: response_notification, notify: {:end_of_stream, :input}}, state}
  end

  @impl true
  def handle_event(pad, event, ctx, state) do
    super(pad, event, ctx, state)
  end
end