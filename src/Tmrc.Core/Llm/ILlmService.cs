using System.Collections.Generic;
using System.Threading.Tasks;

namespace Tmrc.Core.Llm;

public interface ILlmService
{
    Task<string> GenerateAnswerAsync(string context, string question);
    Task<IReadOnlyList<string>> GetAvailableModelsAsync();
}
