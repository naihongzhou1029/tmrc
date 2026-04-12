using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Linq;

namespace Tmrc.Core.Llm;

public class OpenAiService : ILlmService
{
    private readonly HttpClient _http;
    private readonly string _apiKey;
    private readonly string _model;

    public OpenAiService(string apiKey, string model = "gpt-4o")
    {
        _http = new HttpClient();
        _apiKey = apiKey;
        _model = model;
    }

    public async Task<string> GenerateAnswerAsync(string context, string question)
    {
        var request = new
        {
            model = _model,
            messages = new[]
            {
                new { role = "system", content = "You are a helpful assistant. Answer the user question based on the provided context (OCR text from their screen)." },
                new { role = "user", content = $"Context:\n{context}\n\nQuestion: {question}" }
            }
        };

        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, "https://api.openai.com/v1/chat/completions");
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);
        httpRequest.Content = new StringContent(JsonSerializer.Serialize(request), Encoding.UTF8, "application/json");

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString() ?? string.Empty;
    }

    public async Task<IReadOnlyList<string>> GetAvailableModelsAsync()
    {
        using var httpRequest = new HttpRequestMessage(HttpMethod.Get, "https://api.openai.com/v1/models");
        httpRequest.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _apiKey);

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        var models = new List<string>();
        foreach (var m in doc.RootElement.GetProperty("data").EnumerateArray())
        {
            models.Add(m.GetProperty("id").GetString() ?? string.Empty);
        }
        return models.Where(m => m.Contains("gpt")).OrderBy(m => m).ToList();
    }
}
