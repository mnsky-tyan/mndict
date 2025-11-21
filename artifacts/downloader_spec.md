# Model Downloader Specification

## Requirements

### Protocol
- **HTTPS Only**: All downloads must use HTTPS.
- **Resumable**: Support `Range` requests to resume interrupted downloads.

### Storage
- **Location**: App internal storage (`getApplicationDocumentsDirectory` or similar).
- **Permissions**: No special permissions needed for internal storage.

### Pre-flight Checks
1. **Disk Space**: Check available space > (Model Size * 1.1).
2. **RAM Estimate**: Call `get_required_ram_estimate` (if metadata available) or check device RAM > Model RAM requirement.

### Validation
- **Checksum**: Verify SHA-256 hash after download.
- **Signature**: (Optional) Verify GPG signature if provided.

### Metadata
Store a `model_info.json` next to the model file:
```json
{
  "model_name": "llama-3-8b-quantized",
  "format": "GGUF",
  "quantization": "Q4_K_M",
  "sha256": "...",
  "recommended_thread_count": 4,
  "required_ram_estimate": 4294967296
}
```

### Error Handling
- **Network Error**: Retry with exponential backoff.
- **Corrupt File**: Delete and restart.
- **Insufficient Space**: Abort and notify user.
