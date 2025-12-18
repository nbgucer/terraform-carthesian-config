using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using MultiConfigApp.Models;
using MultiConfigApp.Services;

namespace MultiConfigApp.Controllers;

[ApiController]
[Route("api/[controller]")]
public class ConfigController : ControllerBase
{
    private readonly AppConfiguration _config;
    private readonly IMessageService _messageService;
    private readonly ILogger<ConfigController> _logger;

    public ConfigController(
        IOptions<AppConfiguration> config,
        IMessageService messageService,
        ILogger<ConfigController> logger)
    {
        _config = config.Value;
        _messageService = messageService;
        _logger = logger;
    }

    [HttpGet("info")]
    public IActionResult GetConfigInfo()
    {
        var info = new
        {
            Configuration = _config,
            InjectedService = new
            {
                Type = _messageService.GetServiceType(),
                Description = _messageService.GetServiceDescription()
            },
            Timestamp = DateTime.UtcNow,
            MachineName = Environment.MachineName,
            ProcessId = Environment.ProcessId
        };

        _logger.LogInformation(
            "Configuration requested - App: {AppName}, Env: {Environment}, Service: {ServiceType}",
            _config.AppDisplayName,
            _config.Environment,
            _messageService.GetServiceType());

        return Ok(info);
    }

    [HttpPost("send")]
    public async Task<IActionResult> SendMessage([FromBody] SendMessageRequest request)
    {
        if (string.IsNullOrEmpty(request.Recipient) || string.IsNullOrEmpty(request.Message))
        {
            return BadRequest("Recipient and Message are required");
        }

        try
        {
            var result = await _messageService.SendMessageAsync(request.Recipient, request.Message);
            
            return Ok(new
            {
                Success = true,
                Result = result,
                ServiceType = _messageService.GetServiceType(),
                AppName = _config.AppDisplayName,
                Environment = _config.Environment
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error sending message");
            return StatusCode(500, new { Success = false, Error = ex.Message });
        }
    }

    [HttpGet("features")]
    public IActionResult GetFeatureFlags()
    {
        var features = new
        {
            AlphaEnabled = _config.FeatureFlagAlpha,
            BetaEnabled = _config.FeatureFlagBeta,
            Environment = _config.Environment,
            AppName = _config.AppDisplayName
        };

        return Ok(features);
    }
}

public class SendMessageRequest
{
    public string Recipient { get; set; } = string.Empty;
    public string Message { get; set; } = string.Empty;
}