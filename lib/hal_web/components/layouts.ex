defmodule HalWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by the HAL dashboard.

  See the `layouts` directory for all templates.
  """
  use HalWeb, :html

  embed_templates "layouts/*"
end
