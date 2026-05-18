Mox.defmock(Summoner.HTTPClientMock, for: Summoner.HTTPClient)
Mox.defmock(Summoner.InferenceAdapterMock, for: Arcanum.Provider)
Mox.defmock(Summoner.ToolExecutorMock, for: Summoner.Orchestration.ToolExecutor)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Summoner.Repo, :manual)
