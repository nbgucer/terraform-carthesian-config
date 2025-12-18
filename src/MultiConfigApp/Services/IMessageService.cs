namespace MultiConfigApp.Services;

public interface IMessageService
{
    string GetServiceType();
    Task<string> SendMessageAsync(string recipient, string message);
    string GetServiceDescription();
}