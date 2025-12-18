using MultiConfigApp.Models;
using MultiConfigApp.Services;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container
builder.Services.AddControllers();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Configure AppConfiguration from appsettings and environment variables
builder.Services.Configure<AppConfiguration>(
    builder.Configuration.GetSection("AppConfiguration"));

// Register the appropriate service based on configuration
var appConfig = builder.Configuration
    .GetSection("AppConfiguration")
    .Get<AppConfiguration>() ?? new AppConfiguration();

// Dependency Injection based on ServiceType configuration
switch (appConfig.ServiceType?.ToLower())
{
    case "email":
        builder.Services.AddSingleton<IMessageService, EmailMessageService>();
        break;
    case "sms":
        builder.Services.AddSingleton<IMessageService, SmsMessageService>();
        break;
    default:
        builder.Services.AddSingleton<IMessageService, EmailMessageService>();
        break;
}

// Add health checks
builder.Services.AddHealthChecks();

var app = builder.Build();

// Configure the HTTP request pipeline
if (app.Environment.IsDevelopment() || app.Environment.EnvironmentName == "dev")
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.MapControllers();

// Health check endpoint
app.MapHealthChecks("/health");

// Simple root endpoint
app.MapGet("/", () => "Multi-Config App is running!");

app.Run();