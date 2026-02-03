defmodule Factory.V0Client do
  @moduledoc """
  Client for v0.dev API to generate Next.js landing pages.
  
  v0 generates React/Next.js components from natural language prompts.
  We use it to rapidly create landing pages for experiment validation.
  """
  require Logger

  @base_url "https://api.v0.dev/v1"
  @timeout_ms 120_000  # 2 minutes - v0 can be slow
  @model "v0-1.0-md"

  @doc """
  Generate a landing page from a prompt.
  
  Returns {:ok, %{code: string, preview_url: string}} or {:error, reason}
  
  ## Example
  
      Factory.V0Client.generate(
        "Create a landing page for an AI-powered invoice tool for plumbers. 
         Include hero section, 3 benefits, pricing, and email capture form.",
        style: :modern,
        framework: :nextjs
      )
  """
  def generate(prompt, opts \\ []) do
    api_key = get_api_key()
    
    if is_nil(api_key) do
      {:error, "V0_API_KEY not configured"}
    else
      style = Keyword.get(opts, :style, :modern)
      
      enhanced_prompt = """
      #{prompt}
      
      Requirements:
      - Use shadcn/ui components
      - Mobile responsive
      - Include a clear CTA with email capture
      - Style: #{style}
      - Export as a single page component
      """
      
      body = %{
        model: @model,
        messages: [
          %{role: "user", content: enhanced_prompt}
        ]
      }
      
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]
      
      Logger.info("[V0Client] Generating landing page...")
      
      case HTTPoison.post("#{@base_url}/chat/completions", Jason.encode!(body), headers, recv_timeout: @timeout_ms) do
        {:ok, %{status_code: 200, body: response_body}} ->
          parse_response(response_body)
        
        {:ok, %{status_code: status, body: body}} ->
          Logger.error("[V0Client] API error #{status}: #{body}")
          {:error, "v0 API error: #{status}"}
        
        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("[V0Client] Request failed: #{inspect(reason)}")
          {:error, "Request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Iterate on existing code with a refinement prompt.
  """
  def iterate(existing_code, refinement_prompt, opts \\ []) do
    full_prompt = """
    Here's my existing landing page code:
    
    ```tsx
    #{existing_code}
    ```
    
    Please modify it with these changes:
    #{refinement_prompt}
    
    Return the complete updated code.
    """
    
    generate(full_prompt, opts)
  end

  @doc """
  Generate multiple variations for A/B testing.
  """
  def generate_variations(base_prompt, count \\ 3) do
    variations = [
      {"minimal", "Use minimal design with lots of whitespace, single CTA"},
      {"social_proof", "Emphasize social proof, testimonials, trust badges"},
      {"urgency", "Add urgency elements, limited time offer, countdown"},
      {"benefit_focused", "Lead with benefits, problem-solution format"},
      {"story", "Tell a story, narrative approach, emotional appeal"}
    ]
    
    selected = Enum.take_random(variations, count)
    
    results = Enum.map(selected, fn {name, modifier} ->
      prompt = "#{base_prompt}\n\nStyle modifier: #{modifier}"
      
      case generate(prompt) do
        {:ok, result} -> {:ok, Map.put(result, :variant, name)}
        error -> error
      end
    end)
    
    successes = Enum.filter(results, &match?({:ok, _}, &1)) |> Enum.map(&elem(&1, 1))
    
    if length(successes) > 0 do
      {:ok, successes}
    else
      {:error, "All variations failed to generate"}
    end
  end

  @doc """
  Extract components from v0 response for deployment.
  """
  def extract_deployable(v0_response) do
    # v0 returns code in markdown blocks, extract the TSX
    code = v0_response.code
    
    # Ensure it has necessary Next.js structure
    %{
      page_tsx: ensure_page_wrapper(code),
      dependencies: extract_dependencies(code),
      tailwind_config: generate_tailwind_config()
    }
  end

  # Private functions

  defp get_api_key do
    System.get_env("V0_API_KEY")
  end

  defp parse_response(body) do
    case Jason.decode(body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        # Extract code from markdown blocks
        code = extract_code_block(content)
        {:ok, %{code: code, raw_response: content}}
      
      {:ok, data} ->
        Logger.warning("[V0Client] Unexpected response format: #{inspect(data)}")
        {:error, "Unexpected response format"}
      
      {:error, reason} ->
        {:error, "Failed to parse response: #{inspect(reason)}"}
    end
  end

  defp extract_code_block(content) do
    # Match ```tsx or ```jsx or ``` code blocks
    regex = ~r/```(?:tsx|jsx|typescript|javascript)?\n([\s\S]*?)```/
    
    case Regex.run(regex, content) do
      [_, code] -> String.trim(code)
      nil -> content  # Return raw if no code block found
    end
  end

  defp ensure_page_wrapper(code) do
    # Ensure the code is a valid Next.js page
    if String.contains?(code, "export default") do
      code
    else
      """
      import React from 'react'
      
      #{code}
      
      export default function LandingPage() {
        return <Component />
      }
      """
    end
  end

  defp extract_dependencies(code) do
    # Common shadcn/ui dependencies
    base_deps = [
      "@radix-ui/react-slot",
      "class-variance-authority",
      "clsx",
      "tailwind-merge",
      "lucide-react"
    ]
    
    # Check for specific components used
    additional = []
    
    additional = if String.contains?(code, "Button"), do: ["@radix-ui/react-slot" | additional], else: additional
    additional = if String.contains?(code, "Input"), do: additional, else: additional
    additional = if String.contains?(code, "Dialog"), do: ["@radix-ui/react-dialog" | additional], else: additional
    additional = if String.contains?(code, "Accordion"), do: ["@radix-ui/react-accordion" | additional], else: additional
    
    Enum.uniq(base_deps ++ additional)
  end

  defp generate_tailwind_config do
    """
    /** @type {import('tailwindcss').Config} */
    module.exports = {
      darkMode: ["class"],
      content: [
        './pages/**/*.{ts,tsx}',
        './components/**/*.{ts,tsx}',
        './app/**/*.{ts,tsx}',
      ],
      theme: {
        extend: {},
      },
      plugins: [require("tailwindcss-animate")],
    }
    """
  end
end
