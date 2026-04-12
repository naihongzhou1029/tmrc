# 2026-04-12

## Feature: Semantic LLM Search (`tmrc query`)

### Task Overview
Implement a semantic search feature that uses LLMs (OpenAI, Gemini, Ollama) to answer natural language questions based on the recorded OCR text from the user's screen.

### Phase 1: Requirement Analysis & Planning
- **Design Goals**: Local-first, secure API key storage, automated interactive setup.
- **Architectural Decisions**:
  - Store provider/model configuration in `config.ini`.
  - Store sensitive API keys in Windows User Environment Variables (`TMRC_LLM_API_KEY`) to avoid plaintext exposure.
  - Implement an abstraction layer (`ILlmService`) with lightweight HTTP client providers.
  - Trigger interactive setup on the first run of `query` if configuration is missing.

### Phase 2: Implementation Details
- **Configuration**:
  - Updated `TmrcConfig` to include `LlmProvider` and `LlmModel`.
  - Added `SaveToFile` to `ConfigLoader` to persist user choices from the interactive setup.
- **LLM Services**:
  - Created `ILlmService` with `GenerateAnswerAsync` and `GetAvailableModelsAsync`.
  - Implemented `OpenAiService`, `GeminiService`, and `OllamaService` using `HttpClient`.
- **CLI Commands**:
  - Implemented `QueryCommand` to handle argument parsing, interactive setup (including fetching available models from the provider), and query execution.
  - Integrated `query` into the main `Program.cs` switch.

### Phase 3: Testing & Debugging
- **Unit Tests**: Added `LlmConfigOverride` and `SaveAndLoadConfig` to `ConfigTests.cs`.
- **Debugging**: Ensured `QueryCommand` correctly fetches the last 24h of OCR text by default and orders them chronologically to build a coherent context for the LLM.
- **Linting**: Applied `dotnet-format` to the solution.

### Phase 4: Finalization
- **Documentation**: Updated `README.md`, `GEMINI.md`, `specs/building_progress.md`, `specs/spec.md`, and `specs/test.md`.
- **Verification**: Verified build success and test pass status.

### Insights & Observations
- Using User Environment Variables for API keys is a robust and standard way to keep secrets out of the application folder while still allowing programmatic setup.
- Fetching available models directly from the LLM provider API improves the UX significantly during initial configuration.
- The event-based segmentation model and OCR indexing provided a solid foundation for building the LLM context.
