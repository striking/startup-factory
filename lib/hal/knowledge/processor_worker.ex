defmodule Hal.Knowledge.ProcessorWorker do
  @moduledoc """
  Oban worker for processing documents in the background.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3

  alias Hal.Knowledge.Processor

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"document_id" => document_id}}) do
    case Processor.process(document_id) do
      {:ok, _doc} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
