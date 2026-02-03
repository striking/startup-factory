defmodule HAL.Scheduler do
  @moduledoc """
  Quantum scheduler for periodic tasks.

  This scheduler handles time-based agent wake-ups and evaluations.
  Configuration is defined in config/config.exs.
  """
  use Quantum, otp_app: :hal
end
