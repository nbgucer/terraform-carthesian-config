namespace MultiConfigApp.Models;

public class AppConfiguration
{
    public string ServiceType { get; set; } = "Email";
    public string AppDisplayName { get; set; } = "Default App";
    public string Environment { get; set; } = "dev";
    public bool FeatureFlagAlpha { get; set; } = false;
    public bool FeatureFlagBeta { get; set; } = false;
    public int ApiTimeoutSeconds { get; set; } = 30;
    public int MaxRetryCount { get; set; } = 3;
}