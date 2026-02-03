defmodule HalWeb.SettingsLive do
  @moduledoc """
  Settings page for managing HAL integrations.

  Allows users to:
  - Connect/disconnect Google (Gmail + Calendar)
  - View connection status
  - Manage notification preferences
  """

  use HalWeb, :live_view
  require Logger

  alias HAL.Credentials
  alias Hal.Notifications.Proactive

  @impl true
  def mount(_params, session, socket) do
    user_id = get_user_id(session)

    # Check local credentials status
    google_connected = Credentials.exists?(:google)

    # Load notification preferences
    {:ok, notif_prefs} = Proactive.get_preferences(user_id)

    socket =
      socket
      |> assign(:user_id, user_id)
      |> assign(:google_connected, google_connected)
      |> assign(:notif_prefs, notif_prefs)
      |> assign(:page_title, "Settings")

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_" <> pref_name, _params, socket) do
    user_id = socket.assigns.user_id
    prefs = socket.assigns.notif_prefs

    # Convert to atom and toggle
    field = String.to_existing_atom(pref_name)
    current_value = Map.get(prefs, field)

    case Proactive.update_preferences(user_id, %{field => !current_value}) do
      {:ok, updated_prefs} ->
        {:noreply, assign(socket, :notif_prefs, updated_prefs)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to update preference")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 py-8">
      <div class="max-w-3xl mx-auto px-4">
        <!-- Header -->
        <div class="mb-8">
          <div class="flex items-center space-x-4 mb-4">
            <.link navigate={~p"/"} class="text-gray-600 hover:text-gray-900">
              ← Back
            </.link>
            <h1 class="text-2xl font-bold text-gray-900">Settings</h1>
          </div>
          <p class="text-gray-600">Manage your HAL integrations and preferences.</p>
        </div>

        <!-- Integrations Section -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Connected Services</h2>
            <p class="text-sm text-gray-500 mt-1">
              Connect external services to unlock HAL's full capabilities.
            </p>
          </div>

          <!-- Google Integration -->
          <div class="px-6 py-5">
            <div class="flex items-center justify-between">
              <div class="flex items-center space-x-4">
                <div class="w-12 h-12 bg-white rounded-lg border border-gray-200 flex items-center justify-center">
                  <svg class="w-6 h-6" viewBox="0 0 24 24">
                    <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"/>
                    <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"/>
                    <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"/>
                    <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"/>
                  </svg>
                </div>
                <div>
                  <h3 class="font-medium text-gray-900">Google</h3>
                  <p class="text-sm text-gray-500">Gmail and Google Calendar access</p>
                </div>
              </div>

              <div class="flex items-center space-x-3">
                <%= if @google_connected do %>
                  <span class="flex items-center text-sm text-green-600">
                    <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clip-rule="evenodd"/>
                    </svg>
                    Configured
                  </span>
                <% else %>
                  <span class="flex items-center text-sm text-amber-600">
                    <svg class="w-4 h-4 mr-1" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd"/>
                    </svg>
                    Not configured
                  </span>
                <% end %>
              </div>
            </div>

            <%= if @google_connected do %>
              <div class="mt-4 p-4 bg-green-50 rounded-lg">
                <h4 class="text-sm font-medium text-green-800 mb-2">Enabled Features</h4>
                <ul class="text-sm text-green-700 space-y-1">
                  <li class="flex items-center">
                    <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    Read and search emails
                  </li>
                  <li class="flex items-center">
                    <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    Send emails on your behalf
                  </li>
                  <li class="flex items-center">
                    <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    View calendar events
                  </li>
                  <li class="flex items-center">
                    <svg class="w-4 h-4 mr-2" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd"/>
                    </svg>
                    Create and manage calendar events
                  </li>
                </ul>
              </div>
            <% else %>
              <div class="mt-4 p-4 bg-amber-50 rounded-lg">
                <h4 class="text-sm font-medium text-amber-800 mb-2">Setup Required</h4>
                <p class="text-sm text-amber-700 mb-2">
                  Add your Google credentials to enable Gmail and Calendar features:
                </p>
                <code class="block text-xs bg-amber-100 p-2 rounded font-mono text-amber-800">
                  ~/.hal/credentials/google.json
                </code>
                <p class="text-xs text-amber-600 mt-2">
                  See ~/.hal/credentials/README.md for setup instructions.
                </p>
              </div>
            <% end %>
          </div>
        </div>

        <!-- Notification Preferences Section -->
        <div class="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden mt-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900">Proactive Notifications</h2>
            <p class="text-sm text-gray-500 mt-1">
              Configure when HAL should proactively notify you.
            </p>
          </div>

          <div class="divide-y divide-gray-100">
            <!-- Calendar Reminders -->
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 class="font-medium text-gray-900">📅 Calendar Reminders</h3>
                <p class="text-sm text-gray-500">Get notified before meetings start</p>
              </div>
              <button
                phx-click="toggle_calendar_reminders"
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 #{if @notif_prefs.calendar_reminders, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @notif_prefs.calendar_reminders, do: "translate-x-5", else: "translate-x-0"}"} />
              </button>
            </div>

            <!-- Email Alerts -->
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 class="font-medium text-gray-900">📧 Urgent Email Alerts</h3>
                <p class="text-sm text-gray-500">Get notified about urgent emails</p>
              </div>
              <button
                phx-click="toggle_email_alerts"
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 #{if @notif_prefs.email_alerts, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @notif_prefs.email_alerts, do: "translate-x-5", else: "translate-x-0"}"} />
              </button>
            </div>

            <!-- Task Reminders -->
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 class="font-medium text-gray-900">✅ Task Reminders</h3>
                <p class="text-sm text-gray-500">Get reminded about tasks due today</p>
              </div>
              <button
                phx-click="toggle_task_reminders"
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 #{if @notif_prefs.task_reminders, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @notif_prefs.task_reminders, do: "translate-x-5", else: "translate-x-0"}"} />
              </button>
            </div>

            <!-- Quiet Hours -->
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 class="font-medium text-gray-900">🌙 Quiet Hours</h3>
                <p class="text-sm text-gray-500">Suppress notifications during sleep (10 PM - 8 AM)</p>
              </div>
              <button
                phx-click="toggle_quiet_hours_enabled"
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 #{if @notif_prefs.quiet_hours_enabled, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @notif_prefs.quiet_hours_enabled, do: "translate-x-5", else: "translate-x-0"}"} />
              </button>
            </div>

            <!-- Daily Summary -->
            <div class="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 class="font-medium text-gray-900">📋 Daily Summary</h3>
                <p class="text-sm text-gray-500">Receive a morning briefing at 9 AM</p>
              </div>
              <button
                phx-click="toggle_daily_summary"
                class={"relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 #{if @notif_prefs.daily_summary, do: "bg-blue-600", else: "bg-gray-200"}"}
              >
                <span class={"pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out #{if @notif_prefs.daily_summary, do: "translate-x-5", else: "translate-x-0"}"} />
              </button>
            </div>
          </div>
        </div>

        <!-- Privacy Note -->
        <div class="mt-6 p-4 bg-blue-50 rounded-lg">
          <div class="flex">
            <svg class="w-5 h-5 text-blue-500 mr-3 mt-0.5" fill="currentColor" viewBox="0 0 20 20">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clip-rule="evenodd"/>
            </svg>
            <div>
              <h4 class="text-sm font-medium text-blue-800">Privacy Note</h4>
              <p class="text-sm text-blue-700 mt-1">
                Your credentials are stored locally at ~/.hal/credentials/.
                HAL only accesses your data when you ask it to. Delete the
                credential file to revoke access.
              </p>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Get user ID from session (same logic as other LiveViews)
  defp get_user_id(session) do
    case session["oauth_user_id"] do
      nil -> get_or_create_web_user()
      user_id -> user_id
    end
  end

  defp get_or_create_web_user do
    case Hal.Repo.get_by(Hal.Accounts.User, external_id: "web-chat-user", platform: "terminal") do
      nil ->
        {:ok, user} =
          %Hal.Accounts.User{}
          |> Hal.Accounts.User.changeset(%{
            external_id: "web-chat-user",
            platform: "terminal",
            username: "Web User",
            role: "owner"
          })
          |> Hal.Repo.insert()

        user.id

      user ->
        user.id
    end
  end
end
