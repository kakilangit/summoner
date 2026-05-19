Mox.defmock(Summoner.Ports.HTTPClientMock, for: Summoner.Ports.HTTPClient)
Mox.defmock(Summoner.Services.InferenceAdapterMock, for: Arcanum.Provider)
Mox.defmock(Summoner.ToolExecutorMock, for: Summoner.Services.Orchestration.ToolExecutor)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Summoner.Repo, :manual)
