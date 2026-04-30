# Read API key from environment variable
$apiKey = $env:PIXELLAB_API_KEY

if (-not $apiKey) {
    Write-Error "Environment variable PIXELLAB_API_KEY is not set"
    exit 1
}

# Build request body
$body = @{
    description = "A skilled martial artist with a strong sense of justice. He is known for his powerful Hadouken and Shoryuken techniques."
    action = "idle"
    view = "side"
    direction = "east"
    negative_description = "No negative description"
    image_size = @{
        width = 64
        height = 64
    }
    reference_image = "ryu_animations/Ryu/ryu_ref_image.png"
    n_frames = 4
} | ConvertTo-Json -Depth 5

# Send request
$response = Invoke-RestMethod `
    -Uri "https://api.pixellab.ai/v2/animate-with-text" `
    -Method POST `
    -Headers @{
        "Authorization" = "Bearer $apiKey"
        "Content-Type"  = "application/json"
    } `
    -Body $body

# Print response
$response | ConvertTo-Json -Depth 10