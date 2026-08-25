FROM mcr.microsoft.com/dotnet/sdk:9.0 AS build
WORKDIR /src
COPY src/Ikun.Telemetry.Api/Ikun.Telemetry.Api.csproj src/Ikun.Telemetry.Api/
RUN dotnet restore src/Ikun.Telemetry.Api/Ikun.Telemetry.Api.csproj
COPY src/Ikun.Telemetry.Api/ src/Ikun.Telemetry.Api/
RUN dotnet publish src/Ikun.Telemetry.Api/Ikun.Telemetry.Api.csproj -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:9.0 AS runtime
WORKDIR /app
RUN addgroup --system --gid 10001 ikun && adduser --system --uid 10001 --ingroup ikun ikun
COPY --from=build /out/ ./
USER ikun
ENV ASPNETCORE_ENVIRONMENT=Production
ENV ASPNETCORE_URLS=http://127.0.0.1:5080
ENV IKUN_TELEMETRY_BIND_ADDRESS=0.0.0.0
EXPOSE 5080
ENTRYPOINT ["dotnet", "Ikun.Telemetry.Api.dll"]

# Runtime secrets are injected by the orchestrator, never baked into this image.
# Program.cs binds the API to localhost:5080 inside the host namespace.
# Do not run privileged or mount a Docker socket.
