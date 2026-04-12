using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Linq;

namespace Tmrc.Core.Llm;

public class OllamaService : ILlmService
{
    private readonly HttpClient _http;
    private readonly string _endpoint;
    private readonly string _model;

    public OllamaService(string endpoint = "http://localhost:11434", string model = "llama3")
    {
        _http = new HttpClient();
        _endpoint = endpoint.TrimEnd('/');
        _model = model;
    }

    public async Task<string> GenerateAnswerAsync(string context, string question)
    {
        var request = new
        {
            model = _model,
            prompt = $"You are a helpful assistant. Answer the user question based on the provided context (OCR text from their screen).\n\nContext:\n{context}\n\nQuestion: {question}",
            stream = false
        };

        var url = $"{_endpoint}/api/generate";
        using var httpRequest = new HttpRequestMessage(HttpMethod.Post, url);
        httpRequest.Content = new StringContent(JsonSerializer.Serialize(request), Encoding.UTF8, "application/json");

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        return doc.RootElement.GetProperty("response").GetString() ?? string.Empty;
    }

    public async Task<IReadOnlyList<string>> GetAvailableModelsAsync()
    {
        var url = $"{_endpoint}/api/tags";
        using var httpRequest = new HttpRequestMessage(HttpMethod.Get, url);

        var response = await _http.SendAsync(httpRequest);
        response.EnsureSuccessStatusCode();

        var body = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(body);
        var models = new List<string>();
        foreach (var m in doc.RootElement.GetProperty("models").EnumerateArray())
        {
            models.Add(m.GetProperty("name").GetString() ?? string.Empty);
        }
        return models.OrderBy(m => m).ToList();
    }
}
