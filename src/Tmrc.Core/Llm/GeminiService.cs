using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Linq;

namespace Tmrc.Core.Llm;

public class GeminiService : ILlmService
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly string _model;

    public GeminiService(string apiKey, string model = "gemini-1.5-pro")
    {
        _http = new HttpClient();
        _apiKey = apiKey;
        _model = model;
    }

    public async Task<string> GenerateAnswerAsync(string context, string question)
    {
        var request = new
        {
            contents = new[]
            {
                new { role = "user", parts = new[] { new { text = $"You are a helpful assistant. Answer the user question based on the provided context (OCR text from their screen).\n\nContext:\n{context}\n\nQuestion: {question}" } } }
            }
        };

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/{_model}:generateContent?key={_apiKey}";
        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, url);
        httpRequest.Content = new StringContent(JsonSerializer.Serialize(request), Encoding.UTF8, "application/json");

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.GetProperty("candidates")[0].GetProperty("content").GetProperty("parts")[0].GetProperty("text").GetString() ?? string.Empty;
    }

    public async Task<IReadOnlyList<string>> GetAvailableModelsAsync()
    {
        var url = $"https://generativelanguage.googleapis.com/v1beta/models?key={_apiKey}";
        using var httpRequest = new HttpRequestMessage(HttpMethod.Get, url);

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        var models = new List<string>();
        foreach (var m in doc.RootElement.GetProperty("models").EnumerateArray())
        {
            var name = m.GetProperty("name").GetString() ?? string.Empty;
            if (name.StartsWith("models/"))
                name = name["models/".Length..];
            models.Add(name);
        }
        return models.Where(m => m.Contains("gemini")).OrderBy(m => m).ToList();
    }
}
