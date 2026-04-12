using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using Tmrc.Core.Config;
using Tmrc.Core.Indexing;
using Tmrc.Core.Llm;
using Tmrc.Core.Recall;
using Tmrc.Core.Storage;

namespace Tmrc.Cli.Query;

public static class QueryCommand
{
    private const string ApiKeyEnvVar = "TMRC_LLM_API_KEY";

    public static int Execute(string[] args)
    {
        var configPath = Path.Combine(Directory.GetCurrentDirectory(), "config.ini");
        var cfg = ConfigLoader.LoadFromFile(configPath);

        // Parse arguments for query and time range
        string? sinceExpr = null;
        string? untilExpr = null;
        var queryParts = new List<string>();

        for (var i = 0; i < args.Length; i++)
        {
            var a = args[i];
            if (a == "--since" && i + 1 < args.Length)
            {
                sinceExpr = args[++i];
            }
            else if (a == "--until" && i + 1 < args.Length)
            {
                untilExpr = args[++i];
            }
            else
            {
                queryParts.Add(a);
            }
        }

        var userQuery = string.Join(" ", queryParts).Trim();
        if (string.IsNullOrWhiteSpace(userQuery))
        {
            Console.Error.WriteLine("Usage: tmrc query \"your question\" [--since <expr>] [--until <expr>]");
            return 1;
        }

        // Check if setup is needed
        var apiKey = Environment.GetEnvironmentVariable(ApiKeyEnvVar, EnvironmentVariableTarget.User);
        if (string.IsNullOrEmpty(cfg.LlmProvider) || string.IsNullOrEmpty(cfg.LlmModel) || (cfg.LlmProvider != "ollama" && string.IsNullOrEmpty(apiKey)))
        {
            cfg = RunSetup(cfg, configPath).GetAwaiter().GetResult();
            apiKey = Environment.GetEnvironmentVariable(ApiKeyEnvVar, EnvironmentVariableTarget.User);
        }

        ILlmService? llm = null;
        try
        {
            llm = cfg.LlmProvider switch
            {
                "openai" => new OpenAiService(apiKey!, cfg.LlmModel!),
                "gemini" => new GeminiService(apiKey!, cfg.LlmModel!),
                "ollama" => new OllamaService(model: cfg.LlmModel!),
                _ => null
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error initializing LLM: {ex.Message}");
            return 1;
        }

        if (llm == null)
        {
            Console.Error.WriteLine($"Unsupported provider: {cfg.LlmProvider}");
            return 1;
        }

        // Fetch context
        var storage = new StorageManager(cfg.StorageRoot);
        var indexPath = storage.IndexPath(cfg.Session);
        if (!File.Exists(indexPath))
        {
            Console.WriteLine("No index found; nothing to query.");
            return 0;
        }

        var now = DateTimeOffset.Now;
        DateTimeOffset from;
        DateTimeOffset to;

        if (sinceExpr is not null || untilExpr is not null)
        {
            var fromExpr = sinceExpr ?? "1d ago";
            var toExpr = untilExpr ?? "now";
            try
            {
                var range = TimeRangeParser.ParseRelative(fromExpr, toExpr, now);
                from = range.From;
                to = range.To;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Failed to parse time range: {ex.Message}");
                return 1;
            }
        }
        else
        {
            // Default: last 24h.
            to = now;
            from = now.AddHours(-24);
        }

        var store = new IndexStore(indexPath);
        var rows = store.QueryByTimeRange(from, to);
        if (rows.Count == 0)
        {
            Console.WriteLine("No recordings found in the requested time range.");
            return 0;
        }

        var contextBuilder = new System.Text.StringBuilder();
        foreach (var row in rows.OrderBy(r => r.Start))
        {
            if (!string.IsNullOrWhiteSpace(row.OcrText))
            {
                contextBuilder.AppendLine($"[{row.Start:HH:mm:ss}] {row.OcrText}");
            }
        }

        var context = contextBuilder.ToString();
        if (string.IsNullOrWhiteSpace(context))
        {
            Console.WriteLine("No text content found in the recordings for the given range.");
            return 0;
        }

        Console.WriteLine("Thinking...");
        try
        {
            var answer = llm.GenerateAnswerAsync(context, userQuery).GetAwaiter().GetResult();
            Console.WriteLine();
            Console.WriteLine(answer);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Error during query: {ex.Message}");
            return 1;
        }

        return 0;
    }

    private static async Task<TmrcConfig> RunSetup(TmrcConfig cfg, string configPath)
    {
        Console.WriteLine("=== tmrc LLM Setup ===");
        Console.WriteLine("Choose provider:");
        Console.WriteLine("1. OpenAI");
        Console.WriteLine("2. Gemini");
        Console.WriteLine("3. Ollama");
        Console.Write("Selection [1-3]: ");
        var choice = Console.ReadLine();

        var provider = choice switch
        {
            "1" => "openai",
            "2" => "gemini",
            "3" => "ollama",
            _ => "openai"
        };

        string? apiKey = null;
        if (provider != "ollama")
        {
            Console.Write($"Enter {provider} API Key: ");
            apiKey = ReadPassword();
            Environment.SetEnvironmentVariable(ApiKeyEnvVar, apiKey, EnvironmentVariableTarget.User);
            Console.WriteLine("\nAPI Key saved to User Environment Variables.");
        }

        Console.WriteLine("Fetching available models...");
        ILlmService tempLlm = provider switch
        {
            "openai" => new OpenAiService(apiKey!),
            "gemini" => new GeminiService(apiKey!),
            "ollama" => new OllamaService(),
            _ => throw new Exception("Invalid provider")
        };

        try
        {
            var models = await tempLlm.GetAvailableModelsAsync();
            if (models.Count == 0)
            {
                throw new Exception("No models found.");
            }

            Console.WriteLine("Select model:");
            for (int i = 0; i < models.Count; i++)
            {
                Console.WriteLine($"{i + 1}. {models[i]}");
            }
            Console.Write($"Selection [1-{models.Count}]: ");
            var modelChoiceStr = Console.ReadLine();
            if (int.TryParse(modelChoiceStr, out var modelIndex) && modelIndex > 0 && modelIndex <= models.Count)
            {
                cfg = cfg with { LlmProvider = provider, LlmModel = models[modelIndex - 1] };
            }
            else
            {
                cfg = cfg with { LlmProvider = provider, LlmModel = models[0] };
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Could not fetch models: {ex.Message}");
            Console.Write("Enter model name manually: ");
            var manualModel = Console.ReadLine();
            cfg = cfg with { LlmProvider = provider, LlmModel = string.IsNullOrWhiteSpace(manualModel) ? (provider == "ollama" ? "llama3" : (provider == "openai" ? "gpt-4o" : "gemini-1.5-pro")) : manualModel };
        }

        ConfigLoader.SaveToFile(cfg, configPath);
        Console.WriteLine("Configuration saved to config.ini.");
        return cfg;
    }

    private static string ReadPassword()
    {
        var pass = new System.Text.StringBuilder();
        while (true)
        {
            var key = Console.ReadKey(true);
            if (key.Key == ConsoleKey.Enter) break;
            if (key.Key == ConsoleKey.Backspace && pass.Length > 0) pass.Length--;
            else if (key.KeyChar != '\0') pass.Append(key.KeyChar);
        }
        return pass.ToString();
    }
}
