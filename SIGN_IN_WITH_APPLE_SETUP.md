# Sign in with Apple Setup Guide

## Error -7026 Fix

The error `AKAuthenticationError Code=-7026` indicates that Sign in with Apple is not properly configured. Follow these steps to fix it:

## Step 1: Configure in Xcode

1. **Open your project in Xcode**
2. **Select your project** in the navigator (top-level "FriendshipV2")
3. **Select the "FriendshipV2" target**
4. **Go to the "Signing & Capabilities" tab**
5. **Click the "+ Capability" button**
6. **Add "Sign in with Apple"**

This will automatically:
- Add the capability to your entitlements file
- Configure your App ID in Apple Developer Portal (if you have automatic signing enabled)

## Step 2: Configure in Apple Developer Portal

1. **Go to [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)**
2. **Select "Identifiers"**
3. **Find or create your App ID**: `com.Augmego.FriendshipV2`
4. **Edit the App ID**
5. **Enable "Sign in with Apple"** capability
6. **Save the changes**

## Step 3: Configure Services ID (Optional, for web integration)

If you want to support Sign in with Apple on your website as well:

1. **Go to "Identifiers" in Apple Developer Portal**
2. **Click the "+" button to create a new identifier**
3. **Select "Services IDs"**
4. **Register a Services ID** (e.g., `com.Augmego.FriendshipV2.web`)
5. **Enable "Sign in with Apple"**
6. **Configure domains and redirect URLs**

## Step 4: Verify Entitlements

The entitlements file should now include:

```xml
<key>com.apple.developer.applesignin</key>
<array>
    <string>Default</string>
</array>
```

## Step 5: Clean and Rebuild

1. **Clean build folder**: `Cmd + Shift + K`
2. **Delete derived data** (optional): `Cmd + Shift + Option + K`
3. **Rebuild the project**: `Cmd + B`
4. **Run on a physical device** (Sign in with Apple doesn't work in simulator for testing)

## Important Notes

### Testing Requirements

- **Physical Device Required**: Sign in with Apple requires a physical iOS device for testing
- **Apple ID**: You must be signed in with an Apple ID on the device
- **Development Team**: Your app must be signed with a valid development team

### Simulator Limitations

- Sign in with Apple **may not work** in the iOS Simulator
- Always test on a **physical device** for production testing
- The simulator may show errors even if configuration is correct

### Bundle ID

Your bundle ID is: `com.Augmego.FriendshipV2`

Make sure this matches exactly in:
- Xcode project settings
- Apple Developer Portal App ID
- Entitlements file

## Troubleshooting

### Still Getting Error -7026?

1. **Verify capability is added**:
   - Check "Signing & Capabilities" tab in Xcode
   - Verify `com.apple.developer.applesignin` is in entitlements

2. **Check Apple Developer Portal**:
   - Ensure App ID has "Sign in with Apple" enabled
   - Wait a few minutes for changes to propagate

3. **Verify signing**:
   - Ensure you're using automatic signing OR
   - Manually select a provisioning profile that includes Sign in with Apple

4. **Test on physical device**:
   - Simulator may show false errors
   - Always test on a real device

### Error Code Reference

- **-7026**: Sign in with Apple not configured
- **1000**: Unknown error (usually configuration issue)
- **1001**: Canceled by user
- **1002**: Failed authentication

## After Configuration

Once properly configured, you should see:
- Sign in with Apple button works
- Apple authentication dialog appears
- No -7026 errors in console

If you still see errors after following these steps, check:
1. Development team is set correctly
2. App ID matches in all places
3. Capability is enabled in both Xcode and Developer Portal
4. Testing on a physical device (not simulator)

