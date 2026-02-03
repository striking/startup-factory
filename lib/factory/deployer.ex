defmodule Factory.Deployer do
  @moduledoc """
  Deploys generated landing pages to Vercel.
  
  Uses Vercel's API to:
  1. Create a new project from our Next.js template
  2. Push the generated landing page code
  3. Trigger deployment
  4. Return the live URL
  
  All experiments deploy to subdomains: {experiment-id}.vercel.app
  """
  require Logger

  @vercel_api "https://api.vercel.com"
  @template_repo "startup-factory-template"  # Our base Next.js template

  @doc """
  Deploy a landing page to Vercel.
  
  Returns {:ok, url} or {:error, reason}
  """
  def deploy(experiment_id, landing_page_code, name) do
    with {:ok, token} <- get_token(),
         {:ok, project} <- create_or_get_project(token, experiment_id, name),
         {:ok, _} <- push_code(token, project, landing_page_code),
         {:ok, deployment} <- trigger_deployment(token, project) do
      
      url = deployment["url"] || "https://#{experiment_id}.vercel.app"
      Logger.info("[Deployer] Deployed #{experiment_id} to #{url}")
      {:ok, url}
    end
  end

  @doc """
  Update an existing deployment with new code.
  """
  def redeploy(experiment_id, new_code) do
    with {:ok, token} <- get_token(),
         {:ok, project} <- get_project(token, experiment_id),
         {:ok, _} <- push_code(token, project, new_code),
         {:ok, deployment} <- trigger_deployment(token, project) do
      
      url = deployment["url"]
      Logger.info("[Deployer] Redeployed #{experiment_id} to #{url}")
      {:ok, url}
    end
  end

  @doc """
  Delete a deployment (cleanup after experiment ends).
  """
  def cleanup(experiment_id) do
    with {:ok, token} <- get_token(),
         {:ok, _} <- delete_project(token, experiment_id) do
      Logger.info("[Deployer] Cleaned up #{experiment_id}")
      :ok
    end
  end

  @doc """
  Get deployment status and metrics.
  """
  def status(experiment_id) do
    with {:ok, token} <- get_token(),
         {:ok, project} <- get_project(token, experiment_id) do
      
      # Get recent deployments
      case request(:get, "/v9/projects/#{project["id"]}/deployments", token) do
        {:ok, %{"deployments" => deployments}} ->
          latest = List.first(deployments)
          {:ok, %{
            project_id: project["id"],
            name: project["name"],
            url: latest && latest["url"],
            state: latest && latest["state"],
            created_at: latest && latest["createdAt"]
          }}
        
        error -> error
      end
    end
  end

  # Private functions

  defp get_token do
    case System.get_env("VERCEL_TOKEN") do
      nil -> {:error, "VERCEL_TOKEN not configured"}
      token -> {:ok, token}
    end
  end

  defp create_or_get_project(token, experiment_id, name) do
    # First try to get existing project
    case get_project(token, experiment_id) do
      {:ok, project} -> {:ok, project}
      {:error, _} -> create_project(token, experiment_id, name)
    end
  end

  defp get_project(token, experiment_id) do
    case request(:get, "/v9/projects/sf-#{experiment_id}", token) do
      {:ok, project} -> {:ok, project}
      {:error, %{"error" => %{"code" => "not_found"}}} -> {:error, :not_found}
      error -> error
    end
  end

  defp create_project(token, experiment_id, name) do
    body = %{
      name: "sf-#{experiment_id}",
      framework: "nextjs",
      gitRepository: nil,  # We'll push directly, no git
      environmentVariables: [
        %{key: "NEXT_PUBLIC_EXPERIMENT_ID", value: experiment_id, target: ["production", "preview"]},
        %{key: "NEXT_PUBLIC_EXPERIMENT_NAME", value: name, target: ["production", "preview"]}
      ]
    }
    
    request(:post, "/v9/projects", token, body)
  end

  defp push_code(token, project, landing_page_code) do
    # For Vercel, we need to create a deployment with files
    # This creates the file structure inline
    
    files = [
      %{
        file: "app/page.tsx",
        data: Base.encode64(landing_page_code)
      },
      %{
        file: "app/layout.tsx",
        data: Base.encode64(layout_template())
      },
      %{
        file: "package.json",
        data: Base.encode64(package_json())
      },
      %{
        file: "tailwind.config.js", 
        data: Base.encode64(tailwind_config())
      },
      %{
        file: "app/globals.css",
        data: Base.encode64(global_css())
      },
      %{
        file: "next.config.js",
        data: Base.encode64("/** @type {import('next').NextConfig} */\nmodule.exports = { output: 'export' }")
      },
      %{
        file: "tsconfig.json",
        data: Base.encode64(tsconfig())
      }
    ]
    
    body = %{
      name: project["name"],
      files: files,
      projectSettings: %{
        framework: "nextjs"
      }
    }
    
    request(:post, "/v13/deployments", token, body)
  end

  defp trigger_deployment(token, project) do
    # In Vercel, pushing code auto-triggers deployment
    # Just return the deployment info
    case request(:get, "/v9/projects/#{project["id"]}/deployments?limit=1", token) do
      {:ok, %{"deployments" => [latest | _]}} -> {:ok, latest}
      {:ok, %{"deployments" => []}} -> {:error, "No deployments found"}
      error -> error
    end
  end

  defp delete_project(token, experiment_id) do
    request(:delete, "/v9/projects/sf-#{experiment_id}", token)
  end

  defp request(method, path, token, body \\ nil) do
    url = "#{@vercel_api}#{path}"
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]
    
    options = [recv_timeout: 30_000]
    
    result = case method do
      :get -> HTTPoison.get(url, headers, options)
      :post -> HTTPoison.post(url, Jason.encode!(body), headers, options)
      :delete -> HTTPoison.delete(url, headers, options)
    end
    
    case result do
      {:ok, %{status_code: code, body: resp_body}} when code in 200..299 ->
        Jason.decode(resp_body)
      
      {:ok, %{status_code: code, body: resp_body}} ->
        Logger.error("[Deployer] Vercel API error #{code}: #{resp_body}")
        case Jason.decode(resp_body) do
          {:ok, error} -> {:error, error}
          _ -> {:error, "HTTP #{code}"}
        end
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end

  # Templates

  defp layout_template do
    """
    import './globals.css'
    import type { Metadata } from 'next'
    import { Inter } from 'next/font/google'
    
    const inter = Inter({ subsets: ['latin'] })
    
    export const metadata: Metadata = {
      title: process.env.NEXT_PUBLIC_EXPERIMENT_NAME || 'Landing Page',
      description: 'Startup Factory Experiment',
    }
    
    export default function RootLayout({
      children,
    }: {
      children: React.ReactNode
    }) {
      return (
        <html lang="en">
          <body className={inter.className}>{children}</body>
        </html>
      )
    }
    """
  end

  defp package_json do
    """
    {
      "name": "startup-factory-landing",
      "version": "0.1.0",
      "private": true,
      "scripts": {
        "dev": "next dev",
        "build": "next build",
        "start": "next start"
      },
      "dependencies": {
        "next": "14.0.0",
        "react": "^18",
        "react-dom": "^18",
        "tailwindcss": "^3.3.0",
        "autoprefixer": "^10.0.1",
        "postcss": "^8",
        "@radix-ui/react-slot": "^1.0.2",
        "class-variance-authority": "^0.7.0",
        "clsx": "^2.0.0",
        "tailwind-merge": "^2.0.0",
        "lucide-react": "^0.294.0"
      },
      "devDependencies": {
        "typescript": "^5",
        "@types/node": "^20",
        "@types/react": "^18",
        "@types/react-dom": "^18"
      }
    }
    """
  end

  defp tailwind_config do
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
      plugins: [],
    }
    """
  end

  defp global_css do
    """
    @tailwind base;
    @tailwind components;
    @tailwind utilities;
    
    :root {
      --foreground-rgb: 0, 0, 0;
      --background-rgb: 255, 255, 255;
    }
    
    body {
      color: rgb(var(--foreground-rgb));
      background: rgb(var(--background-rgb));
    }
    """
  end

  defp tsconfig do
    """
    {
      "compilerOptions": {
        "target": "es5",
        "lib": ["dom", "dom.iterable", "esnext"],
        "allowJs": true,
        "skipLibCheck": true,
        "strict": true,
        "noEmit": true,
        "esModuleInterop": true,
        "module": "esnext",
        "moduleResolution": "bundler",
        "resolveJsonModule": true,
        "isolatedModules": true,
        "jsx": "preserve",
        "incremental": true,
        "plugins": [{ "name": "next" }],
        "paths": { "@/*": ["./*"] }
      },
      "include": ["next-env.d.ts", "**/*.ts", "**/*.tsx", ".next/types/**/*.ts"],
      "exclude": ["node_modules"]
    }
    """
  end
end
