namespace MultiConfigApp.Services;

public class EmailMessageService : IMessageService
{
    private readonly ILogger<EmailMessageService> _logger;

    public EmailMessageService(ILogger<EmailMessageService> logger)
    {
        _logger = logger;
    }

    public string GetServiceType()
    {
        return "Email";
    }

    public string GetServiceDescription()
    {
        return "Email Message Service - Sends messages via email protocol";
    }

    public async Task<string> SendMessageAsync(string recipient, string message)
    {
        _logger.LogInformation("Sending email to {Recipient}", recipient);
        
        // Simulate async email sending
        await Task.Delay(100);
        
        var result = $"Email sent to {recipient}: {message}";
        _logger.LogInformation("Email sent successfully");
        
        return result;
    }
}