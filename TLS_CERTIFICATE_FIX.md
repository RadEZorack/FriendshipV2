# TLS Certificate Error Fix

## Issue

iOS is rejecting the SSL certificate for `augmego.com` because it's serving a certificate for `*.i.db.ondigitalocean.com` (a database certificate), not a web server certificate.

## Immediate Fix Applied

I've switched the backend URL in `AuthService.swift` from `https://augmego.com` to `https://dev3.augmego.com` which should have a valid certificate.

## Server-Side Certificate Fix (Required for Production)

The root cause is that `augmego.com` needs a proper SSL certificate. Here's what needs to be fixed:

### Option 1: Fix Certificate on augmego.com (Recommended)

1. **Check your DNS/Proxy configuration**:
   - Ensure `augmego.com` points to your web server, not a database
   - The certificate should match the domain name

2. **Get a valid SSL certificate**:
   - Use Let's Encrypt (free)
   - Or use your hosting provider's SSL certificate
   - Ensure it's for `augmego.com` (not a database subdomain)

3. **Configure your web server** (nginx/apache):
   ```nginx
   server {
       server_name augmego.com;
       ssl_certificate /path/to/cert.pem;
       ssl_certificate_key /path/to/key.pem;
       # ... rest of config
   }
   ```

### Option 2: Use dev3.augmego.com (Temporary)

The code now uses `dev3.augmego.com` which should work. Once `augmego.com` has a valid certificate, update:

```swift
private let backendBaseURL = URL(string: "https://augmego.com")!
```

## Testing

After switching to `dev3.augmego.com`, the TLS error should be resolved. Test the Sign in with Apple flow again.

## ATS Exception (Not Recommended for Production)

If you need to temporarily allow the invalid certificate (NOT recommended for production), you would need to:

1. Create an `Info.plist` file (since project uses `GENERATE_INFOPLIST_FILE`)
2. Set `INFOPLIST_FILE` in build settings
3. Add ATS exceptions

However, this is a security risk and should only be used for development/testing.

## Current Status

✅ Backend URL changed to `dev3.augmego.com`
⚠️ Need to fix SSL certificate for `augmego.com` for production use

