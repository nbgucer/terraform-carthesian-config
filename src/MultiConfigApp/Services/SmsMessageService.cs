namespace MultiConfigApp.Services;

public class SmsMessageService : IMessageService
{
    private readonly ILogger<SmsMessageService> _logger;

    public SmsMessageService(ILogger<SmsMessageService> logger)
    {
        _logger = logger;
    }

    public string GetServiceType()
    {
        return "SMS";
    }

    public string GetServiceDescription()
    {
        return "SMS Message Service - Sends messages via SMS protocol";
    }

    public async Task<string> SendMessageAsync(string recipient, string message)
    {
        _logger.LogInformation("Sending SMS to {Recipient}", recipient);
        
        // Simulate async SMS sending
        await Task.Delay(50);
        
        var result = $"SMS sent to {recipient}: {message}";
        _logger.LogInformation("SMS sent successfully");
        
        return result;
    }
}